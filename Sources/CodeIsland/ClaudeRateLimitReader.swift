import Combine
import Foundation
import SwiftUI

/// Real Claude rate-limit data captured from Claude Code's statusline JSON
/// (v2.1.80+). The wrapper script writes ~/.codeisland/rate-limits.json on
/// every Claude Code interaction. This reader watches that file so the
/// UsageBar reflects the actual session/weekly usage —
/// no API calls, no estimates, no auth.
struct ClaudeRateLimits: Equatable {
    let fiveHourPercent: Int?
    let sevenDayPercent: Int?
    let fiveHourResetAt: Date?
    let sevenDayResetAt: Date?
    let capturedAt: Date
    let model: String?

    var maxPercent: Int { max(fiveHourPercent ?? 0, sevenDayPercent ?? 0) }

    /// Claude Code only sends these numbers to the statusline of the terminal app; the
    /// desktop app never runs it. When the last reading is older than a 5-hour window, the
    /// numbers describe a window that is already over, so they are not shown as current.
    var isFresh: Bool { Date().timeIntervalSince(capturedAt) < 5 * 3600 }

    var color: Color {
        let m = maxPercent
        if m >= 90 { return Color(red: 0.95, green: 0.30, blue: 0.30) }
        if m >= 70 { return Color(red: 1.0,  green: 0.65, blue: 0.25) }
        return Color(red: 0.36, green: 0.85, blue: 0.50)
    }
}

/// File-scope so the background parser can reach them without crossing the
/// reader's main-actor isolation.
private let rateLimitCachePath: URL = FileManager.default
    .homeDirectoryForCurrentUser
    .appendingPathComponent(".codeisland/rate-limits.json")

private let rateLimitISO8601: ISO8601DateFormatter = {
    let f = ISO8601DateFormatter()
    f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    return f
}()

@MainActor
final class ClaudeRateLimitReader: ObservableObject {
    static let shared = ClaudeRateLimitReader()

    @Published private(set) var limits: ClaudeRateLimits?
    @Published private(set) var isInstalled: Bool = false
    /// The Claude Code CLI on this Mac answered but isn't signed in to a plan, so it can't
    /// report the limits. The desktop app's own login doesn't reach it.
    @Published private(set) var cliSignedOut = false

    private var timer: Timer?
    private var probeTimer: Timer?
    private var cacheWatcher: FSEventStreamRef?
    /// The latest answer from asking Claude Code directly.
    nonisolated(unsafe) private static var probed: ClaudeRateLimits?
    private(set) var isRunning = false
    private var isProbing = false
    private var lastProbeAt: Date = .distantPast

    /// Whether anyone would see a fresh reading right now: a Claude session is working or
    /// the panel is open. Set by the app; with no answer the probe is allowed.
    var probeDemand: (() -> Bool)?

    /// A reading younger than this, from any source, makes asking Claude Code pointless.
    private static let probeStaleAfter: TimeInterval = 15 * 60
    /// Floor between two probes, so reopening the panel doesn't spawn the CLI each time.
    private static let minProbeGap: TimeInterval = 5 * 60

    private init() {}

    func start() {
        guard !isRunning else { return }
        isRunning = true
        // The statusline wrapper rewrites the cache on every interaction; react to that
        // instead of re-reading it every 10 seconds whether anything changed or not.
        startWatchingCache()
        // Backstop for what the watcher doesn't cover: the desktop app's history (written
        // now and then, never live), whether the statusline is installed, and a cache folder
        // that didn't exist yet at launch.
        timer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.startWatchingCache()
                self?.refresh()
            }
        }
        timer?.tolerance = 15
        refresh()
        // Ask Claude Code itself: it works for sessions in the desktop app too, which never run
        // the terminal statusline. Each ask launches a whole Claude Code process, so it only
        // happens when a reading would be seen and the last one is old (see probeIfNeeded).
        probeTimer = Timer.scheduledTimer(withTimeInterval: 300, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.probeIfNeeded() }
        }
        probeTimer?.tolerance = 30
        // First check once discovery has had a moment to find the sessions already running.
        DispatchQueue.main.asyncAfter(deadline: .now() + 15) { [weak self] in
            self?.probeIfNeeded()
        }
    }

    /// Asks Claude Code for the limits when the newest reading is stale and someone would
    /// see the answer. Also called when the usage row appears.
    func probeIfNeeded() {
        guard isRunning, !isProbing else { return }
        let now = Date()
        if let captured = limits?.capturedAt, now.timeIntervalSince(captured) < Self.probeStaleAfter { return }
        guard now.timeIntervalSince(lastProbeAt) >= Self.minProbeGap else { return }
        guard probeDemand?() ?? true else { return }
        probe()
    }

    private func startWatchingCache() {
        guard cacheWatcher == nil else { return }
        let dir = rateLimitCachePath.deletingLastPathComponent().path
        guard FileManager.default.fileExists(atPath: dir) else { return }

        var context = FSEventStreamContext()
        // The reader is a process-lifetime singleton and the stream is delivered on the main
        // queue, so the unretained pointer can't outlive it.
        context.info = Unmanaged.passUnretained(self).toOpaque()
        let stream = FSEventStreamCreate(
            nil,
            { (_, info, numEvents, eventPaths, _, _) in
                guard let info else { return }
                // The folder also holds the hook script, the bridge and the statusline's raw
                // payload; only the cache itself matters here.
                let paths = Unmanaged<CFArray>.fromOpaque(eventPaths).takeUnretainedValue() as? [String] ?? []
                guard paths.prefix(numEvents).contains(where: { $0.hasSuffix("/rate-limits.json") }) else { return }
                let reader = Unmanaged<ClaudeRateLimitReader>.fromOpaque(info).takeUnretainedValue()
                Task { @MainActor in reader.refresh() }
            },
            &context,
            [dir] as CFArray,
            FSEventStreamEventId(kFSEventStreamEventIdSinceNow),
            1.0,
            FSEventStreamCreateFlags(kFSEventStreamCreateFlagUseCFTypes | kFSEventStreamCreateFlagFileEvents)
        )
        guard let stream else { return }
        FSEventStreamSetDispatchQueue(stream, .main)
        FSEventStreamStart(stream)
        cacheWatcher = stream
    }

    /// Opens Terminal running `claude /login`, then asks for the limits every 20 seconds
    /// for five minutes, so they show up as soon as the sign-in finishes. A `.command`
    /// file opened with `open` needs no Automation permission.
    func openLogin() {
        guard let binary = ClaudeUsageProbe.claudeBinary() else { return }
        let script = FileManager.default.temporaryDirectory.appendingPathComponent("hatchling-claude-login.command")
        let body = """
        #!/bin/zsh -l
        clear
        echo "Hatchling: entre na sua conta do Claude pra ver os limites de 5h e semanal."
        echo
        '\(binary.replacingOccurrences(of: "'", with: "'\\''"))' /login
        """
        guard (try? body.write(to: script, atomically: true, encoding: .utf8)) != nil else { return }
        try? FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: script.path)
        NSWorkspace.shared.open(script)

        loginWatch?.invalidate()
        var ticks = 0
        loginWatch = Timer.scheduledTimer(withTimeInterval: 20, repeats: true) { [weak self] timer in
            MainActor.assumeIsolated {
                ticks += 1
                guard let self, ticks <= 15, self.cliSignedOut else { timer.invalidate(); return }
                self.probe()
            }
        }
    }

    private var loginWatch: Timer?

    private func probe() {
        guard !isProbing else { return }
        isProbing = true
        lastProbeAt = Date()
        Task.detached(priority: .utility) {
            #if DEBUG
            // Preview the signed-out row without signing out.
            let result = ProcessInfo.processInfo.environment["HATCHLING_FAKE_SIGNED_OUT"] != nil
                ? .signedOut : ClaudeUsageProbe.run()
            #else
            let result = ClaudeUsageProbe.run()
            #endif
            await MainActor.run {
                self.isProbing = false
                switch result {
                case .limits(let l):
                    Self.probed = l
                    if self.cliSignedOut { self.cliSignedOut = false }
                case .signedOut:
                    if !self.cliSignedOut { self.cliSignedOut = true }
                case .unavailable:
                    break
                }
                self.refresh()
            }
        }
    }

    func stop() {
        isRunning = false
        timer?.invalidate()
        timer = nil
        probeTimer?.invalidate()
        probeTimer = nil
        if let stream = cacheWatcher {
            FSEventStreamStop(stream)
            FSEventStreamInvalidate(stream)
            FSEventStreamRelease(stream)
            cacheWatcher = nil
        }
    }

    /// Reads the cache off the main thread and republishes only on change —
    /// an unconditional assignment on every read would redraw the notch forever.
    func refresh() {
        Task.detached(priority: .utility) {
            let installed = StatuslineInstaller.isInstalled
            // Three sources; the most recent reading wins.
            let parsed = [Self.parseCache(), Self.parseDesktopHistory(), Self.probed]
                .compactMap { $0 }
                .max { $0.capturedAt < $1.capturedAt }
            await MainActor.run {
                if self.isInstalled != installed { self.isInstalled = installed }
                if let parsed, self.limits != parsed { self.limits = parsed }
            }
        }
    }

    private nonisolated static func parseCache() -> ClaudeRateLimits? {
        guard let data = try? Data(contentsOf: rateLimitCachePath),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { return nil }

        let captured = (json["capturedAt"] as? Double).map { Date(timeIntervalSince1970: $0) } ?? Date()
        let rl = json["rate_limits"] as? [String: Any] ?? [:]
        let five = rl["five_hour"] as? [String: Any]
        let seven = rl["seven_day"] as? [String: Any]

        return ClaudeRateLimits(
            fiveHourPercent: percent(five?["used_percentage"]),
            sevenDayPercent: percent(seven?["used_percentage"]),
            fiveHourResetAt: resetDate(five?["resets_at"]),
            sevenDayResetAt: resetDate(seven?["resets_at"]),
            capturedAt: captured,
            model: json["model"] as? String
        )
    }

    /// The Claude desktop app keeps a short history of the plan meters it has seen
    /// (`plan-usage-history.json`: `fh` five-hour %, `sd` weekly %), written now and then
    /// rather than live. No reset times in it.
    private nonisolated static func parseDesktopHistory() -> ClaudeRateLimits? {
        let url = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/Claude/plan-usage-history.json")
        guard let data = try? Data(contentsOf: url),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let samples = json["samples"] as? [[String: Any]],
              let last = samples.max(by: { ($0["t"] as? Double ?? 0) < ($1["t"] as? Double ?? 0) }),
              let t = last["t"] as? Double,
              let u = last["u"] as? [String: Any] else { return nil }
        return ClaudeRateLimits(
            fiveHourPercent: percent(u["fh"]),
            sevenDayPercent: percent(u["sd"]),
            fiveHourResetAt: nil,
            sevenDayResetAt: nil,
            capturedAt: Date(timeIntervalSince1970: t / 1000),
            model: nil
        )
    }

    private nonisolated static func percent(_ v: Any?) -> Int? {
        switch v {
        case let n as NSNumber: return Int(n.doubleValue.rounded())
        case let s as String: return Double(s).map { Int($0.rounded()) }
        default: return nil
        }
    }

    private nonisolated static func resetDate(_ v: Any?) -> Date? {
        switch v {
        case let n as NSNumber: return Date(timeIntervalSince1970: n.doubleValue)
        case let s as String:
            if let d = Double(s) { return Date(timeIntervalSince1970: d) }
            return rateLimitISO8601.date(from: s)
        default: return nil
        }
    }
}

// MARK: - Asking Claude Code

/// Asks the Claude Code CLI for the plan meters through its own SDK control request
/// (`get_usage`), the one the desktop app uses inside. No model call, no tokens; Claude
/// Code uses its own login, and Hatchling never touches a credential. It runs with
/// `--setting-sources project` in an empty folder, so no user hooks fire and no session
/// shows up in the notch.
enum ClaudeUsageProbe {
    enum Result {
        case limits(ClaudeRateLimits)
        case signedOut
        case unavailable
    }

    nonisolated static func run() -> Result {
        guard let binary = claudeBinary() else { return .unavailable }
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("hatchling-usage-probe", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)

        let process = Process()
        process.executableURL = URL(fileURLWithPath: binary)
        process.arguments = ["-p", "--setting-sources", "project", "--input-format", "stream-json",
                             "--output-format", "stream-json", "--verbose"]
        process.currentDirectoryURL = dir
        let input = Pipe(), output = Pipe()
        process.standardInput = input
        process.standardOutput = output
        process.standardError = FileHandle.nullDevice
        guard (try? process.run()) != nil else { return .unavailable }

        let request = #"{"type":"control_request","request_id":"hatchling-usage","request":{"subtype":"get_usage"}}"# + "\n"
        input.fileHandleForWriting.write(Data(request.utf8))

        // Read lines until the answer arrives, for at most 20 seconds.
        var buffer = Data()
        var answer: [String: Any]?
        let deadline = Date().addingTimeInterval(20)
        let handle = output.fileHandleForReading
        while answer == nil, Date() < deadline {
            let chunk = handle.availableData
            if chunk.isEmpty { break }
            buffer.append(chunk)
            while let nl = buffer.firstIndex(of: 0x0A) {
                let line = buffer[..<nl]
                buffer.removeSubrange(...nl)
                guard let json = try? JSONSerialization.jsonObject(with: line) as? [String: Any],
                      json["type"] as? String == "control_response",
                      let response = json["response"] as? [String: Any],
                      response["request_id"] as? String == "hatchling-usage" else { continue }
                answer = response["response"] as? [String: Any] ?? [:]
                break
            }
        }
        try? input.fileHandleForWriting.close()
        if process.isRunning { process.terminate() }

        guard let answer else { return .unavailable }
        guard answer["rate_limits_available"] as? Bool == true,
              let rl = answer["rate_limits"] as? [String: Any] else { return .signedOut }
        func window(_ key: String) -> (Int?, Date?) {
            guard let w = rl[key] as? [String: Any] else { return (nil, nil) }
            let pct = (w["utilization"] as? NSNumber).map { Int($0.doubleValue.rounded()) }
            let reset = (w["resets_at"] as? String).flatMap { iso($0) }
            return (pct, reset)
        }
        let five = window("five_hour"), seven = window("seven_day")
        return .limits(ClaudeRateLimits(
            fiveHourPercent: five.0, sevenDayPercent: seven.0,
            fiveHourResetAt: five.1, sevenDayResetAt: seven.1,
            capturedAt: Date(), model: nil
        ))
    }

    private nonisolated static func iso(_ s: String) -> Date? {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let d = f.date(from: s) { return d }
        f.formatOptions = [.withInternetDateTime]
        return f.date(from: s)
    }

    /// The `claude` on the user's PATH, in the usual install places (the app doesn't
    /// inherit the login shell's PATH).
    nonisolated static func claudeBinary() -> String? {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let candidates = [
            "\(home)/.local/bin/claude", "\(home)/.claude/local/claude",
            "/opt/homebrew/bin/claude", "/usr/local/bin/claude",
        ]
        return candidates.first { FileManager.default.isExecutableFile(atPath: $0) }
    }
}
