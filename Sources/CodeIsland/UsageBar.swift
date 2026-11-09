import SwiftUI

/// Slim row at the top of the expanded panel showing live rate-limit usage
/// for Claude (5h + 7d windows) and Codex (primary + secondary windows).
struct UsageBar: View {
    @ObservedObject private var codex = CodexUsageMonitor.shared
    @ObservedObject private var claude = ClaudeRateLimitReader.shared

    // Cor de cada CLI. A barra herda a cor da fonte enquanto o uso está normal,
    // para Claude e Codex se distinguirem de relance; quando o consumo sobe, o
    // alerta vence a identidade (ver `colorFor(pct:accent:)`).
    private static let claudeColor = Color(red: 0.85, green: 0.47, blue: 0.34)
    private static let codexColor  = Color(red: 0.35, green: 0.60, blue: 0.95)

    var body: some View {
        let hasClaude = claude.limits != nil
        let hasCodex = !(codex.snapshot?.isEmpty ?? true)
        HStack(spacing: 0) {
            if let lim = claude.limits {
                claudeSegment(limits: lim)
            }
            if hasClaude && hasCodex {
                // A hairline between the two agents instead of a wide gap.
                Rectangle()
                    .fill(.white.opacity(0.1))
                    .frame(width: 1, height: 10)
                    .padding(.horizontal, 12)
            }
            if let snap = codex.snapshot, !snap.isEmpty {
                codexSegment(snapshot: snap)
            }
            if !hasClaude && !hasCodex {
                Text(claude.isInstalled ? L10n.shared["usage_waiting"] : L10n.shared["usage_per_card"])
                    .font(.system(size: 10))
                    .tracking(0.2)
                    .foregroundStyle(.white.opacity(0.30))
            }
            Spacer(minLength: 0)
        }
        .frame(height: 14)
        .padding(.horizontal, 16)
    }

    @ViewBuilder
    private func claudeSegment(limits: ClaudeRateLimits) -> some View {
        HStack(spacing: 8) {
            sourceTag("Claude", color: Self.claudeColor)
            if let pct = limits.fiveHourPercent {
                window(label: "5h", pct: pct, resetsAt: limits.fiveHourResetAt, accent: Self.claudeColor)
            }
            if let pct = limits.sevenDayPercent, pct >= 1 {
                window(label: "7d", pct: pct, resetsAt: limits.sevenDayResetAt, accent: Self.claudeColor)
            }
        }
    }

    @ViewBuilder
    private func codexSegment(snapshot: CodexUsageSnapshot) -> some View {
        HStack(spacing: 8) {
            sourceTag("Codex", color: Self.codexColor)
            ForEach(snapshot.windows) { w in
                window(
                    label: w.label,
                    pct: w.roundedUsedPercentage,
                    resetsAt: w.resetsAt,
                    accent: Self.codexColor
                )
            }
        }
    }

    @ViewBuilder
    private func sourceTag(_ name: String, color: Color) -> some View {
        Text(name.capitalized)
            .font(.system(size: 10, weight: .semibold))
            .foregroundStyle(color.opacity(0.9))
            .fixedSize()
    }

    /// Label, bar, percentage and, when known, when the window starts over. Every window
    /// has the same bar and the same number width, so the row lines up.
    @ViewBuilder
    private func window(label: String, pct: Int, resetsAt: Date?, accent: Color) -> some View {
        let accent = colorFor(pct: pct, accent: accent)
        HStack(spacing: 6) {
            // Fixed size: when the row is tight SwiftUI squeezed these labels to nothing.
            Text(verbatim: label)
                .font(.system(size: 9, weight: .medium, design: .monospaced))
                .tracking(0.2)
                .foregroundStyle(.white.opacity(0.38))
                .fixedSize()
            ProgressTrack(pct: pct, color: accent)
                .frame(width: 40, height: 3)
            Text("\(pct)%")
                .font(.system(size: 10, weight: .semibold, design: .monospaced))
                .foregroundStyle(accent.opacity(0.95))
                .monospacedDigit()
                .fixedSize()
                .frame(minWidth: 26, alignment: .leading)
            if let t = resetTimeShort(resetsAt) {
                Text(String(format: L10n.shared["usage_resets_in"], t))
                    .font(.system(size: 9, design: .monospaced))
                    .tracking(0.2)
                    .foregroundStyle(.white.opacity(0.28))
                    .lineLimit(1)
                    .layoutPriority(-1)
            }
        }
    }

    /// Alerta acima de 70%, cor da fonte abaixo disso.
    ///
    /// Abaixo do limiar as barras carregam a identidade do CLI, senão Claude e
    /// Codex ficam idênticos e só o badge os distingue. A partir de 70% o
    /// alerta assume: aí o que importa é o consumo, não de quem ele é.
    private func colorFor(pct: Int, accent: Color) -> Color {
        if pct >= 90 { return Color(red: 0.95, green: 0.30, blue: 0.30) }
        if pct >= 70 { return Color(red: 1.0,  green: 0.65, blue: 0.25) }
        return accent
    }

    private func resetTimeShort(_ date: Date?) -> String? {
        guard let date else { return nil }
        let r = date.timeIntervalSinceNow
        if r <= 0 { return nil }
        if r < 3600 { return "\(Int(r / 60))m" }
        if r < 86400 {
            let h = Int(r / 3600)
            let m = Int(r.truncatingRemainder(dividingBy: 3600) / 60)
            return m > 0 ? "\(h)h\(m)m" : "\(h)h"
        }
        return "\(Int(r / 86400))d"
    }
}

private struct ProgressTrack: View {
    let pct: Int
    let color: Color

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: 1.5)
                    .fill(color.opacity(0.2))
                RoundedRectangle(cornerRadius: 1.5)
                    .fill(color)
                    .frame(width: geo.size.width * CGFloat(min(max(pct, 0), 100)) / 100.0)
            }
        }
    }
}
