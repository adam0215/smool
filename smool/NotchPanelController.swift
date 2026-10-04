import SwiftUI

@MainActor
final class NotchPanelController: NSObject {
    private(set) var demoNotchEnabled = false
    let presentation: NotchPresentation
    private var panel: NotchPanel?
    private weak var hostingView: NSHostingView<NotchView>?
    private var localMonitor: Any?
    private var outsideMonitor: Any?
    private(set) var isOpen = false
    private var isClosing = false
    private var transition = 0
    private var resizeTransition = 0
    private var isStopped = false
    private let fileDrop = NotchFileDropController()
    private var captureTask: Task<Void, Never>?

    init(presentation: NotchPresentation = NotchPresentation()) {
        self.presentation = presentation
        super.init()
        NotificationCenter.default.addObserver(self, selector: #selector(screenConfigurationChanged), name: NSApplication.didChangeScreenParametersNotification, object: nil)
    }

    func start() {
        presentation.composeInCodex = { [weak self] text in
            guard let self, let id = self.presentation.prepareCodexDraft(text) else { return }
            self.selectApplet(id)
            self.open()
        }
        fileDrop.isEnabled = { [weak self] in
            self?.presentation.registry.applet(for: AppletID(rawValue: "files")) != nil
        }
        fileDrop.acceptFiles = { [weak self] urls in self?.acceptDroppedFiles(urls) ?? false }
        fileDrop.start(demoNotch: demoNotchEnabled)
        presentation.updateBackgroundServices()
        observeStatus()
    }

    func captureSelection() {
        captureTask?.cancel()
        captureTask = Task { [weak self] in
            let preview: SelectionPreview
            do { preview = .text(try await SelectedTextCapture.capture()) }
            catch let error as SelectionCaptureError { preview = .failure(error) }
            catch { preview = .failure(.unsupported) }
            guard let self, !Task.isCancelled else { return }
            self.presentation.presentCapturedSelection(preview)
            self.open()
            self.resizeContent()
        }
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

    func settingsDidChange() {
        presentation.reconcileSettings()
        presentation.updateBackgroundServices()
        let demo = presentation.settings.demoNotchEnabled
        if demo != demoNotchEnabled {
            demoNotchEnabled = demo
            if isOpen, let screen = panel?.screen ?? targetScreen {
                fileDrop.start(demoNotch: demo)
                presentation.layout = NotchLayout(screen: screen, demoNotch: demo)
                resizeContent()
            } else {
                resetPresentation()
            }
        }
        else if isOpen { resizeContent() }
        else { updateCollapsedPanel() }
    }

    private var targetScreen: NSScreen? {
        NSScreen.screens.first(where: { $0.frame.contains(NSEvent.mouseLocation) }) ?? NSScreen.main
    }

    func open() {
        guard !isOpen, let screen = targetScreen else { return }

        isOpen = true
        isClosing = false
        transition += 1
        resizeTransition += 1
        let currentTransition = transition
        presentation.layout = NotchLayout(screen: screen, demoNotch: demoNotchEnabled)
        presentation.layout.contentHeight = presentation.contentHeight

        let panel = panel ?? makePanel()
        self.panel = panel
        presentation.usesExpandedFrame = true
        panel.allowsKeyboardFocus = true
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
        captureTask?.cancel()
        guard isOpen else { return }
        isOpen = false
        panel?.allowsKeyboardFocus = false
        panel?.makeFirstResponder(nil)
        panel?.resignKey()
        presentation.capturedSelection = nil
        presentation.dismissTool()
        presentation.showsSettings = false
        presentation.activeApplet.dismissOverlay()
        isClosing = true
        transition += 1
        resizeTransition += 1
        let currentTransition = transition
        removeEventMonitors()

        withAnimation(animation, completionCriteria: .removed) {
            presentation.isExpanded = false
        } completion: { [weak self] in
            guard let self, self.transition == currentTransition else { return }
            self.isClosing = false
            self.updateCollapsedPanel()
        }
    }

    func stop() {
        isStopped = true
        fileDrop.stop()
        captureTask?.cancel()
        isOpen = false
        presentation.isExpanded = false
        presentation.stopBackgroundServices()
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
            close: { [weak self] in self?.goBackOrClose() },
            restoreFocus: { [weak self] in self?.restoreFocus() },
            resizeContent: { [weak self] in
                guard let self, self.isOpen, self.presentation.layout.contentHeight != self.presentation.contentHeight else { return }
                self.resizeContent()
            },
            activateStatus: { [weak self] id in
                guard let self else { return }
                self.presentation.registry.applet(for: id)?.activateStatus()
                self.selectApplet(id)
                self.open()
            },
            acceptFiles: { [weak self] urls in
                self?.acceptDroppedFiles(urls) ?? false
            },
            open: { [weak self] in self?.open() }
        ))
        // Keep SwiftUI out of NSWindow's content-size negotiation. Even with
        // sizing disabled, a root hosting view updates its graph during that pass.
        content.sizingOptions = []
        content.safeAreaRegions = []
        content.autoresizingMask = [.width, .height]
        let container = NSView(frame: panel.contentLayoutRect)
        content.frame = container.bounds
        container.addSubview(content)
        panel.contentView = container
        hostingView = content
        return panel
    }

    func acceptDroppedFiles(_ urls: [URL]) -> Bool {
        guard !urls.isEmpty, let id = presentation.addFiles(urls) else { return false }
        // Preserve an open editor and its first responder. A closed notch stays closed.
        if !isOpen { presentation.select(id) }
        return true
    }

    func selectApplet(_ id: AppletID) {
        guard presentation.selection != id || presentation.showsSettings || presentation.hostTool != nil || presentation.capturedSelection != nil,
              let applet = presentation.registry.applet(for: id) else { return }
        restoreFocus()
        if !isOpen {
            presentation.select(id)
            presentation.layout.contentHeight = presentation.contentHeight
            return
        }
        resizeContent(height: applet.contentHeight) { self.presentation.select(id) }
    }

    func showSettings() {
        presentation.activeApplet.dismissOverlay()
        presentation.dismissTool()
        presentation.capturedSelection = nil
        presentation.showsSettings = true
        if isOpen { resizeContent() }
        else { open() }
        restoreFocus()
    }

    func goBackOrClose() {
        if panel?.firstResponder is NSTextView {
            restoreFocus()
        } else if presentation.capturedSelection != nil {
            presentation.capturedSelection = nil
            restoreFocus()
        } else if presentation.showsSettings {
            presentation.showsSettings = false
            resizeContent()
            restoreFocus()
        } else if presentation.displayedApplet.hasPresentedOverlay {
            presentation.displayedApplet.dismissOverlay()
            restoreFocus()
        } else if presentation.hostTool != nil {
            presentation.dismissTool(returnToSource: true)
            resizeContent()
            restoreFocus()
        } else {
            close()
        }
    }

    func restoreFocus() {
        guard isOpen else { return }
        panel?.makeFirstResponder(hostingView)
        panel?.makeKeyAndOrderFront(nil)
        presentation.focusGeneration &+= 1
    }

    func showTerminationFailure() {
        presentation.terminationError = "Your notes could not be saved. Your text is still in smool. Try saving again before quitting."
        let notesID = AppletID(rawValue: "notes")
        presentation.settings.setEnabled(true, for: notesID)
        selectApplet(notesID)
        open()
        resizeContent()
        restoreFocus()
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
            guard let self, self.isOpen else { return event }
            if event.type == .keyDown, event.window === self.panel, event.keyCode == 53 {
                self.goBackOrClose()
                return nil
            }
            if event.type == .keyDown, event.window === self.panel {
                let modifiers = event.modifierFlags.intersection([.command, .control, .option, .shift])
                if (modifiers == .command && event.charactersIgnoringModifiers?.lowercased() == "k") ||
                    (modifiers == [.command, .shift] && event.charactersIgnoringModifiers?.lowercased() == "w") {
                    self.restoreFocus()
                    self.presentation.showTool(modifiers.contains(.shift) ? .workspaces : .actions)
                    self.resizeContent()
                    return nil
                }
            }
            if event.type == .keyDown, event.window === self.panel,
               self.presentation.showsSettings,
               self.presentation.handleSettingsKey(event.keyCode, modifiers: event.modifierFlags,
                                                   characters: event.charactersIgnoringModifiers) {
                return nil
            }
            if event.type == .keyDown, event.window === self.panel,
               event.modifierFlags.intersection([.command, .control, .option, .shift]) == .command {
                if event.charactersIgnoringModifiers == "," {
                    self.presentation.openSettings()
                    return nil
                }
                if let number = Int(event.charactersIgnoringModifiers ?? ""), let applet = self.presentation.registry.applet(number: number) {
                    self.selectApplet(applet.id)
                    return nil
                }
                if (event.keyCode == 123 || event.keyCode == 124), !(self.panel?.firstResponder is NSTextView) {
                    let arrow: AppletArrow = event.keyCode == 123 ? .left : .right
                    if self.presentation.capturedSelection != nil || !self.presentation.displayedApplet.handleArrow(arrow, command: true) {
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
            if event.type == .keyDown, event.window === self.panel, self.presentation.capturedSelection != nil {
                return event
            }
            if event.type == .keyDown, event.window === self.panel,
               event.modifierFlags.intersection([.command, .control, .option, .shift]).isEmpty,
               !self.presentation.showsSettings, self.presentation.capturedSelection == nil,
               self.panel?.firstResponder is NSTextView,
               let arrow = AppletArrow(rawValue: event.keyCode),
               self.presentation.displayedApplet.handleEditingArrow(arrow) {
                return nil
            }
            if event.type == .keyDown, event.window === self.panel,
               event.modifierFlags.intersection([.command, .control, .option, .shift]).isEmpty,
               !self.presentation.displayedApplet.hasPresentedOverlay,
               !(self.panel?.firstResponder is NSTextView),
               self.navigateApplet(keyCode: event.keyCode) {
                return nil
            }
            if event.type != .keyDown, event.window !== self.panel, !self.presentation.displayedApplet.hasPresentedOverlay {
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
        guard !presentation.showsSettings, let arrow = AppletArrow(rawValue: keyCode) else { return false }
        return withAnimation(NSWorkspace.shared.accessibilityDisplayShouldReduceMotion ? nil : .smooth(duration: 0.24)) {
            presentation.displayedApplet.handleArrow(arrow, command: false)
        }
    }

    private func removeEventMonitors() {
        if let localMonitor { NSEvent.removeMonitor(localMonitor) }
        if let outsideMonitor { NSEvent.removeMonitor(outsideMonitor) }
        localMonitor = nil
        outsideMonitor = nil
    }

    @objc private func screenConfigurationChanged() {
        guard !isStopped else { return }
        guard isOpen else { resetPresentation(); return }
        fileDrop.start(demoNotch: demoNotchEnabled)
        guard let screen = panel?.screen ?? targetScreen else { return }
        presentation.layout = NotchLayout(screen: screen, demoNotch: demoNotchEnabled)
        resizeContent()
    }

    private func resetPresentation() {
        if !isStopped { fileDrop.start(demoNotch: demoNotchEnabled) }
        isOpen = false
        isClosing = false
        transition += 1
        resizeTransition += 1
        presentation.isExpanded = false
        panel?.allowsKeyboardFocus = false
        panel?.orderOut(nil)
        removeEventMonitors()

        guard let screen = targetScreen else { return }
        presentation.layout = NotchLayout(screen: screen, demoNotch: demoNotchEnabled)
        updateCollapsedPanel()
    }

    private func observeStatus() {
        guard !isStopped else { return }
        withObservationTracking {
            _ = presentation.statusItems
        } onChange: { [weak self] in
            Task { @MainActor [weak self] in
                guard let self, !self.isStopped else { return }
                self.updateCollapsedPanel()
                self.observeStatus()
            }
        }
    }

    private func updateCollapsedPanel() {
        guard !isOpen, !isClosing, !isStopped else { return }
        let size = presentation.collapsedSize
        guard size.height > 0 else { panel?.orderOut(nil); return }
        let panel = panel ?? makePanel()
        self.panel = panel
        presentation.usesExpandedFrame = false
        panel.allowsKeyboardFocus = false
        panel.setFrame(presentation.layout.collapsedFrame(statusCount: presentation.statusItems.count), display: true)
        // The narrow collapsed frame accepts status clicks and files without stealing keyboard focus.
        panel.ignoresMouseEvents = false
        panel.orderFrontRegardless()
    }
}

final class NotchPanel: NSPanel {
    var allowsKeyboardFocus = false
    override var canBecomeKey: Bool { allowsKeyboardFocus }
    override var canBecomeMain: Bool { false }

    override func constrainFrameRect(_ frameRect: NSRect, to screen: NSScreen?) -> NSRect {
        frameRect
    }
}
