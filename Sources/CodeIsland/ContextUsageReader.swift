import Foundation
import SwiftUI
import CodeIslandCore

/// Snapshot of how much of a single session's model-context window is filled.
struct ContextUsage: Equatable {
    let model: String
    /// Total tokens currently in the model's context window
    /// (input + cache_creation + cache_read + reserved system).
    let usedTokens: Int
    /// Hard limit of the model's context window (e.g. 200_000 or 1_000_000).
    let contextLimit: Int

    var pct: Int {
        guard contextLimit > 0 else { return 0 }
        return Int((Double(usedTokens) / Double(contextLimit) * 100.0).rounded())
    }

    var color: Color {
        if pct >= 90 { return Color(red: 0.95, green: 0.30, blue: 0.30) }
        if pct >= 70 { return Color(red: 1.0,  green: 0.65, blue: 0.25) }
        return Color(red: 0.36, green: 0.85, blue: 0.50)
    }

    /// Compact display name — strip "claude-" / vendor prefix and shorten.
    var modelShort: String {
        var s = model
        for prefix in ["claude-", "openai/", "anthropic/"] {
            if s.hasPrefix(prefix) { s.removeFirst(prefix.count) }
        }
        return s
    }

    /// "94k / 200k" style.
    var tokensCompact: String {
        "\(formatK(usedTokens))/\(formatK(contextLimit))"
    }

    private func formatK(_ n: Int) -> String {
        if n >= 1_000_000 { return String(format: "%.1fM", Double(n) / 1_000_000) }
        if n >= 1_000 { return "\(n / 1_000)k" }
        return "\(n)"
    }
}

/// Cached per-session context usage. Reads JSONL transcripts on demand,
/// background-refreshes when a session's lastActivity advances past the cached snapshot.
@MainActor
final class ContextUsageStore: ObservableObject {
    static let shared = ContextUsageStore()

    /// Only the usage itself is published: views observing the store re-render when a
    /// percentage moves, not every time a re-read confirms the same number.
    @Published private var cache: [String: ContextUsage] = [:]
    /// The session.lastActivity each cached value was read at — used to decide whether the
    /// cache is stale. Kept apart from `cache` so bumping it doesn't notify observers.
    private var capturedAt: [String: Date] = [:]
    /// Newest lastActivity seen per session, so a delayed re-read is stamped with it.
    private var latestActivity: [String: Date] = [:]
    /// When the last re-read of each session started.
    private var lastRefreshAt: [String: Date] = [:]
    private var inFlight: Set<String> = []
    /// Sessions with a re-read already waiting out the throttle.
    private var trailingRefresh: Set<String> = []

    /// Every hook advances lastActivity, so without a floor the transcript tail would be
    /// re-scanned on each one. A session's usage is re-read at most this often; the last
    /// change in a burst is still picked up by a trailing re-read.
    private static let minRefreshInterval: TimeInterval = 8

    /// Lookup with stale-while-revalidate semantics. Triggers a background
    /// refresh when the cached value pre-dates the latest activity.
    func lookup(for session: SessionSnapshot, sessionId: String) -> ContextUsage? {
        if latestActivity[sessionId].map({ $0 < session.lastActivity }) ?? true {
            latestActivity[sessionId] = session.lastActivity
        }
        let isFresh = (capturedAt[sessionId] ?? .distantPast) >= session.lastActivity
        if !isFresh {
            scheduleRefresh(sessionId: sessionId, session: session)
        }
        return cache[sessionId]
    }

    private func scheduleRefresh(sessionId: String, session: SessionSnapshot) {
        guard !inFlight.contains(sessionId), !trailingRefresh.contains(sessionId) else { return }

        let sinceLast = Date().timeIntervalSince(lastRefreshAt[sessionId] ?? .distantPast)
        let wait = Self.minRefreshInterval - sinceLast
        guard wait > 0 else {
            startRefresh(sessionId: sessionId, session: session)
            return
        }

        trailingRefresh.insert(sessionId)
        Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(wait))
            guard let self else { return }
            self.trailingRefresh.remove(sessionId)
            self.startRefresh(sessionId: sessionId, session: session)
        }
    }

    private func startRefresh(sessionId: String, session: SessionSnapshot) {
        guard !inFlight.contains(sessionId) else { return }
        inFlight.insert(sessionId)
        lastRefreshAt[sessionId] = Date()
        let source = session.source ?? "claude"
        let cwd = session.cwd
        // Stamped before the read starts, so whatever the read finds is at least this new.
        let activity = max(latestActivity[sessionId] ?? session.lastActivity, session.lastActivity)

        Task.detached(priority: .background) { [weak self] in
            let usage = ContextUsageReader.read(
                sessionId: sessionId, source: source, cwd: cwd
            )
            await MainActor.run { [weak self] in
                guard let self else { return }
                self.inFlight.remove(sessionId)
                // Stamp even an empty read, so a session with nothing to show isn't
                // re-read until it moves again.
                self.capturedAt[sessionId] = activity
                if let usage, self.cache[sessionId] != usage {
                    self.cache[sessionId] = usage
                }
            }
        }
    }

    /// For testing/debug: drop the cache.
    func reset() {
        cache.removeAll()
        capturedAt.removeAll()
        latestActivity.removeAll()
        lastRefreshAt.removeAll()
        inFlight.removeAll()
        trailingRefresh.removeAll()
    }
}

// MARK: - Reader

enum ContextUsageReader {
    private static let smallWindow = 200_000
    private static let extendedWindow = 1_000_000

    /// Claude models whose window is 200K. Every Claude model from Opus/Sonnet 4.6 on
    /// (the 4.7/4.8 line, Opus/Sonnet/Haiku 5 and 5.5, Fable) has 1M, and the table used to
    /// say 200K for all of them, so an Opus 5.5 session at 160K showed 80% instead of 16%.
    /// Date-suffixed ids ("claude-sonnet-4-20250514") match by prefix.
    private static let smallWindowPrefixes = [
        "claude-haiku-4-5", "claude-opus-4-5", "claude-sonnet-4-5",
        "claude-opus-4-1", "claude-opus-4-0", "claude-opus-4-2",
        "claude-sonnet-4-0", "claude-sonnet-4-2", "claude-3",
    ]

    static func read(sessionId: String, source: String, cwd: String?) -> ContextUsage? {
        switch source {
        case "claude":
            return readClaude(sessionId: sessionId, cwd: cwd)
        default:
            // Other CLIs (codex, gemini…) use different transcript formats.
            // Skip for now — codex plan-window % still shows in the UsageBar.
            return nil
        }
    }

    // MARK: Claude

    private static func readClaude(sessionId: String, cwd: String?) -> ContextUsage? {
        guard let url = locateClaudeJSONL(sessionId: sessionId, cwd: cwd) else { return nil }

        // Walk lines from the bottom to find the most recent assistant turn with
        // usage. Session files reach hundreds of MB, so we scan the tail instead
        // of loading the transcript into memory.
        let lastUsage: (model: String, used: Int)? = TranscriptTail.scanBackwards(url: url) { line in
            guard let json = try? JSONSerialization.jsonObject(with: line) as? [String: Any] else { return nil }
            // Only consider assistant turns
            guard (json["type"] as? String) == "assistant" else { return nil }
            let msg = (json["message"] as? [String: Any]) ?? json
            guard let model = msg["model"] as? String,
                  let usage = msg["usage"] as? [String: Any] else { return nil }
            let inTok    = (usage["input_tokens"] as? Int) ?? 0
            let cacheCr  = (usage["cache_creation_input_tokens"] as? Int) ?? 0
            let cacheRd  = (usage["cache_read_input_tokens"] as? Int) ?? 0
            let total = inTok + cacheCr + cacheRd
            guard total > 0 else { return nil }
            return (model, total)
        }

        guard let last = lastUsage else { return nil }
        let limit = contextWindow(for: last.model, usedTokens: last.used)
        return ContextUsage(
            model: last.model,
            usedTokens: last.used,
            contextLimit: limit
        )
    }

    private static func locateClaudeJSONL(sessionId: String, cwd: String?) -> URL? {
        let home = FileManager.default.homeDirectoryForCurrentUser
        let projects = home.appendingPathComponent(".claude/projects", isDirectory: true)
        // Preferred path: encoded-cwd directory
        if let cwd, !cwd.isEmpty {
            let encoded = cwd.replacingOccurrences(of: "/", with: "-")
            let preferred = projects
                .appendingPathComponent(encoded, isDirectory: true)
                .appendingPathComponent("\(sessionId).jsonl")
            if FileManager.default.fileExists(atPath: preferred.path) {
                return preferred
            }
        }
        // Fallback: scan all project dirs (cheap, dirs are small)
        guard let dirs = try? FileManager.default.contentsOfDirectory(
            at: projects, includingPropertiesForKeys: nil
        ) else { return nil }
        for dir in dirs {
            let candidate = dir.appendingPathComponent("\(sessionId).jsonl")
            if FileManager.default.fileExists(atPath: candidate.path) {
                return candidate
            }
        }
        return nil
    }

    /// Pick a context-window size for the model. Heuristic: if the
    /// observed usage already exceeds 200k, the session must be on a 1m variant.
    private static func contextWindow(for model: String, usedTokens: Int) -> Int {
        if model.contains("[1m]") || usedTokens > smallWindow { return extendedWindow }
        if smallWindowPrefixes.contains(where: { model.hasPrefix($0) }) { return smallWindow }
        // Any other Claude model is a current one, with 1M; other vendors' models, unknown here,
        // keep the conservative guess.
        return model.hasPrefix("claude-") ? extendedWindow : smallWindow
    }
}
