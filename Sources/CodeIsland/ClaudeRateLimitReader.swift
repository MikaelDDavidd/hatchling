import Combine
import Foundation
import SwiftUI

/// Real Claude rate-limit data captured from Claude Code's statusline JSON
/// (v2.1.80+). The wrapper script writes ~/.codeisland/rate-limits.json on
/// every Claude Code interaction. This reader polls that file on a short
/// interval so the UsageBar reflects the actual session/weekly usage —
/// no API calls, no estimates, no auth.
struct ClaudeRateLimits: Equatable {
    let fiveHourPercent: Int?
    let sevenDayPercent: Int?
    let fiveHourResetAt: Date?
    let sevenDayResetAt: Date?
    let capturedAt: Date
    let model: String?

    var maxPercent: Int { max(fiveHourPercent ?? 0, sevenDayPercent ?? 0) }

    var color: Color {
        let m = maxPercent
        if m >= 90 { return Color(red: 0.95, green: 0.30, blue: 0.30) }
        if m >= 70 { return Color(red: 1.0,  green: 0.65, blue: 0.25) }
        return Color(red: 0.36, green: 0.85, blue: 0.50)
    }
}

@MainActor
final class ClaudeRateLimitReader: ObservableObject {
    static let shared = ClaudeRateLimitReader()

    @Published private(set) var limits: ClaudeRateLimits?
    @Published private(set) var isInstalled: Bool = false

    private var timer: Timer?
    private(set) var isRunning = false

    private static let cachePath: URL = FileManager.default
        .homeDirectoryForCurrentUser
        .appendingPathComponent(".codeisland/rate-limits.json")

    private init() {}

    func start() {
        guard !isRunning else { return }
        isRunning = true
        // Poll often enough to feel live, but file writes are cheap so 10s is fine.
        timer = Timer.scheduledTimer(withTimeInterval: 10, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.refresh() }
        }
        refresh()
    }

    func stop() {
        isRunning = false
        timer?.invalidate()
        timer = nil
    }

    func refresh() {
        isInstalled = StatuslineInstaller.isInstalled
        guard let data = try? Data(contentsOf: Self.cachePath),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { return }

        let captured = (json["capturedAt"] as? Double).map { Date(timeIntervalSince1970: $0) } ?? Date()
        let rl = json["rate_limits"] as? [String: Any] ?? [:]
        let five = rl["five_hour"] as? [String: Any]
        let seven = rl["seven_day"] as? [String: Any]

        limits = ClaudeRateLimits(
            fiveHourPercent: percent(five?["used_percentage"]),
            sevenDayPercent: percent(seven?["used_percentage"]),
            fiveHourResetAt: resetDate(five?["resets_at"]),
            sevenDayResetAt: resetDate(seven?["resets_at"]),
            capturedAt: captured,
            model: json["model"] as? String
        )
    }

    private func percent(_ v: Any?) -> Int? {
        switch v {
        case let n as NSNumber: return Int(n.doubleValue.rounded())
        case let s as String: return Double(s).map { Int($0.rounded()) }
        default: return nil
        }
    }

    private func resetDate(_ v: Any?) -> Date? {
        switch v {
        case let n as NSNumber: return Date(timeIntervalSince1970: n.doubleValue)
        case let s as String:
            if let d = Double(s) { return Date(timeIntervalSince1970: d) }
            let f = ISO8601DateFormatter()
            f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            return f.date(from: s)
        default: return nil
        }
    }
}
