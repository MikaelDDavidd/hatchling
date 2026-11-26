import XCTest
@testable import CodeIsland

@MainActor
final class PanelPinTests: XCTestCase {
    func testPinnedPanelDoesNotCloseByItself() {
        let appState = AppState()
        appState.surface = .sessionList
        appState.panelPinned = true
        appState.surface = .collapsed
        XCTAssertEqual(appState.surface, .sessionList)
    }

    func testPinningAClosedPanelOpensIt() {
        let appState = AppState()
        appState.panelPinned = true
        XCTAssertEqual(appState.surface, .sessionList)
    }

    func testTheCollapseButtonUnpinsAndCloses() {
        let appState = AppState()
        appState.panelPinned = true
        appState.collapsePanel()
        XCTAssertFalse(appState.panelPinned)
        XCTAssertEqual(appState.surface, .collapsed)
    }

    func testUnpinnedPanelClosesAsBefore() {
        let appState = AppState()
        appState.surface = .sessionList
        appState.surface = .collapsed
        XCTAssertEqual(appState.surface, .collapsed)
    }
}
