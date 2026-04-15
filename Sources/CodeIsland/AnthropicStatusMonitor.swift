import Combine
import Foundation
import SwiftUI

/// Snapshot of Anthropic's public statuspage.
struct AnthropicStatus: Equatable {
    /// Indicator from Statuspage: "none" | "minor" | "major" | "critical" | "maintenance"
    let indicator: String
    /// Friendly summary, e.g. "All Systems Operational" or "Partial System Outage"
    let description: String
    /// Active incidents, most recent first.
    let incidents: [Incident]
    /// Components currently NOT operational, in display order.
    let degradedComponents: [Component]

    struct Incident: Equatable, Identifiable {
        let id: String
        let name: String
        let status: String          // investigating | identified | monitoring | resolved
        let impact: String          // none | minor | major | critical
        let shortLink: String?
    }

    struct Component: Equatable, Identifiable {
        let id: String
        let name: String
        let status: String          // operational | degraded_performance | partial_outage | major_outage | maintenance
    }

    var color: Color {
        switch indicator {
        case "none": return Color(red: 0.36, green: 0.85, blue: 0.50)
        case "minor": return Color(red: 1.0,  green: 0.78, blue: 0.30)
        case "major": return Color(red: 1.0,  green: 0.55, blue: 0.20)
        case "critical": return Color(red: 0.95, green: 0.30, blue: 0.30)
        case "maintenance": return Color(red: 0.45, green: 0.72, blue: 1.0)
        default: return Color.white.opacity(0.5)
        }
    }

    var isOk: Bool { indicator == "none" }
}

/// Polls Anthropic's statuspage every 5 minutes.
@MainActor
final class AnthropicStatusMonitor: ObservableObject {
    static let shared = AnthropicStatusMonitor()

    @Published private(set) var status: AnthropicStatus?
    @Published private(set) var lastError: String?

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
        isRunning = false
        refreshTimer?.invalidate()
        refreshTimer = nil
    }

    func refresh() async {
        guard let url = URL(string: "https://status.claude.com/api/v2/summary.json") else { return }
        var req = URLRequest(url: url)
        req.setValue("Mozilla/5.0 Hatchling/0.1", forHTTPHeaderField: "User-Agent")
        req.timeoutInterval = 10
        do {
            let (data, response) = try await URLSession.shared.data(for: req)
            guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
                lastError = "HTTP \((response as? HTTPURLResponse)?.statusCode ?? 0)"
                return
            }
            guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                lastError = "decode error"
                return
            }
            let s = (json["status"] as? [String: Any]) ?? [:]
            let indicator = (s["indicator"] as? String) ?? "none"
            let description = (s["description"] as? String) ?? "Unknown"

            let incidents: [AnthropicStatus.Incident] = ((json["incidents"] as? [[String: Any]]) ?? []).compactMap { d in
                guard let id = d["id"] as? String,
                      let name = d["name"] as? String,
                      let st = d["status"] as? String else { return nil }
                return AnthropicStatus.Incident(
                    id: id,
                    name: name,
                    status: st,
                    impact: (d["impact"] as? String) ?? "none",
                    shortLink: d["shortlink"] as? String
                )
            }

            let degraded: [AnthropicStatus.Component] = ((json["components"] as? [[String: Any]]) ?? []).compactMap { d in
                guard let id = d["id"] as? String,
                      let name = d["name"] as? String,
                      let st = d["status"] as? String,
                      st != "operational",
                      (d["group"] as? Bool) != true
                else { return nil }
                return AnthropicStatus.Component(id: id, name: name, status: st)
            }

            status = AnthropicStatus(
                indicator: indicator,
                description: description,
                incidents: incidents,
                degradedComponents: degraded
            )
            lastError = nil
        } catch {
            lastError = error.localizedDescription
        }
    }
}
