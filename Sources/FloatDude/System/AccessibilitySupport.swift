import ApplicationServices
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
}

struct SystemAccessibilityProvider: AccessibilityProviding {
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
}

typealias AccessibilitySupport = SystemAccessibilityProvider
