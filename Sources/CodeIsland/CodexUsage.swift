import Combine
import Foundation
import SwiftUI

/// One rate-limit window from Codex (primary = ~5h, secondary = ~7d).
struct CodexUsageWindow: Equatable, Sendable, Identifiable {
    var key: String
    var label: String
    var usedPercentage: Double
    var windowMinutes: Int
    var resetsAt: Date?

    var id: String { key }
    var roundedUsedPercentage: Int { Int(usedPercentage.rounded()) }
}

struct CodexUsageSnapshot: Equatable, Sendable {
    var sourceFilePath: String
    var capturedAt: Date?
    var planType: String?
    var windows: [CodexUsageWindow]

    var maxPercent: Int { Int(windows.map(\.usedPercentage).max()?.rounded() ?? 0) }
    var isEmpty: Bool { windows.isEmpty }

    var color: Color {
        let m = maxPercent
        if m >= 90 { return Color(red: 0.95, green: 0.30, blue: 0.30) }
        if m >= 70 { return Color(red: 1.0,  green: 0.65, blue: 0.25) }
        return Color(red: 0.36, green: 0.85, blue: 0.50)
    }
}

/// Periodically loads the latest Codex usage snapshot and publishes it.
/// 100% local — parses ~/.codex/sessions/rollout-*.jsonl, no network.
@MainActor
final class CodexUsageMonitor: ObservableObject {
    static let shared = CodexUsageMonitor()

    @Published private(set) var snapshot: CodexUsageSnapshot?
    @Published private(set) var isLoading = false

    private var refreshTimer: Timer?
    private(set) var isRunning = false

    private init() {}

    func start() {
        guard !isRunning else { return }
        isRunning = true
        refreshTimer = Timer.scheduledTimer(withTimeInterval: 300, repeats: true) { [weak self] _ in
            Task { @MainActor in await self?.refresh() }
        }
        Task { await refresh() }
    }

    func stop() {
        guard isRunning else { return }
        isRunning = false
        refreshTimer?.invalidate()
        refreshTimer = nil
    }

    func refresh() async {
        guard !isLoading else { return }
        isLoading = true
        defer { isLoading = false }
        snapshot = try? CodexUsageLoader.load()
    }
}

// MARK: - Loader (parses rollout JSONL)

enum CodexUsageLoader {
    static let defaultRootURL: URL = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent(".codex/sessions", isDirectory: true)

    private struct Candidate {
        var fileURL: URL
        var modifiedAt: Date
    }

    static func load(
        fromRootURL rootURL: URL = defaultRootURL,
        fileManager: FileManager = .default
    ) throws -> CodexUsageSnapshot? {
        guard fileManager.fileExists(atPath: rootURL.path),
              let enumerator = fileManager.enumerator(
                at: rootURL,
                includingPropertiesForKeys: [.contentModificationDateKey, .isRegularFileKey],
                options: [.skipsHiddenFiles]
              ) else { return nil }

        var candidates: [Candidate] = []
        for case let fileURL as URL in enumerator {
            guard fileURL.lastPathComponent.hasPrefix("rollout-"),
                  fileURL.pathExtension == "jsonl",
                  let resourceValues = try? fileURL.resourceValues(
                    forKeys: [.contentModificationDateKey, .isRegularFileKey]
                  ),
                  resourceValues.isRegularFile == true else { continue }
            candidates.append(Candidate(
                fileURL: fileURL,
                modifiedAt: resourceValues.contentModificationDate ?? .distantPast
            ))
        }

        // Newest file first; among ties, lexicographic-desc on path
        let sorted = candidates.sorted { lhs, rhs in
            lhs.modifiedAt == rhs.modifiedAt
                ? lhs.fileURL.path.localizedStandardCompare(rhs.fileURL.path) == .orderedDescending
                : lhs.modifiedAt > rhs.modifiedAt
        }
        for cand in sorted {
            if let snap = loadLatestSnapshot(from: cand.fileURL, modifiedAt: cand.modifiedAt) {
                return snap
            }
        }
        return nil
    }

    private static func loadLatestSnapshot(from fileURL: URL, modifiedAt: Date) -> CodexUsageSnapshot? {
        guard let contents = try? String(contentsOf: fileURL, encoding: .utf8) else { return nil }
        var latest: CodexUsageSnapshot?
        contents.enumerateLines { line, _ in
            if let s = snapshot(from: line, filePath: fileURL.path, fallbackTimestamp: modifiedAt) {
                latest = s
            }
        }
        return latest
    }

    private static func snapshot(from line: String, filePath: String, fallbackTimestamp: Date) -> CodexUsageSnapshot? {
        guard let object = jsonObject(for: line),
              object["type"] as? String == "event_msg" else { return nil }

        let payload = object["payload"] as? [String: Any] ?? [:]
        guard payload["type"] as? String == "token_count",
              let rateLimits = payload["rate_limits"] as? [String: Any] else { return nil }

        let windows = ["primary", "secondary"].compactMap { key in
            usageWindow(for: key, in: rateLimits)
        }
        guard !windows.isEmpty else { return nil }

        return CodexUsageSnapshot(
            sourceFilePath: filePath,
            capturedAt: timestamp(from: object["timestamp"]) ?? fallbackTimestamp,
            planType: string(from: rateLimits["plan_type"]),
            windows: windows
        )
    }

    private static func usageWindow(for key: String, in rateLimits: [String: Any]) -> CodexUsageWindow? {
        guard let payload = rateLimits[key] as? [String: Any],
              let used = number(from: payload["used_percent"]),
              let win = integer(from: payload["window_minutes"]) else { return nil }
        return CodexUsageWindow(
            key: key,
            label: windowLabel(forMinutes: win),
            usedPercentage: used,
            windowMinutes: win,
            resetsAt: date(from: payload["resets_at"])
        )
    }

    private static func windowLabel(forMinutes minutes: Int) -> String {
        let days = minutes / 1_440
        let restAfterDays = minutes % 1_440
        let hours = restAfterDays / 60
        let mins = restAfterDays % 60
        if days > 0, hours == 0, mins == 0 { return "\(days)d" }
        if days > 0, hours > 0 { return "\(days)d \(hours)h" }
        if hours > 0, mins == 0 { return "\(hours)h" }
        if hours > 0 { return "\(hours)h \(mins)m" }
        return "\(minutes)m"
    }

    private static func jsonObject(for line: String) -> [String: Any]? {
        guard let data = line.data(using: .utf8),
              let obj = try? JSONSerialization.jsonObject(with: data),
              let dict = obj as? [String: Any] else { return nil }
        return dict
    }

    private static func timestamp(from value: Any?) -> Date? {
        guard let s = value as? String else { return nil }
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f.date(from: s)
    }

    private static func number(from value: Any?) -> Double? {
        switch value {
        case let n as NSNumber: return n.doubleValue
        case let s as String: return Double(s)
        default: return nil
        }
    }

    private static func integer(from value: Any?) -> Int? {
        switch value {
        case let n as NSNumber: return n.intValue
        case let s as String: return Int(s)
        default: return nil
        }
    }

    private static func date(from value: Any?) -> Date? {
        switch value {
        case let n as NSNumber: return Date(timeIntervalSince1970: n.doubleValue)
        case let s as String:
            guard let secs = Double(s) else { return nil }
            return Date(timeIntervalSince1970: secs)
        default: return nil
        }
    }

    private static func string(from value: Any?) -> String? {
        switch value {
        case let s as String: return s.isEmpty ? nil : s
        case let n as NSNumber: return n.stringValue
        default: return nil
        }
    }
}
