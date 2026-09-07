import XCTest
@testable import FloatDude

final class UIStateTests: XCTestCase {
    func testOneShotStateMachineCoversPromptStreamingCompletionAndCancel() {
        var model = FloatingPanelViewModel(
            selectedText: "First line\nSecond line\nThird line",
            prompt: "  clarify this  ",
            selectedAction: .explain
        )

        XCTAssertEqual(model.state, .idle)
        XCTAssertEqual(model.selectedTextPreview, "First line\nSecond line")

        model.beginPrompting()
        XCTAssertEqual(model.state, .prompting)
        XCTAssertTrue(model.submit())
        XCTAssertEqual(model.state, .loading(action: .explain))

        model.appendStream("First ")
        XCTAssertEqual(model.state, .streaming(text: "First "))
        model.appendStream("answer")
        XCTAssertEqual(model.state, .streaming(text: "First answer"))

        model.complete()
        XCTAssertEqual(model.state, .completed(text: "First answer"))

        model.beginPrompting()
        XCTAssertEqual(model.state, .prompting)
        XCTAssertTrue(model.submit())
        model.cancel()
        XCTAssertEqual(model.state, .cancelled)
    }

    func testEmptyPromptCannotStartRequest() {
        var model = FloatingPanelViewModel(prompt: " \n\t", selectedAction: .translate)

        XCTAssertFalse(model.submit())
        XCTAssertEqual(model.state, .idle)
        model.choose(.rewrite)
        XCTAssertEqual(model.selectedAction, .rewrite)
        XCTAssertEqual(model.state, .prompting)
    }

    func testErrorAndPresentationFlagsAreDeterministic() {
        var model = FloatingPanelViewModel(prompt: "question")
        XCTAssertFalse(model.state.isResponseVisible)
        XCTAssertFalse(model.state.isBusy)

        XCTAssertTrue(model.submit())
        XCTAssertTrue(model.state.isResponseVisible)
        XCTAssertTrue(model.state.isBusy)

        model.fail(with: "Provider unavailable")
        XCTAssertEqual(model.state, .error(message: "Provider unavailable"))
        XCTAssertTrue(model.state.isResponseVisible)
        XCTAssertFalse(model.state.isBusy)
        XCTAssertEqual(model.state.statusTitle, "Error")
    }

    func testMarkdownParserRecognizesAnswerStructure() {
        let markdown = """
        # Result

        A **clear** paragraph with [docs](https://example.com).

        - First
        - Second

        1. One
        2. Two

        > Keep context.

        ```swift
        let answer = 42
        ```

        | Name | Value |
        | --- | ---: |
        | Answer | 42 |
        """

        XCTAssertEqual(
            MarkdownDocument.parse(markdown),
            [
                .heading(level: 1, text: "Result"),
                .paragraph("A **clear** paragraph with [docs](https://example.com)."),
                .unorderedList(["First", "Second"]),
                .orderedList(["One", "Two"]),
                .quote("Keep context."),
                .code(language: "swift", text: "let answer = 42"),
                .table(headers: ["Name", "Value"], rows: [["Answer", "42"]]),
            ]
        )
    }

    func testMarkdownParserPreservesUnclosedStreamingCodeFence() {
        XCTAssertEqual(
            MarkdownDocument.parse("```json\n{\"ready\": true}"),
            [.code(language: "json", text: "{\"ready\": true}")]
        )
    }
}
