import SwiftUI
import CodeIslandCore

/// Renders an agent's markdown inside the notch panel.
///
/// The panel is a narrow column of monospaced text, so this stays deliberately plain: headings
/// get weight rather than size, bullets get a hanging indent, fenced code gets a tinted block.
/// Nothing here changes the reading width, because at this size an indent costs more than it
/// gives back.
struct MarkdownText: View {
    let text: String
    var size: CGFloat = 11.5
    var opacity: Double = 0.92

    private var blocks: [MarkdownBlock] { MarkdownCache.blocks(for: text) }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(Array(blocks.enumerated()), id: \.offset) { _, block in
                view(for: block)
            }
        }
        .textSelection(.enabled)
    }

    @ViewBuilder
    private func view(for block: MarkdownBlock) -> some View {
        switch block {
        case let .paragraph(text):
            inline(text)

        case let .heading(level, text):
            inline(text, size: size + (level <= 2 ? 1 : 0), weight: .bold, opacity: 1.0)
                .padding(.top, 2)

        case let .bullet(marker, text, indent):
            HStack(alignment: .top, spacing: 6) {
                Text(marker)
                    .font(.system(size: size, design: .monospaced))
                    .foregroundStyle(.white.opacity(opacity * 0.45))
                inline(text)
            }
            .padding(.leading, CGFloat(indent) * 10)

        case let .code(language, text):
            VStack(alignment: .leading, spacing: 3) {
                if let language {
                    Text(language)
                        .font(.system(size: 8, weight: .semibold, design: .monospaced))
                        .foregroundStyle(.white.opacity(0.3))
                }
                Text(text)
                    .font(.system(size: size - 0.5, design: .monospaced))
                    .foregroundStyle(.white.opacity(opacity))
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(.horizontal, 7)
            .padding(.vertical, 5)
            .background(RoundedRectangle(cornerRadius: 5).fill(.white.opacity(0.055)))

        case let .table(headers, rows):
            // Stacked, not gridded. The panel is a narrow column and a three-column table laid
            // out inside it is unreadable at any font size — so each row becomes a small block
            // led by its first cell, with the remaining columns labelled by their header.
            VStack(alignment: .leading, spacing: 7) {
                ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
                    VStack(alignment: .leading, spacing: 2) {
                        if let lead = row.first, !lead.isEmpty {
                            inline(lead, weight: .semibold, opacity: 1.0)
                        }
                        ForEach(Array(row.dropFirst().enumerated()), id: \.offset) { column, cell in
                            if !cell.isEmpty {
                                HStack(alignment: .top, spacing: 5) {
                                    if let header = headers.dropFirst(column + 1).first, !header.isEmpty {
                                        Text(header)
                                            .font(.system(size: size - 1.5, design: .monospaced))
                                            .foregroundStyle(.white.opacity(0.38))
                                    }
                                    inline(cell)
                                }
                                .padding(.leading, 8)
                            }
                        }
                    }
                }
            }

        case .rule:
            Rectangle()
                .fill(.white.opacity(0.09))
                .frame(height: 1)
                .padding(.vertical, 1)
        }
    }

    private func inline(
        _ text: String,
        size: CGFloat? = nil,
        weight: Font.Weight = .regular,
        opacity override: Double? = nil
    ) -> some View {
        Text(MarkdownCache.inline(for: text))
            .font(.system(size: size ?? self.size, weight: weight, design: .monospaced))
            .foregroundStyle(.white.opacity(override ?? opacity))
            .lineSpacing(2)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// Parsing on every redraw would be wasted work — the same turn is laid out again on every
/// scroll — so both passes are memoised per string.
private enum MarkdownCache {
    private static var blockCache: [String: [MarkdownBlock]] = [:]
    private static var inlineCache: [String: AttributedString] = [:]
    private static let limit = 256

    static func blocks(for text: String) -> [MarkdownBlock] {
        if let hit = blockCache[text] { return hit }
        let parsed = MarkdownBlockParser.blocks(text)
        if blockCache.count >= limit { blockCache.removeAll(keepingCapacity: true) }
        blockCache[text] = parsed
        return parsed
    }

    /// Bold, italics, code spans and links, with the surrounding punctuation removed.
    static func inline(for text: String) -> AttributedString {
        if let hit = inlineCache[text] { return hit }
        let parsed = (try? AttributedString(
            markdown: text,
            options: .init(
                allowsExtendedAttributes: true,
                interpretedSyntax: .inlineOnlyPreservingWhitespace,
                failurePolicy: .returnPartiallyParsedIfPossible
            )
        )) ?? AttributedString(text)
        if inlineCache.count >= limit { inlineCache.removeAll(keepingCapacity: true) }
        inlineCache[text] = parsed
        return parsed
    }
}
