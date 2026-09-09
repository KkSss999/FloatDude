import AppKit
import Foundation
import SwiftUI

enum FloatingPanelState: Equatable, Sendable {
    case idle
    case prompting
    case loading(action: PromptAction)
    case streaming(text: String)
    case completed(text: String)
    case cancelled
    case error(message: String)

    var isBusy: Bool {
        switch self {
        case .loading, .streaming: true
        default: false
        }
    }

    var isResponseVisible: Bool {
        switch self {
        case .loading, .streaming, .completed, .cancelled, .error: true
        case .idle, .prompting: false
        }
    }

    var responseText: String? {
        switch self {
        case .streaming(let text), .completed(let text): text
        default: nil
        }
    }

    var statusTitle: String {
        switch self {
        case .idle: "Ready"
        case .prompting: "Prompt"
        case .loading: "Loading"
        case .streaming: "Streaming"
        case .completed: "Complete"
        case .cancelled: "Cancelled"
        case .error: "Error"
        }
    }

    var headerSymbolName: String {
        switch self {
        case .loading, .streaming: "sparkles"
        case .completed: "checkmark.circle"
        case .cancelled: "pause.circle"
        case .error: "exclamationmark.triangle"
        case .idle, .prompting: "text.bubble"
        }
    }
}

/// Pure state and transition model for deterministic coordinator and UI tests.
struct FloatingPanelViewModel: Equatable, Sendable {
    var selectedText: String
    var prompt: String
    var selectedAction: PromptAction
    private(set) var state: FloatingPanelState

    init(
        selectedText: String = "",
        prompt: String = "",
        selectedAction: PromptAction = .ask,
        state: FloatingPanelState = .idle
    ) {
        self.selectedText = selectedText
        self.prompt = prompt
        self.selectedAction = selectedAction
        self.state = state
    }

    var selectedTextPreview: String {
        FloatingPanelText.selectedPreview(selectedText)
    }

    mutating func beginPrompting() {
        guard !state.isBusy else { return }
        state = .prompting
    }

    mutating func choose(_ action: PromptAction) {
        selectedAction = action
        if !state.isBusy { state = .prompting }
    }

    @discardableResult
    mutating func submit() -> Bool {
        guard !state.isBusy,
              !prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        else { return false }

        state = .loading(action: selectedAction)
        return true
    }

    mutating func appendStream(_ delta: String) {
        guard !delta.isEmpty else { return }
        switch state {
        case .loading:
            state = .streaming(text: delta)
        case .streaming(let text):
            state = .streaming(text: text + delta)
        default:
            break
        }
    }

    mutating func complete(with text: String? = nil) {
        let resolved: String
        if let text {
            resolved = text
        } else {
            resolved = state.responseText ?? ""
        }
        state = .completed(text: resolved)
    }

    mutating func cancel() {
        guard state.isBusy else { return }
        state = .cancelled
    }

    mutating func fail(with message: String) {
        state = .error(message: message)
    }
}

struct FloatingPanelHandlers {
    var onAction: ((PromptAction) -> Void)?
    var onSubmit: ((PromptAction, String) -> Void)?
    var onCopy: ((String) -> Void)?
    var onCancel: (() -> Void)?
    var onRetry: (() -> Void)?
    var onOpenSettings: (() -> Void)?
    var onNewConversation: (() -> Void)?
    var onSelectConversation: ((UUID) -> Void)?
    var onDeleteConversation: ((UUID) -> Void)?
    var onAddAttachments: (([URL]) -> Void)?
    var onRemoveAttachment: ((UUID) -> Void)?

    init(
        onAction: ((PromptAction) -> Void)? = nil,
        onSubmit: ((PromptAction, String) -> Void)? = nil,
        onCopy: ((String) -> Void)? = nil,
        onCancel: (() -> Void)? = nil,
        onRetry: (() -> Void)? = nil,
        onOpenSettings: (() -> Void)? = nil,
        onNewConversation: (() -> Void)? = nil,
        onSelectConversation: ((UUID) -> Void)? = nil,
        onDeleteConversation: ((UUID) -> Void)? = nil,
        onAddAttachments: (([URL]) -> Void)? = nil,
        onRemoveAttachment: ((UUID) -> Void)? = nil
    ) {
        self.onAction = onAction
        self.onSubmit = onSubmit
        self.onCopy = onCopy
        self.onCancel = onCancel
        self.onRetry = onRetry
        self.onOpenSettings = onOpenSettings
        self.onNewConversation = onNewConversation
        self.onSelectConversation = onSelectConversation
        self.onDeleteConversation = onDeleteConversation
        self.onAddAttachments = onAddAttachments
        self.onRemoveAttachment = onRemoveAttachment
    }
}

enum FloatingPanelText {
    static func selectedPreview(_ text: String) -> String {
        text.components(separatedBy: .newlines)
            .prefix(2)
            .joined(separator: "\n")
    }
}

/// SwiftUI content boundary for the AppKit-backed floating panel.
/// Window level, focus, and actual dismissal remain coordinator concerns.
struct FloatingPanel: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @Binding private var state: FloatingPanelState
    @Binding private var prompt: String
    @Binding private var selectedAction: PromptAction

    private let language: SettingsLanguage
    private let selectedText: String
    private let selectedSource: CapturedContext.Source?
    private let canRewriteSelection: Bool
    private let contextGuidance: String?
    private let conversations: [AgentConversation]
    private let activeConversationID: UUID?
    private let conversationMessages: [AgentMessage]
    private let attachments: [AgentAttachment]
    private let attachmentStatus: String?
    private let onOpenAccessibilitySettings: (() -> Void)?
    private let onContentHeightChange: ((CGFloat) -> Void)?
    private let handlers: FloatingPanelHandlers
    private let customContent: AnyView?
    @State private var didExpandOnce = false
    @State private var isConversationPickerPresented = false
    @State private var conversationPendingDeletionID: UUID?
    @State private var isAtConversationBottom = true

    init(
        state: Binding<FloatingPanelState>,
        prompt: Binding<String>,
        language: SettingsLanguage = .systemDefault,
        selectedText: String = "",
        selectedSource: CapturedContext.Source? = nil,
        canRewriteSelection: Bool = false,
        contextGuidance: String? = nil,
        selectedAction: Binding<PromptAction> = .constant(.ask),
        conversations: [AgentConversation] = [],
        activeConversationID: UUID? = nil,
        conversationMessages: [AgentMessage] = [],
        attachments: [AgentAttachment] = [],
        attachmentStatus: String? = nil,
        handlers: FloatingPanelHandlers = .init(),
        onOpenAccessibilitySettings: (() -> Void)? = nil,
        onContentHeightChange: ((CGFloat) -> Void)? = nil
    ) {
        self._state = state
        self._prompt = prompt
        self._selectedAction = selectedAction
        self.language = language
        self.selectedText = selectedText
        self.selectedSource = selectedSource
        self.canRewriteSelection = canRewriteSelection
        self.contextGuidance = contextGuidance
        self.conversations = conversations
        self.activeConversationID = activeConversationID
        self.conversationMessages = conversationMessages
        self.attachments = attachments
        self.attachmentStatus = attachmentStatus
        self.onOpenAccessibilitySettings = onOpenAccessibilitySettings
        self.onContentHeightChange = onContentHeightChange
        self.handlers = handlers
        self.customContent = nil
    }

    /// Keeps the original presentation-only content boundary available for
    /// callers that want to supply a custom panel surface.
    init<Content: View>(@ViewBuilder content: () -> Content) {
        self._state = .constant(.idle)
        self._prompt = .constant("")
        self._selectedAction = .constant(.ask)
        self.language = .systemDefault
        self.selectedText = ""
        self.selectedSource = nil
        self.canRewriteSelection = false
        self.contextGuidance = nil
        self.conversations = []
        self.activeConversationID = nil
        self.conversationMessages = []
        self.attachments = []
        self.attachmentStatus = nil
        self.onOpenAccessibilitySettings = nil
        self.onContentHeightChange = nil
        self.handlers = .init()
        self.customContent = AnyView(content())
    }

    var body: some View {
        Group {
            if let customContent {
                customContent
            } else {
                panelSurface
            }
        }
    }

    private var panelSurface: some View {
        VStack(spacing: 0) {
            panelHeader
                .padding(.horizontal, 18)
                .padding(.top, 14)
                .padding(.bottom, 10)

            Rectangle()
                .fill(Color.primary.opacity(0.10))
                .frame(height: 0.5)
                .padding(.horizontal, 18)

            GeometryReader { viewport in
                ScrollViewReader { proxy in
                    ScrollView(.vertical) {
                        VStack(alignment: .leading, spacing: 10) {
                            if !conversationMessages.isEmpty {
                                conversationTranscript
                            }

                            PromptView(
                                prompt: $prompt,
                                language: language,
                                selectedText: selectedText,
                                selectedSource: selectedSource,
                                canRewriteSelection: canRewriteSelection,
                                attachments: attachments,
                                attachmentStatus: attachmentStatus,
                                contextGuidance: contextGuidance,
                                selectedAction: $selectedAction,
                                isDisabled: state.isBusy,
                                onAction: handlers.onAction,
                                onSubmit: submit,
                                onCancel: handlers.onCancel,
                                onAddAttachments: handlers.onAddAttachments,
                                onRemoveAttachment: handlers.onRemoveAttachment,
                                onOpenAccessibilitySettings: onOpenAccessibilitySettings
                            )

                            conversationStateFooter

                            Color.clear
                                .frame(height: 1)
                                .id(PanelScrollAnchor.bottom)
                                .background {
                                    GeometryReader { marker in
                                        Color.clear.preference(
                                            key: PanelScrollBottomPreference.self,
                                            value: marker.frame(in: .named(PanelScrollAnchor.coordinateSpace)).maxY
                                        )
                                    }
                                }
                        }
                        .padding(.horizontal, 18)
                        .padding(.top, 12)
                        .padding(.bottom, 18)
                        .background {
                            GeometryReader { content in
                                Color.clear.preference(
                                    key: PanelContentHeightPreference.self,
                                    value: content.size.height
                                )
                            }
                        }
                    }
                    .coordinateSpace(name: PanelScrollAnchor.coordinateSpace)
                    .scrollIndicators(.hidden)
                    .onPreferenceChange(PanelScrollBottomPreference.self) { bottomY in
                        isAtConversationBottom = bottomY <= viewport.size.height + 8
                    }
                    .onPreferenceChange(PanelContentHeightPreference.self) { contentHeight in
                        guard contentHeight > 0 else { return }
                        onContentHeightChange?(contentHeight + PanelLayout.fixedHeaderHeight)
                    }
                    .overlay(alignment: .leading) {
                        if conversationMessages.contains(where: { $0.role == .user }) {
                            ConversationNavigationRail(messages: conversationMessages, language: language) { messageID in
                                withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.18)) {
                                    proxy.scrollTo(messageID, anchor: .top)
                                }
                            }
                            .padding(.leading, 8)
                        }
                    }
                    .overlay(alignment: .bottomTrailing) {
                        if !isAtConversationBottom, !conversationMessages.isEmpty {
                            Button {
                                scrollToConversationBottom(proxy, animated: true)
                            } label: {
                                Image(systemName: "arrow.down.to.line.compact")
                                    .font(.system(size: 13, weight: .semibold))
                                    .frame(width: 32, height: 32)
                                    .background(.regularMaterial, in: Circle())
                            }
                            .buttonStyle(.plain)
                            .help(copy.text(.jumpLatest))
                            .accessibilityLabel(copy.text(.jumpLatest))
                            .padding(14)
                            .transition(reduceMotion ? .identity : .scale.combined(with: .opacity))
                        }
                    }
                    .onAppear {
                        updateExpansion(for: state)
                        DispatchQueue.main.async {
                            scrollToConversationBottom(proxy, animated: false)
                        }
                    }
                    .onChange(of: state) { _, newState in
                        updateExpansion(for: newState)
                        if isAtConversationBottom || newState.isBusy {
                            DispatchQueue.main.async {
                                scrollToConversationBottom(proxy, animated: newState.isBusy)
                            }
                        }
                    }
                    .onChange(of: activeConversationID) { _, _ in
                        DispatchQueue.main.async {
                            scrollToConversationBottom(proxy, animated: false)
                        }
                    }
                    .onChange(of: conversationMessages.last?.id) { _, _ in
                        guard isAtConversationBottom else { return }
                        DispatchQueue.main.async {
                            scrollToConversationBottom(proxy, animated: true)
                        }
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .glassMaterial(cornerRadius: 28)
        .shadow(color: .black.opacity(0.16), radius: 4, x: 0, y: 2)
        .padding(5)
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.24), value: didExpandOnce)
        .transaction { transaction in
            if reduceMotion { transaction.animation = nil }
        }
        .confirmationDialog(
            copy.text(.deleteConversationQuestion),
            isPresented: deleteConfirmationPresented,
            titleVisibility: .visible
        ) {
            if let conversationPendingDeletionID {
                Button(copy.text(.deleteConversation), role: .destructive) {
                    handlers.onDeleteConversation?(conversationPendingDeletionID)
                    self.conversationPendingDeletionID = nil
                }
            }
        } message: {
            Text(copy.text(.conversationDeleteHelp))
        }
    }

    private var panelHeader: some View {
        HStack(alignment: .center, spacing: 10) {
            HStack(spacing: 10) {
                Image(systemName: "sparkle")
                    .font(.system(size: 21, weight: .light))
                    .accessibilityHidden(true)
                Text("FloatDude")
                    .font(.system(size: 14, weight: .medium, design: .rounded))
                Spacer(minLength: 8)
            }
            .frame(height: 26)
            .overlay { PanelDragHandle().accessibilityHidden(true) }
            .help(language == .simplifiedChinese ? "拖动以移动窗口" : "Drag to move")
            conversationMenu
            Button {
                handlers.onCancel?()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .frame(width: 26, height: 26)
            }
            .buttonStyle(.plain)
            .keyboardShortcut(.escape)
            .help(language == .simplifiedChinese ? "关闭（Esc）" : "Close (Esc)")
            .accessibilityLabel(copy.text(.closeFloatDude))
        }
    }

    private var copy: ProductCopy {
        ProductCopy(language: language)
    }

    private var conversationMenu: some View {
        Button {
            isConversationPickerPresented = true
        } label: {
            Image(systemName: "bubble.left.and.bubble.right")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.secondary)
                .frame(width: 26, height: 26)
        }
        .buttonStyle(.plain)
        .fixedSize()
        .help(copy.text(.conversations))
        .popover(isPresented: $isConversationPickerPresented, arrowEdge: .bottom) {
            VStack(alignment: .leading, spacing: 4) {
                Button(copy.text(.newConversation), systemImage: "plus") {
                    isConversationPickerPresented = false
                    handlers.onNewConversation?()
                }
                .buttonStyle(.plain)
                .padding(.horizontal, 10)
                .padding(.vertical, 7)

                Divider()

                ForEach(conversations) { conversation in
                    conversationPickerRow(conversation)
                }
            }
            .padding(6)
            .frame(minWidth: 250, maxWidth: 320, alignment: .leading)
        }
    }

    private func conversationPickerRow(_ conversation: AgentConversation) -> some View {
        HStack(spacing: 8) {
            Button {
                isConversationPickerPresented = false
                handlers.onSelectConversation?(conversation.id)
            } label: {
                HStack(spacing: 7) {
                    Image(systemName: conversation.id == activeConversationID ? "checkmark" : "bubble.left")
                        .frame(width: 14)
                    Text(conversation.title)
                        .lineLimit(1)
                    Spacer(minLength: 0)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            Button {
                isConversationPickerPresented = false
                conversationPendingDeletionID = conversation.id
            } label: {
                Image(systemName: "trash")
                    .font(.system(size: 12, weight: .medium))
                    .frame(width: 28, height: 26)
            }
            .buttonStyle(.borderless)
            .foregroundStyle(.red)
            .help(copy.text(.deleteConversation))
            .accessibilityLabel("\(copy.text(.deleteConversation)) \(conversation.title)")
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .background(
            conversation.id == activeConversationID
                ? Color.accentColor.opacity(0.14)
                : Color.clear,
            in: RoundedRectangle(cornerRadius: 7, style: .continuous)
        )
    }

    private var deleteConfirmationPresented: Binding<Bool> {
        Binding(
            get: { conversationPendingDeletionID != nil },
            set: { isPresented in
                if !isPresented {
                    conversationPendingDeletionID = nil
                }
            }
        )
    }

    private var conversationTranscript: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(conversationMessages) { message in
                VStack(alignment: .leading, spacing: 3) {
                    Text(message.role == .user ? copy.text(.you) : copy.text(.floatDude))
                        .font(.system(size: 9, weight: .semibold))
                        .tracking(0.8)
                        .foregroundStyle(.secondary)
                    if message.role == .assistant {
                        MarkdownResponse(text: message.content)
                            .font(.callout)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    } else {
                        Text(message.content)
                            .font(.callout)
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 7)
                .glassInset(cornerRadius: 10)
                .id(message.id)
            }
        }
    }

    @ViewBuilder
    private var conversationStateFooter: some View {
        switch state {
        case let .completed(text):
            if !text.isEmpty {
                HStack {
                    Button {
                        handlers.onCopy?(text)
                    } label: {
                        Label(copy.text(.copy), systemImage: "doc.on.doc")
                            .font(.callout.weight(.medium))
                    }
                    .buttonStyle(.plain)
                    Spacer()
                    Text(copy.text(.complete))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 8)
                .glassInset(cornerRadius: 10)
            }
        case .cancelled:
            Label(copy.text(.cancelled), systemImage: "pause.circle")
                .font(.callout)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 10)
                .padding(.vertical, 8)
                .glassInset(cornerRadius: 10)
        case let .error(message):
            VStack(alignment: .leading, spacing: 8) {
                Label(copy.text(.responseError), systemImage: "exclamationmark.triangle")
                    .font(.callout.weight(.semibold))
                    .foregroundStyle(.orange)
                Text(message)
                    .font(.callout)
                    .fixedSize(horizontal: false, vertical: true)
                HStack(spacing: 12) {
                    if handlers.onRetry != nil {
                        Button(copy.text(.tryAgain)) { handlers.onRetry?() }
                    }
                    if handlers.onOpenSettings != nil {
                        Button(copy.text(.menuSettings)) { handlers.onOpenSettings?() }
                    }
                }
                .buttonStyle(.borderless)
            }
            .padding(10)
            .glassInset(cornerRadius: 10, emphasized: true)
        case .idle, .prompting, .loading, .streaming:
            EmptyView()
        }
    }

    private func submit(action: PromptAction, prompt: String) {
        handlers.onSubmit?(action, prompt)
    }

    private func updateExpansion(for newState: FloatingPanelState) {
        guard newState.isResponseVisible else { return }
        // The response phase has one expansion event for the lifetime of this
        // panel; subsequent stream chunks only update content within the same
        // response region.
        if !didExpandOnce { didExpandOnce = true }
    }

    private func scrollToConversationBottom(_ proxy: ScrollViewProxy, animated: Bool) {
        if animated, !reduceMotion {
            withAnimation(.easeInOut(duration: 0.18)) {
                proxy.scrollTo(PanelScrollAnchor.bottom, anchor: .bottom)
            }
        } else {
            proxy.scrollTo(PanelScrollAnchor.bottom, anchor: .bottom)
        }
    }
}

private enum PanelScrollAnchor {
    static let bottom = "floatdude.conversation.bottom"
    static let coordinateSpace = "floatdude.conversation.scroll"
}

private enum PanelLayout {
    // Header: 14pt top + 26pt content + 10pt bottom, divider, and outer shell.
    static let fixedHeaderHeight: CGFloat = 56
}

private struct PanelScrollBottomPreference: PreferenceKey {
    static let defaultValue: CGFloat = .greatestFiniteMagnitude

    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}

private struct PanelContentHeightPreference: PreferenceKey {
    static let defaultValue: CGFloat = 0

    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}

/// A compact conversation map. At rest it is only a quiet sequence of short
/// ticks; hover expands the target and reveals an excerpt. Each tick is a
/// direct scroll target so long chats remain navigable without a separate list.
private struct ConversationNavigationRail: View {
    let messages: [AgentMessage]
    let language: SettingsLanguage
    let onJump: (UUID) -> Void

    @State private var isHoveringRail = false
    @State private var hoveredMessageID: UUID?

    private var navigationMessages: [AgentMessage] {
        constSample(messages.filter { $0.role == .user }, maximum: 18)
    }

    private var copy: ProductCopy {
        ProductCopy(language: language)
    }

    var body: some View {
        HStack(spacing: 8) {
            VStack(spacing: 5) {
                ForEach(navigationMessages) { message in
                    let isHovered = hoveredMessageID == message.id
                    Button {
                        onJump(message.id)
                    } label: {
                        Capsule()
                            .fill(isHovered ? Color.primary.opacity(0.9) : Color.primary.opacity(0.42))
                            .frame(
                                width: isHoveringRail ? markerWidth(for: message, highlighted: isHovered) : 6,
                                height: isHoveringRail ? 3 : 2
                            )
                            .frame(width: 28, height: 7, alignment: .leading)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .onHover { hovering in
                        hoveredMessageID = hovering ? message.id : nil
                    }
                    .accessibilityLabel(
                        message.role == .user
                            ? copy.text(.jumpToUserMessage)
                            : "\(copy.text(.jumpLatest)) · FloatDude"
                    )
                }
            }
            .padding(.vertical, 4)
            .contentShape(Rectangle())
            .onHover { hovering in
                isHoveringRail = hovering
                if !hovering { hoveredMessageID = nil }
            }

            if isHoveringRail, let hoveredMessage {
                VStack(alignment: .leading, spacing: 5) {
                    Text(hoveredMessage.role == .user ? copy.text(.you) : copy.text(.floatDude))
                        .font(.system(size: 9, weight: .semibold))
                        .tracking(0.8)
                        .foregroundStyle(.secondary)
                    Text(hoveredMessage.content)
                        .font(.callout)
                        .lineLimit(3)
                        .multilineTextAlignment(.leading)
                }
                .frame(width: 240, alignment: .leading)
                .padding(12)
                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .strokeBorder(Color.primary.opacity(0.14), lineWidth: 0.5)
                }
                .shadow(color: .black.opacity(0.16), radius: 12, y: 4)
                .transition(.opacity.combined(with: .scale(scale: 0.96, anchor: .leading)))
            }
        }
        .animation(.easeOut(duration: 0.16), value: isHoveringRail)
    }

    private var hoveredMessage: AgentMessage? {
        guard let hoveredMessageID else { return nil }
        return navigationMessages.first(where: { $0.id == hoveredMessageID })
    }

    private func markerWidth(for message: AgentMessage, highlighted: Bool) -> CGFloat {
        guard highlighted else { return 9 }
        return min(27, max(14, CGFloat(message.content.count) / 8 + 12))
    }

    private func constSample(_ allMessages: [AgentMessage], maximum: Int) -> [AgentMessage] {
        guard allMessages.count > maximum else { return allMessages }
        let step = Double(allMessages.count - 1) / Double(maximum - 1)
        return (0..<maximum).map { index in
            allMessages[Int((Double(index) * step).rounded())]
        }
    }
}

/// NSHostingView/NSScrollView consume mouse events before background window
/// dragging sees them. Give the title strip an explicit native drag target;
/// keep it away from the close button, text selection and input controls.
private struct PanelDragHandle: NSViewRepresentable {
    func makeNSView(context: Context) -> DragView { DragView() }
    func updateNSView(_ view: DragView, context: Context) {}

    final class DragView: NSView {
        private var grabPoint: NSPoint?
        override var mouseDownCanMoveWindow: Bool { false }
        override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
        override func mouseDown(with event: NSEvent) {
            grabPoint = event.locationInWindow
        }
        override func mouseDragged(with event: NSEvent) {
            guard let window, let grabPoint else { return }
            window.setFrameOrigin(NSPoint(
                x: window.frame.minX + event.locationInWindow.x - grabPoint.x,
                y: window.frame.minY + event.locationInWindow.y - grabPoint.y
            ))
        }
        override func mouseUp(with event: NSEvent) {
            grabPoint = nil
        }
    }
}
