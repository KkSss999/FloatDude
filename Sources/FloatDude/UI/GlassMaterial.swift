import AppKit
import SwiftUI

/// Native material surface with a solid, appearance-aware fallback when the
/// user asks macOS to reduce transparency.
struct GlassMaterial: ViewModifier {
    let cornerRadius: CGFloat

    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.colorSchemeContrast) private var colorSchemeContrast

    private var increaseContrast: Bool {
        colorSchemeContrast == .increased
    }

    func body(content: Content) -> some View {
        content
            .background {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(reduceTransparency ? Color(nsColor: .windowBackgroundColor) : Color.clear)
                if !reduceTransparency {
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .fill(.ultraThinMaterial)
                }
            }
            .overlay {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .strokeBorder(
                        Color.primary.opacity(increaseContrast ? 0.48 : 0.18),
                        lineWidth: increaseContrast ? 1.5 : 1
                    )
            }
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
    }
}

extension View {
    func glassMaterial(cornerRadius: CGFloat = 20) -> some View {
        modifier(GlassMaterial(cornerRadius: cornerRadius))
    }
}
