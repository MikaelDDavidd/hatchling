import SwiftUI
import AppKit
import Combine

/// Settings for the phone app: where the relay is, and which devices may drive this Mac.
///
/// The QR is drawn here rather than fetched. It encodes a string the app already knows how to
/// read, so generating it locally keeps the pairing code from taking any detour it does not
/// need to take. The same QR is also one click away in the panel, from the phone button.
struct MobileSettingsPage: View {
    @AppStorage(SettingsKey.mobileBridgeEnabled) private var enabled = SettingsDefaults.mobileBridgeEnabled
    @AppStorage(SettingsKey.mobileRelayURL) private var relayURL = SettingsDefaults.mobileRelayURL
    /// Edited here, stored in the Keychain (see RelayTokenStore), not in UserDefaults.
    @State private var relayToken = RelayTokenStore.token
    @AppStorage(SettingsKey.mobileAllowKeystrokeInjection) private var allowKeystrokes = SettingsDefaults.mobileAllowKeystrokeInjection

    @ObservedObject private var bridge = MobileBridge.shared
    @ObservedObject private var l10n = L10n.shared
    @State private var now = Date()
    @State private var revealToken = false

    private let tick = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    var body: some View {
        Form {
            connectionSection
            if enabled {
                pairingSection
                if !bridge.pairedDevices.isEmpty { devicesSection }
                promptSection
            }
        }
        .formStyle(.grouped)
        .onAppear {
            if case .online = bridge.state { bridge.refreshPairedDevices() }
        }
        .onReceive(tick) { now = $0 }
        .onChange(of: relayToken) { _, value in
            RelayTokenStore.token = value
        }
        .onChange(of: enabled) { _, isOn in
            isOn ? bridge.start() : bridge.stop()
        }
    }

    // MARK: - Connection

    private var connectionSection: some View {
        Section {
            Toggle(l10n["phone_connect_toggle"], isOn: $enabled)

            if enabled {
                TextField(l10n["phone_server"], text: $relayURL, prompt: Text("wss://hatch.odd-now.com/ws"))
                    .font(.system(size: 11, design: .monospaced))

                HStack {
                    if revealToken {
                        TextField(l10n["phone_token"], text: $relayToken, prompt: Text("HATCHLING_MAC_TOKEN"))
                            .font(.system(size: 11, design: .monospaced))
                    } else {
                        SecureField(l10n["phone_token"], text: $relayToken, prompt: Text("HATCHLING_MAC_TOKEN"))
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
                    Text(l10n["phone_state"])
                    Spacer()
                    Circle().fill(statusColor).frame(width: 7, height: 7)
                    Text(statusText)
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(.secondary)
                    Button(l10n["phone_reconnect"]) { bridge.restart() }
                        .controlSize(.small)
                        .disabled(relayURL.isEmpty || relayToken.isEmpty)
                }
            }
        } header: {
            Text(l10n["phone_section_connection"])
        } footer: {
            Text(l10n["phone_connection_footer"])
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
        }
    }

    private var statusColor: Color {
        switch bridge.state {
        case .online: return .green
        case .connecting, .retrying: return .orange
        case .failed: return .red
        case .off: return .secondary
        }
    }

    private var statusText: String {
        switch bridge.state {
        case .off: return l10n["phone_status_off"]
        case .connecting: return l10n["phone_status_connecting"]
        case .online(let peers):
            switch peers {
            case 0: return l10n["phone_status_no_phone"]
            case 1: return l10n["phone_status_one"]
            default: return String(format: l10n["phone_status_many"], peers)
            }
        case .retrying(let attempt): return String(format: l10n["phone_status_retrying"], attempt)
        case .failed(let message): return message
        }
    }

    private var isOnline: Bool {
        if case .online = bridge.state { return true }
        return false
    }

    // MARK: - Pairing

    @ViewBuilder
    private var pairingSection: some View {
        Section {
            if let code = bridge.pairingCode, code.expiresAt > now {
                HStack(alignment: .top, spacing: 18) {
                    if let qr = PairingQR.image(relay: relayURL, code: code.code) {
                        Image(nsImage: qr)
                            .interpolation(.none)  // a QR has to stay crisp
                            .resizable()
                            .frame(width: 136, height: 136)
                            .padding(7)
                            .background(Color.white)
                            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                    }

                    VStack(alignment: .leading, spacing: 6) {
                        Text(PairingQR.spaced(code.code))
                            .font(.system(size: 24, weight: .semibold, design: .monospaced))
                            .tracking(1)
                            .textSelection(.enabled)

                        let remaining = max(0, Int(code.expiresAt.timeIntervalSince(now)))
                        Text(String(format: l10n["phone_valid_for"], PairingQR.clock(remaining)))
                            .font(.system(size: 11, design: .monospaced))
                            .monospacedDigit()
                            .foregroundStyle(remaining < 60 ? .orange : .secondary)

                        Text(l10n["phone_pair_hint"])
                            .font(.system(size: 12))
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                            .padding(.top, 4)

                        Button(l10n["phone_cancel"]) { bridge.clearPairingCode() }
                            .controlSize(.small)
                            .padding(.top, 6)
                    }
                    Spacer(minLength: 0)
                }
                .padding(.vertical, 6)
            } else {
                HStack {
                    Button(l10n["phone_generate"]) { bridge.requestPairingCode() }
                        .disabled(!isOnline)
                    if !isOnline {
                        Text(l10n["phone_connect_first"])
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                    }
                }
            }
        } header: {
            Text(l10n["phone_pair_section"])
        } footer: {
            Text(l10n["phone_pair_footer"])
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
        }
    }

    // MARK: - Devices

    private var devicesSection: some View {
        Section(l10n["phone_paired_list"]) {
            ForEach(bridge.pairedDevices) { device in
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(device.name)
                        Text(seen(device))
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button(l10n["phone_revoke"]) { bridge.revoke(deviceId: device.id) }
                        .controlSize(.small)
                }
            }
        }
    }

    private func seen(_ device: MobileBridge.PairedDevice) -> String {
        guard let date = device.lastSeen else { return l10n["phone_never"] }
        if now.timeIntervalSince(date) < 120 { return l10n["phone_connected_now"] }
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        formatter.locale = Locale(identifier: l10n.effectiveLanguage == "pt" ? "pt_BR" : "en_US")
        return String(format: l10n["phone_last_seen"], formatter.localizedString(for: date, relativeTo: now))
    }

    // MARK: - Prompt injection

    private var promptSection: some View {
        Section {
            Toggle(l10n["phone_prompts_toggle"], isOn: $allowKeystrokes)
        } header: {
            Text(l10n["phone_prompts"])
        } footer: {
            Text(l10n["phone_prompts_footer"])
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
        }
    }
}
