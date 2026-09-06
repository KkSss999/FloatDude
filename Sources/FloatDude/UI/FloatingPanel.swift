import SwiftUI

/// SwiftUI content boundary for the future AppKit-backed floating `NSPanel`.
/// `FloatingPanelController` ownership, window level, focus, and dismissal rules
/// belong in the implementation phase; this view must remain presentation-only.
struct FloatingPanel<Content: View>: View {
    private let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        content
    }
}
