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
    func selectedText(from focusedElement: AXUIElement) throws -> String?
    func selectedTextBounds(from focusedElement: AXUIElement) throws -> CGRect?
    func canReplaceSelectedText(in focusedElement: AXUIElement) throws -> Bool
}

extension AccessibilityProviding {
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

    func focusedElement() throws -> AXUIElement? {
        guard isTrusted else {
            return nil
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
        let applicationElement = AXUIElementCreateApplication(frontmost.processIdentifier)
        focusedValue = nil
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
