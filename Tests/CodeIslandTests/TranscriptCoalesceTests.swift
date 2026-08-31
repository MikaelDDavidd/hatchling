import XCTest
@testable import CodeIsland
import CodeIslandCore

/// Merging the transcript's line-per-block layout back into turns.
final class TranscriptCoalesceTests: XCTestCase {

    private func message(_ user: Bool, _ text: String, at: Int, tools: [String] = []) -> MobileChatMessage {
        MobileChatMessage(user: user, text: text, at: at, tools: tools)
    }

    func testToolOnlyEntriesFoldIntoWhatWasSaidBeforeThem() {
        // Newest first, the order a page comes back in.
        let page = [
            message(false, "", at: 30, tools: ["Read"]),
            message(false, "", at: 20, tools: ["Bash"]),
            message(false, "starting", at: 10),
        ]

        let turns = TranscriptReader.coalesce(page)

        XCTAssertEqual(turns.count, 1)
        XCTAssertEqual(turns[0].text, "starting")
        XCTAssertEqual(turns[0].tools, ["Bash", "Read"], "in the order they ran")
        XCTAssertEqual(turns[0].at, 10)
    }

    func testTwoThingsSaidStayTwoTurns() {
        // The whole point: a working session is a sequence of sentences, each with what it went
        // on to run. Merging them all would be one wall of text.
        let page = [
            message(false, "", at: 40, tools: ["Bash"]),
            message(false, "zero erro", at: 30),
            message(false, "", at: 20, tools: ["Edit"]),
            message(false, "vou rodar o analyze", at: 10),
        ]

        let turns = TranscriptReader.coalesce(page)

        XCTAssertEqual(turns.map(\.text), ["zero erro", "vou rodar o analyze"])
        XCTAssertEqual(turns[0].tools, ["Bash"])
        XCTAssertEqual(turns[1].tools, ["Edit"])
    }

    func testToolsRunBeforeAnythingWasSaidAttachToTheReportThatFollows() {
        // Agents often act first and narrate afterwards. Left alone, those calls would draw a
        // card of chips with no sentence on it.
        let page = [
            message(false, "achei o problema", at: 30),
            message(false, "", at: 20, tools: ["Grep"]),
            message(true, "investiga isso", at: 10),
        ]

        let turns = TranscriptReader.coalesce(page)

        XCTAssertEqual(turns.count, 2)
        XCTAssertEqual(turns[0].text, "achei o problema")
        XCTAssertEqual(turns[0].tools, ["Grep"])
        XCTAssertEqual(turns[0].at, 20, "the turn started when it began working")
    }

    func testToolsStillRunningKeepATurnOfTheirOwn() {
        // The last thing in the transcript is a call with no report yet — that is the agent
        // working right now, and it should show.
        let page = [
            message(false, "", at: 20, tools: ["Bash"]),
            message(true, "roda aí", at: 10),
        ]

        let turns = TranscriptReader.coalesce(page)

        XCTAssertEqual(turns.count, 2)
        XCTAssertEqual(turns[0].tools, ["Bash"])
        XCTAssertTrue(turns[0].text.isEmpty)
    }

    func testASpeakerChangeStartsANewTurn() {
        let page = [
            message(false, "resposta", at: 30),
            message(true, "pergunta", at: 20),
            message(false, "anterior", at: 10),
        ]

        let turns = TranscriptReader.coalesce(page)

        XCTAssertEqual(turns.map(\.user), [false, true, false])
        XCTAssertEqual(turns.map(\.text), ["resposta", "pergunta", "anterior"])
    }

    func testToolOnlyEntriesAttachToTheTurnTheyBelongTo() {
        let page = [
            message(false, "", at: 30, tools: ["Edit"]),
            message(false, "vou corrigir", at: 20),
            message(true, "arruma isso", at: 10),
        ]

        let turns = TranscriptReader.coalesce(page)

        XCTAssertEqual(turns.count, 2)
        XCTAssertEqual(turns[0].text, "vou corrigir")
        XCTAssertEqual(turns[0].tools, ["Edit"])
        XCTAssertTrue(turns[1].user)
    }

    func testChronologicalOrderIsPreserved() {
        let held = [
            message(true, "oi", at: 10),
            message(false, "um", at: 20),
            message(false, "", at: 30, tools: ["Bash"]),
            message(false, "dois", at: 40),
        ]

        let turns = TranscriptReader.coalesceChronological(held)

        XCTAssertEqual(turns.map(\.text), ["oi", "um", "dois"])
        XCTAssertEqual(turns.map(\.at), [10, 20, 40])
        XCTAssertEqual(turns[1].tools, ["Bash"])
    }

    func testEmptyInputStaysEmpty() {
        XCTAssertTrue(TranscriptReader.coalesce([]).isEmpty)
        XCTAssertTrue(TranscriptReader.coalesceChronological([]).isEmpty)
    }
}
