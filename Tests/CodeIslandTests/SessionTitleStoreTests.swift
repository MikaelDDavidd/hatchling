import XCTest
@testable import CodeIsland

final class SessionTitleStoreTests: XCTestCase {
    func testCodexThreadNameLookupReturnsLatestMatchingTitle() throws {
        let lines = [
            #"{"id":"019d6330-beed-7a13-b61e-cacf03d3cefe","thread_name":"Old title","updated_at":"2026-04-06T14:20:00Z"}"#,
            #"{"id":"019d6330-beed-7a13-b61e-cacf03d3cefe","thread_name":"充分探索项目找到通用问题","updated_at":"2026-04-06T14:28:21Z"}"#
        ].joined(separator: "\n")

        let title = try SessionTitleStore.codexThreadName(
            sessionId: "019d6330-beed-7a13-b61e-cacf03d3cefe",
            indexContents: lines
        )

        XCTAssertEqual(title, "充分探索项目找到通用问题")
    }

    func testCodexThreadNameLookupIgnoresBlankTitlesAndBadLines() throws {
        let lines = [
            #"{"id":"019d6331-3593-7b53-9513-c1dd25d708b0","thread_name":"","updated_at":"2026-04-06T14:28:38Z"}"#,
            "not-json"
        ].joined(separator: "\n")

        let title = try SessionTitleStore.codexThreadName(
            sessionId: "019d6331-3593-7b53-9513-c1dd25d708b0",
            indexContents: lines
        )

        XCTAssertNil(title)
    }

    func testClaudeTitlesSurviveWindowCutInsideMultibyteCharacter() {
        // A read window that starts in the middle of "ã" (0xC3 0xA3) must not lose the
        // complete title lines after it.
        let cutLine = Data([0xA3]) + Data(#"o parcial"}"#.utf8)
        let titleLine = Data(#"{"type":"custom-title","customTitle":"Revisão do painel"}"#.utf8)
        let aiLine = Data(#"{"type":"ai-title","aiTitle":"Ajustar notch"}"#.utf8)
        let window = cutLine + Data("\n".utf8) + titleLine + Data("\n".utf8) + aiLine

        let titles = SessionTitleStore.latestClaudeTitles(in: window)

        XCTAssertEqual(titles.custom, "Revisão do painel")
        XCTAssertEqual(titles.ai, "Ajustar notch")
    }
}
