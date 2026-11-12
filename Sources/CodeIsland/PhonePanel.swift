import SwiftUI
import AppKit
import CoreImage.CIFilterBuiltins
import Combine

/// Whether the panel is showing the phone page instead of the selected tab.
///
/// Not a tab of its own: pairing is something you do once in a while, and a fourth tab would
/// sit in the selector forever for it. The phone button opens the page; picking a tab or
/// collapsing the panel closes it.
@MainActor
final class PhonePanel: ObservableObject {
    static let shared = PhonePanel()
    @Published var open = false

    func toggle() {
        withAnimation(.spring(response: 0.34, dampingFraction: 0.82)) { open.toggle() }
    }

    func close() {
        guard open else { return }
        withAnimation(.spring(response: 0.34, dampingFraction: 0.82)) { open = false }
    }
}

/// The phone button in the panel header. It sits beside "collapse" and carries a green dot
/// while a phone is connected, so the header also answers "is my phone with me?".
struct PhoneHeaderButton: View {
    @ObservedObject private var panel = PhonePanel.shared
    @ObservedObject private var bridge = MobileBridge.shared
    @ObservedObject private var l10n = L10n.shared
    @State private var hovering = false

    private var phoneOnline: Bool {
        if case .online(let peers) = bridge.state { return peers > 0 }
        return false
    }

    var body: some View {
        Button { panel.toggle() } label: {
            Image(systemName: "iphone")
                .font(.system(size: 11.5, weight: .medium))
                .foregroundStyle(.white.opacity(panel.open || hovering ? 0.95 : 0.55))
                .frame(width: 26, height: 26)
                .background(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(.white.opacity(panel.open ? 0.12 : (hovering ? 0.08 : 0)))
                )
                .overlay(alignment: .topTrailing) {
                    if phoneOnline {
                        Circle()
                            .fill(Color(red: 0.37, green: 0.81, blue: 0.42))
                            .frame(width: 5, height: 5)
                            .overlay(Circle().stroke(.black, lineWidth: 1.5))
                            .offset(x: -5, y: 5)
                    }
                }
                .contentShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        }
        .buttonStyle(.plain)
        .onHover { h in withAnimation(NotchAnimation.micro) { hovering = h } }
        .help(l10n["phone_tooltip"])
    }
}

/// The phone page inside the panel: Hatch, the QR the phone scans, the code for typing by
/// hand, and the phones already paired.
struct PhonePairingView: View {
    @ObservedObject private var bridge = MobileBridge.shared
    @ObservedObject private var l10n = L10n.shared
    @AppStorage(SettingsKey.mobileBridgeEnabled) private var enabled = SettingsDefaults.mobileBridgeEnabled
    @AppStorage(SettingsKey.mobileRelayURL) private var relayURL = SettingsDefaults.mobileRelayURL
    @State private var now = Date()
    /// Name of the phone that just paired, so Hatch can say so before the list takes over.
    @State private var justPaired: String?
    /// Phones already known when the page opened, so only a new one counts as "just paired".
    @State private var knownIds: Set<String> = []
    /// A code has been on screen, so a new phone in the list was this page's doing.
    @State private var codeShown = false

    private let tick = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    private var isOnline: Bool {
        if case .online = bridge.state { return true }
        return false
    }

    private var liveCode: MobileBridge.PairingCode? {
        guard let code = bridge.pairingCode, code.expiresAt > now else { return nil }
        return code
    }

    /// When the page last asked the relay for a code that hasn't arrived yet.
    @State private var requestedAt: Date?
    /// Codes renewed on their own during this visit. An expired code used to leave a spinner
    /// and "making a code…" forever; now a new one is fetched, but only a few times, so a
    /// panel left open all day doesn't keep minting codes nobody scans.
    @State private var autoRenewals = 0
    private static let maxAutoRenewals = 3

    /// No code on screen and none coming: it expired past the renewals, or the relay never
    /// answered the request.
    private var codeStalled: Bool {
        guard liveCode == nil else { return false }
        if let requestedAt { return now.timeIntervalSince(requestedAt) > 10 }
        return bridge.pairingCode != nil
    }

    private func requestCode() {
        requestedAt = now
        bridge.requestPairingCode()
    }

    /// Called every second: renews an expired code while renewals remain.
    private func renewIfExpired() {
        guard isOnline, justPaired == nil, let code = bridge.pairingCode, code.expiresAt <= now,
              autoRenewals < Self.maxAutoRenewals else { return }
        autoRenewals += 1
        requestCode()
    }

    /// The raw reason the relay connection failed, kept for the tooltip.
    private var rawFailure: String? {
        if case .failed(let message) = bridge.state { return message }
        return nil
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 16) {
                MascotView(source: "claude", status: justPaired == nil ? .idle : .processing, size: 50, global: true)
                    .padding(.horizontal, 6)
                SpeechBubble(text: hatchLine, thinking: false)
                    .frame(maxWidth: 420, alignment: .leading)
                    // Hatch says it plainly; the relay's own words are here for a bug report.
                    .help(rawFailure ?? "")
                Spacer(minLength: 0)
            }

            if !enabled || !isOnline {
                offlineBody
            } else {
                pairingBody
            }

            if !bridge.pairedDevices.isEmpty {
                Rectangle().fill(.white.opacity(0.06)).frame(height: 1)
                devicesBody
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 16)
        .padding(.bottom, 14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .onReceive(tick) {
            now = $0
            renewIfExpired()
        }
        .onDisappear { PhonePanel.shared.close() }
        .onAppear {
            knownIds = Set(bridge.pairedDevices.map(\.id))
            if isOnline {
                bridge.refreshPairedDevices()
                if liveCode == nil { requestCode() }
            }
        }
        .onChange(of: bridge.state) { _, state in
            if case .online = state, liveCode == nil, justPaired == nil { requestCode() }
        }
        .onChange(of: bridge.pairingCode) { _, code in
            if code != nil {
                codeShown = true
                requestedAt = nil
            }
        }
        .onChange(of: bridge.pairedDevices) { _, new in
            if codeShown, let fresh = new.first(where: { !knownIds.contains($0.id) }) {
                justPaired = fresh.name
                codeShown = false
            }
            knownIds.formUnion(new.map(\.id))
        }
    }

    private var hatchLine: String {
        if let name = justPaired { return String(format: l10n["phone_paired_line"], name) }
        if !enabled { return l10n["phone_off_line"] }
        switch bridge.state {
        case .off: return l10n["phone_off_line"]
        case .connecting, .retrying: return l10n["phone_connecting_line"]
        case .failed(let message): return RelayErrorText.friendly(message)
        case .online: return codeStalled ? l10n["phone_code_expired"] : l10n["phone_hatch_line"]
        }
    }

    // MARK: - Pairing

    @ViewBuilder
    private var pairingBody: some View {
        HStack(alignment: .top, spacing: 18) {
            ZStack {
                RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Color.white)
                if let code = liveCode, let qr = PairingQR.image(relay: relayURL, code: code.code) {
                    Image(nsImage: qr)
                        .interpolation(.none)
                        .resizable()
                        .padding(11)
                } else if codeStalled {
                    Image(systemName: "clock.badge.exclamationmark")
                        .font(.system(size: 28, weight: .regular))
                        .foregroundStyle(.black.opacity(0.35))
                } else {
                    ProgressView().controlSize(.small).colorScheme(.light)
                }
            }
            .frame(width: 164, height: 164)

            VStack(alignment: .leading, spacing: 6) {
                Text(l10n["phone_code"])
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.white.opacity(0.45))
                Text(liveCode.map { PairingQR.spaced($0.code) } ?? "···· ····")
                    .font(.system(size: 24, weight: .semibold, design: .monospaced))
                    .tracking(1)
                    .foregroundStyle(.white.opacity(0.95))
                    .textSelection(.enabled)
                Text(liveCode.map { String(format: l10n["phone_valid_for"], PairingQR.clock(remaining($0))) }
                     ?? l10n[codeStalled ? "phone_code_expired_short" : "phone_generating"])
                    .font(.system(size: 11, design: .monospaced))
                    .monospacedDigit()
                    .foregroundStyle((liveCode.map(remaining) ?? 999) < 60 ? Color(red: 0.91, green: 0.64, blue: 0.24) : .white.opacity(0.45))
                Text(l10n["phone_instructions"])
                    .font(.system(size: 12))
                    .foregroundStyle(.white.opacity(0.55))
                    .lineSpacing(2)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 6)
                HStack {
                    Spacer()
                    // The main action once the code is gone; a quiet extra while one is showing.
                    PanelButton(title: l10n[codeStalled ? "phone_generate" : "phone_new_code"], primary: codeStalled) {
                        justPaired = nil
                        // Someone is here and asked: the automatic renewals start over.
                        autoRenewals = 0
                        requestCode()
                    }
                }
                .padding(.top, 8)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func remaining(_ code: MobileBridge.PairingCode) -> Int {
        max(0, Int(code.expiresAt.timeIntervalSince(now)))
    }

    @ViewBuilder
    private var offlineBody: some View {
        HStack {
            Spacer()
            if enabled, case .failed = bridge.state {
                PanelButton(title: l10n["phone_retry"]) { bridge.restart() }
            }
            PanelButton(title: l10n["phone_open_settings"]) { SettingsWindowController.shared.show() }
        }
    }

    // MARK: - Devices

    private var devicesBody: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(l10n["phone_paired_list"])
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.white.opacity(0.45))
            ForEach(bridge.pairedDevices) { device in
                HStack(spacing: 10) {
                    Circle()
                        .fill(isRecent(device) ? Color(red: 0.37, green: 0.81, blue: 0.42) : .white.opacity(0.25))
                        .frame(width: 7, height: 7)
                    Text(device.name)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.9))
                        .lineLimit(1)
                    Text(seen(device))
                        .font(.system(size: 12))
                        .foregroundStyle(.white.opacity(0.45))
                        .lineLimit(1)
                    Spacer(minLength: 8)
                    Button { bridge.revoke(deviceId: device.id) } label: {
                        Text(l10n["phone_disconnect"])
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(Color(red: 1.0, green: 0.54, blue: 0.54))
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .background(
                    RoundedRectangle(cornerRadius: 14, style: .continuous).fill(.white.opacity(0.04))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(.white.opacity(0.06), lineWidth: 1)
                )
            }
        }
    }

    private func isRecent(_ device: MobileBridge.PairedDevice) -> Bool {
        guard let seen = device.lastSeen else { return false }
        return now.timeIntervalSince(seen) < 120
    }

    private func seen(_ device: MobileBridge.PairedDevice) -> String {
        guard let date = device.lastSeen else { return l10n["phone_never"] }
        if isRecent(device) { return l10n["phone_connected_now"] }
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .short
        formatter.locale = Locale(identifier: l10n.effectiveLanguage == "pt" ? "pt_BR" : "en_US")
        return String(format: l10n["phone_last_seen"], formatter.localizedString(for: date, relativeTo: now))
    }
}

/// The panel's button: quiet grey, or white with black text for the one main action of a
/// view, the same pair the approval cards use.
struct PanelButton: View {
    let title: String
    var primary: Bool = false
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(primary ? Color.black : Color.white.opacity(0.85))
                .padding(.horizontal, 12)
                .frame(height: 28)
                .background(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(primary ? Color.white.opacity(hovering ? 1 : 0.92) : Color.white.opacity(hovering ? 0.11 : 0.07))
                )
                .contentShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
    }
}

/// The QR the phone scans: the relay and the code, as JSON, which is what the app reads.
enum PairingQR {
    static func image(relay: String, code: String) -> NSImage? {
        let payload: [String: String] = ["relay": relay, "pair": code]
        guard let data = try? JSONSerialization.data(withJSONObject: payload, options: [.sortedKeys]) else { return nil }

        let filter = CIFilter.qrCodeGenerator()
        filter.message = data
        filter.correctionLevel = "M"
        guard let output = filter.outputImage else { return nil }

        // Integer scale so module edges land on pixel boundaries.
        let scaled = output.transformed(by: CGAffineTransform(scaleX: 10, y: 10))
        guard let cgImage = CIContext().createCGImage(scaled, from: scaled.extent) else { return nil }
        return NSImage(cgImage: cgImage, size: NSSize(width: scaled.extent.width, height: scaled.extent.height))
    }

    /// "K7Q2M9XA" as "K7Q2 M9XA", the way the phone shows its eight boxes.
    static func spaced(_ code: String) -> String {
        guard code.count == 8 else { return code }
        return String(code.prefix(4)) + " " + String(code.suffix(4))
    }

    static func clock(_ seconds: Int) -> String {
        String(format: "%d:%02d", seconds / 60, seconds % 60)
    }
}

/// A relay or bridge failure as one short sentence. The raw text ("relay speaks protocol v2",
/// a URLSession error, whatever the relay sent) meant nothing to most people and came in
/// English; the UI shows this and keeps the raw text for a tooltip.
enum RelayErrorText {
    static func friendly(_ raw: String) -> String {
        let l10n = L10n.shared
        let text = raw.lowercased()
        func has(_ words: String...) -> Bool { words.contains { text.contains($0) } }

        if has("not configured") { return l10n["relay_err_not_configured"] }
        if has("protocol") { return l10n["relay_err_protocol"] }
        if has("token", "unauthor", "forbidden", "auth", "401", "403", "denied") { return l10n["relay_err_auth"] }
        if has("timed out", "timeout", "tempo limite", "esgotou") { return l10n["relay_err_timeout"] }
        if has("offline", "internet", "network", "rede", "host", "dns", "could not connect", "não foi possível conectar") {
            return l10n["relay_err_unreachable"]
        }
        return l10n["relay_err_generic"]
    }
}
