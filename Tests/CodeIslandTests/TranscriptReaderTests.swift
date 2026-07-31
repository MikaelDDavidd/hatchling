import XCTest
@testable import CodeIsland
import CodeIslandCore

/// Reading a conversation back out of a CLI transcript.
///
/// Built against a synthetic file rather than a real one so the assertions stay true when the
/// machine running them has no Claude history — but shaped exactly like the real thing,
/// including the parts that must be skipped.
final class TranscriptReaderTests: XCTestCase {

    private var file: URL!

    override func setUpWithError() throws {
        file = FileManager.default.temporaryDirectory
            .appendingPathComponent("transcript-\(UUID().uuidString).jsonl")
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: file)
    }

    private func write(_ lines: [String]) throws {
        try lines.joined(separator: "\n").write(to: file, atomically: true, encoding: .utf8)
    }

    private func userLine(_ text: String, at: String = "2026-07-25T04:42:54.934Z") -> String {
        """
        {"type":"user","timestamp":"\(at)","message":{"role":"user","content":"\(text)"}}
        """
    }

    private func assistantLine(text: String?, tools: [String] = [], sidechain: Bool = false) -> String {
        var blocks: [String] = [#"{"type":"thinking","thinking":"hmm"}"#]
        if let text { blocks.append("{\"type\":\"text\",\"text\":\"\(text)\"}") }
        for tool in tools { blocks.append("{\"type\":\"tool_use\",\"name\":\"\(tool)\"}") }
        return """
        {"type":"assistant","isSidechain":\(sidechain),"timestamp":"2026-07-25T04:43:00.000Z","message":{"role":"assistant","content":[\(blocks.joined(separator: ","))]}}
        """
    }

    // MARK: - Order and paging

    func testNewestMessageComesFirst() throws {
        // A chat opens at the bottom, so the page has to start from the end of the file.
        try write([
            userLine("primeira"),
            assistantLine(text: "resposta um"),
            userLine("segunda"),
            assistantLine(text: "resposta dois"),
        ])

        let page = try XCTUnwrap(TranscriptReader.page(path: file.path, before: nil, limit: 10))
        XCTAssertEqual(page.messages.first?.text, "resposta dois")
        XCTAssertEqual(page.messages.last?.text, "primeira")
    }

    func testPagingWalksBackwardsWithoutRepeatingOrSkipping() throws {
        var lines: [String] = []
        for index in 0..<50 { lines.append(userLine("m\(index)")) }
        try write(lines)

        let first = try XCTUnwrap(TranscriptReader.page(path: file.path, before: nil, limit: 20))
        XCTAssertEqual(first.messages.count, 20)
        XCTAssertEqual(first.messages.first?.text, "m49")
        XCTAssertFalse(first.reachedStart)

        let second = try XCTUnwrap(TranscriptReader.page(path: file.path, before: first.nextBefore, limit: 20))
        XCTAssertEqual(second.messages.first?.text, "m29", "second page must continue where the first stopped")

        let all = first.messages.map(\.text) + second.messages.map(\.text)
        XCTAssertEqual(Set(all).count, all.count, "a message was served twice")
    }

    func testTheStartOfTheConversationIsAnnounced() throws {
        try write([userLine("only one")])

        let page = try XCTUnwrap(TranscriptReader.page(path: file.path, before: nil, limit: 20))
        XCTAssertEqual(page.messages.count, 1)
        XCTAssertTrue(page.reachedStart, "the app needs to know to stop asking for more")
        XCTAssertNil(page.nextBefore)
    }

    // MARK: - What counts as conversation

    func testSubagentChatterIsLeftOut() throws {
        // Interleaving a subagent's thread into this one reads as nonsense.
        try write([
            userLine("pergunta"),
            assistantLine(text: "do subagente", sidechain: true),
            assistantLine(text: "resposta de verdade"),
        ])

        let page = try XCTUnwrap(TranscriptReader.page(path: file.path, before: nil, limit: 10))
        XCTAssertEqual(page.messages.count, 2)
        XCTAssertFalse(page.messages.contains { $0.text == "do subagente" })
    }

    func testThinkingIsNotShown() throws {
        try write([assistantLine(text: "o que eu disse")])

        let page = try XCTUnwrap(TranscriptReader.page(path: file.path, before: nil, limit: 10))
        XCTAssertEqual(page.messages.first?.text, "o que eu disse")
        XCTAssertFalse(page.messages.first?.text.contains("hmm") ?? true)
    }

    func testToolsAreNamedNotExpanded() throws {
        try write([assistantLine(text: "vou rodar", tools: ["Bash", "Read"])])

        let message = try XCTUnwrap(TranscriptReader.page(path: file.path, before: nil, limit: 10)?.messages.first)
        XCTAssertEqual(message.tools, ["Bash", "Read"])
        XCTAssertEqual(message.text, "vou rodar")
    }

    func testATurnThatOnlyCalledToolsStillAppears() throws {
        // It shows the agent acting, which is exactly what someone watching from a phone wants.
        try write([assistantLine(text: nil, tools: ["Bash"])])

        let page = try XCTUnwrap(TranscriptReader.page(path: file.path, before: nil, limit: 10))
        XCTAssertEqual(page.messages.count, 1)
        XCTAssertEqual(page.messages.first?.tools, ["Bash"])
    }

    func testBookkeepingLinesAreIgnored() throws {
        try write([
            #"{"type":"file-history-snapshot","messageId":"x"}"#,
            #"{"type":"ai-title","title":"Some title"}"#,
            #"{"type":"permission-mode","mode":"acceptEdits"}"#,
            userLine("a unica mensagem"),
            "not json at all",
        ])

        let page = try XCTUnwrap(TranscriptReader.page(path: file.path, before: nil, limit: 10))
        XCTAssertEqual(page.messages.count, 1)
        XCTAssertEqual(page.messages.first?.text, "a unica mensagem")
    }

    // MARK: - Robustness

    func testAMessageLongerThanTheCapIsTruncated() throws {
        try write([userLine(String(repeating: "x", count: 20_000))])

        let message = try XCTUnwrap(TranscriptReader.page(path: file.path, before: nil, limit: 10)?.messages.first)
        XCTAssertEqual(message.text.count, 8000)
    }

    func testAMissingFileIsNotACrash() {
        XCTAssertNil(TranscriptReader.page(path: "/nope/does-not-exist.jsonl", before: nil))
    }

    func testAnEmptyFileIsNotACrash() throws {
        try write([])
        XCTAssertNil(TranscriptReader.page(path: file.path, before: nil))
    }

    /// The window is 512 KB, so a conversation bigger than one window exercises the seam where
    /// a line is split across two reads — the classic place a backwards reader loses a message.
    func testAConversationLargerThanOneWindowPagesCorrectly() throws {
        var lines: [String] = []
        let padding = String(repeating: "y", count: 2000)
        for index in 0..<400 { lines.append(userLine("m\(index) \(padding)")) }
        try write(lines)

        let page = try XCTUnwrap(TranscriptReader.page(path: file.path, before: nil, limit: 30))
        XCTAssertEqual(page.messages.count, 30)
        XCTAssertTrue(page.messages.first?.text.hasPrefix("m399") ?? false)
        XCTAssertFalse(page.reachedStart)

        // And walking all the way back must arrive at the first message exactly once.
        var seen: [String] = []
        var cursor: Int? = nil
        for _ in 0..<20 {
            guard let next = TranscriptReader.page(path: file.path, before: cursor, limit: 30) else { break }
            seen.append(contentsOf: next.messages.map { String($0.text.prefix(6)) })
            if next.reachedStart { break }
            cursor = next.nextBefore
        }
        XCTAssertEqual(Set(seen).count, seen.count, "paging across the window seam duplicated a message")
        XCTAssertTrue(seen.contains { $0.hasPrefix("m0 ") }, "never reached the first message")
    }
}
