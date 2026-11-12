import SwiftUI

/// Settings page that surfaces the user's Claude Code buddy (companion): its name,
/// personality, rarity and stats from `~/.claude.json`. The buddy is drawn as Hatch; the
/// species only flavours what it says.
struct BuddyPage: View {
    private var pt: Bool { L10n.shared.effectiveLanguage == "pt" }
    @ObservedObject private var l10n = L10n.shared
    @ObservedObject private var reader = BuddyReader.shared
    @State private var isPetting = false

    var body: some View {
        Form {
            if let buddy = reader.buddy {
                Section {
                    HStack(alignment: .top, spacing: 24) {
                        // Sprite card (dark backdrop, like MioIsland). Petting Hatch is a
                        // control, so it is a Button and works from the keyboard too.
                        Button(action: petHatch) {
                            VStack {
                                MascotView(source: "claude", status: .idle, size: 72, global: true)
                                    .padding(.vertical, 22)
                                    .padding(.horizontal, 34)
                            }
                            .background(
                                RoundedRectangle(cornerRadius: 12, style: .continuous)
                                    .fill(Color.black.opacity(0.85))
                            )
                            .frame(minWidth: 160)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Hatch")
                        .accessibilityHint(L10n.shared["a11y_pet_hatch"])

                        // Identity column
                        VStack(alignment: .leading, spacing: 10) {
                            HStack(spacing: 8) {
                                Text(buddy.name)
                                    .font(.system(size: 18, weight: .bold))
                                if buddy.isShiny {
                                    Text(l10n["buddy_shiny"])
                                        .font(.system(size: 11, weight: .semibold))
                                        .foregroundStyle(.yellow)
                                }
                            }
                            Text(buddy.hatchPersonality(pt: pt))
                                .font(.system(size: 12))
                                .foregroundStyle(.secondary)
                                .lineLimit(3)
                                .fixedSize(horizontal: false, vertical: true)

                            HStack(spacing: 6) {
                                Text(buddy.rarity.displayName)
                                    .font(.system(size: 11, weight: .semibold, design: .monospaced))
                                    .foregroundStyle(buddy.rarity.color)
                            }
                            if let hatchedAt = buddy.hatchedAt {
                                Text(String(format: l10n["buddy_hatched_on"], hatchedAt.formatted(date: .abbreviated, time: .omitted)))
                                    .font(.system(size: 10, design: .monospaced))
                                    .foregroundStyle(.tertiary)
                            }
                        }
                        Spacer()
                    }
                    .padding(.vertical, 6)
                } header: {
                    Text(l10n["buddy_section"])
                }

                Section {
                    StatBar(name: "DEBUGGING", value: buddy.stats.debugging, color: .blue)
                    StatBar(name: "PATIENCE",  value: buddy.stats.patience,  color: .green)
                    StatBar(name: "CHAOS",     value: buddy.stats.chaos,     color: .red)
                    StatBar(name: "WISDOM",    value: buddy.stats.wisdom,    color: .purple)
                    StatBar(name: "SNARK",     value: buddy.stats.snark,     color: .orange)
                } header: {
                    Text(l10n["buddy_stats"])
                } footer: {
                    Text(l10n["buddy_stats_footer"])
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }

                Section {
                    Button(l10n["buddy_reload_from"]) {
                        reader.reload()
                    }
                }
            } else {
                Section {
                    VStack(alignment: .leading, spacing: 10) {
                        HStack {
                            Image(systemName: "pawprint.circle")
                                .font(.system(size: 28))
                                .foregroundStyle(.tertiary)
                            VStack(alignment: .leading) {
                                Text(l10n["buddy_none_title"])
                                    .font(.system(size: 14, weight: .semibold))
                                // LocalizedStringKey so the backticks still render as code, as the literal did.
                                Text(LocalizedStringKey(l10n["buddy_none_body"]))
                                    .font(.system(size: 12))
                                    .foregroundStyle(.secondary)
                            }
                        }
                        Button(l10n["buddy_reload"]) { reader.reload() }
                    }
                    .padding(.vertical, 4)
                }
            }
        }
        .formStyle(.grouped)
    }

    private func petHatch() {
        HatchReaction.wave.post()
        withAnimation(.easeInOut(duration: 0.2)) { isPetting = true }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.4) {
            withAnimation(.easeInOut(duration: 0.2)) { isPetting = false }
        }
    }
}

private struct StatBar: View {
    let name: String
    let value: Int
    let color: Color

    var body: some View {
        HStack(spacing: 12) {
            Text(name)
                .font(.system(size: 11, weight: .semibold, design: .monospaced))
                .frame(width: 90, alignment: .leading)
                .foregroundStyle(.secondary)

            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 4)
                        .fill(Color.secondary.opacity(0.15))
                    RoundedRectangle(cornerRadius: 4)
                        .fill(color.gradient)
                        .frame(width: geo.size.width * CGFloat(min(max(value, 0), 100)) / 100.0)
                }
            }
            .frame(height: 8)

            Text("\(value)")
                .font(.system(size: 11, design: .monospaced))
                .frame(width: 32, alignment: .trailing)
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 2)
    }
}
