import Combine
import Foundation
import SwiftUI

/// One transient alert string that should briefly replace the gerund verb
/// in the notch when usage crosses a 5% bucket above 70%.
struct UsageAlert: Identifiable, Equatable {
    let id = UUID()
    let text: String
    let color: Color

    static func == (lhs: UsageAlert, rhs: UsageAlert) -> Bool {
        lhs.id == rhs.id
    }
}

/// Watches the Anthropic + Codex usage monitors and emits transient alerts
/// whenever a window crosses a new 5% bucket above 70%. The alert is
/// auto-cleared after 4s so the gerund verb returns.
@MainActor
final class UsageAlertCenter: ObservableObject {
    static let shared = UsageAlertCenter()

    @Published private(set) var pending: UsageAlert?

    /// Last 5%-bucket we already alerted on, per source/window.
    /// Reset to 0 once usage falls back below threshold.
    private var lastBuckets: [String: Int] = [:]
    private var clearTask: Task<Void, Never>?
    private var cancellables: Set<AnyCancellable> = []
    private let alertThreshold = 70
    private let bucketSize = 5
    private let displayDuration: TimeInterval = 4.0

    private init() {
        // Bind to both monitors. They are @MainActor so we observe on main.
        ClaudeRateLimitReader.shared.$limits
            .sink { [weak self] limits in
                guard let self else { return }
                Task { @MainActor [weak self] in
                    self?.evaluateClaude(limits)
                }
            }
            .store(in: &cancellables)
        CodexUsageMonitor.shared.$snapshot
            .sink { [weak self] snap in
                guard let self else { return }
                Task { @MainActor [weak self] in
                    self?.evaluateCodex(snap)
                }
            }
            .store(in: &cancellables)
    }

    // MARK: - Evaluators

    private func evaluateClaude(_ limits: ClaudeRateLimits?) {
        guard let limits else { return }
        if let pct = limits.fiveHourPercent {
            consider(key: "claude.5h", label: "Claude 5h", pct: pct)
        }
        if let pct = limits.sevenDayPercent {
            consider(key: "claude.7d", label: "Claude 7d", pct: pct)
        }
    }

    private func evaluateCodex(_ snap: CodexUsageSnapshot?) {
        guard let snap else { return }
        for w in snap.windows {
            consider(key: "codex.\(w.key)", label: "Codex \(w.label)", pct: w.roundedUsedPercentage)
        }
    }

    /// Decide whether to surface an alert for one (source, window).
    private func consider(key: String, label: String, pct: Int) {
        // Below threshold — clear any past bucket so re-crossing fires again
        guard pct >= alertThreshold else {
            lastBuckets[key] = 0
            return
        }
        let bucket = (pct / bucketSize) * bucketSize
        let previous = lastBuckets[key] ?? 0
        guard bucket > previous else { return }
        lastBuckets[key] = bucket
        emit(text: "\(label): \(pct)%", color: colorFor(pct: pct))
    }

    private func emit(text: String, color: Color) {
        let alert = UsageAlert(text: text, color: color)
        pending = alert
        clearTask?.cancel()
        clearTask = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(self?.displayDuration ?? 4 * 1_000_000_000))
            guard let self, self.pending?.id == alert.id else { return }
            withAnimation(.easeInOut(duration: 0.25)) {
                self.pending = nil
            }
        }
    }

    private func colorFor(pct: Int) -> Color {
        if pct >= 90 { return Color(red: 0.95, green: 0.30, blue: 0.30) }
        if pct >= 80 { return Color(red: 1.0,  green: 0.55, blue: 0.20) }
        return Color(red: 1.0,  green: 0.78, blue: 0.30)
    }
}
