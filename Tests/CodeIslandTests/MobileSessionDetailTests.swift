import XCTest
@testable import CodeIsland
import CodeIslandCore

/// The transcript the phone's detail screen is built from.
///
/// The interesting decisions here are about what does *not* cross the wire: a session can
/// accumulate hundreds of tool calls and a single assistant message can be enormous, and the
/// relay would carry all of it every few seconds if nothing capped it.
@MainActor
final class MobileSessionDetailTests: XCTestCase {

    private func session(tools: Int = 0, messages: Int = 0) -> SessionSnapshot {
        var snapshot = SessionSnapshot()
        snapshot.cwd = "/Users/mikaeldavid/Projetos/Hatchling"
        for index in 0..<tools {
            snapshot.toolHistory.append(
                ToolHistoryEntry(
                    tool: "Tool\(index)",
                    description: "step \(index)",
                    timestamp: Date(timeIntervalSince1970: TimeInterval(1000 + index)),
                    success: index % 5 != 0,
                    agentType: index % 3 == 0 ? "Explore" : nil
                )
            )
        }
        for index in 0..<messages {
            snapshot.recentMessages.append(ChatMessage(isUser: index % 2 == 0, text: "message \(index)"))
        }
        return snapshot
    }

    func testDetailCarriesToolsNewestFirst() {
        // The phone reads from the top, so the most recent call has to be the first row.
        let appState = AppState()
        appState.sessions["s"] = session(tools: 5)

        let detail = appState.mobileSessionDetail(for: "s")
        XCTAssertEqual(detail?.tools.first?.tool, "Tool4")
        XCTAssertEqual(detail?.tools.last?.tool, "Tool0")
    }

    func testToolHistoryIsCapped() {
        // A long session can run hundreds of tools; the wire carries the recent window.
        let appState = AppState()
        appState.sessions["s"] = session(tools: 200)

        let detail = appState.mobileSessionDetail(for: "s")
        XCTAssertEqual(detail?.tools.count, 60)
        // Still the newest ones, not the first 60.
        XCTAssertEqual(detail?.tools.first?.tool, "Tool199")
    }

    func testFailuresAndSubagentsSurvive() {
        let appState = AppState()
        appState.sessions["s"] = session(tools: 6)

        let detail = appState.mobileSessionDetail(for: "s")
        let entries = try? XCTUnwrap(detail?.tools)
        XCTAssertEqual(entries?.first(where: { $0.tool == "Tool0" })?.ok, false, "index 0 was seeded as a failure")
        XCTAssertEqual(entries?.first(where: { $0.tool == "Tool0" })?.agent, "Explore")
        XCTAssertNil(entries?.first(where: { $0.tool == "Tool1" })?.agent, "main thread entries carry no agent")
    }

    func testHugeMessagesAreTruncatedRatherThanSent() {
        let appState = AppState()
        var snapshot = session()
        snapshot.recentMessages.append(ChatMessage(isUser: false, text: String(repeating: "x", count: 50_000)))
        appState.sessions["s"] = snapshot

        let detail = appState.mobileSessionDetail(for: "s")
        XCTAssertEqual(detail?.messages.first?.text.count, 4000)
    }

    func testUnknownSessionHasNoDetail() {
        let appState = AppState()
        XCTAssertNil(appState.mobileSessionDetail(for: "nope"))
    }

    func testWatchingASessionIsRefusedWhenItIsGone() {
        let appState = AppState()
        XCTAssertEqual(appState.handleMobileCommand(.watch(sessionId: "nope")), "Unknown session")
    }

    func testWatchingRemembersTheSessionSoUpdatesKeepFlowing() {
        // Without this the detail screen would show whatever was true when it was opened and
        // then quietly go stale.
        let appState = AppState()
        appState.sessions["s"] = session(tools: 2)
        defer { MobileBridge.shared.watchedSessionId = nil }

        XCTAssertNil(appState.handleMobileCommand(.watch(sessionId: "s")))
        XCTAssertEqual(MobileBridge.shared.watchedSessionId, "s")

        XCTAssertNil(appState.handleMobileCommand(.unwatch))
        XCTAssertNil(MobileBridge.shared.watchedSessionId)
    }

    func testDetailEncodesToTheKeysTheAppExpects() throws {
        let appState = AppState()
        appState.sessions["s"] = session(tools: 1, messages: 1)

        let detail = try XCTUnwrap(appState.mobileSessionDetail(for: "s"))
        let data = try JSONEncoder().encode(detail)
        let json = try XCTUnwrap(try JSONSerialization.jsonObject(with: data) as? [String: Any])

        XCTAssertEqual(Set(json.keys).isSuperset(of: ["sessionId", "tools", "messages", "subagents"]), true)

        let tool = try XCTUnwrap((json["tools"] as? [[String: Any]])?.first)
        XCTAssertEqual(Set(tool.keys).isSuperset(of: ["tool", "at", "ok"]), true, "tool shape drifted from PROTOCOL.md")

        let message = try XCTUnwrap((json["messages"] as? [[String: Any]])?.first)
        XCTAssertNotNil(message["user"])
        XCTAssertNotNil(message["text"])
    }
}
