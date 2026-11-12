import XCTest
@testable import CodeIsland

final class UpdateVersionTests: XCTestCase {
    func testOnlyAStrictlyNewerVersionInstalls() {
        XCTAssertTrue(UpdateChecker.isNewer(remote: "0.5.10", local: "0.5.9"))
        XCTAssertTrue(UpdateChecker.isNewer(remote: "0.6.0", local: "0.5.10"))
        XCTAssertFalse(UpdateChecker.isNewer(remote: "0.5.9", local: "0.5.9"))
        XCTAssertFalse(UpdateChecker.isNewer(remote: "0.5.8", local: "0.5.9"))
        XCTAssertFalse(UpdateChecker.isNewer(remote: "", local: "0.5.9"))
    }
}
