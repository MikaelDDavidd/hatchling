import SwiftUI

/// Settings page that surfaces the user's Claude Code buddy (companion):
/// species, rarity, stats and an animated ASCII sprite — all derived
/// deterministically from `~/.claude.json` via BuddyReader.
struct BuddyPage: View {
    @ObservedObject private var reader = BuddyReader.shared
    @State private var isPetting = false

    var body: some View {
        Form {
            if let buddy = reader.buddy {
                Section {
                    HStack(alignment: .top, spacing: 24) {
                        // Sprite card (dark backdrop, like MioIsland)
                        VStack {
                            BuddyASCIIView(buddy: buddy, isPetting: isPetting)
                                .padding(.vertical, 14)
                                .padding(.horizontal, 18)
                        }
                        .background(
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .fill(Color.black.opacity(0.85))
                        )
                        .frame(minWidth: 160)
                        .onTapGesture {
                            withAnimation(.easeInOut(duration: 0.2)) { isPetting = true }
                            DispatchQueue.main.asyncAfter(deadline: .now() + 1.4) {
                                withAnimation(.easeInOut(duration: 0.2)) { isPetting = false }
                            }
                        }

                        // Identity column
                        VStack(alignment: .leading, spacing: 10) {
                            HStack(spacing: 8) {
                                Text(buddy.species.emoji)
                                Text(buddy.name)
                                    .font(.system(size: 18, weight: .bold))
                                if buddy.isShiny {
                                    Text("✨ shiny")
                                        .font(.system(size: 11, weight: .semibold, design: .monospaced))
                                        .foregroundStyle(.yellow)
                                        .padding(.horizontal, 6)
                                        .padding(.vertical, 2)
                                        .background(
                                            Capsule().fill(Color.yellow.opacity(0.18))
                                        )
                                }
                            }
                            Text(buddy.personality)
                                .font(.system(size: 12))
                                .foregroundStyle(.secondary)
                                .lineLimit(3)

                            HStack(spacing: 6) {
                                Text(buddy.rarity.stars)
                                    .foregroundStyle(buddy.rarity.color)
                                    .font(.system(size: 11, design: .monospaced))
                                Text(buddy.rarity.displayName)
                                    .font(.system(size: 11, weight: .semibold, design: .monospaced))
                                    .foregroundStyle(buddy.rarity.color)
                                Text("·")
                                    .foregroundStyle(.tertiary)
                                Text("hat: \(buddy.hat)")
                                    .font(.system(size: 11, design: .monospaced))
                                    .foregroundStyle(.secondary)
                            }
                            if let hatchedAt = buddy.hatchedAt {
                                Text("hatched \(hatchedAt.formatted(date: .abbreviated, time: .omitted))")
                                    .font(.system(size: 10, design: .monospaced))
                                    .foregroundStyle(.tertiary)
                            }
                        }
                        Spacer()
                    }
                    .padding(.vertical, 6)
                } header: {
                    Text("Your Buddy")
                }

                Section {
                    StatBar(name: "DEBUGGING", value: buddy.stats.debugging, color: .blue)
                    StatBar(name: "PATIENCE",  value: buddy.stats.patience,  color: .green)
                    StatBar(name: "CHAOS",     value: buddy.stats.chaos,     color: .red)
                    StatBar(name: "WISDOM",    value: buddy.stats.wisdom,    color: .purple)
                    StatBar(name: "SNARK",     value: buddy.stats.snark,     color: .orange)
                } header: {
                    Text("Stats")
                } footer: {
                    Text("Stats são determinísticos — derivados do seu user id + salt do Claude Code via wyhash. Não mudam entre sessões.")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }

                Section {
                    Button("Reload from ~/.claude.json") {
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
                                Text("Nenhum buddy encontrado")
                                    .font(.system(size: 14, weight: .semibold))
                                Text("Roda Claude Code uma vez pra gerar `~/.claude.json` com seu companion. Depois clica em Reload.")
                                    .font(.system(size: 12))
                                    .foregroundStyle(.secondary)
                            }
                        }
                        Button("Reload") { reader.reload() }
                    }
                    .padding(.vertical, 4)
                }
            }
        }
        .formStyle(.grouped)
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
