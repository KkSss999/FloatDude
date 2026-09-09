import AppKit
import Foundation
import CoreGraphics
@preconcurrency import ApplicationServices

struct CapturedContext: Sendable, Equatable {
    enum Source: String, Sendable, Equatable {
        case accessibilitySelection
        case selectionCopy
        case clipboard
        case directInput

        var displayName: String {
            return switch self {
            case .accessibilitySelection: "Accessibility selection"
            case .selectionCopy: "Feishu shortcut snapshot"
            case .clipboard: "Clipboard"
            case .directInput: "Direct input"
            }
        }

        func displayName(in language: SettingsLanguage) -> String {
            let copy = ProductCopy(language: language)
            return switch self {
            case .accessibilitySelection: copy.text(.accessibilitySelection)
            case .selectionCopy: copy.text(.feishuSnapshot)
            case .clipboard: copy.text(.clipboard)
            case .directInput: copy.text(.directInput)
            }
        }
    }

    let text: String
    let source: Source
    let applicationName: String?
    /// True only when Accessibility confirms the focused element accepts a
    /// direct replacement through its selected-text attribute.
    let canReplaceSelection: Bool
    /// AppKit desktop coordinates for placement avoidance when Accessibility
    /// exposes the bounds of the source selection.
    let selectionRect: CGRect?
    /// Safe, non-sensitive explanation for why a fallback source was used.
    let guidance: String?

    init(
        text: String,
        source: Source,
        applicationName: String?,
        canReplaceSelection: Bool = false,
        selectionRect: CGRect? = nil,
        guidance: String? = nil
    ) {
        self.text = text
        self.source = source
        self.applicationName = applicationName
        self.canReplaceSelection = canReplaceSelection
        self.selectionRect = selectionRect
        self.guidance = guidance
    }
}

enum ContextCaptureError: Error, LocalizedError, Sendable, Equatable {
    case exceedsCharacterLimit(source: CapturedContext.Source, count: Int, limit: Int)
    case sensitiveContent(source: CapturedContext.Source)

    var errorDescription: String? {
        switch self {
        case let .exceedsCharacterLimit(source, count, limit):
            "The \(source.rawValue) context contains \(count) characters; the maximum is \(limit)."
        case let .sensitiveContent(source):
            "The \(source.displayName.lowercased()) appears to contain a credential and was not sent."
        }
    }
}

enum ContextCaptureUnavailableReason: String, Sendable, Equatable {
    case accessibilityPermissionDenied
    case noSelectionOrClipboard
    case sensitiveClipboardBlocked

    var guidance: String {
        switch self {
        case .accessibilityPermissionDenied:
            "Accessibility access is unavailable. Clipboard fallback and direct input are still available."
        case .noSelectionOrClipboard:
            "No selection or clipboard text is available. Enter a prompt below."
        case .sensitiveClipboardBlocked:
            "Clipboard content looks like a credential and was blocked. Select text again or type a prompt instead."
        }
    }
}

enum ContextCaptureResult: Sendable, Equatable {
    case captured(CapturedContext)
    case unavailable(reason: ContextCaptureUnavailableReason)
    case rejected(ContextCaptureError)
}

protocol ContextCapturing: Sendable {
    /// Capture before activating the panel. `directInput` is supplied by the
    /// coordinator's editable input field and is the final fallback.
    func captureContext(directInput: String?) -> ContextCaptureResult
    /// Explicit user shortcut capture. May use a clipboard-preserving copy
    /// snapshot after AX fails; background refresh must never call this method.
    func captureShortcutSelection() -> ContextCaptureResult?
    /// A best-effort update used while the nonactivating panel remains on
    /// screen. It intentionally never reads the clipboard: a live refresh must
    /// only reflect a newly selected piece of text from another application.
    func captureLiveSelection() -> ContextCaptureResult?
    func captureLiveSelection(from processID: pid_t?) -> ContextCaptureResult?
}

extension ContextCapturing {
    func captureShortcutSelection() -> ContextCaptureResult? {
        captureLiveSelection()
    }

    func captureLiveSelection() -> ContextCaptureResult? { nil }
    func captureLiveSelection(from _: pid_t?) -> ContextCaptureResult? {
        captureLiveSelection()
    }
}

@MainActor
protocol LiveSelectionObserving: AnyObject {
    func start(onSelectionChange: @escaping (pid_t) -> Void)
    func stop()
}

/// A narrowly scoped last-resort capture for renderers that allow users to
/// select visible text but never expose that selection to Accessibility.
/// Implementations must preserve the user's pasteboard exactly.
protocol SelectionCopyFallback: Sendable {
    func captureSelection(bundleIdentifier: String?, processID: pid_t) -> String?
}

struct SelectionCapture: ContextCapturing {
    static let maximumContextCharacters = 12_000

    private let accessibility: any AccessibilityProviding
    private let pasteboard: any PasteboardProviding
    private let selectionCopyFallback: any SelectionCopyFallback

    init(
        accessibility: any AccessibilityProviding = SystemAccessibilityProvider(),
        pasteboard: any PasteboardProviding = SystemClipboardManager(),
        selectionCopyFallback: any SelectionCopyFallback = FeishuSelectionCopyFallback()
    ) {
        self.accessibility = accessibility
        self.pasteboard = pasteboard
        self.selectionCopyFallback = selectionCopyFallback
    }

    init(
        accessibility: any AccessibilityProviding,
        clipboard: any ClipboardManaging
    ) {
        self.init(accessibility: accessibility, pasteboard: clipboard)
    }

    func captureContext(directInput: String? = nil) -> ContextCaptureResult {
        // This method performs only short, synchronous system reads. The
        // coordinator must call it before showing/activating the panel.
        if let shortcutResult = captureShortcutSelection() {
            switch shortcutResult {
            case .captured, .rejected:
                return shortcutResult
            case .unavailable:
                break
            }
        }

        if let clipboardText = readClipboardText() {
            guard !SensitiveTextDetector.containsSensitiveClipboardValue(clipboardText) else {
                return .unavailable(reason: .sensitiveClipboardBlocked)
            }
            if let result = makeResult(
                text: clipboardText,
                source: .clipboard,
                guidance: accessibility.isTrusted
                    ? nil
                    : "Using Clipboard because Accessibility access is unavailable."
            ) {
                return result
            }
        }

        guard let directInput else {
            return .unavailable(
                reason: accessibility.isTrusted
                    ? .noSelectionOrClipboard
                    : .accessibilityPermissionDenied
            )
        }

        return makeResult(text: directInput, source: .directInput)
            ?? .unavailable(reason: .noSelectionOrClipboard)
    }

    func captureShortcutSelection() -> ContextCaptureResult? {
        guard let sourceApplication = NSWorkspace.shared.frontmostApplication,
              sourceApplication.bundleIdentifier != Bundle.main.bundleIdentifier
        else { return nil }
        let sourceProcessID = sourceApplication.processIdentifier
        accessibility.prepareForSelectionCapture(in: sourceProcessID)
        if let selection = readSelection(),
           let result = makeResult(
               text: selection.text,
               source: .accessibilitySelection,
               canReplaceSelection: selection.canReplace,
               selectionRect: selection.rect
           ) {
            return result
        }
        if let selection = readSelection(from: sourceProcessID),
           let result = makeResult(
               text: selection.text,
               source: .accessibilitySelection,
               canReplaceSelection: selection.canReplace,
               selectionRect: selection.rect
           ) {
            return result
        }

        if let copiedSelection = selectionCopyFallback.captureSelection(
            bundleIdentifier: sourceApplication.bundleIdentifier,
            processID: sourceProcessID
        ),
            let result = makeResult(
               text: copiedSelection,
               source: .selectionCopy,
               guidance: "Captured from Feishu when you invoked the shortcut. Live selection updates are unavailable in this renderer."
           ) {
            return result
        }
        return .unavailable(reason: .noSelectionOrClipboard)
    }

    func captureLiveSelection() -> ContextCaptureResult? {
        // The panel is nonactivating, but an input-control focus transition can
        // still make FloatDude the frontmost accessibility target on some macOS
        // versions. Never turn text the user is typing into a fresh external
        // selection context.
        if NSWorkspace.shared.frontmostApplication?.bundleIdentifier == Bundle.main.bundleIdentifier {
            return nil
        }
        guard let frontmost = NSWorkspace.shared.frontmostApplication,
              frontmost.bundleIdentifier != Bundle.main.bundleIdentifier
        else { return nil }
        if let selection = readSelection(),
           let result = makeResult(
               text: selection.text,
               source: .accessibilitySelection,
               canReplaceSelection: selection.canReplace,
               selectionRect: selection.rect
           ) {
            return result
        }
        return captureLiveSelection(from: frontmost.processIdentifier)
    }

    func captureLiveSelection(from processID: pid_t?) -> ContextCaptureResult? {
        accessibility.prepareForSelectionCapture(in: processID)
        guard let selection = readSelection(from: processID) else { return nil }
        return makeResult(
            text: selection.text,
            source: .accessibilitySelection,
            canReplaceSelection: selection.canReplace,
            selectionRect: selection.rect
        )
    }

    private func readSelection(from processID: pid_t? = nil) -> (text: String, rect: CGRect?, canReplace: Bool)? {
        do {
            guard let focusedElement = try accessibility.focusedElement(in: processID) else {
                return nil
            }
            for candidate in accessibility.textSelectionCandidates(from: focusedElement) {
                guard let text = try accessibility.selectedText(from: candidate),
                      !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                else { continue }
                return (
                    text,
                    try? accessibility.selectedTextBounds(from: candidate),
                    (try? accessibility.canReplaceSelectedText(in: candidate)) ?? false
                )
            }
            return nil
        } catch {
            // Accessibility is intentionally non-blocking. AX errors and
            // permission changes simply advance the fallback chain.
            return nil
        }
    }

    private func readClipboardText() -> String? {
        pasteboard.readText()
    }

    private func makeResult(
        text: String,
        source: CapturedContext.Source,
        canReplaceSelection: Bool = false,
        selectionRect: CGRect? = nil,
        guidance: String? = nil
    ) -> ContextCaptureResult? {
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return nil
        }

        guard !SensitiveTextDetector.containsCredential(in: text) else {
            return .rejected(.sensitiveContent(source: source))
        }

        let count = text.count
        guard count <= Self.maximumContextCharacters else {
            return .rejected(
                .exceedsCharacterLimit(
                    source: source,
                    count: count,
                    limit: Self.maximumContextCharacters
                )
            )
        }

        return .captured(
            CapturedContext(
                text: text,
                source: source,
                applicationName: nil,
                canReplaceSelection: canReplaceSelection,
                selectionRect: selectionRect,
                guidance: guidance
            )
        )
    }
}

/// Feishu can render selectable message text without exposing AXSelectedText.
/// At the user's explicit hot-key invocation, take a short-lived Cmd-C snapshot
/// and restore every pasteboard item immediately. It never runs in the
/// background and is deliberately limited to Feishu's known bundle identifier.
struct FeishuSelectionCopyFallback: SelectionCopyFallback {
    private static let bundleIdentifiers: Set<String> = [
        "com.bytedance.macos.feishu",
    ]

    func captureSelection(bundleIdentifier: String?, processID: pid_t) -> String? {
        guard processID > 0,
              let bundleIdentifier,
              Self.bundleIdentifiers.contains(bundleIdentifier)
        else { return nil }

        let pasteboard = NSPasteboard.general
        let snapshot = PasteboardSnapshot(pasteboard: pasteboard)
        let initialChangeCount = pasteboard.changeCount
        sendCopyShortcut()

        var changed = false
        for _ in 0..<8 {
            RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.015))
            if pasteboard.changeCount != initialChangeCount {
                changed = true
                break
            }
        }
        guard changed else { return nil }
        let selectedText = pasteboard.string(forType: .string)
        snapshot.restore(to: pasteboard)
        return selectedText
    }

    private func sendCopyShortcut() {
        guard let keyDown = CGEvent(
            keyboardEventSource: nil,
            virtualKey: 8, // ANSI C
            keyDown: true
        ),
        let keyUp = CGEvent(
            keyboardEventSource: nil,
            virtualKey: 8,
            keyDown: false
        )
        else { return }
        keyDown.flags = .maskCommand
        keyUp.flags = .maskCommand
        keyDown.post(tap: .cghidEventTap)
        keyUp.post(tap: .cghidEventTap)
    }

    private struct PasteboardSnapshot {
        let items: [[NSPasteboard.PasteboardType: Data]]

        init(pasteboard: NSPasteboard) {
            items = pasteboard.pasteboardItems?.map { item in
                Dictionary(uniqueKeysWithValues: item.types.compactMap { type in
                    item.data(forType: type).map { data in (type, data) }
                })
            } ?? []
        }

        func restore(to pasteboard: NSPasteboard) {
            pasteboard.clearContents()
            let restoredItems = items.map { representations -> NSPasteboardItem in
                let item = NSPasteboardItem()
                for (type, data) in representations {
                    item.setData(data, forType: type)
                }
                return item
            }
            if !restoredItems.isEmpty {
                pasteboard.writeObjects(restoredItems)
            }
        }
    }
}

/// Event-driven selection delivery for the current source application. The
/// system-wide AX element cannot be observed, so this object watches each
/// frontmost non-FloatDude process, then subscribes to the focused element's
/// selected-text changes. Some applications omit that notification; callers
/// retain a low-frequency polling fallback for those cases.
@MainActor
final class SystemLiveSelectionObserver: NSObject, LiveSelectionObserving {
    private var observer: AXObserver?
    private var observedProcessID: pid_t?
    private var observedApplication: AXUIElement?
    private var observedFocusedElement: AXUIElement?
    private var workspaceActivationToken: NSObjectProtocol?
    private var onSelectionChange: ((pid_t) -> Void)?

    func start(onSelectionChange: @escaping (pid_t) -> Void) {
        self.onSelectionChange = onSelectionChange
        guard workspaceActivationToken == nil else {
            observeFrontmostApplication()
            return
        }
        workspaceActivationToken = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.observeFrontmostApplication()
            }
        }
        observeFrontmostApplication()
    }

    func stop() {
        if let workspaceActivationToken {
            NSWorkspace.shared.notificationCenter.removeObserver(workspaceActivationToken)
        }
        workspaceActivationToken = nil
        tearDownObserver()
        onSelectionChange = nil
    }

    private func observeFrontmostApplication() {
        guard let application = NSWorkspace.shared.frontmostApplication,
              application.bundleIdentifier != Bundle.main.bundleIdentifier
        else {
            tearDownObserver()
            return
        }
        guard observedProcessID != application.processIdentifier else { return }
        tearDownObserver()

        var newObserver: AXObserver?
        guard AXObserverCreate(application.processIdentifier, Self.callback, &newObserver) == .success,
              let newObserver
        else { return }

        let applicationElement = AXUIElementCreateApplication(application.processIdentifier)
        SystemAccessibilityProvider().prepareForSelectionCapture(in: application.processIdentifier)
        let refcon = UnsafeMutableRawPointer(Unmanaged.passUnretained(self).toOpaque())
        observer = newObserver
        observedProcessID = application.processIdentifier
        observedApplication = applicationElement
        CFRunLoopAddSource(
            CFRunLoopGetMain(),
            AXObserverGetRunLoopSource(newObserver),
            .commonModes
        )

        _ = AXObserverAddNotification(
            newObserver,
            applicationElement,
            kAXFocusedUIElementChangedNotification as CFString,
            refcon
        )
        observeFocusedElement()
    }

    private func observeFocusedElement() {
        guard let observer, let observedProcessID else { return }
        let provider = SystemAccessibilityProvider()
        guard let focusedElement = try? provider.focusedElement(in: observedProcessID)
        else { return }
        observedFocusedElement = focusedElement
        let refcon = UnsafeMutableRawPointer(Unmanaged.passUnretained(self).toOpaque())
        // AXSelectedTextChanged is the precise signal. AXValueChanged gives
        // text controls that omit it a useful second chance without assuming
        // every application supports either notification.
        for notification in [kAXSelectedTextChangedNotification, kAXValueChangedNotification] {
            _ = AXObserverAddNotification(observer, focusedElement, notification as CFString, refcon)
        }
    }

    private func handle(notification: String) {
        guard let observedProcessID else { return }
        if notification == kAXFocusedUIElementChangedNotification {
            observeFocusedElement()
        }
        onSelectionChange?(observedProcessID)
    }

    private func tearDownObserver() {
        if let observer {
            CFRunLoopRemoveSource(
                CFRunLoopGetMain(),
                AXObserverGetRunLoopSource(observer),
                .commonModes
            )
        }
        observer = nil
        observedProcessID = nil
        observedApplication = nil
        observedFocusedElement = nil
    }

    private static let callback: AXObserverCallback = { _, _, notification, refcon in
        guard let refcon else { return }
        let owner = Unmanaged<SystemLiveSelectionObserver>.fromOpaque(refcon).takeUnretainedValue()
        let name = notification as String
        Task { @MainActor in
            owner.handle(notification: name)
        }
    }
}
