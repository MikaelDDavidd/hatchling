import XCTest
@testable import CodeIsland
import CodeIslandCore

/// The wire format has three implementations — Swift here, TypeScript in the relay, Kotlin in
/// the app. Nothing but tests keeps them honest, so these assert on the actual JSON rather than
/// round-tripping through Swift's own encoder, which would pass even if a key were renamed.
final class MobileProtocolTests: XCTestCase {

    private func encodeToObject<T: Encodable>(_ value: T) throws -> [String: Any] {
        let data = try JSONEncoder().encode(value)
        return try XCTUnwrap(try JSONSerialization.jsonObject(with: data) as? [String: Any])
    }

    // MARK: - Envelope

    func testEnvelopeCarriesTheFieldsTheRelayReads() throws {
        let envelope = MobileEnvelope(
            type: MobileMessageType.hello,
            body: MobileHello(role: "mac", token: "hbt_x", device: "Mac")
        )
        let json = try encodeToObject(envelope)

        XCTAssertEqual(json["v"] as? Int, 1)
        XCTAssertEqual(json["type"] as? String, "hello")
        XCTAssertNotNil(json["id"] as? String)
        XCTAssertNotNil(json["ts"] as? Int)

        let body = try XCTUnwrap(json["body"] as? [String: Any])
        XCTAssertEqual(body["role"] as? String, "mac")
        XCTAssertEqual(body["token"] as? String, "hbt_x")
    }

    func testEnvelopeHeaderDecodesWithoutKnowingTheBody() throws {
        // The relay sends bodies this build may not have a type for yet; the header must still
        // parse so the receiver can switch on `type` and ignore what it does not know.
        let raw = """
        {"v":1,"type":"something.new","id":"01ABC","ts":1753900000,"body":{"whatever":[1,2,3]}}
        """
        let header = try JSONDecoder().decode(MobileEnvelopeHeader.self, from: Data(raw.utf8))
        XCTAssertEqual(header.type, "something.new")
        XCTAssertEqual(header.id, "01ABC")
        XCTAssertEqual(header.v, 1)
    }

    // MARK: - Session

    func testSessionKeysMatchTheProtocolDocument() throws {
        let session = MobileSession(
            sessionId: "s1", source: "claude", status: "running", project: "Hatchling",
            cwd: "/tmp", model: "opus-5", currentTool: "Bash", toolDescription: "tests",
            lastUserPrompt: "run", lastAssistantMessage: "done",
            startTime: 1, lastActivity: 2, interrupted: false, canPrompt: true, contextPercent: 43
        )
        let json = try encodeToObject(session)

        let expected: Set<String> = [
            "sessionId", "source", "status", "project", "cwd", "model", "currentTool",
            "toolDescription", "lastUserPrompt", "lastAssistantMessage", "startTime",
            "lastActivity", "interrupted", "canPrompt", "contextPercent",
        ]
        XCTAssertEqual(Set(json.keys), expected, "Session shape drifted from docs/PROTOCOL.md")
    }

    func testOptionalSessionFieldsAreOmittedNotNulled() throws {
        let session = MobileSession(
            sessionId: "s1", source: "claude", status: "idle", project: "P",
            cwd: nil, model: nil, currentTool: nil, toolDescription: nil,
            lastUserPrompt: nil, lastAssistantMessage: nil,
            startTime: 1, lastActivity: 2, interrupted: false, canPrompt: false, contextPercent: nil
        )
        let json = try encodeToObject(session)
        XCTAssertNil(json["cwd"])
        XCTAssertNil(json["contextPercent"])
        XCTAssertEqual(json["canPrompt"] as? Bool, false)
    }

    // MARK: - Attention

    func testQuestionAnswersAreKeyedByQuestionText() throws {
        // Regression guard for bda258e: keying by `header` silently loses the answer.
        let answer = MobileQuestionAnswer(
            attentionId: "a1",
            answers: ["Which database should we use?": "Postgres"]
        )
        let json = try encodeToObject(answer)
        let answers = try XCTUnwrap(json["answers"] as? [String: Any])
        XCTAssertEqual(answers["Which database should we use?"] as? String, "Postgres")
    }

    func testAttentionSurvivesARoundTrip() throws {
        let attention = MobileAttention(
            attentionId: "a1", sessionId: "s1", kind: "question", project: "Hatchling",
            tool: "AskUserQuestion", toolInput: nil,
            questions: [
                MobileQuestion(
                    question: "Which database?", header: "DB", multiSelect: false,
                    options: [
                        MobileQuestionOption(label: "Postgres", description: "Relational"),
                        MobileQuestionOption(label: "SQLite", description: nil),
                    ]
                )
            ]
        )
        let data = try JSONEncoder().encode(attention)
        let decoded = try JSONDecoder().decode(MobileAttention.self, from: data)

        XCTAssertEqual(decoded.attentionId, "a1")
        XCTAssertEqual(decoded.questions?.count, 1)
        XCTAssertEqual(decoded.questions?.first?.options.count, 2)
        XCTAssertEqual(decoded.questions?.first?.options.first?.description, "Relational")
        XCTAssertNil(decoded.questions?.first?.options.last?.description)
    }

    // MARK: - Ids

    func testGeneratedIdsAreSortableAndUnique() {
        var ids: [String] = []
        for _ in 0..<200 { ids.append(MobileID.generate()) }

        XCTAssertEqual(Set(ids).count, 200, "ids collided")
        XCTAssertTrue(ids.allSatisfy { $0.count == 26 }, "expected 26-char ULID layout")

        // Timestamp-prefixed, so lexicographic order tracks creation order. The phone relies on
        // this to sort attention without a separate sequence number.
        let alphabet = Set("0123456789ABCDEFGHJKMNPQRSTVWXYZ")
        XCTAssertTrue(ids.allSatisfy { $0.allSatisfy(alphabet.contains) }, "non-Crockford char")

        let earliest: String = ids[0]
        Thread.sleep(forTimeInterval: 0.005)
        let latest: String = MobileID.generate()
        XCTAssertGreaterThan(latest, earliest, "ids should sort by creation time")
    }
}
