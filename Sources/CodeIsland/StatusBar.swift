import SwiftUI
import AppKit

/// Compact pill at the top of the expanded panel reporting Anthropic
/// service status. Click to open status.claude.com.
struct StatusBar: View {
    @ObservedObject private var monitor = AnthropicStatusMonitor.shared

    @State private var hovering = false

    var body: some View {
        if let s = monitor.status {
            // A Button rather than a tap gesture, so keyboard and VoiceOver can reach it too.
            Button(action: openStatusPage) {
                HStack(spacing: 6) {
                    Circle()
                        .fill(s.color)
                        .frame(width: 6, height: 6)

                    Text("Anthropic")
                        .font(.system(size: 10, weight: .medium))
                        .tracking(0.2)
                        .foregroundStyle(.white.opacity(0.45))

                    Text(summary(for: s))
                        .font(.system(size: 10, weight: .medium))
                        .tracking(0.2)
                        .foregroundStyle(s.color.opacity(0.95))
                        .lineLimit(1)
                        .truncationMode(.tail)

                    if !s.degradedComponents.isEmpty {
                        Text("·")
                            .foregroundStyle(.white.opacity(0.20))
                        Text(degradedSummary(s.degradedComponents))
                            .font(.system(size: 10))
                            .foregroundStyle(.white.opacity(0.55))
                            .lineLimit(1)
                            .truncationMode(.tail)
                    }

                    if !s.incidents.isEmpty {
                        Text("·")
                            .foregroundStyle(.white.opacity(0.20))
                        Text(String(format: L10n.shared[s.incidents.count == 1 ? "status_incident_one" : "status_incident_many"], s.incidents.count))
                            .font(.system(size: 10, weight: .medium))
                            .foregroundStyle(s.color.opacity(0.85))
                    }

                    Spacer(minLength: 0)

                    // The way out to the status page, only under the mouse.
                    Image(systemName: "arrow.up.right.square")
                        .font(.system(size: 9))
                        .foregroundStyle(.white.opacity(0.35))
                        .opacity(hovering ? 1 : 0)
                }
                .frame(height: 14)
                .padding(.horizontal, 16)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .onHover { hovering = $0 }
            .help(tooltip(for: s))
            .accessibilityLabel("Anthropic: \(summary(for: s))")
            .accessibilityHint(L10n.shared["a11y_open_status"])
        }
    }

    private func openStatusPage() {
        if let url = URL(string: "https://status.claude.com") {
            NSWorkspace.shared.open(url)
        }
    }

    /// Statuspage reports one of five levels; each gets a short line in the app's language
    /// instead of the page's English sentence.
    private func summary(for s: AnthropicStatus) -> String {
        switch s.indicator {
        case "none": return L10n.shared["status_none"]
        case "minor": return L10n.shared["status_minor"]
        case "major": return L10n.shared["status_major"]
        case "critical": return L10n.shared["status_critical"]
        case "maintenance": return L10n.shared["status_maintenance"]
        default: return s.description
        }
    }

    private func degradedSummary(_ components: [AnthropicStatus.Component]) -> String {
        let names = components.prefix(2).map { $0.name }
        let suffix = components.count > 2 ? " +\(components.count - 2)" : ""
        return names.joined(separator: ", ") + suffix
    }

    private func tooltip(for s: AnthropicStatus) -> String {
        var lines: [String] = [s.description]
        for c in s.degradedComponents.prefix(8) {
            lines.append("  • \(c.name): \(humanize(c.status))")
        }
        for i in s.incidents.prefix(4) {
            lines.append("  ! \(i.name) (\(i.status))")
        }
        return lines.joined(separator: "\n")
    }

    private func humanize(_ s: String) -> String {
        s.replacingOccurrences(of: "_", with: " ")
    }
}
