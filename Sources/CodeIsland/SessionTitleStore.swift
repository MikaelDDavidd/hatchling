import Foundation
import CodeIslandCore

struct ResolvedSessionTitle: Sendable, Equatable {
    let title: String
    let source: SessionTitleSource
}

enum SessionTitleStore {
    static func supports(provider: String) -> Bool {
        switch provider {
        case "codex", "claude":
            return true
        default:
            return false
        }
    }

    static func title(for sessionId: String, provider: String, cwd: String? = nil) -> ResolvedSessionTitle? {
        switch provider {
        case "codex":
            guard let title = codexThreadName(sessionId: sessionId) else { return nil }
            return ResolvedSessionTitle(title: title, source: .codexThreadName)
        case "claude":
            return claudeTitle(sessionId: sessionId, cwd: cwd)
        default:
            return nil
        }
    }

    static func codexThreadName(sessionId: String) -> String? {
        let path = NSHomeDirectory() + "/.codex/session_index.jsonl"
        guard let stamp = FileStamp(path: path) else { return nil }
        // The index is shared by every Codex thread and only changes when one is named or
        // renamed, so a lookup against an unchanged file reuses the last answer instead of
        // reading and parsing the whole index on every hook.
        let key = "codex:\(sessionId)"
        if let cached = cache.lookup(key, stamp: stamp) { return cached?.title }
        guard let data = FileManager.default.contents(atPath: path) else { return nil }
        let title = codexThreadName(sessionId: sessionId, indexData: data)
        cache.store(key, stamp: stamp, title: title.map { ResolvedSessionTitle(title: $0, source: .codexThreadName) })
        return title
    }

    static func codexThreadName(sessionId: String, indexContents: String) throws -> String? {
        codexThreadName(sessionId: sessionId, indexData: Data(indexContents.utf8))
    }

    static func codexThreadName(sessionId: String, indexData: Data) -> String? {
        struct Entry: Decodable {
            let id: String
            let thread_name: String?
            let updated_at: String?
        }

        // Only lines that mention this session can match, so the bytes are searched first
        // and the JSON decoder runs on those few lines rather than on every thread's entry.
        let idMarker = Data(sessionId.utf8)
        guard !idMarker.isEmpty, indexData.range(of: idMarker) != nil else { return nil }

        let decoder = JSONDecoder()
        let iso8601 = ISO8601DateFormatter()
        var latestMatch: (updatedAt: Date, title: String)?

        for line in indexData.split(whereSeparator: isLineBreak) {
            guard line.range(of: idMarker) != nil,
                  let entry = try? decoder.decode(Entry.self, from: Data(line)),
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

    static func claudeTitle(sessionId: String, cwd: String?) -> ResolvedSessionTitle? {
        guard let cwd else { return nil }

        let projectDir = cwd.claudeProjectDirEncoded()
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let path = "\(home)/.claude/projects/\(projectDir)/\(sessionId).jsonl"

        // The transcript only needs reading again once it has changed on disk.
        guard let stamp = FileStamp(path: path) else { return nil }
        let key = "claude:\(path)"
        if let cached = cache.lookup(key, stamp: stamp) { return cached }

        let resolved = readClaudeTitle(atPath: path)
        cache.store(key, stamp: stamp, title: resolved)
        return resolved
    }

    private static func readClaudeTitle(atPath path: String) -> ResolvedSessionTitle? {
        guard let handle = FileHandle(forReadingAtPath: path) else {
            return nil
        }
        defer { handle.closeFile() }

        let fileSize = handle.seekToEndOfFile()
        let readSize: UInt64 = min(fileSize, 65536)

        handle.seek(toFileOffset: 0)
        let headData = handle.readData(ofLength: Int(readSize))

        let tailData: Data
        if fileSize > readSize {
            handle.seek(toFileOffset: fileSize - readSize)
            tailData = handle.readDataToEndOfFile()
        } else {
            tailData = headData
        }

        // The windows are scanned as bytes, line by line. Decoding a whole window as one
        // String failed whenever the 64 KB cut landed inside a multi-byte character, which
        // blanked the title; now only the cut line itself is skipped.
        let tailTitles = latestClaudeTitles(in: tailData)
        let headTitles = latestClaudeTitles(in: headData)

        if let customTitle = tailTitles.custom ?? headTitles.custom {
            return ResolvedSessionTitle(title: customTitle, source: .claudeCustomTitle)
        }
        if let aiTitle = tailTitles.ai ?? headTitles.ai {
            return ResolvedSessionTitle(title: aiTitle, source: .claudeAiTitle)
        }
        return nil
    }

    private static let customTitleMarker = Data("custom-title".utf8)
    private static let aiTitleMarker = Data("ai-title".utf8)

    static func latestClaudeTitles(in contents: Data) -> (custom: String?, ai: String?) {
        // Title entries are rare in a transcript, so the JSON parser only runs on lines whose
        // bytes mention one; a window without either marker is skipped outright.
        guard contents.range(of: customTitleMarker) != nil || contents.range(of: aiTitleMarker) != nil else {
            return (nil, nil)
        }

        var latestCustomTitle: String?
        var latestAiTitle: String?

        for line in contents.split(whereSeparator: isLineBreak) {
            guard line.range(of: customTitleMarker) != nil || line.range(of: aiTitleMarker) != nil,
                  let json = try? JSONSerialization.jsonObject(with: Data(line)) as? [String: Any],
                  let type = json["type"] as? String
            else {
                continue
            }

            switch type {
            case "custom-title":
                if let title = trimmedTitle(json["customTitle"]) {
                    latestCustomTitle = title
                }
            case "ai-title":
                if let title = trimmedTitle(json["aiTitle"]) {
                    latestAiTitle = title
                }
            default:
                continue
            }
        }

        return (latestCustomTitle, latestAiTitle)
    }

    private static func isLineBreak(_ byte: UInt8) -> Bool {
        byte == UInt8(ascii: "\n") || byte == UInt8(ascii: "\r")
    }

    private static func trimmedTitle(_ value: Any?) -> String? {
        guard let raw = value as? String else { return nil }
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private static let cache = TitleCache()
}

/// Size and modification date of a file: when both match, its contents are taken as unchanged.
private struct FileStamp: Equatable {
    let size: UInt64
    let modified: Date

    init?(path: String) {
        guard let attributes = try? FileManager.default.attributesOfItem(atPath: path),
              let size = attributes[.size] as? NSNumber,
              let modified = attributes[.modificationDate] as? Date
        else { return nil }
        self.size = size.uint64Value
        self.modified = modified
    }
}

/// Last title read from each file, valid while the file's stamp is unchanged. Reads run off
/// the main actor, so access is serialised with a lock.
private final class TitleCache: @unchecked Sendable {
    private struct Entry {
        let stamp: FileStamp
        let title: ResolvedSessionTitle?
    }

    private let lock = NSLock()
    private var entries: [String: Entry] = [:]
    private let limit = 256

    /// `nil` when there is no valid entry; `.some(nil)` when the file is known to have no title.
    func lookup(_ key: String, stamp: FileStamp) -> ResolvedSessionTitle?? {
        lock.lock()
        defer { lock.unlock() }
        guard let entry = entries[key], entry.stamp == stamp else { return nil }
        return .some(entry.title)
    }

    func store(_ key: String, stamp: FileStamp, title: ResolvedSessionTitle?) {
        lock.lock()
        defer { lock.unlock() }
        // Sessions come and go over a long run; dropping everything past the limit keeps the
        // cache bounded, and the next read simply repopulates what is still in use.
        if entries.count >= limit, entries[key] == nil {
            entries.removeAll(keepingCapacity: true)
        }
        entries[key] = Entry(stamp: stamp, title: title)
    }
}
