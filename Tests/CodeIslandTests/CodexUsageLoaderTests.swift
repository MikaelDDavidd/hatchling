import XCTest
@testable import CodeIsland

final class CodexUsageLoaderTests: XCTestCase {
    private var root: URL!

    override func setUpWithError() throws {
        root = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("CodexUsageLoaderTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: root)
    }

    private func tokenCountLine(primary: Double, secondary: Double, plan: String = "pro") -> String {
        """
        {"type":"event_msg","timestamp":"2026-07-25T01:00:00.000Z","payload":{"type":"token_count",\
        "rate_limits":{"plan_type":"\(plan)",\
        "primary":{"used_percent":\(primary),"window_minutes":300},\
        "secondary":{"used_percent":\(secondary),"window_minutes":10080}}}}
        """
    }

    @discardableResult
    private func writeRollout(
        day: String,
        name: String,
        lines: [String],
        modifiedAt: Date? = nil
    ) throws -> URL {
        let dir = root.appendingPathComponent("2026/07/\(day)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let url = dir.appendingPathComponent(name)
        try lines.joined(separator: "\n").write(to: url, atomically: true, encoding: .utf8)
        if let modifiedAt {
            try FileManager.default.setAttributes([.modificationDate: modifiedAt], ofItemAtPath: url.path)
        }
        return url
    }

    func testReadsMostRecentRateLimitsFromRollout() throws {
        try writeRollout(day: "25", name: "rollout-2026-07-25T10-00-00-abc.jsonl", lines: [
            #"{"type":"session_meta","payload":{"cwd":"/tmp/project"}}"#,
            tokenCountLine(primary: 10, secondary: 5),
            #"{"type":"event_msg","payload":{"type":"agent_message","message":"hi"}}"#,
            tokenCountLine(primary: 73.4, secondary: 21)
        ])

        let snap = try XCTUnwrap(CodexUsageLoader.load(fromRootURL: root))
        XCTAssertEqual(snap.planType, "pro")
        XCTAssertEqual(snap.maxPercent, 73)
        XCTAssertEqual(snap.windows.count, 2)
        XCTAssertEqual(snap.windows.first?.label, "5h")
        XCTAssertEqual(snap.windows.last?.label, "7d")
    }

    /// The regression that hung the app on launch: a rollout far larger than the
    /// first tail window must still resolve, cheaply, from its tail.
    func testResolvesUsageFromLargeRolloutTail() throws {
        let padding = String(repeating: "z", count: 4096)
        var lines = [#"{"type":"session_meta","payload":{"cwd":"/tmp/project"}}"#]
        // ~8 MB of noise ahead of the usage record.
        for _ in 0..<2000 {
            lines.append(#"{"type":"event_msg","payload":{"type":"agent_message","message":"\#(padding)"}}"#)
        }
        lines.append(tokenCountLine(primary: 55, secondary: 12))
        try writeRollout(day: "25", name: "rollout-2026-07-25T11-00-00-big.jsonl", lines: lines)

        let snap = try XCTUnwrap(CodexUsageLoader.load(fromRootURL: root))
        XCTAssertEqual(snap.maxPercent, 55)
    }

    func testPrefersNewestFileAndFallsBackWhenItHasNoRateLimits() throws {
        try writeRollout(
            day: "24",
            name: "rollout-2026-07-24T10-00-00-old.jsonl",
            lines: [tokenCountLine(primary: 30, secondary: 8)],
            modifiedAt: Date(timeIntervalSince1970: 1_700_000_000)
        )
        // Newest file, but nothing usable inside — loader must fall through.
        try writeRollout(
            day: "25",
            name: "rollout-2026-07-25T10-00-00-new.jsonl",
            lines: [#"{"type":"event_msg","payload":{"type":"agent_message","message":"no usage here"}}"#],
            modifiedAt: Date(timeIntervalSince1970: 1_800_000_000)
        )

        let snap = try XCTUnwrap(CodexUsageLoader.load(fromRootURL: root))
        XCTAssertEqual(snap.maxPercent, 30)
    }

    func testReturnsNilWhenNoRolloutsExist() throws {
        XCTAssertNil(try CodexUsageLoader.load(fromRootURL: root))
        let missing = root.appendingPathComponent("does-not-exist", isDirectory: true)
        XCTAssertNil(try CodexUsageLoader.load(fromRootURL: missing))
    }
}
