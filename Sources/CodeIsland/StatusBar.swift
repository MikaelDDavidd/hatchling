import SwiftUI
import AppKit

/// Compact pill at the top of the expanded panel reporting Anthropic
/// service status. Click to open status.claude.com.
struct StatusBar: View {
    @ObservedObject private var monitor = AnthropicStatusMonitor.shared

    var body: some View {
        if let s = monitor.status {
            HStack(spacing: 6) {
                Circle()
                    .fill(s.color)
                    .frame(width: 6, height: 6)

                Text("Anthropic:")
                    .font(.system(size: 9, weight: .medium, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.45))

                Text(s.description)
                    .font(.system(size: 9, weight: .semibold, design: .monospaced))
                    .foregroundStyle(s.color.opacity(0.95))
                    .lineLimit(1)
                    .truncationMode(.tail)

                if !s.degradedComponents.isEmpty {
                    Text("·")
                        .foregroundStyle(.white.opacity(0.20))
                    Text(degradedSummary(s.degradedComponents))
                        .font(.system(size: 9, design: .monospaced))
                        .foregroundStyle(.white.opacity(0.55))
                        .lineLimit(1)
                        .truncationMode(.tail)
                }

                if !s.incidents.isEmpty {
                    Text("·")
                        .foregroundStyle(.white.opacity(0.20))
                    Text("\(s.incidents.count) incident\(s.incidents.count == 1 ? "" : "s")")
                        .font(.system(size: 9, weight: .semibold, design: .monospaced))
                        .foregroundStyle(s.color.opacity(0.85))
                }

                Spacer(minLength: 0)

                Image(systemName: "arrow.up.right.square")
                    .font(.system(size: 9))
                    .foregroundStyle(.white.opacity(0.30))
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 4)
            .contentShape(Rectangle())
            .onTapGesture {
                if let url = URL(string: "https://status.claude.com") {
                    NSWorkspace.shared.open(url)
                }
            }
            .help(tooltip(for: s))
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
            lines.append("  ⚠ \(i.name) (\(i.status))")
        }
        return lines.joined(separator: "\n")
    }

    private func humanize(_ s: String) -> String {
        s.replacingOccurrences(of: "_", with: " ")
    }
}
