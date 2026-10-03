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
    private var resizeTransition = 0

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
        resizeTransition += 1
        let currentTransition = transition
        presentation.layout = NotchLayout(screen: screen, demoNotch: demoNotchEnabled)
        presentation.layout.contentHeight = presentation.contentHeight

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
        presentation.showsActions = false
        presentation.activeApplet.dismissOverlay()
        isOpen = false
        transition += 1
        resizeTransition += 1
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
        resizeTransition += 1
        removeEventMonitors()
        panel?.orderOut(nil)
        NotificationCenter.default.removeObserver(self)
    }

    private var animation: Animation {
        if NSWorkspace.shared.accessibilityDisplayShouldReduceMotion {
            return .linear(duration: 0.01)
        }
        return isOpen
            ? .spring(response: 0.54, dampingFraction: 0.76)
            : .spring(response: 0.66, dampingFraction: 0.76)
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

        let content = NSHostingView(rootView: NotchView(
            presentation: presentation,
            selectApplet: { [weak self] in self?.selectApplet($0) },
            close: { [weak self] in self?.close() },
            restoreFocus: { [weak self] in
                guard let self else { return }
                if !self.isOpen { self.open() }
                else { self.panel?.makeKeyAndOrderFront(nil) }
            },
            resizeContent: { [weak self] in
                guard let self, self.presentation.layout.contentHeight != self.presentation.contentHeight else { return }
                self.resizeContent()
            }
        ))
        content.safeAreaRegions = []
        panel.contentView = content
        return panel
    }

    private func selectApplet(_ id: AppletID) {
        guard presentation.selection != id, let applet = presentation.registry.applet(for: id) else { return }
        resizeContent(height: applet.contentHeight) { self.presentation.select(id) }
    }

    private func resizeContent(height: CGFloat? = nil, update: () -> Void = {}) {
        resizeTransition += 1
        let resize = resizeTransition
        var targetLayout = presentation.layout
        targetLayout.contentHeight = height ?? presentation.contentHeight
        let targetFrame = targetLayout.windowFrame

        // Grow the transparent host before animating, then trim it afterward.
        // Keeping both frames top-aligned prevents either direction from clipping.
        if let panel {
            panel.setFrame(panel.frame.union(targetFrame), display: true)
        }
        withAnimation(
            NSWorkspace.shared.accessibilityDisplayShouldReduceMotion ? nil : .spring(response: 0.46, dampingFraction: 0.76),
            completionCriteria: .removed
        ) {
            update()
            presentation.layout = targetLayout
        } completion: { [weak self] in
            guard let self, self.isOpen, self.resizeTransition == resize else { return }
            self.panel?.setFrame(targetFrame, display: true)
        }
    }

    private func installEventMonitors() {
        removeEventMonitors()

        localMonitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .leftMouseDown, .rightMouseDown]) { [weak self] event in
            guard let self else { return event }
            if event.type == .keyDown, event.window === self.panel,
               event.modifierFlags.intersection([.command, .control, .option, .shift]) == .command {
                if let number = Int(event.charactersIgnoringModifiers ?? ""), let applet = self.presentation.registry.applet(number: number) {
                    self.selectApplet(applet.id)
                    return nil
                }
                if (event.keyCode == 123 || event.keyCode == 124), !(self.panel?.firstResponder is NSTextView) {
                    let arrow: AppletArrow = event.keyCode == 123 ? .left : .right
                    if !self.presentation.activeApplet.handleArrow(arrow, command: true) {
                        self.selectApplet(self.presentation.registry.neighbor(of: self.presentation.selection, offset: arrow.offset))
                    }
                    return nil
                }
            }
            if event.type == .keyDown, event.window === self.panel, event.keyCode == 48 {
                let modifiers = event.modifierFlags.intersection([.command, .control, .option, .shift])
                if modifiers == .control || modifiers == [.control, .shift] {
                    self.selectApplet(self.presentation.registry.neighbor(of: self.presentation.selection, offset: modifiers.contains(.shift) ? -1 : 1))
                    return nil
                }
            }
            if event.type == .keyDown, event.window === self.panel,
               event.modifierFlags.intersection([.command, .control, .option, .shift]).isEmpty,
               !self.presentation.showsActions, !self.presentation.activeApplet.hasPresentedOverlay,
               self.navigateApplet(keyCode: event.keyCode) {
                return nil
            }
            if event.type != .keyDown, event.window !== self.panel, !self.presentation.showsActions, !self.presentation.activeApplet.hasPresentedOverlay {
                self.close()
            }
            return event
        }

        outsideMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
            self?.close()
        }
    }

    // Route deck arrows before SwiftUI transfers focus during a page transition.
    // Editing scopes keep their native arrow keys.
    private func navigateApplet(keyCode: UInt16) -> Bool {
        guard let arrow = AppletArrow(rawValue: keyCode) else { return false }
        return withAnimation(NSWorkspace.shared.accessibilityDisplayShouldReduceMotion ? nil : .smooth(duration: 0.24)) {
            presentation.activeApplet.handleArrow(arrow, command: false)
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
        resizeTransition += 1
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
