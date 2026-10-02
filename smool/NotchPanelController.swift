import SwiftUI

@MainActor
final class NotchPanelController: NSObject {
    private(set) var demoNotchEnabled = false
    private let presentation = NotchPresentation()
    private var panel: NotchPanel?
    private var localMonitor: Any?
    private var outsideMonitor: Any?
    private var isOpen = false
    private var transition = 0

    override init() {
        super.init()
        NotificationCenter.default.addObserver(self, selector: #selector(screenConfigurationChanged), name: NSApplication.didChangeScreenParametersNotification, object: nil)
    }

    func toggle() {
        if isOpen {
            close()
        } else {
            open()
        }
    }

    func setDemoNotchEnabled(_ enabled: Bool) {
        demoNotchEnabled = enabled
        resetPresentation()
    }

    private var targetScreen: NSScreen? {
        NSScreen.screens.first(where: { $0.frame.contains(NSEvent.mouseLocation) }) ?? NSScreen.main
    }

    func open() {
        guard !isOpen, let screen = targetScreen else { return }

        isOpen = true
        transition += 1
        let currentTransition = transition
        presentation.layout = NotchLayout(screen: screen, demoNotch: demoNotchEnabled)

        let panel = panel ?? makePanel()
        self.panel = panel
        panel.setFrame(presentation.layout.windowFrame, display: true)
        panel.ignoresMouseEvents = false
        panel.makeKeyAndOrderFront(nil)
        panel.contentView?.layoutSubtreeIfNeeded()
        panel.displayIfNeeded()
        installEventMonitors()

        // Render the collapsed shape before starting its expansion.
        DispatchQueue.main.async { [weak self] in
            guard let self, self.transition == currentTransition else { return }
            withAnimation(self.animation) {
                self.presentation.isExpanded = true
            }
        }
    }

    func close() {
        isOpen = false
        transition += 1
        let currentTransition = transition
        removeEventMonitors()

        withAnimation(animation, completionCriteria: .removed) {
            presentation.isExpanded = false
        } completion: { [weak self] in
            guard let self, self.transition == currentTransition else { return }
            self.panel?.orderOut(nil)
            if self.presentation.layout.notch.isSimulated {
                self.panel?.ignoresMouseEvents = true
                self.panel?.orderFrontRegardless()
            }
        }
    }

    func stop() {
        isOpen = false
        transition += 1
        removeEventMonitors()
        panel?.orderOut(nil)
        NotificationCenter.default.removeObserver(self)
    }

    private var animation: Animation {
        NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
            ? .linear(duration: 0.01)
            : .spring(duration: 0.32, bounce: 0.18)
    }

    private func makePanel() -> NotchPanel {
        let panel = NotchPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = false
        panel.level = .statusBar
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        panel.hidesOnDeactivate = false
        panel.isMovable = false
        panel.isReleasedWhenClosed = false
        panel.animationBehavior = .none
        panel.title = "smool"

        let content = NSHostingView(rootView: NotchView(presentation: presentation) { [weak self] app in
            self?.openApp(app)
        })
        content.safeAreaRegions = []
        panel.contentView = content
        return panel
    }

    private func openApp(_ app: HomeApp) {
        let workspace = NSWorkspace.shared
        close()

        guard let url = workspace.urlForApplication(withBundleIdentifier: app.bundleIdentifier) else {
            workspace.open(app.webURL)
            return
        }

        workspace.openApplication(at: url, configuration: .init()) { _, error in
            if error != nil {
                DispatchQueue.main.async { NSWorkspace.shared.open(app.webURL) }
            }
        }
    }

    private func installEventMonitors() {
        removeEventMonitors()

        localMonitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .leftMouseDown, .rightMouseDown]) { [weak self] event in
            guard let self else { return event }
            if event.type == .keyDown, event.keyCode == 53 {
                self.close()
                return nil
            }
            if event.type != .keyDown, event.window !== self.panel {
                self.close()
            }
            return event
        }

        outsideMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
            self?.close()
        }
    }

    private func removeEventMonitors() {
        if let localMonitor { NSEvent.removeMonitor(localMonitor) }
        if let outsideMonitor { NSEvent.removeMonitor(outsideMonitor) }
        localMonitor = nil
        outsideMonitor = nil
    }

    @objc private func screenConfigurationChanged() {
        resetPresentation()
    }

    private func resetPresentation() {
        isOpen = false
        transition += 1
        presentation.isExpanded = false
        panel?.orderOut(nil)
        removeEventMonitors()

        guard demoNotchEnabled, let screen = targetScreen else { return }
        presentation.layout = NotchLayout(screen: screen, demoNotch: true)
        guard presentation.layout.notch.isSimulated else { return }

        let panel = panel ?? makePanel()
        self.panel = panel
        panel.setFrame(presentation.layout.windowFrame, display: true)
        panel.ignoresMouseEvents = true
        panel.orderFrontRegardless()
    }
}

private final class NotchPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    override func constrainFrameRect(_ frameRect: NSRect, to screen: NSScreen?) -> NSRect {
        frameRect
    }
}
