import Foundation
import CodeIslandCore
import os

/// Talks to the relay so the phone app can watch and drive sessions.
///
/// Deliberately one-way in its coupling: `AppState` calls `publish…` when something changes and
/// hands over a `commandHandler` to run what the phone asks. The bridge knows nothing about the
/// panel, and the panel knows nothing about sockets.
@MainActor
final class MobileBridge {
    static let shared = MobileBridge()

    private static let log = Logger(subsystem: "com.mikaeldavid.CodeIsland", category: "MobileBridge")

    enum State: Equatable {
        case off
        case connecting
        case online(peers: Int)
        case retrying(attempt: Int)
        case failed(String)
    }

    private(set) var state: State = .off {
        didSet { if state != oldValue { onStateChange?(state) } }
    }

    var onStateChange: ((State) -> Void)?

    /// A live pairing code, when one has been asked for. Cleared once it expires or is used.
    private(set) var pairingCode: PairingCode? {
        didSet { onPairingCodeChange?(pairingCode) }
    }
    var onPairingCodeChange: ((PairingCode?) -> Void)?

    /// Phones that have been paired. The relay owns this list; the Mac shows it.
    private(set) var pairedDevices: [PairedDevice] = [] {
        didSet { onDevicesChange?(pairedDevices) }
    }
    var onDevicesChange: (([PairedDevice]) -> Void)?

    struct PairingCode: Equatable {
        let code: String
        let expiresAt: Date

        var isExpired: Bool { Date() >= expiresAt }
        var secondsRemaining: Int { max(0, Int(expiresAt.timeIntervalSinceNow)) }
    }

    struct PairedDevice: Identifiable, Equatable {
        let id: String
        let name: String
        let lastSeen: Date?
    }

    /// Runs a command from the phone. Returns nil on success, or a reason to send back.
    /// `AppState` installs this; keeping it a closure is what keeps this file free of app logic.
    var commandHandler: ((Command) async -> String?)?

    enum Command {
        case permissionRespond(attentionId: String, decision: String)
        case questionAnswer(attentionId: String, answers: [String: String])
        case questionSkip(attentionId: String)
        case interrupt(sessionId: String)
        case prompt(sessionId: String, text: String)
        case refresh
    }

    private var task: URLSessionWebSocketTask?
    private var session: URLSession?
    private var retryAttempt = 0
    private var retryTimer: Timer?
    private var pingTimer: Timer?
    private var deliberateStop = false

    /// Last payload sent per session, so `publish` can send patches instead of the whole list.
    private var lastSent: [String: MobileSession] = [:]

    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    private var relayURL: URL? {
        let raw = UserDefaults.standard.string(forKey: SettingsKey.mobileRelayURL) ?? ""
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        return URL(string: trimmed)
    }

    private var token: String {
        UserDefaults.standard.string(forKey: SettingsKey.mobileRelayToken) ?? ""
    }

    private var isEnabled: Bool {
        UserDefaults.standard.bool(forKey: SettingsKey.mobileBridgeEnabled)
    }

    private init() {}

    // MARK: - Lifecycle

    func start() {
        guard isEnabled else {
            state = .off
            return
        }
        guard let url = relayURL, !token.isEmpty else {
            state = .failed("relay not configured")
            return
        }
        deliberateStop = false
        connect(to: url)
    }

    func stop() {
        deliberateStop = true
        retryTimer?.invalidate()
        retryTimer = nil
        pingTimer?.invalidate()
        pingTimer = nil
        task?.cancel(with: .goingAway, reason: nil)
        task = nil
        session?.invalidateAndCancel()
        session = nil
        lastSent.removeAll()
        state = .off
    }

    func restart() {
        stop()
        start()
    }

    private func connect(to url: URL) {
        state = .connecting

        let config = URLSessionConfiguration.default
        config.waitsForConnectivity = true
        let session = URLSession(configuration: config)
        self.session = session

        let task = session.webSocketTask(with: url)
        self.task = task
        task.resume()

        receiveLoop()
        sendHello()
        schedulePing()
    }

    private func sendHello() {
        let name = Host.current().localizedName ?? "Mac"
        send(type: MobileMessageType.hello, body: MobileHello(role: "mac", token: token, device: name))
    }

    // MARK: - Receiving

    private func receiveLoop() {
        task?.receive { [weak self] result in
            Task { @MainActor in
                guard let self else { return }
                switch result {
                case .failure(let error):
                    self.handleDisconnect(reason: error.localizedDescription)
                case .success(let message):
                    switch message {
                    case .string(let text):
                        self.handle(text: text)
                    case .data(let data):
                        self.handle(text: String(decoding: data, as: UTF8.self))
                    @unknown default:
                        break
                    }
                    self.receiveLoop()
                }
            }
        }
    }

    private func handle(text: String) {
        guard let data = text.data(using: .utf8),
              let header = try? decoder.decode(MobileEnvelopeHeader.self, from: data) else {
            Self.log.error("unparseable frame")
            return
        }

        guard header.v == MobileProtocol.version else {
            state = .failed("relay speaks protocol v\(header.v), this build speaks v\(MobileProtocol.version)")
            stop()
            return
        }

        switch header.type {
        case MobileMessageType.ready:
            retryAttempt = 0
            let peers = (try? decoder.decode(MobileEnvelope<MobileReady>.self, from: data))?.body?.peers ?? []
            state = .online(peers: peers.filter { $0.role == "phone" }.count)
            // A phone that just arrived has no state; hand it everything.
            lastSent.removeAll()
            onStateChange?(state)

        case MobileMessageType.error:
            let body = (try? decoder.decode(MobileEnvelope<MobileError>.self, from: data))?.body
            state = .failed(body?.message ?? "relay error")

        case MobileMessageType.pairCreated:
            // The relay reuses this type for both a fresh code and the device list, so which
            // one arrived is decided by what the body actually contains.
            if let body = (try? decoder.decode(MobileEnvelope<MobilePairCode>.self, from: data))?.body,
               let code = body.code, let expiresAt = body.expiresAt {
                pairingCode = PairingCode(
                    code: code,
                    expiresAt: Date(timeIntervalSince1970: TimeInterval(expiresAt) / 1000)
                )
            }
            if let body = (try? decoder.decode(MobileEnvelope<MobilePairDevices>.self, from: data))?.body,
               let devices = body.devices {
                pairedDevices = devices.map {
                    PairedDevice(
                        id: $0.id,
                        name: $0.name,
                        lastSeen: $0.lastSeen.map { Date(timeIntervalSince1970: TimeInterval($0) / 1000) }
                    )
                }
                // A device list arriving means a phone just redeemed the code.
                pairingCode = nil
            }

        case MobileMessageType.permissionRespond:
            guard let body = (try? decoder.decode(MobileEnvelope<MobilePermissionRespond>.self, from: data))?.body else { return }
            run(.permissionRespond(attentionId: body.attentionId, decision: body.decision), ref: header.id)

        case MobileMessageType.questionAnswer:
            guard let body = (try? decoder.decode(MobileEnvelope<MobileQuestionAnswer>.self, from: data))?.body else { return }
            run(.questionAnswer(attentionId: body.attentionId, answers: body.answers), ref: header.id)

        case MobileMessageType.questionSkip:
            guard let body = (try? decoder.decode(MobileEnvelope<MobileAttentionRef>.self, from: data))?.body else { return }
            run(.questionSkip(attentionId: body.attentionId), ref: header.id)

        case MobileMessageType.sessionInterrupt:
            guard let body = (try? decoder.decode(MobileEnvelope<MobileSessionRef>.self, from: data))?.body else { return }
            run(.interrupt(sessionId: body.sessionId), ref: header.id)

        case MobileMessageType.sessionPrompt:
            guard let body = (try? decoder.decode(MobileEnvelope<MobilePrompt>.self, from: data))?.body else { return }
            run(.prompt(sessionId: body.sessionId, text: body.text), ref: header.id)

        case MobileMessageType.sessionsRefresh:
            lastSent.removeAll()
            run(.refresh, ref: header.id)

        default:
            break
        }
    }

    private func run(_ command: Command, ref: String) {
        Task { @MainActor in
            let failure = await commandHandler?(command)
            send(
                type: MobileMessageType.ack,
                body: MobileAck(ref: ref, ok: failure == nil, detail: failure)
            )
        }
    }

    // MARK: - Publishing

    /// Sends whatever changed since last time. Full list on first call after a phone connects,
    /// per-session patches after that.
    func publish(sessions: [String: MobileSession]) {
        guard case .online = state else { return }

        if lastSent.isEmpty {
            let all = sessions.values.sorted { $0.sessionId < $1.sessionId }
            send(type: MobileMessageType.sessions, body: MobileSessionList(sessions: all))
            lastSent = sessions
            return
        }

        for (id, session) in sessions where lastSent[id] != session {
            send(type: MobileMessageType.sessionPatch, body: session)
        }
        for id in lastSent.keys where sessions[id] == nil {
            send(type: MobileMessageType.sessionGone, body: MobileSessionGone(sessionId: id))
        }
        lastSent = sessions
    }

    func publish(attention: MobileAttention) {
        send(type: MobileMessageType.attention, body: attention)
    }

    func publishAttentionCleared(attentionId: String, reason: String) {
        send(type: MobileMessageType.attentionCleared,
             body: MobileAttentionCleared(attentionId: attentionId, reason: reason))
    }

    func publish(usage: MobileUsage) {
        send(type: MobileMessageType.usage, body: usage)
    }

    // MARK: - Pairing

    func requestPairingCode() {
        pairingCode = nil
        send(type: MobileMessageType.pairCreate, body: MobileEmpty())
    }

    func refreshPairedDevices() {
        send(type: MobileMessageType.pairList, body: MobileEmpty())
    }

    func revoke(deviceId: String) {
        send(type: MobileMessageType.pairRevoke, body: MobilePairRevoke(deviceId: deviceId))
    }

    func clearPairingCode() {
        pairingCode = nil
    }

    private func send<Body: Codable>(type: String, body: Body?) {
        guard let task else { return }
        let envelope = MobileEnvelope(type: type, body: body)
        guard let data = try? encoder.encode(envelope),
              let text = String(data: data, encoding: .utf8) else {
            Self.log.error("failed to encode \(type)")
            return
        }
        task.send(.string(text)) { [weak self] error in
            guard let error else { return }
            Task { @MainActor in
                self?.handleDisconnect(reason: error.localizedDescription)
            }
        }
    }

    // MARK: - Keepalive and retry

    private func schedulePing() {
        pingTimer?.invalidate()
        pingTimer = Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.task?.sendPing { error in
                    guard let error else { return }
                    Task { @MainActor in
                        self?.handleDisconnect(reason: "ping failed: \(error.localizedDescription)")
                    }
                }
            }
        }
    }

    private func handleDisconnect(reason: String) {
        guard !deliberateStop else { return }
        guard retryTimer == nil else { return }  // already scheduled

        pingTimer?.invalidate()
        pingTimer = nil
        task?.cancel(with: .abnormalClosure, reason: nil)
        task = nil
        lastSent.removeAll()

        retryAttempt += 1
        state = .retrying(attempt: retryAttempt)
        Self.log.info("relay disconnected (\(reason)); retry \(self.retryAttempt)")

        // Exponential backoff to 30s, with jitter so several Macs don't sync up on the relay.
        let base = min(pow(2.0, Double(retryAttempt - 1)), 30)
        let delay = base + Double.random(in: 0...(base * 0.25))

        retryTimer = Timer.scheduledTimer(withTimeInterval: delay, repeats: false) { [weak self] _ in
            Task { @MainActor in
                guard let self else { return }
                self.retryTimer = nil
                guard !self.deliberateStop, let url = self.relayURL else { return }
                self.connect(to: url)
            }
        }
    }
}
