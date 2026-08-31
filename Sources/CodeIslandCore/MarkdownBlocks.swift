import Foundation

/// One renderable chunk of an agent's message.
///
/// Agents write markdown, and until now the chat showed it raw: `**Status**` with the asterisks,
/// backticks around every path, bullets as literal hyphens. Full markdown is far more than the
/// conversation needs, so this covers what agents actually emit — headings, bullets, fenced code,
/// paragraphs — and leaves inline styling (bold, italic, code spans, links) to each platform's
/// own inline renderer, which both already have.
public enum MarkdownBlock: Equatable {
    case paragraph(String)
    case heading(level: Int, text: String)
    /// `marker` is the bullet glyph or the ordinal ("•", "1."), already resolved for display.
    case bullet(marker: String, text: String, indent: Int)
    case code(language: String?, text: String)
    /// A pipe table. `headers` may be empty when the first column has no title, which is how
    /// agents usually write a comparison table.
    case table(headers: [String], rows: [[String]])
    case rule
}

/// Collapses a turn's tool calls into one chip per tool.
///
/// A turn that ran Bash six times used to draw six identical chips, which says nothing the first
/// chip did not. Order of first use is kept, because it is the order the agent worked in.
public enum ToolSummary {
    public struct Entry: Equatable, Hashable {
        public let name: String
        public let count: Int

        public init(name: String, count: Int) {
            self.name = name
            self.count = count
        }

        public var label: String { count > 1 ? "\(name) ×\(count)" : name }
    }

    public static func summarize(_ tools: [String]) -> [Entry] {
        var order: [String] = []
        var counts: [String: Int] = [:]
        for tool in tools {
            let name = shortName(tool)
            if counts[name] == nil { order.append(name) }
            counts[name, default: 0] += 1
        }
        return order.map { Entry(name: $0, count: counts[$0] ?? 1) }
    }

    /// Trims the plumbing off an MCP tool name.
    ///
    /// `mcp__Claude_Browser__computer` is mostly punctuation announcing that it came from MCP,
    /// which the reader already knows and which pushes the part that identifies the tool past
    /// the edge of the chip. The phone applies the same rule.
    public static func shortName(_ raw: String) -> String {
        var name = raw
        if name.hasPrefix("mcp__") { name.removeFirst("mcp__".count) }
        return name.replacingOccurrences(of: "__", with: "·")
    }
}

public enum MarkdownBlockParser {
    /// Splits a message into blocks. Never fails: anything unrecognised stays a paragraph, so the
    /// worst case is the text people see today.
    public static func blocks(_ text: String) -> [MarkdownBlock] {
        var blocks: [MarkdownBlock] = []
        var paragraph: [String] = []
        var fence: (language: String?, lines: [String])?
        var tableRows: [[String]] = []

        func flushParagraph() {
            let joined = paragraph.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
            if !joined.isEmpty { blocks.append(.paragraph(joined)) }
            paragraph = []
        }

        /// A table is recognised only once it ends, because until then it is indistinguishable
        /// from prose that happens to contain pipes.
        func flushTable() {
            defer { tableRows = [] }
            guard !tableRows.isEmpty else { return }

            // A divider row (`|---|---|`) marks the row above it as headers. Without one there
            // are no headers, only rows.
            var rows = tableRows
            var headers: [String] = []
            if rows.count >= 2, rows[1].allSatisfy(isDivider) {
                headers = rows[0]
                rows.removeSubrange(0...1)
            } else if rows.count >= 1, rows[0].allSatisfy(isDivider) {
                rows.removeFirst()
            }

            guard !rows.isEmpty else {
                if !headers.isEmpty { blocks.append(.table(headers: [], rows: [headers])) }
                return
            }
            blocks.append(.table(headers: headers, rows: rows))
        }

        for raw in text.components(separatedBy: "\n") {
            let trimmed = raw.trimmingCharacters(in: .whitespaces)

            // A fence swallows everything until it closes, including lines that would otherwise
            // look like headings or bullets — that is the whole point of a code block.
            if trimmed.hasPrefix("```") {
                if var open = fence {
                    blocks.append(.code(language: open.language, text: open.lines.joined(separator: "\n")))
                    open.lines = []
                    fence = nil
                } else {
                    flushParagraph()
                    let language = String(trimmed.dropFirst(3)).trimmingCharacters(in: .whitespaces)
                    fence = (language.isEmpty ? nil : language, [])
                }
                continue
            }
            if fence != nil {
                fence?.lines.append(raw)
                continue
            }

            if let cells = tableRow(trimmed) {
                flushParagraph()
                tableRows.append(cells)
                continue
            }
            flushTable()

            if trimmed.isEmpty {
                flushParagraph()
                continue
            }

            if let heading = heading(trimmed) {
                flushParagraph()
                blocks.append(heading)
                continue
            }

            if trimmed == "---" || trimmed == "***" || trimmed == "___" {
                flushParagraph()
                blocks.append(.rule)
                continue
            }

            if let bullet = bullet(raw) {
                flushParagraph()
                blocks.append(bullet)
                continue
            }

            paragraph.append(raw)
        }

        flushTable()

        // An unterminated fence still has content worth showing.
        if let open = fence {
            blocks.append(.code(language: open.language, text: open.lines.joined(separator: "\n")))
        }
        flushParagraph()

        return blocks
    }

    /// Cells of a pipe-delimited row, or nil when the line is not one.
    ///
    /// Requires a leading pipe: prose with a pipe in the middle of it is prose, and treating it
    /// as a table would mangle far more messages than it would improve.
    private static func tableRow(_ trimmed: String) -> [String]? {
        guard trimmed.hasPrefix("|"), trimmed.count > 1 else { return nil }
        var body = trimmed.dropFirst()
        if body.hasSuffix("|") { body = body.dropLast() }
        return body.components(separatedBy: "|").map {
            $0.trimmingCharacters(in: .whitespaces)
        }
    }

    private static func isDivider(_ cell: String) -> Bool {
        !cell.isEmpty && cell.allSatisfy { $0 == "-" || $0 == ":" || $0 == " " }
    }

    private static func heading(_ trimmed: String) -> MarkdownBlock? {
        let hashes = trimmed.prefix(while: { $0 == "#" }).count
        guard hashes >= 1, hashes <= 6 else { return nil }
        let rest = trimmed.dropFirst(hashes)
        guard rest.first == " " else { return nil }
        return .heading(level: hashes, text: rest.trimmingCharacters(in: .whitespaces))
    }

    private static func bullet(_ raw: String) -> MarkdownBlock? {
        let leading = raw.prefix(while: { $0 == " " || $0 == "\t" }).count
        let indent = min(leading / 2, 3)
        let trimmed = raw.trimmingCharacters(in: .whitespaces)

        for marker in ["- ", "* ", "+ "] where trimmed.hasPrefix(marker) {
            return .bullet(
                marker: "•",
                text: String(trimmed.dropFirst(marker.count)).trimmingCharacters(in: .whitespaces),
                indent: indent
            )
        }

        // Ordered items keep their own number so a list that starts at 3 still reads as 3.
        let digits = trimmed.prefix(while: \.isNumber)
        guard !digits.isEmpty, digits.count <= 3 else { return nil }
        let afterDigits = trimmed.dropFirst(digits.count)
        guard afterDigits.hasPrefix(". ") || afterDigits.hasPrefix(") ") else { return nil }
        return .bullet(
            marker: "\(digits).",
            text: String(afterDigits.dropFirst(2)).trimmingCharacters(in: .whitespaces),
            indent: indent
        )
    }
}
