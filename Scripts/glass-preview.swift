import AppKit
import SwiftUI

/// Isolated UI review: synthetic content only, no runtime, clipboard or network.
/// Build with run-glass-preview.sh, then inspect the real native windows.
@main
struct GlassPreview {
    @MainActor static func main() {
        let app = NSApplication.shared
        app.setActivationPolicy(.regular)
        let menu = NSMenu()
        let appItem = NSMenuItem()
        let appMenu = NSMenu()
        appMenu.addItem(withTitle: "Quit Glass Preview", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        appItem.submenu = appMenu
        menu.addItem(appItem)
        app.mainMenu = menu
        let canvas = NSWindow(contentRect: NSRect(x: 100, y: 100, width: 1320, height: 760),
                              styleMask: [.titled, .closable], backing: .buffered, defer: false)
        canvas.title = "FloatDude — Glass material review"
        canvas.contentView = NSHostingView(rootView: backdrop)
        canvas.center()
        canvas.makeKeyAndOrderFront(nil)

        let samples: [(String, FloatingPanelState, String, ColorScheme, Bool)] = [
            ("Light · selection", .prompting, "Good tools disappear into the work.\nKeep the useful things close.", .light, false),
            ("Dark · response", .completed(text: "## A clearer answer\n\nGlass keeps **context** visible while preserving focus.\n\n- Stable placement\n- Native Markdown\n\n```swift\nlet ready = true\n```"), "Good tools disappear into the work.", .dark, false),
            ("Light · direct input", .prompting, "", .light, false),
            ("Increased contrast · error", .error(message: "Connection unavailable. Try again or check Settings."), "Review this short passage.", .light, true),
        ]
        var windows: [NSWindow] = [canvas]
        for (index, sample) in samples.enumerated() {
            let height: CGFloat = sample.1.isResponseVisible ? 560 : sample.2.isEmpty ? 176 : 236
            let conversation = AgentConversation(
                title: "Material research",
                messages: index == 1
                    ? [AgentMessage(role: .user, content: "Summarize the attached design notes.")]
                    : []
            )
            let attachment = AgentAttachment(
                displayName: "design-notes.pdf",
                kind: .pdf,
                storedPath: "/synthetic/design-notes.pdf",
                byteCount: 12_400
            )
            let origin = NSPoint(x: canvas.frame.minX + [32.0, 460.0, 32.0, 888.0][index],
                                 y: canvas.frame.maxY - (index == 2 ? 380 : 85) - height)
            let panel = NSPanel(contentRect: NSRect(origin: origin, size: CGSize(width: 400, height: height)),
                                styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
            panel.title = sample.0
            panel.isOpaque = false
            panel.backgroundColor = .clear
            panel.hasShadow = true
            panel.appearance = NSAppearance(named: sample.4 ? .accessibilityHighContrastAqua : sample.3 == .dark ? .darkAqua : .aqua)
            panel.contentView = NSHostingView(rootView:
                FloatingPanel(state: .constant(sample.1), prompt: .constant(""),
                              selectedText: sample.2,
                              canRewriteSelection: !sample.2.isEmpty,
                              selectedAction: .constant(.explain),
                              conversations: [conversation],
                              activeConversationID: conversation.id,
                              conversationMessages: conversation.messages,
                              attachments: index == 1 ? [attachment] : [],
                              attachmentStatus: index == 1 ? "1 file ready for read" : nil)
                    .environment(\.colorScheme, sample.3)
            )
            canvas.addChildWindow(panel, ordered: .above)
            panel.orderFront(nil)
            windows.append(panel)
        }
        app.activate(ignoringOtherApps: true)
        withExtendedLifetime(windows) { app.run() }
    }

    @MainActor private static var backdrop: some View {
        ReviewBackdrop().frame(width: 1320, height: 760).clipped()
    }
}

private struct ReviewBackdrop: View {
    @State private var background = 0

    private var colors: [Color] {
        background == 1
            ? [Color(red: 0.07, green: 0.12, blue: 0.24),
               Color(red: 0.18, green: 0.33, blue: 0.39),
               Color(red: 0.10, green: 0.13, blue: 0.20)]
            : [Color(red: 0.68, green: 0.79, blue: 0.84),
               Color(red: 0.88, green: 0.79, blue: 0.68),
               Color(red: 0.29, green: 0.42, blue: 0.49)]
    }

    var body: some View {
        ZStack {
            LinearGradient(colors: colors, startPoint: .topLeading, endPoint: .bottomTrailing)
            if background == 2 {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(0..<20, id: \.self) { row in
                        Text("\(row + 1)  Notes from a quiet workspace. Select a passage, ask a question, then return to your work.      A clear surface keeps the surrounding document in view.")
                            .font(.system(size: 13, design: .monospaced))
                    }
                }
                .foregroundStyle(.black.opacity(0.8))
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .padding(.top, 65)
            }
            VStack(alignment: .leading, spacing: 18) {
                Text("FLOATDUDE / MATERIAL STUDY").font(.system(size: 12, weight: .semibold)).tracking(3)
                if background != 2 {
                    Text("A little help.\nA lighter presence.")
                        .font(.system(size: 64, weight: .medium, design: .serif))
                }
                Spacer()
                HStack {
                    Text("Native SwiftUI surfaces · synthetic content · no model requests")
                        .font(.system(size: 12))
                    Spacer()
                    Picker("Review background", selection: $background) {
                        Text("Daylight").tag(0)
                        Text("Dark desktop").tag(1)
                        Text("Dense text").tag(2)
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    .frame(width: 320)
                }
            }
            .foregroundStyle(background == 1 ? .white.opacity(0.8) : .black.opacity(0.7))
            .padding(35)
            .frame(width: 1320, height: 760, alignment: .leading)
        }
    }
}
