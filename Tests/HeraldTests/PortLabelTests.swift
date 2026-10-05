import XCTest
@testable import HeraldCore

final class PortLabelTests: XCTestCase {
    /// The reset button names the port without a thousands separator.
    func testResetPortTitleHasNoGrouping() {
        XCTAssertEqual(HeraldPaths.resetPortTitle, "Reset to 48617")
    }
}
