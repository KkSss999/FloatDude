import AppKit
import SwiftUI

@MainActor
final class FloatingPanelController: NSObject, NSWindowDelegate {
    typealias Hook = PanelLifecycle.Hook

    nonisolated static let defaultPanelSize = CGSize(width: 420, height: 260)

    private let positioner: any WindowPositioning
    private var lifecycle: PanelLifecycle!
    private var panel: DismissiblePanel?
    private var content: AnyView?
    private var requestedPanelSize = FloatingPanelController.defaultPanelSize
    private var selectionRect: CGRect?
    private let terminationObserver: TerminationObserver

    var isPresented: Bool {
        lifecycle.isPresented
    }

    /// The one physical panel is retained and reused for the controller's
    /// entire lifetime.
    var window: NSPanel? {
        panel
    }

    init(
        positioner: any WindowPositioning = WindowPositioner(),
        onDismiss: @escaping Hook = { _ in },
        onCancel: @escaping Hook = { _ in }
    ) {
        self.positioner = positioner
        self.terminationObserver = TerminationObserver()
        super.init()
        terminationObserver.owner = self
        lifecycle = PanelLifecycle(
            onDismiss: { [weak self] reason in
                self?.hidePhysicalPanel()
                onDismiss(reason)
            },
            onCancel: onCancel
        )
        terminationObserver.start()
    }

    func present<Content: View>(
        @ViewBuilder content: () -> Content,
        panelSize: CGSize = FloatingPanelController.defaultPanelSize,
        avoiding selectionRect: CGRect? = nil,
        activateForInput: Bool = false
    ) {
        present(
            AnyView(FloatingPanel(content: content)),
            panelSize: panelSize,
            avoiding: selectionRect,
            activateForInput: activateForInput
        )
    }

    func present(
        _ content: AnyView,
        panelSize: CGSize = FloatingPanelController.defaultPanelSize,
        avoiding selectionRect: CGRect? = nil,
        activateForInput: Bool = false
    ) {
        self.content = content
        requestedPanelSize = panelSize
        self.selectionRect = selectionRect
        _ = lifecycle.present()
        showPhysicalPanel(activateForInput: activateForInput)
    }

    func update(panelSize: CGSize, avoiding selectionRect: CGRect? = nil) {
        requestedPanelSize = panelSize
        self.selectionRect = selectionRect
        guard lifecycle.isPresented else { return }
        showPhysicalPanel()
    }

    /// The coordinator calls this from its global-hotkey handler. A shortcut
    /// while visible cancels and dismisses; while hidden it presents the last
    /// configured content without creating another NSPanel.
    func handleShortcut() {
        if lifecycle.isPresented {
            _ = lifecycle.handle(.shortcut)
        } else if content != nil {
            _ = lifecycle.handle(.shortcut)
            showPhysicalPanel()
        }
    }

    func dismiss() {
        _ = lifecycle.handle(.dismiss)
    }

    func cancel() {
        _ = lifecycle.handle(.escape)
    }

    func windowDidResignKey(_ notification: Notification) {
        guard lifecycle.isPresented else { return }
        _ = lifecycle.handle(.clickAway)
    }

    func windowDidResignMain(_ notification: Notification) {
        guard lifecycle.isPresented else { return }
        _ = lifecycle.handle(.clickAway)
    }

    func windowShouldClose(_ sender: NSWindow) -> Bool {
        _ = lifecycle.handle(.dismiss)
        return false
    }

    private func showPhysicalPanel() {
        showPhysicalPanel(activateForInput: false)
    }

    private func showPhysicalPanel(activateForInput: Bool) {
        guard let content else { return }

        let panel = self.panel ?? makePanel()
        let fittedSize = positioner.fittedPanelSize(for: requestedPanelSize)
        panel.contentView = NSHostingView(rootView: content)
        panel.setContentSize(fittedSize)
        panel.setFrameOrigin(
            positioner.origin(forPanelSize: fittedSize, avoiding: selectionRect)
        )
        panel.orderFrontRegardless()
        if activateForInput {
            NSApp.activate(ignoringOtherApps: true)
            panel.makeKeyAndOrderFront(nil)
        }
    }

    private func makePanel() -> DismissiblePanel {
        let panel = DismissiblePanel(
            contentRect: NSRect(origin: .zero, size: FloatingPanelController.defaultPanelSize),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: true
        )
        panel.isFloatingPanel = true
        panel.level = .floating
        panel.hidesOnDeactivate = false
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.isReleasedWhenClosed = false
        panel.delegate = self
        panel.onCancelOperation = { [weak self] in
            self?.cancel()
        }
        self.panel = panel
        return panel
    }

    private func hidePhysicalPanel() {
        panel?.orderOut(nil)
    }

    fileprivate func handleTermination() {
        _ = lifecycle.handle(.terminate)
    }
}

@MainActor
private final class TerminationObserver: NSObject, @unchecked Sendable {
    weak var owner: FloatingPanelController?

    func start() {
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(applicationWillTerminate),
            name: NSApplication.willTerminateNotification,
            object: NSApplication.shared
        )
    }

    @objc private func applicationWillTerminate() {
        Task { @MainActor [weak owner] in
            owner?.handleTermination()
        }
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }
}

@MainActor
private final class DismissiblePanel: NSPanel {
    var onCancelOperation: (@MainActor @Sendable () -> Void)?

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }

    override func cancelOperation(_ sender: Any?) {
        onCancelOperation?()
    }
}
