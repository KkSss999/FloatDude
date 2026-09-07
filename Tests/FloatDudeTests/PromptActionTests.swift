import XCTest
@testable import FloatDude

final class PromptActionTests: XCTestCase {
    func testV010ExposesExactlyFourActions() {
        XCTAssertEqual(PromptAction.allCases, [.explain, .translate, .rewrite, .ask])
    }

    func testNonEmptyAskInputAlwaysUsesAskAction() {
        XCTAssertEqual(
            PromptAction.actionForSubmission(prompt: "What does this mean?", fallback: .explain),
            .ask
        )
        XCTAssertEqual(
            PromptAction.actionForSubmission(prompt: "  ", fallback: .rewrite),
            .rewrite
        )
    }
}
