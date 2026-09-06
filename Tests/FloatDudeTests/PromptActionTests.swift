import XCTest
@testable import FloatDude

final class PromptActionTests: XCTestCase {
    func testV010ExposesExactlyFourActions() {
        XCTAssertEqual(PromptAction.allCases, [.explain, .translate, .rewrite, .ask])
    }
}
