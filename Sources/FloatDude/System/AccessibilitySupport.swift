@preconcurrency import ApplicationServices
import AppKit
import Foundation

/// The small seam used by context capture to read the focused AX element.
///
/// Implementations must be best-effort: a denied Accessibility permission, a
/// missing focused element, and an AX error are all represented by `nil` (or a
/// thrown error) so the caller can continue with the next context source.
protocol AccessibilityProviding: Sendable {
    var isTrusted: Bool { get }
    func focusedElement() throws -> AXUIElement?
    func focusedElement(in processID: pid_t?) throws -> AXUIElement?
    func textSelectionCandidates(from focusedElement: AXUIElement) -> [AXUIElement]
    func prepareForSelectionCapture(in processID: pid_t?)
    func selectedText(from focusedElement: AXUIElement) throws -> String?
    func selectedTextBounds(from focusedElement: AXUIElement) throws -> CGRect?
    func canReplaceSelectedText(in focusedElement: AXUIElement) throws -> Bool
}

extension AccessibilityProviding {
    func focusedElement(in _: pid_t?) throws -> AXUIElement? {
        try focusedElement()
    }

    func textSelectionCandidates(from focusedElement: AXUIElement) -> [AXUIElement] {
        [focusedElement]
    }

    func prepareForSelectionCapture(in _: pid_t?) {}

    func selectedTextBounds(from focusedElement: AXUIElement) throws -> CGRect? {
        nil
    }

    func canReplaceSelectedText(in focusedElement: AXUIElement) throws -> Bool {
        false
    }
}

struct SystemAccessibilityProvider: AccessibilityProviding {
    @discardableResult
    static func requestAccessIfNeeded() -> Bool {
        if AXIsProcessTrusted() {
            return true
        }
        let options = [
            kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true,
        ] as CFDictionary
        return AXIsProcessTrustedWithOptions(options)
    }

    static var settingsPaneName: String {
        ProcessInfo.processInfo.operatingSystemVersion.majorVersion >= 27
            ? "Device Control and Data Access" : "Accessibility"
    }

    static func revealRunningApp() {
        NSWorkspace.shared.activateFileViewerSelecting([Bundle.main.bundleURL])
    }

    static func openAccessibilitySettings() {
        guard let url = URL(
            string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility"
        ) else {
            return
        }
        NSWorkspace.shared.open(url)
    }

    var isTrusted: Bool {
        AXIsProcessTrusted()
    }

    func prepareForSelectionCapture(in processID: pid_t?) {
        guard let processID,
              let application = NSRunningApplication(processIdentifier: processID),
              application.bundleIdentifier == "com.bytedance.macos.feishu"
        else { return }

        // Feishu's desktop renderer is Chromium/Electron-like. Electron only
        // exposes its full AX tree to third-party assistive technology after
        // AXManualAccessibility is enabled. The operation is best-effort and
        // ignored by native applications and older Feishu builds.
        let applicationElement = AXUIElementCreateApplication(processID)
        _ = AXUIElementSetAttributeValue(
            applicationElement,
            "AXManualAccessibility" as CFString,
            kCFBooleanTrue
        )
    }

    func focusedElement() throws -> AXUIElement? {
        try focusedElement(in: nil)
    }

    func focusedElement(in processID: pid_t?) throws -> AXUIElement? {
        guard isTrusted else {
            return nil
        }

        if let processID {
            return try focusedElement(inApplication: AXUIElementCreateApplication(processID))
        }

        let systemWideElement = AXUIElementCreateSystemWide()
        var focusedValue: CFTypeRef?
        let systemStatus = AXUIElementCopyAttributeValue(
            systemWideElement,
            kAXFocusedUIElementAttribute as CFString,
            &focusedValue
        )

        if systemStatus == .success,
           let focusedValue,
           CFGetTypeID(focusedValue) == AXUIElementGetTypeID() {
            return unsafeDowncast(focusedValue, to: AXUIElement.self)
        }

        // macOS 27 can return cannotComplete for the system-wide focused
        // element even after TCC trust is granted. Querying the frontmost AX
        // application is the supported equivalent and preserves the source
        // app because capture runs inside the hot-key callback.
        guard let frontmost = NSWorkspace.shared.frontmostApplication else {
            return nil
        }
        return try focusedElement(inApplication: AXUIElementCreateApplication(frontmost.processIdentifier))
    }

    private func focusedElement(inApplication applicationElement: AXUIElement) throws -> AXUIElement? {
        var focusedValue: CFTypeRef?
        let applicationStatus = AXUIElementCopyAttributeValue(
            applicationElement,
            kAXFocusedUIElementAttribute as CFString,
            &focusedValue
        )
        guard applicationStatus == .success,
              let focusedValue,
              CFGetTypeID(focusedValue) == AXUIElementGetTypeID()
        else { return nil }
        return unsafeDowncast(focusedValue, to: AXUIElement.self)
    }

    func textSelectionCandidates(from focusedElement: AXUIElement) -> [AXUIElement] {
        var candidates: [AXUIElement] = [focusedElement]
        var ancestor = focusedElement
        for _ in 0..<4 {
            var parentValue: CFTypeRef?
            guard AXUIElementCopyAttributeValue(
                ancestor,
                kAXParentAttribute as CFString,
                &parentValue
            ) == .success,
            let parentValue,
            CFGetTypeID(parentValue) == AXUIElementGetTypeID()
            else { break }
            let parent = unsafeDowncast(parentValue, to: AXUIElement.self)
            candidates.append(parent)
            ancestor = parent
        }

        // Electron often places selected text on an AXWebArea or a nearby
        // descendant instead of the focused group. Search a bounded local
        // neighborhood so one pathological tree cannot stall the hot-key path.
        var queue = candidates
        var cursor = 0
        while cursor < queue.count, candidates.count < 64 {
            let element = queue[cursor]
            cursor += 1
            var childrenValue: CFTypeRef?
            guard AXUIElementCopyAttributeValue(
                element,
                kAXChildrenAttribute as CFString,
                &childrenValue
            ) == .success,
            let children = childrenValue as? [AXUIElement]
            else { continue }
            for child in children where candidates.count < 64 {
                candidates.append(child)
                queue.append(child)
            }
        }
        return candidates
    }

    func selectedText(from focusedElement: AXUIElement) throws -> String? {
        var selectedValue: CFTypeRef?
        let status = AXUIElementCopyAttributeValue(
            focusedElement,
            kAXSelectedTextAttribute as CFString,
            &selectedValue
        )

        guard status == .success else {
            return nil
        }

        return selectedValue as? String
    }

    func canReplaceSelectedText(in focusedElement: AXUIElement) throws -> Bool {
        var settable = DarwinBoolean(false)
        let status = AXUIElementIsAttributeSettable(
            focusedElement,
            kAXSelectedTextAttribute as CFString,
            &settable
        )
        return status == .success && settable.boolValue
    }

    func selectedTextBounds(from focusedElement: AXUIElement) throws -> CGRect? {
        var rangeValue: CFTypeRef?
        let rangeStatus = AXUIElementCopyAttributeValue(
            focusedElement,
            kAXSelectedTextRangeAttribute as CFString,
            &rangeValue
        )
        guard rangeStatus == .success,
              let rangeValue,
              CFGetTypeID(rangeValue) == AXValueGetTypeID()
        else {
            return nil
        }

        let rangeAXValue = unsafeDowncast(rangeValue, to: AXValue.self)
        var range = CFRange()
        guard AXValueGetValue(rangeAXValue, .cfRange, &range) else {
            return nil
        }

        var boundsValue: CFTypeRef?
        let boundsStatus = AXUIElementCopyParameterizedAttributeValue(
            focusedElement,
            kAXBoundsForRangeParameterizedAttribute as CFString,
            rangeAXValue,
            &boundsValue
        )
        guard boundsStatus == .success,
              let boundsValue,
              CFGetTypeID(boundsValue) == AXValueGetTypeID()
        else {
            return nil
        }

        let boundsAXValue = unsafeDowncast(boundsValue, to: AXValue.self)
        var accessibilityRect = CGRect.zero
        guard AXValueGetValue(boundsAXValue, .cgRect, &accessibilityRect) else {
            return nil
        }
        return appKitDesktopRect(fromAccessibilityRect: accessibilityRect)
    }

    private func appKitDesktopRect(fromAccessibilityRect rect: CGRect) -> CGRect {
        // AX coordinates are measured downward from the main display's top;
        // using the tallest display makes selections jump when screens are
        // arranged above or below the main display.
        guard let desktopTop = NSScreen.screens.first?.frame.maxY else {
            return rect
        }
        return CGRect(
            x: rect.minX,
            y: desktopTop - rect.maxY,
            width: rect.width,
            height: rect.height
        )
    }
}

typealias AccessibilitySupport = SystemAccessibilityProvider
