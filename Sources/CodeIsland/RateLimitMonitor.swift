import Combine
import Foundation
import SwiftUI

/// Parsed rate-limit display info for Anthropic Claude.
struct RateLimitDisplayInfo: Equatable {
    let fiveHourPercent: Int?
    let sevenDayPercent: Int?
    let fiveHourResetAt: Date?
    let sevenDayResetAt: Date?

    var maxPercent: Int { max(fiveHourPercent ?? 0, sevenDayPercent ?? 0) }

    var color: Color {
        let m = maxPercent
        if m >= 90 { return Color(red: 0.95, green: 0.30, blue: 0.30) }
        if m >= 70 { return Color(red: 1.0,  green: 0.65, blue: 0.25) }
        return Color(red: 0.36, green: 0.85, blue: 0.50)
    }
}

/// Polls Anthropic's OAuth usage endpoint every 5 minutes.
/// Reads the access token from the macOS Keychain (Claude Code credentials).
@MainActor
final class RateLimitMonitor: ObservableObject {
    static let shared = RateLimitMonitor()

    @Published private(set) var info: RateLimitDisplayInfo?
    @Published private(set) var isLoading = false
    @Published private(set) var lastError: String?

    private var refreshTimer: Timer?
    private(set) var isRunning = false

    private init() {}

    /// Begin polling on a 5-minute interval and immediately refresh.
    /// Idempotent — repeated calls are no-ops.
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
        if let next = await fetchFromAPI() { info = next }
    }

    // MARK: - HTTP

    private func fetchFromAPI() async -> RateLimitDisplayInfo? {
        guard let token = Self.readOAuthToken() else {
            lastError = "OAuth token not found in Keychain"
            return nil
        }
        guard let url = URL(string: "https://api.anthropic.com/api/oauth/usage") else { return nil }

        var request = URLRequest(url: url)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("oauth-2025-04-20", forHTTPHeaderField: "anthropic-beta")
        request.timeoutInterval = 10

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
                lastError = "API \((response as? HTTPURLResponse)?.statusCode ?? 0)"
                return nil
            }
            guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                lastError = "decode error"
                return nil
            }

            let formatter = ISO8601DateFormatter()
            formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]

            let fiveHour = json["five_hour"] as? [String: Any]
            let sevenDay = json["seven_day"] as? [String: Any]

            lastError = nil
            return RateLimitDisplayInfo(
                fiveHourPercent: (fiveHour?["utilization"] as? Double).map { Int($0) },
                sevenDayPercent: (sevenDay?["utilization"] as? Double).map { Int($0) },
                fiveHourResetAt: (fiveHour?["resets_at"] as? String).flatMap { formatter.date(from: $0) },
                sevenDayResetAt: (sevenDay?["resets_at"] as? String).flatMap { formatter.date(from: $0) }
            )
        } catch {
            lastError = error.localizedDescription
            return nil
        }
    }

    // MARK: - Keychain

    /// Read OAuth access token from Claude Code's Keychain entry.
    /// Same path used by the official CLI (`security find-generic-password -s "Claude Code-credentials"`).
    private static func readOAuthToken() -> String? {
        let process = Process()
        let pipe = Pipe()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/security")
        process.arguments = ["find-generic-password", "-s", "Claude Code-credentials", "-w"]
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice

        do {
            try process.run()
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            process.waitUntilExit()
            guard process.terminationStatus == 0,
                  let raw = String(data: data, encoding: .utf8)?
                    .trimmingCharacters(in: .whitespacesAndNewlines),
                  let json = try? JSONSerialization.jsonObject(with: Data(raw.utf8)) as? [String: Any],
                  let oauth = json["claudeAiOauth"] as? [String: Any],
                  let token = oauth["accessToken"] as? String
            else { return nil }
            return token
        } catch {
            return nil
        }
    }
}
