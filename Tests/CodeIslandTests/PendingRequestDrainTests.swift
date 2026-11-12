import XCTest
@testable import CodeIsland
import CodeIslandCore

/// A pending permission must be settled only by evidence that its own agent moved past it.
/// It used to be answered "deny" by any activity in the session, a subagent starting included.
@MainActor
final class PendingRequestDrainTests: XCTestCase {

    private func event(_ json: [String: Any]) -> HookEvent {
        let data = try! JSONSerialization.data(withJSONObject: json)
        return HookEvent(from: data)!
    }

    private func permission(session: String, tool: String = "Bash", agent: String? = nil, toolUseId: String? = nil) -> HookEvent {
        var json: [String: Any] = ["hook_event_name": "PermissionRequest", "session_id": session, "tool_name": tool,
                                   "tool_input": ["command": "npm test"]]
        if let agent { json["agent_id"] = agent }
        if let toolUseId { json["tool_use_id"] = toolUseId }
        return event(json)
    }

    private func activity(_ name: String, session: String, tool: String? = nil, agent: String? = nil, toolUseId: String? = nil) -> HookEvent {
        var json: [String: Any] = ["hook_event_name": name, "session_id": session]
        if let tool { json["tool_name"] = tool }
        if let agent { json["agent_id"] = agent }
        if let toolUseId { json["tool_use_id"] = toolUseId }
        return event(json)
    }

    func testSubagentActivityDoesNotSettleTheMainAgentsRequest() {
        let pending = permission(session: "s")
        XCTAssertFalse(AppState.movedPast(pending, incoming: activity("SubagentStart", session: "s", agent: "a1"), normalized: "SubagentStart"))
        XCTAssertFalse(AppState.movedPast(pending, incoming: activity("PreToolUse", session: "s", tool: "Read", agent: "a1"), normalized: "PreToolUse"))
        XCTAssertFalse(AppState.movedPast(pending, incoming: activity("PostToolUse", session: "s", tool: "Bash", agent: "a1"), normalized: "PostToolUse"))
        XCTAssertFalse(AppState.movedPast(pending, incoming: activity("Stop", session: "s", agent: "a1"), normalized: "Stop"))
    }

    func testTheSameAgentFinishingTheToolSettlesIt() {
        let pending = permission(session: "s", toolUseId: "tu-1")
        XCTAssertTrue(AppState.movedPast(pending, incoming: activity("PostToolUse", session: "s", tool: "Bash", toolUseId: "tu-1"), normalized: "PostToolUse"))
        XCTAssertFalse(AppState.movedPast(pending, incoming: activity("PostToolUse", session: "s", tool: "Bash", toolUseId: "tu-2"), normalized: "PostToolUse"))
    }

    func testStopAndANewPromptSettleIt() {
        let pending = permission(session: "s")
        XCTAssertTrue(AppState.movedPast(pending, incoming: activity("Stop", session: "s"), normalized: "Stop"))
        XCTAssertTrue(AppState.movedPast(pending, incoming: activity("UserPromptSubmit", session: "s"), normalized: "UserPromptSubmit"))
    }

    func testASubagentsOwnRequestEndsWithThatSubagent() {
        let pending = permission(session: "s", agent: "a1")
        XCTAssertTrue(AppState.movedPast(pending, incoming: activity("SubagentStop", session: "s", agent: "a1"), normalized: "SubagentStop"))
        XCTAssertFalse(AppState.movedPast(pending, incoming: activity("SubagentStop", session: "s", agent: "a2"), normalized: "SubagentStop"))
    }

    func testADroppedConnectionSettlesOnlyItsOwnRequest() async {
        let appState = AppState()
        let first = Task<Data, Never> {
            await withCheckedContinuation { c in appState.handlePermissionRequest(self.permission(session: "s"), continuation: c, connectionToken: "c1") }
        }
        let second = Task<Data, Never> {
            await withCheckedContinuation { c in appState.handlePermissionRequest(self.permission(session: "s", tool: "Write"), continuation: c, connectionToken: "c2") }
        }
        while appState.permissionQueue.count < 2 { await Task.yield() }
        appState.handlePeerDisconnect(sessionId: "s", connectionToken: "c1")
        _ = await first.value
        XCTAssertEqual(appState.permissionQueue.count, 1)
        XCTAssertEqual(appState.permissionQueue.first?.connectionToken, "c2")
        appState.handlePeerDisconnect(sessionId: "s", connectionToken: "c2")
        _ = await second.value
    }
}
