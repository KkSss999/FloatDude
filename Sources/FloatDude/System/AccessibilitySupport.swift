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
}

extension AccessibilityProviding {
    func selectedTextBounds(from focusedElement: AXUIElement) throws -> CGRect? {
        nil
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
        let status = AXUIElementCopyAttributeValue(
            systemWideElement,
            kAXFocusedUIElementAttribute as CFString,
            &focusedValue
        )

        guard status == .success, let focusedValue else {
            return nil
        }

        guard CFGetTypeID(focusedValue) == AXUIElementGetTypeID() else {
            return nil
        }

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
        guard let desktopTop = NSScreen.screens.map(\.frame.maxY).max() else {
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
