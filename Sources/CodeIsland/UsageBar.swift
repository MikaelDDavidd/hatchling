import SwiftUI

/// Slim row at the top of the expanded panel showing live rate-limit usage
/// for Claude (5h + 7d windows) and Codex (primary + secondary windows).
struct UsageBar: View {
    @ObservedObject private var codex = CodexUsageMonitor.shared
    @ObservedObject private var claude = ClaudeRateLimitReader.shared

    var body: some View {
        HStack(spacing: 14) {
            if let lim = claude.limits {
                claudeSegment(limits: lim)
            }
            if let snap = codex.snapshot, !snap.isEmpty {
                codexSegment(snapshot: snap)
            }
            if claude.limits == nil && (codex.snapshot?.isEmpty ?? true) {
                Text(claude.isInstalled
                     ? "waiting for first Claude turn…"
                     : "per-session context % shown on each card")
                    .font(.system(size: 9, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.30))
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 6)
    }

    @ViewBuilder
    private func claudeSegment(limits: ClaudeRateLimits) -> some View {
        HStack(spacing: 8) {
            sourceTag("Claude", color: Color(red: 0.85, green: 0.47, blue: 0.34))
            if let pct = limits.fiveHourPercent {
                window(label: "5h", pct: pct, resetsAt: limits.fiveHourResetAt)
            }
            if let pct = limits.sevenDayPercent, pct >= 1 {
                window(label: "7d", pct: pct, resetsAt: limits.sevenDayResetAt)
            }
        }
    }

    @ViewBuilder
    private func codexSegment(snapshot: CodexUsageSnapshot) -> some View {
        HStack(spacing: 8) {
            sourceTag("Codex", color: Color(red: 0.42, green: 0.78, blue: 0.50))
            ForEach(snapshot.windows) { w in
                window(
                    label: w.label,
                    pct: w.roundedUsedPercentage,
                    resetsAt: w.resetsAt
                )
            }
        }
    }

    @ViewBuilder
    private func sourceTag(_ name: String, color: Color) -> some View {
        Text(name.uppercased())
            .font(.system(size: 9, weight: .bold, design: .monospaced))
            .foregroundStyle(color.opacity(0.85))
            .padding(.horizontal, 5)
            .padding(.vertical, 1)
            .background(Capsule().fill(color.opacity(0.12)))
    }

    @ViewBuilder
    private func window(label: String, pct: Int, resetsAt: Date?) -> some View {
        let accent = colorFor(pct: pct)
        HStack(spacing: 5) {
            Text(label)
                .font(.system(size: 9, weight: .semibold, design: .monospaced))
                .foregroundStyle(.white.opacity(0.45))
            ProgressTrack(pct: pct, color: accent)
                .frame(width: 44, height: 4)
            Text("\(pct)%")
                .font(.system(size: 10, weight: .semibold, design: .monospaced))
                .foregroundStyle(accent.opacity(0.95))
                .frame(width: 30, alignment: .trailing)
                .monospacedDigit()
            if let t = resetTimeShort(resetsAt) {
                Text(t)
                    .font(.system(size: 9, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.35))
            }
        }
    }

    private func colorFor(pct: Int) -> Color {
        if pct >= 90 { return Color(red: 0.95, green: 0.30, blue: 0.30) }
        if pct >= 70 { return Color(red: 1.0,  green: 0.65, blue: 0.25) }
        return Color(red: 0.36, green: 0.85, blue: 0.50)
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
                RoundedRectangle(cornerRadius: 2)
                    .fill(color.opacity(0.15))
                RoundedRectangle(cornerRadius: 2)
                    .fill(color.gradient)
                    .frame(width: geo.size.width * CGFloat(min(max(pct, 0), 100)) / 100.0)
            }
        }
    }
}
