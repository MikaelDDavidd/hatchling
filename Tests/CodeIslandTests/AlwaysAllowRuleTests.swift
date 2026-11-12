import XCTest
@testable import CodeIsland
import CodeIslandCore

@MainActor
final class AlwaysAllowRuleTests: XCTestCase {
    private func event(_ json: [String: Any]) -> HookEvent {
        HookEvent(from: try! JSONSerialization.data(withJSONObject: json))!
    }

    func testBashIsNarrowedToTheCommandNotTheWholeTool() {
        let rules = AppState.alwaysAllowRules(for: event(["hook_event_name": "PermissionRequest", "session_id": "s",
            "tool_name": "Bash", "tool_input": ["command": "npm run test -- --coverage"]]))
        let rule = ((rules.first?["rules"] as? [[String: Any]])?.first)
        XCTAssertEqual(rule?["toolName"] as? String, "Bash")
        XCTAssertEqual(rule?["ruleContent"] as? String, "npm run:*")
        XCTAssertEqual(rules.first?["destination"] as? String, "session")
    }

    func testTheCLIsOwnSuggestionWinsButStaysInTheSession() {
        let suggestion: [String: Any] = ["type": "addRules", "rules": [["toolName": "Bash", "ruleContent": "npm test:*"]],
                                         "behavior": "allow", "destination": "localSettings"]
        let rules = AppState.alwaysAllowRules(for: event(["hook_event_name": "PermissionRequest", "session_id": "s",
            "tool_name": "Bash", "tool_input": ["command": "npm test"], "permission_suggestions": [suggestion]]))
        XCTAssertEqual(rules.count, 1)
        XCTAssertEqual(rules.first?["destination"] as? String, "session")
        XCTAssertEqual(((rules.first?["rules"] as? [[String: Any]])?.first?["ruleContent"]) as? String, "npm test:*")
    }
}
