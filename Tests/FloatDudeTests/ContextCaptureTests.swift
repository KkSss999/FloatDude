import XCTest
import ApplicationServices
import CoreGraphics
@testable import FloatDude

final class ContextCaptureTests: XCTestCase {
    func testAccessibilitySelectionHasPriorityOverClipboardAndDirectInput() async {
        let accessibility = FakeAccessibilityProvider(selectedText: "选择的文字")
        let pasteboard = FakePasteboard(text: "剪贴板文字")
        let capture = SelectionCapture(accessibility: accessibility, pasteboard: pasteboard)

        let result = capture.captureContext(directInput: "直接输入")

        XCTAssertEqual(
            result,
            .captured(
                CapturedContext(
                    text: "选择的文字",
                    source: .accessibilitySelection,
                    applicationName: nil
                )
            )
        )
        XCTAssertEqual(pasteboard.readCount, 0)
    }

    func testLiveSelectionForObservedProcessUsesAccessibilityOnly() {
        let pasteboard = FakePasteboard(text: "clipboard must not be read")
        let capture = SelectionCapture(
            accessibility: FakeAccessibilityProvider(selectedText: "live selection"),
            pasteboard: pasteboard
        )

        let result = capture.captureLiveSelection(from: 42)

        XCTAssertEqual(
            result,
            .captured(CapturedContext(
                text: "live selection",
                source: .accessibilitySelection,
                applicationName: nil
            ))
        )
        XCTAssertEqual(pasteboard.readCount, 0)
    }

    func testShortcutCaptureKeepsSystemWideAXAheadOfProcessFallback() {
        let copyFallback = FakeSelectionCopyFallback(text: "must not be used")
        let capture = SelectionCapture(
            accessibility: SystemWideOnlyAccessibilityProvider(text: "Codex selection"),
            pasteboard: FakePasteboard(text: "old clipboard"),
            selectionCopyFallback: copyFallback
        )

        XCTAssertEqual(
            capture.captureShortcutSelection(),
            .captured(CapturedContext(
                text: "Codex selection",
                source: .accessibilitySelection,
                applicationName: nil
            ))
        )
        XCTAssertEqual(copyFallback.callCount, 0)
    }

    func testAccessibilitySelectionCarriesBoundsForPanelAvoidance() async {
        let rect = CGRect(x: 100, y: 200, width: 180, height: 24)
        let capture = SelectionCapture(
            accessibility: FakeAccessibilityProvider(selectedText: "selected", selectionRect: rect),
            pasteboard: FakePasteboard()
        )

        let result = capture.captureContext()

        XCTAssertEqual(
            result,
            .captured(
                CapturedContext(
                    text: "selected",
                    source: .accessibilitySelection,
                    applicationName: nil,
                    selectionRect: rect
                )
            )
        )
    }

    func testEditableAccessibilitySelectionExposesRewriteCapability() async {
        let capture = SelectionCapture(
            accessibility: FakeAccessibilityProvider(
                selectedText: "editable",
                canReplaceSelection: true
            ),
            pasteboard: FakePasteboard()
        )

        let result = capture.captureContext()

        XCTAssertEqual(
            result,
            .captured(CapturedContext(
                text: "editable",
                source: .accessibilitySelection,
                applicationName: nil,
                canReplaceSelection: true
            ))
        )
    }

    func testReadOnlyAccessibilitySelectionDoesNotExposeRewriteCapability() async {
        let capture = SelectionCapture(
            accessibility: FakeAccessibilityProvider(
                selectedText: "read only",
                canReplaceSelection: false
            ),
            pasteboard: FakePasteboard()
        )

        guard case let .captured(context) = capture.captureContext() else {
            return XCTFail("Expected captured context")
        }
        XCTAssertFalse(context.canReplaceSelection)
    }

    func testDeniedAccessibilityFallsBackToClipboard() async {
        let accessibility = FakeAccessibilityProvider(mode: .denied)
        let pasteboard = FakePasteboard(text: "clipboard fallback")
        let capture = SelectionCapture(accessibility: accessibility, pasteboard: pasteboard)

        let result = capture.captureContext(directInput: "direct input")

        XCTAssertEqual(
            result,
            .captured(
                CapturedContext(
                    text: "clipboard fallback",
                    source: .clipboard,
                    applicationName: nil,
                    guidance: "Using Clipboard because Accessibility access is unavailable."
                )
            )
        )
        XCTAssertEqual(pasteboard.readCount, 1)
    }

    func testAccessibilityErrorFallsBackToClipboard() async {
        let accessibility = FakeAccessibilityProvider(mode: .failure)
        let pasteboard = FakePasteboard(text: "clipboard after AX error")
        let capture = SelectionCapture(accessibility: accessibility, pasteboard: pasteboard)

        let result = capture.captureContext(directInput: "direct input")

        XCTAssertEqual(
            result,
            .captured(
                CapturedContext(
                    text: "clipboard after AX error",
                    source: .clipboard,
                    applicationName: nil
                )
            )
        )
    }

    func testFeishuCopyFallbackCapturesNewSelectionBeforeExistingClipboard() {
        let pasteboard = FakePasteboard(text: "old clipboard")
        let fallback = FakeSelectionCopyFallback(text: "Feishu selected text")
        let capture = SelectionCapture(
            accessibility: FakeAccessibilityProvider(mode: .failure),
            pasteboard: pasteboard,
            selectionCopyFallback: fallback
        )

        let result = capture.captureContext()

        XCTAssertEqual(
            result,
            .captured(CapturedContext(
                text: "Feishu selected text",
                source: .selectionCopy,
                applicationName: nil,
                guidance: "Captured from Feishu when you invoked the shortcut. Live selection updates are unavailable in this renderer."
            ))
        )
        XCTAssertEqual(fallback.callCount, 1)
        XCTAssertEqual(pasteboard.readCount, 0)
    }

    func testEmptyClipboardFallsBackToDirectInput() async {
        let accessibility = FakeAccessibilityProvider(mode: .denied)
        let pasteboard = FakePasteboard(text: " \n\t")
        let capture = SelectionCapture(accessibility: accessibility, pasteboard: pasteboard)

        let result = capture.captureContext(directInput: "editable direct input")

        XCTAssertEqual(
            result,
            .captured(
                CapturedContext(
                    text: "editable direct input",
                    source: .directInput,
                    applicationName: nil
                )
            )
        )
    }

    func testUnicodeWhitespaceAndNewlinesArePreserved() async {
        let text = "  👩🏽‍💻\n第二行\t"
        let accessibility = FakeAccessibilityProvider(selectedText: text)
        let capture = SelectionCapture(accessibility: accessibility, pasteboard: FakePasteboard())

        let result = capture.captureContext()

        XCTAssertEqual(
            result,
            .captured(
                CapturedContext(
                    text: text,
                    source: .accessibilitySelection,
                    applicationName: nil
                )
            )
        )
    }

    func testWhitespaceOnlyAccessibilitySelectionIsSkipped() async {
        let accessibility = FakeAccessibilityProvider(selectedText: "\n  \t")
        let pasteboard = FakePasteboard(text: "clipboard")
        let capture = SelectionCapture(accessibility: accessibility, pasteboard: pasteboard)

        let result = capture.captureContext()

        XCTAssertEqual(
            result,
            .captured(
                CapturedContext(text: "clipboard", source: .clipboard, applicationName: nil)
            )
        )
    }

    func testOversizedClipboardReturnsRecognizableErrorWithoutTruncating() async {
        let oversizedText = String(repeating: "界", count: SelectionCapture.maximumContextCharacters + 1)
        let accessibility = FakeAccessibilityProvider(mode: .denied)
        let capture = SelectionCapture(
            accessibility: accessibility,
            pasteboard: FakePasteboard(text: oversizedText)
        )

        let result = capture.captureContext(directInput: "must not be selected")

        XCTAssertEqual(
            result,
            .rejected(
                .exceedsCharacterLimit(
                    source: .clipboard,
                    count: oversizedText.count,
                    limit: SelectionCapture.maximumContextCharacters
                )
            )
        )
    }

    func testOversizedDirectInputReturnsRecognizableErrorWithoutTruncating() async {
        let oversizedText = String(repeating: "🙂", count: SelectionCapture.maximumContextCharacters + 1)
        let capture = SelectionCapture(
            accessibility: FakeAccessibilityProvider(mode: .denied),
            pasteboard: FakePasteboard()
        )

        let result = capture.captureContext(directInput: oversizedText)

        XCTAssertEqual(
            result,
            .rejected(
                .exceedsCharacterLimit(
                    source: .directInput,
                    count: oversizedText.count,
                    limit: SelectionCapture.maximumContextCharacters
                )
            )
        )
    }

    func testNoSourcesReturnsUnavailable() async {
        let capture = SelectionCapture(
            accessibility: FakeAccessibilityProvider(mode: .denied),
            pasteboard: FakePasteboard()
        )

        let result = capture.captureContext()
        XCTAssertEqual(result, .unavailable(reason: .accessibilityPermissionDenied))
    }

    func testSensitiveClipboardIsBlockedWithoutReflectingItsValue() async {
        let sensitiveValue = String(repeating: "a", count: 32)
        let capture = SelectionCapture(
            accessibility: FakeAccessibilityProvider(mode: .denied),
            pasteboard: FakePasteboard(text: sensitiveValue)
        )

        let result = capture.captureContext()

        XCTAssertEqual(result, .unavailable(reason: .sensitiveClipboardBlocked))
        XCTAssertFalse(String(describing: result).contains(sensitiveValue))
    }

    func testSensitiveSelectionIsRejectedBeforeClipboardFallback() async {
        let sensitiveValue = "sk-" + String(repeating: "b", count: 24)
        let pasteboard = FakePasteboard(text: "safe clipboard")
        let capture = SelectionCapture(
            accessibility: FakeAccessibilityProvider(selectedText: sensitiveValue),
            pasteboard: pasteboard
        )

        let result = capture.captureContext()

        XCTAssertEqual(result, .rejected(.sensitiveContent(source: .accessibilitySelection)))
        XCTAssertEqual(pasteboard.readCount, 0)
    }
}

private struct FakeAccessibilityProvider: AccessibilityProviding {
    enum Mode: Equatable, Sendable {
        case available
        case denied
        case failure
    }

    let mode: Mode
    let selectedText: String?
    let selectionRect: CGRect?
    let canReplaceSelection: Bool

    var isTrusted: Bool {
        mode != .denied
    }

    init(
        mode: Mode = .available,
        selectedText: String? = nil,
        selectionRect: CGRect? = nil,
        canReplaceSelection: Bool = false
    ) {
        self.mode = mode
        self.selectedText = selectedText
        self.selectionRect = selectionRect
        self.canReplaceSelection = canReplaceSelection
    }

    func focusedElement() throws -> AXUIElement? {
        switch mode {
        case .available:
            // The fake does not need a real AX object; selection is returned
            // from selectedText(from:) after this non-nil sentinel.
            return AXUIElementCreateSystemWide()
        case .denied:
            return nil
        case .failure:
            throw FakeError.failed
        }
    }

    func selectedText(from focusedElement: AXUIElement) throws -> String? {
        if mode == .failure {
            throw FakeError.failed
        }
        return selectedText
    }

    func selectedTextBounds(from focusedElement: AXUIElement) throws -> CGRect? {
        selectionRect
    }

    func canReplaceSelectedText(in focusedElement: AXUIElement) throws -> Bool {
        canReplaceSelection
    }
}

private struct SystemWideOnlyAccessibilityProvider: AccessibilityProviding {
    let text: String
    var isTrusted: Bool { true }

    func focusedElement() throws -> AXUIElement? {
        AXUIElementCreateSystemWide()
    }

    func focusedElement(in processID: pid_t?) throws -> AXUIElement? {
        processID == nil ? AXUIElementCreateSystemWide() : nil
    }

    func selectedText(from focusedElement: AXUIElement) throws -> String? {
        text
    }
}

private struct FakePasteboard: PasteboardProviding {
    let text: String?
    let readCountBox: ReadCountBox

    init(text: String? = nil, readCountBox: ReadCountBox = ReadCountBox()) {
        self.text = text
        self.readCountBox = readCountBox
    }

    var readCount: Int { readCountBox.value }

    func readText() -> String? {
        readCountBox.value += 1
        return text
    }

    func writeText(_ text: String) {}
}

private final class ReadCountBox: @unchecked Sendable {
    var value = 0
}

private final class FakeSelectionCopyFallback: SelectionCopyFallback, @unchecked Sendable {
    let text: String?
    private(set) var callCount = 0

    init(text: String?) {
        self.text = text
    }

    func captureSelection(bundleIdentifier: String?, processID: pid_t) -> String? {
        callCount += 1
        return text
    }
}

private enum FakeError: Error {
    case failed
}
