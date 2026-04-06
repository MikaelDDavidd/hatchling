import Foundation
import CodeIslandCore

struct ResolvedSessionTitle: Sendable, Equatable {
    let title: String
    let source: SessionTitleSource
}

enum SessionTitleStore {
    static func title(for sessionId: String, provider: String) -> ResolvedSessionTitle? {
        switch provider {
        case "codex":
            guard let title = codexThreadName(sessionId: sessionId) else { return nil }
            return ResolvedSessionTitle(title: title, source: .codexThreadName)
        default:
            return nil
        }
    }

    static func codexThreadName(sessionId: String) -> String? {
        let path = NSHomeDirectory() + "/.codex/session_index.jsonl"
        guard let contents = try? String(contentsOfFile: path, encoding: .utf8) else {
            return nil
        }
        return try? codexThreadName(sessionId: sessionId, indexContents: contents)
    }

    static func codexThreadName(sessionId: String, indexContents: String) throws -> String? {
        struct Entry: Decodable {
            let id: String
            let thread_name: String?
            let updated_at: String?
        }

        let decoder = JSONDecoder()
        let iso8601 = ISO8601DateFormatter()
        var latestMatch: (updatedAt: Date, title: String)?

        for line in indexContents.split(whereSeparator: \.isNewline) {
            guard let data = String(line).data(using: .utf8),
                  let entry = try? decoder.decode(Entry.self, from: data),
                  entry.id == sessionId,
                  let rawTitle = entry.thread_name?.trimmingCharacters(in: .whitespacesAndNewlines),
                  !rawTitle.isEmpty
            else {
                continue
            }

            let updatedAt = entry.updated_at.flatMap(iso8601.date(from:)) ?? .distantPast
            if let latestMatch, latestMatch.updatedAt > updatedAt {
                continue
            }

            latestMatch = (updatedAt, rawTitle)
        }

        return latestMatch?.title
    }
}
