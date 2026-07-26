import Foundation

/// Reads JSONL transcripts backwards without loading the whole file.
///
/// Agent transcripts (Codex rollouts, Claude Code session files) grow without
/// bound — multi-GB files happen in practice. Readers here only ever want the
/// most recent record of some kind, so we seek to the end, scan back a bounded
/// window, and only widen it when nothing matched.
enum TranscriptTail {
    /// Window sizes tried in order. Transcripts emit the records we care about
    /// every turn, so the first step almost always hits; the larger steps only
    /// matter for files with huge single lines (big tool outputs).
    static let defaultSteps: [UInt64] = [256 * 1024, 4 * 1024 * 1024, 32 * 1024 * 1024]

    /// Feeds lines to `transform` from newest to oldest, returning the first
    /// non-nil result. Each line arrives as raw bytes — no whole-file `String`
    /// is ever built, which also avoids the UTF-16 breadcrumb cost that makes
    /// `enumerateLines` pathological on large files.
    static func scanBackwards<T>(
        url: URL,
        steps: [UInt64] = defaultSteps,
        transform: (Data) -> T?
    ) -> T? {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return nil }
        defer { try? handle.close() }
        guard let fileSize = try? handle.seekToEnd(), fileSize > 0 else { return nil }

        for step in steps {
            let readSize = min(fileSize, step)
            let reachedFileStart = readSize == fileSize
            guard (try? handle.seek(toOffset: fileSize - readSize)) != nil,
                  let data = try? handle.readToEnd(), !data.isEmpty else { return nil }

            var body = data[...]
            if !reachedFileStart {
                // A window starting mid-file opens with a truncated line. Dropping
                // it also puts the remaining bytes back on a UTF-8 boundary.
                guard let newline = body.firstIndex(of: 0x0A) else { continue }
                body = body[body.index(after: newline)...]
            }

            for line in body.split(separator: 0x0A, omittingEmptySubsequences: true).reversed() {
                if let value = transform(Data(line)) { return value }
            }
            if reachedFileStart { break }
        }
        return nil
    }
}
