import XCTest
@testable import CodeIslandCore

/// Turning an agent's markdown into blocks the chat can lay out.
final class MarkdownBlocksTests: XCTestCase {

    func testHeadingsBulletsAndProseSeparate() {
        let blocks = MarkdownBlockParser.blocks("""
        ## Resumo
        Tudo compilou.

        - primeiro
        - segundo
        """)

        XCTAssertEqual(blocks, [
            .heading(level: 2, text: "Resumo"),
            .paragraph("Tudo compilou."),
            .bullet(marker: "•", text: "primeiro", indent: 0),
            .bullet(marker: "•", text: "segundo", indent: 0),
        ])
    }

    func testOrderedListsKeepTheirOwnNumbers() {
        let blocks = MarkdownBlockParser.blocks("3. terceiro\n4) quarto")

        XCTAssertEqual(blocks, [
            .bullet(marker: "3.", text: "terceiro", indent: 0),
            .bullet(marker: "4.", text: "quarto", indent: 0),
        ])
    }

    func testNestedBulletsCarryTheirIndent() {
        let blocks = MarkdownBlockParser.blocks("- pai\n    - filho")

        XCTAssertEqual(blocks, [
            .bullet(marker: "•", text: "pai", indent: 0),
            .bullet(marker: "•", text: "filho", indent: 2),
        ])
    }

    func testFencedCodeKeepsItsContentVerbatim() {
        let blocks = MarkdownBlockParser.blocks("""
        ```swift
        # not a heading
        - not a bullet
        ```
        """)

        XCTAssertEqual(blocks, [.code(language: "swift", text: "# not a heading\n- not a bullet")])
    }

    func testUnterminatedFenceStillRenders() {
        let blocks = MarkdownBlockParser.blocks("```\nflutter analyze")

        XCTAssertEqual(blocks, [.code(language: nil, text: "flutter analyze")])
    }

    func testParagraphsSurviveLineWrapsButSplitOnBlankLines() {
        let blocks = MarkdownBlockParser.blocks("uma linha\nmesma frase\n\noutro parágrafo")

        XCTAssertEqual(blocks, [
            .paragraph("uma linha\nmesma frase"),
            .paragraph("outro parágrafo"),
        ])
    }

    func testPlainTextIsOneParagraph() {
        XCTAssertEqual(MarkdownBlockParser.blocks("sem marcação"), [.paragraph("sem marcação")])
    }

    func testEmptyTextProducesNoBlocks() {
        XCTAssertEqual(MarkdownBlockParser.blocks("   \n\n  "), [])
    }

    func testHashWithoutSpaceIsNotAHeading() {
        XCTAssertEqual(MarkdownBlockParser.blocks("#hashtag"), [.paragraph("#hashtag")])
    }

    // MARK: - Tables

    func testAPipeTableSplitsIntoHeadersAndRows() {
        let blocks = MarkdownBlockParser.blocks("""
        | | Quick Push | Memes Pack |
        |---|---|---|
        | Billing | ✅ Corrigido | ✅ Já estava OK |
        | Toolchain | ✅ Atualizado | ✅ Atualizado |
        """)

        XCTAssertEqual(blocks, [
            .table(
                headers: ["", "Quick Push", "Memes Pack"],
                rows: [
                    ["Billing", "✅ Corrigido", "✅ Já estava OK"],
                    ["Toolchain", "✅ Atualizado", "✅ Atualizado"],
                ]
            ),
        ])
    }

    func testATableWithoutADividerHasNoHeaders() {
        let blocks = MarkdownBlockParser.blocks("| a | b |\n| c | d |")

        XCTAssertEqual(blocks, [.table(headers: [], rows: [["a", "b"], ["c", "d"]])])
    }

    func testProseWithAPipeInItIsNotATable() {
        let blocks = MarkdownBlockParser.blocks("rode grep foo | wc -l no terminal")

        XCTAssertEqual(blocks, [.paragraph("rode grep foo | wc -l no terminal")])
    }

    func testATableEndsWhenTheProseResumes() {
        let blocks = MarkdownBlockParser.blocks("| a | b |\ndepois disso")

        XCTAssertEqual(blocks, [
            .table(headers: [], rows: [["a", "b"]]),
            .paragraph("depois disso"),
        ])
    }

    func testPipesInsideAFenceAreNotATable() {
        let blocks = MarkdownBlockParser.blocks("```\n| a | b |\n```")

        XCTAssertEqual(blocks, [.code(language: nil, text: "| a | b |")])
    }

    // MARK: - Tool chips

    func testRepeatedToolsCollapseIntoOneChipWithACount() {
        let summary = ToolSummary.summarize(["Bash", "Edit", "Bash", "Bash", "Read"])

        XCTAssertEqual(summary.map(\.label), ["Bash ×3", "Edit", "Read"])
    }

    func testToolOrderFollowsFirstUse() {
        let summary = ToolSummary.summarize(["Read", "Bash", "Read"])

        XCTAssertEqual(summary.map(\.name), ["Read", "Bash"])
    }

    func testMcpPlumbingIsTrimmedOffTheName() {
        XCTAssertEqual(ToolSummary.shortName("mcp__Claude_Browser__computer"), "Claude_Browser·computer")
        XCTAssertEqual(ToolSummary.shortName("Bash"), "Bash")
    }

    func testChipsCountTheShortenedName() {
        let summary = ToolSummary.summarize([
            "mcp__Claude_Browser__computer",
            "mcp__Claude_Browser__computer",
        ])

        XCTAssertEqual(summary.map(\.label), ["Claude_Browser·computer ×2"])
    }
}
