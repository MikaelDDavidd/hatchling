import XCTest
@testable import CodeIsland
import CodeIslandCore

/// Does answering from the phone actually unblock the agent?
///
/// This is the question the whole app hangs on, and the one that has already been got wrong
/// once: answers used to be keyed by header, which meant they came back looking correct and
/// were silently dropped. So these assert on the hook's *response payload* — what the CLI
/// really receives — rather than on the queue being drained.
@MainActor
final class MobileCommandTests: XCTestCase {

    // MARK: - Helpers

    private func permissionEvent(sessionId: String, tool: String = "Bash") throws -> HookEvent {
        let payload: [String: Any] = [
            "hook_event_name": "PermissionRequest",
            "session_id": sessionId,
            "tool_name": tool,
            "tool_input": ["command": "rm -rf build", "description": "Clean the build"],
        ]
        return try XCTUnwrap(HookEvent(from: try JSONSerialization.data(withJSONObject: payload)))
    }

    private func askEvent(sessionId: String, questions: [[String: Any]]) throws -> HookEvent {
        let payload: [String: Any] = [
            "hook_event_name": "PermissionRequest",
            "session_id": sessionId,
            "tool_name": "AskUserQuestion",
            "tool_input": ["questions": questions],
        ]
        return try XCTUnwrap(HookEvent(from: try JSONSerialization.data(withJSONObject: payload)))
    }

    private func decision(from data: Data) throws -> [String: Any] {
        let json = try XCTUnwrap(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        let hookOutput = try XCTUnwrap(json["hookSpecificOutput"] as? [String: Any])
        return try XCTUnwrap(hookOutput["decision"] as? [String: Any])
    }

    // MARK: - Permissions

    func testAllowFromThePhoneUnblocksTheHook() async throws {
        let appState = AppState()
        let event = try permissionEvent(sessionId: "s1")

        let response = Task<Data, Never> {
            await withCheckedContinuation { continuation in
                appState.handlePermissionRequest(event, continuation: continuation)
            }
        }
        await Task.yield()

        let attentionId = try XCTUnwrap(appState.permissionQueue.first?.id)
        let failure = appState.handleMobileCommand(.permissionRespond(attentionId: attentionId, decision: "allow"))
        XCTAssertNil(failure)

        let behavior = try decision(from: await response.value)["behavior"] as? String
        XCTAssertEqual(behavior, "allow")
        XCTAssertTrue(appState.permissionQueue.isEmpty)
    }

    func testDenyFromThePhoneIsRelayedAsDeny() async throws {
        let appState = AppState()
        let event = try permissionEvent(sessionId: "s2")

        let response = Task<Data, Never> {
            await withCheckedContinuation { continuation in
                appState.handlePermissionRequest(event, continuation: continuation)
            }
        }
        await Task.yield()

        let attentionId = try XCTUnwrap(appState.permissionQueue.first?.id)
        XCTAssertNil(appState.handleMobileCommand(.permissionRespond(attentionId: attentionId, decision: "deny")))

        let behavior = try decision(from: await response.value)["behavior"] as? String
        XCTAssertEqual(behavior, "deny")
    }

    /// The race this app makes possible: answer on the Mac, then the phone's tap arrives.
    func testAnAnswerForAResolvedRequestIsRefusedRatherThanAppliedToTheNextOne() async throws {
        let appState = AppState()

        let first = Task<Data, Never> {
            await withCheckedContinuation { continuation in
                appState.handlePermissionRequest(try! self.permissionEvent(sessionId: "a"), continuation: continuation)
            }
        }
        await Task.yield()
        let staleId = try XCTUnwrap(appState.permissionQueue.first?.id)

        // Answered on the Mac.
        appState.approvePermission(always: false)
        _ = await first.value

        // A second request takes its place.
        let second = Task<Data, Never> {
            await withCheckedContinuation { continuation in
                appState.handlePermissionRequest(try! self.permissionEvent(sessionId: "b", tool: "Write"), continuation: continuation)
            }
        }
        await Task.yield()

        // The phone's tap, carrying the id of the one already gone.
        let failure = appState.handleMobileCommand(.permissionRespond(attentionId: staleId, decision: "allow"))
        XCTAssertNotNil(failure, "a stale answer must not fall through to the next request")
        XCTAssertEqual(appState.permissionQueue.count, 1, "the live request should be untouched")

        // Clean up the still-waiting hook.
        appState.denyPermission()
        _ = await second.value
    }

    func testAnUnknownDecisionIsRejected() async throws {
        let appState = AppState()
        let event = try permissionEvent(sessionId: "s3")
        let response = Task<Data, Never> {
            await withCheckedContinuation { continuation in
                appState.handlePermissionRequest(event, continuation: continuation)
            }
        }
        await Task.yield()

        let attentionId = try XCTUnwrap(appState.permissionQueue.first?.id)
        XCTAssertNotNil(appState.handleMobileCommand(.permissionRespond(attentionId: attentionId, decision: "maybe")))
        XCTAssertEqual(appState.permissionQueue.count, 1)

        appState.denyPermission()
        _ = await response.value
    }

    // MARK: - Questions

    func testAnswersFromThePhoneReachTheToolKeyedByQuestionText() async throws {
        let appState = AppState()
        let event = try askEvent(sessionId: "q1", questions: [
            [
                "question": "Which database should we use?",
                "header": "DB",
                "options": [["label": "Postgres", "description": "Relational"], ["label": "SQLite", "description": ""]],
            ]
        ])

        let response = Task<Data, Never> {
            await withCheckedContinuation { continuation in
                appState.handleAskUserQuestion(event, continuation: continuation)
            }
        }
        await Task.yield()

        let attentionId = try XCTUnwrap(appState.questionQueue.first?.id)
        let failure = appState.handleMobileCommand(.questionAnswer(
            attentionId: attentionId,
            answers: ["Which database should we use?": "Postgres"]
        ))
        XCTAssertNil(failure)

        // The payload the CLI receives — keyed by question text, with `questions` still intact.
        let decisionBody = try decision(from: await response.value)
        let updatedInput = try XCTUnwrap(decisionBody["updatedInput"] as? [String: Any])
        let answers = try XCTUnwrap(updatedInput["answers"] as? [String: Any])
        XCTAssertEqual(answers["Which database should we use?"] as? String, "Postgres")
        XCTAssertNotNil(updatedInput["questions"], "dropping questions is the H.map crash")
    }

    func testMultiQuestionAnswersAllArriveTogether() async throws {
        let appState = AppState()
        let event = try askEvent(sessionId: "q2", questions: [
            ["question": "How should we work?", "header": "Mode",
             "options": [["label": "Plan", "description": ""], ["label": "Execute", "description": ""]]],
            ["question": "Which tone?", "header": "Style",
             "options": [["label": "Terse", "description": ""], ["label": "Balanced", "description": ""]]],
        ])

        let response = Task<Data, Never> {
            await withCheckedContinuation { continuation in
                appState.handleAskUserQuestion(event, continuation: continuation)
            }
        }
        await Task.yield()

        let attentionId = try XCTUnwrap(appState.questionQueue.first?.id)
        XCTAssertNil(appState.handleMobileCommand(.questionAnswer(
            attentionId: attentionId,
            answers: ["How should we work?": "Plan", "Which tone?": "Balanced"]
        )))

        let payload = await response.value
        let updatedInput = try XCTUnwrap(try decision(from: payload)["updatedInput"] as? [String: Any])
        let answers = try XCTUnwrap(updatedInput["answers"] as? [String: Any])
        XCTAssertEqual(answers["How should we work?"] as? String, "Plan")
        XCTAssertEqual(answers["Which tone?"] as? String, "Balanced")
    }

    func testSkipFromThePhoneDeniesRatherThanHanging() async throws {
        let appState = AppState()
        let event = try askEvent(sessionId: "q3", questions: [
            ["question": "Anything?", "header": "H", "options": [["label": "A", "description": ""]]]
        ])

        let response = Task<Data, Never> {
            await withCheckedContinuation { continuation in
                appState.handleAskUserQuestion(event, continuation: continuation)
            }
        }
        await Task.yield()

        let attentionId = try XCTUnwrap(appState.questionQueue.first?.id)
        XCTAssertNil(appState.handleMobileCommand(.questionSkip(attentionId: attentionId)))

        let behavior = try decision(from: await response.value)["behavior"] as? String
        XCTAssertEqual(behavior, "deny")
        XCTAssertTrue(appState.questionQueue.isEmpty)
    }

    // MARK: - Interrupt

    func testInterruptingASessionWithNoProcessSaysSoInsteadOfFailingSilently() {
        let appState = AppState()
        var snapshot = SessionSnapshot()
        snapshot.cliPid = nil
        appState.sessions["dead"] = snapshot

        let failure = appState.handleMobileCommand(.interrupt(sessionId: "dead"))
        XCTAssertNotNil(failure)
        XCTAssertTrue(failure?.contains("no live process") == true, "got: \(failure ?? "nil")")
    }

    func testInterruptingAnUnknownSessionIsRefused() {
        let appState = AppState()
        XCTAssertEqual(appState.handleMobileCommand(.interrupt(sessionId: "nope")), "Unknown session")
    }

    // MARK: - Prompt

    func testPromptingASessionThatIsNotInTmuxExplainsWhyRatherThanPretending() {
        // canPrompt is published to the phone so the box can be hidden, but the command must
        // still refuse clearly if it arrives anyway.
        UserDefaults.standard.set(false, forKey: SettingsKey.mobileAllowKeystrokeInjection)
        defer { UserDefaults.standard.removeObject(forKey: SettingsKey.mobileAllowKeystrokeInjection) }

        let appState = AppState()
        var snapshot = SessionSnapshot()
        snapshot.tmuxPane = nil
        snapshot.cliPid = 1
        appState.sessions["plain"] = snapshot

        let failure = appState.handleMobileCommand(.prompt(sessionId: "plain", text: "hello"))
        XCTAssertNotNil(failure)
        XCTAssertTrue(failure?.contains("tmux") == true, "got: \(failure ?? "nil")")
    }

    func testAnEmptyPromptIsRejected() {
        let appState = AppState()
        var snapshot = SessionSnapshot()
        snapshot.tmuxPane = "%1"
        appState.sessions["s"] = snapshot

        XCTAssertEqual(appState.handleMobileCommand(.prompt(sessionId: "s", text: "   ")), "Empty prompt")
    }
}
