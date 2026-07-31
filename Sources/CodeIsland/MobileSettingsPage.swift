import SwiftUI
import CoreImage.CIFilterBuiltins
import AppKit

/// Settings for the phone app: where the relay is, and which devices may drive this Mac.
///
/// The QR is drawn here rather than fetched. It encodes a string the app already knows how to
/// read, so generating it locally keeps the pairing code from taking any detour it does not
/// need to take.
struct MobileSettingsPage: View {
    @AppStorage(SettingsKey.mobileBridgeEnabled) private var enabled = SettingsDefaults.mobileBridgeEnabled
    @AppStorage(SettingsKey.mobileRelayURL) private var relayURL = SettingsDefaults.mobileRelayURL
    @AppStorage(SettingsKey.mobileRelayToken) private var relayToken = SettingsDefaults.mobileRelayToken
    @AppStorage(SettingsKey.mobileAllowKeystrokeInjection) private var allowKeystrokes = SettingsDefaults.mobileAllowKeystrokeInjection

    @State private var bridgeState: MobileBridge.State = .off
    @State private var pairingCode: MobileBridge.PairingCode?
    @State private var devices: [MobileBridge.PairedDevice] = []
    @State private var now = Date()
    @State private var revealToken = false

    private let tick = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    var body: some View {
        Form {
            connectionSection
            if enabled {
                pairingSection
                if !devices.isEmpty { devicesSection }
                promptSection
            }
        }
        .formStyle(.grouped)
        .onAppear {
            bridgeState = MobileBridge.shared.state
            pairingCode = MobileBridge.shared.pairingCode
            devices = MobileBridge.shared.pairedDevices
            MobileBridge.shared.onStateChange = { bridgeState = $0 }
            MobileBridge.shared.onPairingCodeChange = { pairingCode = $0 }
            MobileBridge.shared.onDevicesChange = { devices = $0 }
            if case .online = bridgeState { MobileBridge.shared.refreshPairedDevices() }
        }
        .onReceive(tick) { now = $0 }
        .onChange(of: enabled) { _, isOn in
            isOn ? MobileBridge.shared.start() : MobileBridge.shared.stop()
        }
    }

    // MARK: - Connection

    private var connectionSection: some View {
        Section {
            Toggle("Connect to a relay", isOn: $enabled)

            if enabled {
                TextField("Relay", text: $relayURL, prompt: Text("wss://hatch.odd-now.com/ws"))
                    .font(.system(size: 11, design: .monospaced))

                HStack {
                    if revealToken {
                        TextField("Token", text: $relayToken, prompt: Text("the relay's HATCHLING_MAC_TOKEN"))
                            .font(.system(size: 11, design: .monospaced))
                    } else {
                        SecureField("Token", text: $relayToken, prompt: Text("the relay's HATCHLING_MAC_TOKEN"))
                            .font(.system(size: 11, design: .monospaced))
                    }
                    Button {
                        revealToken.toggle()
                    } label: {
                        Image(systemName: revealToken ? "eye.slash" : "eye")
                    }
                    .buttonStyle(.borderless)
                }

                HStack(spacing: 8) {
                    Circle().fill(statusColor).frame(width: 7, height: 7)
                    Text(statusText)
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button("Reconnect") { MobileBridge.shared.restart() }
                        .controlSize(.small)
                        .disabled(relayURL.isEmpty || relayToken.isEmpty)
                }
            }
        } header: {
            Text("Phone")
        } footer: {
            Text("Hatchling opens an outbound connection carrying session state. Nothing listens for incoming connections on this Mac.")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
        }
    }

    private var statusColor: Color {
        switch bridgeState {
        case .online: return .green
        case .connecting, .retrying: return .orange
        case .failed: return .red
        case .off: return .secondary
        }
    }

    private var statusText: String {
        switch bridgeState {
        case .off: return "off"
        case .connecting: return "connecting…"
        case .online(let peers):
            return peers == 0 ? "connected, no phone" : "connected, \(peers) phone\(peers == 1 ? "" : "s")"
        case .retrying(let attempt): return "reconnecting (attempt \(attempt))"
        case .failed(let message): return message
        }
    }

    private var isOnline: Bool {
        if case .online = bridgeState { return true }
        return false
    }

    // MARK: - Pairing

    @ViewBuilder
    private var pairingSection: some View {
        Section("Pair a phone") {
            if let code = pairingCode, !code.isExpired {
                HStack(alignment: .top, spacing: 18) {
                    if let qr = qrImage(for: code.code) {
                        Image(nsImage: qr)
                            .interpolation(.none)  // a QR has to stay crisp
                            .resizable()
                            .frame(width: 124, height: 124)
                            .padding(6)
                            .background(Color.white)
                            .clipShape(RoundedRectangle(cornerRadius: 6))
                    }

                    VStack(alignment: .leading, spacing: 8) {
                        Text(code.code)
                            .font(.system(size: 24, weight: .semibold, design: .monospaced))
                            .textSelection(.enabled)

                        Text("Expires in \(code.secondsRemaining)s")
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundStyle(code.secondsRemaining < 60 ? .orange : .secondary)

                        Text("Type it into the app, or scan. Single use.")
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)

                        Button("Cancel") { MobileBridge.shared.clearPairingCode() }
                            .controlSize(.small)
                    }
                    Spacer()
                }
                .padding(.vertical, 4)
            } else {
                HStack {
                    Button("Generate pairing code") { MobileBridge.shared.requestPairingCode() }
                        .disabled(!isOnline)
                    if !isOnline {
                        Text("Connect to the relay first")
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
        // Redraw on the tick so an expired code stops being offered.
        .id(pairingCode.map { "\($0.code)-\(Int(now.timeIntervalSince1970))" } ?? "none")
    }

    // MARK: - Devices

    private var devicesSection: some View {
        Section("Paired phones") {
            ForEach(devices) { device in
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(device.name)
                        Text(device.lastSeen.map { "Last seen \(relative($0))" } ?? "Never connected")
                            .font(.system(size: 10))
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button("Revoke") { MobileBridge.shared.revoke(deviceId: device.id) }
                        .controlSize(.small)
                }
            }
        }
    }

    private func relative(_ date: Date) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter.localizedString(for: date, relativeTo: Date())
    }

    // MARK: - Prompt injection

    private var promptSection: some View {
        Section {
            Toggle("Allow prompts outside tmux", isOn: $allowKeystrokes)
        } footer: {
            Text("Sending a prompt to a session running in tmux is exact and needs no permission. Outside tmux there is no supported way to type into another program's terminal, so Hatchling synthesises keystrokes: it needs Accessibility permission, it raises the terminal window, and the text lands wherever focus ends up. Leave this off unless you need it.")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
        }
    }

    // MARK: - QR

    /// Encodes what the app needs to connect: the relay and the code, as JSON.
    private func qrImage(for code: String) -> NSImage? {
        let payload: [String: String] = ["relay": relayURL, "pair": code]
        guard let data = try? JSONSerialization.data(withJSONObject: payload) else { return nil }

        let filter = CIFilter.qrCodeGenerator()
        filter.message = data
        filter.correctionLevel = "M"
        guard let output = filter.outputImage else { return nil }

        // Integer scale so module edges land on pixel boundaries.
        let scaled = output.transformed(by: CGAffineTransform(scaleX: 8, y: 8))
        let context = CIContext()
        guard let cgImage = context.createCGImage(scaled, from: scaled.extent) else { return nil }
        return NSImage(cgImage: cgImage, size: NSSize(width: scaled.extent.width, height: scaled.extent.height))
    }
}
