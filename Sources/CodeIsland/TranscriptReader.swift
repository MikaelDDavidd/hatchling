import Foundation
import CodeIslandCore
import os

/// Reads a session's conversation out of the CLI's own transcript, a page at a time.
///
/// The phone shows a chat, and a chat needs the whole conversation — but the transcript for a
/// working day is tens of megabytes (33 MB for the session this was written in). So it is read
/// backwards in bounded windows, newest first, which is also the order a chat is scrolled: the
/// last exchange is what opens, and older pages load as you scroll up.
///
/// Nothing is cached. The file is the truth, it is append-only, and re-reading a 64 KB window is
/// cheaper than holding a transcript in memory for every session a phone might open.
enum TranscriptReader {

    private static let log = Logger(subsystem: "com.mikaeldavid.CodeIsland", category: "TranscriptReader")

    /// How much of the file to pull in one go while hunting for a page of messages. Sized so a
    /// typical page lands in one or two reads without ever holding much.
    private static let windowSize: UInt64 = 512 * 1024

    // MARK: - Locating

    /// Where a session's transcript lives, or nil when the CLI does not keep one we can read.
    static func transcriptPath(for session: SessionSnapshot, sessionId: String) -> String? {
        guard session.source == "claude" else {
            // Codex and the rest keep their own shapes; the chat is Claude-only until one of
            // them is actually used enough to be worth parsing.
            return nil
        }
        let providerId = session.providerSessionId ?? sessionId
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let root = "\(home)/.claude/projects"

        if let cwd = session.cwd {
            let path = "\(root)/\(encodeProjectDir(cwd))/\(providerId).jsonl"
            if FileManager.default.fileExists(atPath: path) { return path }
        }

        // Fall back to finding the file by name.
        //
        // The directory encoding is Claude Code's business and has already caught us out once:
        // underscores become hyphens too, which is not obvious and is not written down anywhere
        // we control. The session id is a UUID and the file is named after it, so searching is
        // both unambiguous and immune to the next encoding change.
        return findByName("\(providerId).jsonl", under: root)
    }

    /// Mirrors how Claude Code names a project directory.
    ///
    /// Derived from the real directories on disk rather than from documentation: separators,
    /// spaces, underscores and anything non-ASCII all collapse to a hyphen. Verified against
    /// every live session's cwd.
    static func encodeProjectDir(_ cwd: String) -> String {
        var result = ""
        for scalar in cwd.unicodeScalars {
            if scalar == "/" || scalar == "_" || scalar == " " || scalar.value > 127 {
                result.append("-")
            } else {
                result.append(Character(scalar))
            }
        }
        return result
    }

    private static func findByName(_ filename: String, under root: String) -> String? {
        guard let entries = try? FileManager.default.contentsOfDirectory(atPath: root) else { return nil }
        for entry in entries {
            let candidate = "\(root)/\(entry)/\(filename)"
            if FileManager.default.fileExists(atPath: candidate) { return candidate }
        }
        return nil
    }

    // MARK: - Reading

    /// One page of conversation, newest first.
    ///
    /// - Parameter before: line offset from the end returned by a previous page, or nil to start
    ///   at the newest message.
    static func page(
        path: String,
        before: Int?,
        limit: Int = 30
    ) -> MobileChatPage? {
        guard let handle = try? FileHandle(forReadingFrom: path.asFileURL) else {
            log.error("cannot open transcript")
            return nil
        }
        defer { try? handle.close() }
        guard let fileSize = try? handle.seekToEnd(), fileSize > 0 else { return nil }

        var messages: [MobileChatMessage] = []
        var linesScanned = 0
        let skip = before ?? 0
        var offset = fileSize
        var reachedStart = false

        // Walk backwards a window at a time until the page is full or the file runs out.
        while messages.count < limit && !reachedStart {
            let readSize = min(offset, windowSize)
            let start = offset - readSize
            reachedStart = start == 0

            guard (try? handle.seek(toOffset: start)) != nil,
                  let data = try? handle.read(upToCount: Int(readSize)), !data.isEmpty else { break }

            var body = data[...]
            // Unless we are at the very beginning, drop the first partial line — its head is in
            // the window we have not read.
            if !reachedStart, let newline = body.firstIndex(of: 0x0A) {
                body = body[body.index(after: newline)...]
            }

            for line in body.split(separator: 0x0A, omittingEmptySubsequences: true).reversed() {
                guard let message = parse(line: Data(line)) else { continue }
                linesScanned += 1
                if linesScanned <= skip { continue }
                messages.append(message)
                if messages.count >= limit { break }
            }

            offset = start
        }

        // The cursor counts transcript entries, not turns, so it has to be computed before
        // coalescing — otherwise the next page would skip everything that got merged away.
        return MobileChatPage(
            messages: coalesce(messages),
            nextBefore: reachedStart && messages.count < limit ? nil : skip + messages.count,
            reachedStart: reachedStart && messages.count < limit
        )
    }

    /// Folds tool-only entries into the thing that was said before them.
    ///
    /// An assistant turn reaches the transcript as several lines — a line of prose, then a line
    /// per tool call — so read literally the chat becomes a stack of near-empty cards, one per
    /// tool, each wearing its own speaker label.
    ///
    /// Only the empty ones are absorbed. Merging everything a speaker said between two replies
    /// was worse than the problem: it collapsed a working session into one wall of text and cut
    /// the link between a sentence and the commands it announced. Keeping each sentence as its
    /// own turn, with the tools it went on to run listed beneath it, matches how the work
    /// actually happened.
    ///
    /// Input and output are both newest-first, matching the page order.
    static func coalesce(_ messages: [MobileChatMessage]) -> [MobileChatMessage] {
        Array(coalesceChronological(Array(messages.reversed())).reversed())
    }

    /// `coalesce` for lists held oldest-first, which is how the panel keeps them.
    static func coalesceChronological(_ messages: [MobileChatMessage]) -> [MobileChatMessage] {
        var turns: [MobileChatMessage] = []
        /// Tools run before their speaker had said anything they could hang under.
        var orphans: (user: Bool, at: Int, tools: [String])?

        func flushOrphans() {
            guard let held = orphans else { return }
            orphans = nil
            // Nothing to attach to — the agent is mid-run and has not reported back yet.
            turns.append(MobileChatMessage(user: held.user, text: "", at: held.at, tools: held.tools))
        }

        for message in messages {
            guard message.text.isEmpty else {
                // A sentence adopts the tools that ran just before it, which is the case when an
                // agent works first and reports afterwards.
                if let held = orphans, held.user == message.user {
                    orphans = nil
                    turns.append(MobileChatMessage(
                        user: message.user,
                        text: message.text,
                        at: held.at,
                        tools: held.tools + message.tools
                    ))
                    continue
                }
                flushOrphans()
                turns.append(message)
                continue
            }

            // Tools alone: they belong to whatever this speaker last said.
            if let previous = turns.last, previous.user == message.user, !previous.text.isEmpty {
                turns[turns.count - 1] = MobileChatMessage(
                    user: previous.user,
                    text: previous.text,
                    at: previous.at,
                    tools: previous.tools + message.tools
                )
                continue
            }

            if let held = orphans, held.user == message.user {
                orphans = (held.user, held.at, held.tools + message.tools)
            } else {
                flushOrphans()
                orphans = (message.user, message.at, message.tools)
            }
        }

        flushOrphans()
        return turns
    }

    // MARK: - Parsing

    /// Turns one transcript line into a chat message, or nil when it is not part of the
    /// conversation — tool plumbing, file snapshots, title updates and the rest.
    private static func parse(line: Data) -> MobileChatMessage? {
        guard let json = try? JSONSerialization.jsonObject(with: line) as? [String: Any] else { return nil }

        // Subagent chatter belongs to the subagent, not to this conversation. Showing it inline
        // would interleave several threads into one and read as nonsense.
        if json["isSidechain"] as? Bool == true { return nil }

        guard let type = json["type"] as? String, type == "user" || type == "assistant" else { return nil }
        guard let message = json["message"] as? [String: Any] else { return nil }

        let timestamp = (json["timestamp"] as? String).flatMap(iso8601) ?? Date()
        let text: String
        var tools: [String] = []

        switch message["content"] {
        case let string as String:
            text = string
        case let blocks as [[String: Any]]:
            var parts: [String] = []
            for block in blocks {
                switch block["type"] as? String {
                case "text":
                    if let value = block["text"] as? String { parts.append(value) }
                case "tool_use":
                    // Named but not expanded: the detail screen already lists tool calls, and a
                    // wall of arguments in the chat drowns what was actually said.
                    if let name = block["name"] as? String { tools.append(name) }
                default:
                    // thinking, tool_result and anything added later stay out.
                    break
                }
            }
            text = parts.joined(separator: "\n\n")
        default:
            return nil
        }

        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        // A turn that was purely a tool call still matters — it shows the agent acting — but one
        // that is empty of both is noise.
        guard !trimmed.isEmpty || !tools.isEmpty else { return nil }

        return MobileChatMessage(
            user: type == "user",
            text: String(trimmed.prefix(8000)),
            at: Int(timestamp.timeIntervalSince1970),
            tools: tools
        )
    }

    private static let formatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()

    private static let plainFormatter = ISO8601DateFormatter()

    private static func iso8601(_ value: String) -> Date? {
        formatter.date(from: value) ?? plainFormatter.date(from: value)
    }
}

private extension String {
    var asFileURL: URL { URL(fileURLWithPath: self) }
}
