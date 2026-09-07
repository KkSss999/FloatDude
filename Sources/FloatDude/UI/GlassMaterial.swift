import AppKit
import SwiftUI

/// A single optical surface. Content wells do not stack additional blur layers.
/// macOS 26 supplies real Liquid Glass; older systems use behind-window vibrancy.
struct GlassMaterial: ViewModifier {
    let cornerRadius: CGFloat

    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.colorSchemeContrast) private var contrast
    @Environment(\.colorScheme) private var scheme

    private var shape: RoundedRectangle {
        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
    }

    func body(content: Content) -> some View {
        surface(content)
            .overlay {
                if contrast == .increased {
                    shape.strokeBorder(Color.primary.opacity(0.65), lineWidth: 1.5)
                }
            }
    }

    @ViewBuilder
    private func surface(_ content: Content) -> some View {
        if reduceTransparency {
            content
                .background(Color(nsColor: .windowBackgroundColor), in: shape)
                .overlay { shape.strokeBorder(Color.primary.opacity(0.22), lineWidth: 1) }
        } else if #available(macOS 26.0, *) {
            content
                .background {
                    // Full native diffusion prevents text from other windows
                    // competing with our controls. Glass stays behind content.
                    shape.fill(.clear)
                        .glassEffect(.regular, in: shape)
                    shape.fill(scheme == .dark
                               ? Color(red: 0.08, green: 0.10, blue: 0.14).opacity(contrast == .increased ? 0.86 : 0.52)
                               : Color.white.opacity(contrast == .increased ? 0.70 : 0.42))
                }
                .overlay {
                    shape.inset(by: 0.75).strokeBorder(
                        LinearGradient(colors: [.white.opacity(0.8), .white.opacity(0.06),
                                                .white.opacity(0.3)],
                                       startPoint: .topLeading, endPoint: .bottomTrailing),
                        lineWidth: 1
                    )
                    shape.inset(by: 2).strokeBorder(
                        LinearGradient(colors: [.white.opacity(0.24), .clear, .white.opacity(0.08)],
                                       startPoint: .top, endPoint: .bottom), lineWidth: 1
                    )
                }
        } else {
            content
                .background { WindowVibrancy().clipShape(shape) }
                .background(Color(nsColor: .windowBackgroundColor).opacity(0.16), in: shape)
                .overlay {
                    // Directional rim light supplies thickness without tinting the text.
                    shape.strokeBorder(
                        LinearGradient(
                            colors: [.white.opacity(scheme == .dark ? 0.46 : 0.85),
                                     .white.opacity(0.08),
                                     Color(red: 0.65, green: 0.74, blue: 0.91).opacity(0.28),
                                     .white.opacity(0.38)],
                            startPoint: .topLeading, endPoint: .bottomTrailing
                        ), lineWidth: 1
                    )
                    shape.inset(by: 1).strokeBorder(Color.primary.opacity(0.06), lineWidth: 0.5)
                }
                .clipShape(shape)
        }
    }
}

private struct WindowVibrancy: NSViewRepresentable {
    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.blendingMode = .behindWindow
        view.material = .hudWindow
        view.state = .active
        return view
    }

    func updateNSView(_ view: NSVisualEffectView, context: Context) {}
}

/// Quiet, readable content inset inside the outer glass, without nested materials.
struct GlassInset: ViewModifier {
    var cornerRadius: CGFloat
    var emphasized: Bool
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.colorSchemeContrast) private var contrast
    @Environment(\.colorScheme) private var scheme

    func body(content: Content) -> some View {
        content
            .background {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(reduceTransparency
                          ? Color(nsColor: .controlBackgroundColor)
                          : (scheme == .dark ? Color.white.opacity(0.06) : Color.white.opacity(0.22)))
            }
            .overlay {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .strokeBorder(emphasized ? GlassPalette.coral(scheme)
                                  : Color.primary.opacity(contrast == .increased ? 0.5 : 0.10),
                                  lineWidth: emphasized || contrast == .increased ? 1.5 : 0.5)
            }
    }
}

enum GlassPalette {
    static func coral(_ scheme: ColorScheme) -> Color {
        scheme == .dark
            ? Color(red: 1, green: 0.57, blue: 0.48)
            : Color(red: 0.68, green: 0.22, blue: 0.16)
    }
}

struct GlassActionStyle: ButtonStyle {
    var selected = false
    @Environment(\.colorScheme) private var scheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.isEnabled) private var isEnabled
    @State private var hovering = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .padding(.horizontal, 10)
            .frame(minHeight: 32)
            .background {
                Capsule()
                    .fill(selected ? GlassPalette.coral(scheme).opacity(0.10)
                          : Color.primary.opacity(configuration.isPressed ? 0.10 : hovering ? 0.06 : 0))
            }
            .opacity(isEnabled ? 1 : 0.5)
            .onHover { hovering = $0 }
            .animation(reduceMotion ? nil : .easeOut(duration: 0.14), value: hovering)
    }
}

extension View {
    func glassMaterial(cornerRadius: CGFloat = 20) -> some View {
        modifier(GlassMaterial(cornerRadius: cornerRadius))
    }

    func glassInset(cornerRadius: CGFloat = 12, emphasized: Bool = false) -> some View {
        modifier(GlassInset(cornerRadius: cornerRadius, emphasized: emphasized))
    }
}
