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

    func testSensitiveTextDetectorRecognizesCredentialsWithoutMatchingNormalText() {
        XCTAssertTrue(SensitiveTextDetector.containsCredential(
            in: "sk-" + String(repeating: "c", count: 24)
        ))
        XCTAssertTrue(SensitiveTextDetector.containsCredential(
            in: "Authorization: Bearer " + String(repeating: "d", count: 24)
        ))
        let rawHexToken = String(repeating: "e", count: 32)
        XCTAssertFalse(SensitiveTextDetector.containsCredential(in: rawHexToken))
        XCTAssertTrue(SensitiveTextDetector.containsSensitiveClipboardValue(rawHexToken))
        XCTAssertFalse(SensitiveTextDetector.containsCredential(in: "Explain tokio::spawn clearly."))
    }
}
