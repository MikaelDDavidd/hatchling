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

    private struct Entry {
        let usage: ContextUsage
        /// Timestamp of the session.lastActivity at capture time —
        /// used to decide whether the cache is stale.
        let capturedAt: Date
    }

    @Published private var cache: [String: Entry] = [:]
    private var inFlight: Set<String> = []

    /// Lookup with stale-while-revalidate semantics. Triggers a background
    /// refresh when the cached value pre-dates the latest activity.
    func lookup(for session: SessionSnapshot, sessionId: String) -> ContextUsage? {
        let entry = cache[sessionId]
        let isFresh = (entry?.capturedAt ?? .distantPast) >= session.lastActivity
        if !isFresh {
            scheduleRefresh(sessionId: sessionId, session: session)
        }
        return entry?.usage
    }

    private func scheduleRefresh(sessionId: String, session: SessionSnapshot) {
        guard !inFlight.contains(sessionId) else { return }
        inFlight.insert(sessionId)
        let source = session.source ?? "claude"
        let cwd = session.cwd
        let activity = session.lastActivity

        Task.detached(priority: .background) { [weak self] in
            let usage = ContextUsageReader.read(
                sessionId: sessionId, source: source, cwd: cwd
            )
            await MainActor.run { [weak self] in
                guard let self else { return }
                self.inFlight.remove(sessionId)
                if let usage {
                    self.cache[sessionId] = Entry(usage: usage, capturedAt: activity)
                }
            }
        }
    }

    /// For testing/debug: drop the cache.
    func reset() {
        cache.removeAll()
        inFlight.removeAll()
    }
}

// MARK: - Reader

enum ContextUsageReader {
    /// Default Claude/Sonnet/Opus/Haiku context window.
    private static let defaultClaudeWindow = 200_000
    /// Override for `[1m]` model variants and very large contexts.
    private static let extendedWindow = 1_000_000

    /// Lookup table for known models. Falls back to a heuristic if missing.
    private static let knownWindows: [String: Int] = [
        "claude-opus-4-6":      200_000,
        "claude-opus-4-5":      200_000,
        "claude-sonnet-4-6":    200_000,
        "claude-sonnet-4-5":    200_000,
        "claude-haiku-4-5":     200_000,
        "claude-opus-4-6[1m]":  1_000_000,
        "claude-sonnet-4-6[1m]":1_000_000,
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
        guard let raw = try? String(contentsOf: url, encoding: .utf8) else { return nil }

        // Walk lines from the bottom to find the most recent assistant turn with usage.
        var lastUsage: (model: String, used: Int)?
        let lines = raw.split(separator: "\n", omittingEmptySubsequences: true)
        for line in lines.reversed() {
            guard let data = String(line).data(using: .utf8),
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
            else { continue }
            // Only consider assistant turns
            guard (json["type"] as? String) == "assistant" else { continue }
            let msg = (json["message"] as? [String: Any]) ?? json
            guard let model = msg["model"] as? String,
                  let usage = msg["usage"] as? [String: Any] else { continue }
            let inTok    = (usage["input_tokens"] as? Int) ?? 0
            let cacheCr  = (usage["cache_creation_input_tokens"] as? Int) ?? 0
            let cacheRd  = (usage["cache_read_input_tokens"] as? Int) ?? 0
            let total = inTok + cacheCr + cacheRd
            guard total > 0 else { continue }
            lastUsage = (model, total)
            break
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
        if let known = knownWindows[model] {
            // Promote to 1m if the actual usage somehow exceeds the table value.
            return max(known, usedTokens > known ? extendedWindow : known)
        }
        if model.contains("[1m]") || model.contains("1m") { return extendedWindow }
        if usedTokens > defaultClaudeWindow { return extendedWindow }
        return defaultClaudeWindow
    }
}
