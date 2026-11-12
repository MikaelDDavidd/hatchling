import XCTest
@testable import CodeIslandCore

final class IdlePromptTests: XCTestCase {
    private func event(_ payload: [String: Any]) throws -> HookEvent {
        var p = payload
        p["session_id"] = p["session_id"] ?? "s1"
        p["cwd"] = p["cwd"] ?? "/tmp/projeto"
        return try XCTUnwrap(HookEvent(from: try JSONSerialization.data(withJSONObject: p)))
    }

    private func processing() -> [String: SessionSnapshot] {
        var s = SessionSnapshot()
        s.status = .processing
        return ["s1": s]
    }

    /// The Stop was lost; the idle notification is all that arrives.
    func testIdlePromptEndsAProcessingSession() throws {
        var sessions = processing()
        _ = reduceEvent(sessions: &sessions, event: try event([
            "hook_event_name": "Notification", "notification_type": "idle_prompt",
            "message": "Claude is waiting for your input"]), maxHistory: 10)
        XCTAssertEqual(sessions["s1"]?.status, .idle)
        XCTAssertNil(sessions["s1"]?.toolDescription)
    }

    func testOlderClaudeWithoutTheTypeIsRecognisedByItsMessage() throws {
        var sessions = processing()
        _ = reduceEvent(sessions: &sessions, event: try event([
            "hook_event_name": "Notification", "message": "Claude is waiting for your input"]), maxHistory: 10)
        XCTAssertEqual(sessions["s1"]?.status, .idle)
    }

    func testOtherNotificationsKeepTheSessionWorking() throws {
        var sessions = processing()
        _ = reduceEvent(sessions: &sessions, event: try event([
            "hook_event_name": "Notification", "notification_type": "permission_prompt",
            "message": "Claude needs your permission to use Bash"]), maxHistory: 10)
        XCTAssertEqual(sessions["s1"]?.status, .processing)
        XCTAssertEqual(sessions["s1"]?.toolDescription, "Claude needs your permission to use Bash")
    }

    func testAPendingApprovalIsNotClearedByTheIdleNotification() throws {
        var s = SessionSnapshot()
        s.status = .waitingApproval
        var sessions = ["s1": s]
        _ = reduceEvent(sessions: &sessions, event: try event([
            "hook_event_name": "Notification", "notification_type": "idle_prompt",
            "message": "Claude is waiting for your input"]), maxHistory: 10)
        XCTAssertEqual(sessions["s1"]?.status, .waitingApproval)
    }
}
