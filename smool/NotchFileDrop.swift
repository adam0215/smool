import SwiftUI

/// A native destination kept separate from the key panel, so dragging never replaces an editor.
@MainActor
final class NotchFileDropController {
    private var panels: [NotchFileDropPanel] = []
    private var localMonitor: Any?
    private var globalMonitor: Any?
    var acceptFiles: ([URL]) -> Bool = { _ in false }
    var isEnabled: () -> Bool = { true }

    func start(demoNotch: Bool) {
        stop()
        panels = NSScreen.screens.map { screen in
            let layout = NotchLayout(screen: screen, demoNotch: demoNotch)
            let panel = NotchFileDropPanel(layout: layout)
            panel.destination.acceptFiles = { [weak self] urls in self?.acceptFiles(urls) ?? false }
            panel.destination.sessionEnded = { [weak self] in self?.disarm() }
            return panel
        }
        let events: NSEvent.EventTypeMask = [.leftMouseDragged, .leftMouseUp, .leftMouseDown, .rightMouseDown]
        localMonitor = NSEvent.addLocalMonitorForEvents(matching: events) { [weak self] event in
            self?.handle(event)
            return event
        }
        globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: events) { [weak self] event in
            self?.handle(event)
        }
    }

    func stop() {
        if let localMonitor { NSEvent.removeMonitor(localMonitor) }
        if let globalMonitor { NSEvent.removeMonitor(globalMonitor) }
        localMonitor = nil
        globalMonitor = nil
        disarm()
        panels.removeAll()
    }

    private func handle(_ event: NSEvent) {
        guard event.type == .leftMouseDown || event.type == .leftMouseDragged else {
            // A destination owns mouse-up until AppKit has delivered the drop and ended callbacks.
            if event.type != .leftMouseUp || !panels.contains(where: { $0.destination.isPreviewVisible }) {
                disarm()
            }
            return
        }
        // Arm before the source begins its drag session. Only native file-drag callbacks reveal it.
        guard isEnabled() else { return }
        for panel in panels where !panel.isVisible { panel.orderFrontRegardless() }
    }

    private func disarm() {
        for panel in panels {
            panel.destination.reset()
            panel.orderOut(nil)
        }
    }
}

@MainActor
final class NotchFileDropPanel: NSPanel {
    let destination: NotchFileDropView

    init(layout: NotchLayout) {
        destination = NotchFileDropView(layout: layout)
        super.init(contentRect: layout.fileDropFrame, styleMask: [.borderless, .nonactivatingPanel],
                   backing: .buffered, defer: false)
        // A tiny alpha makes the native drag region hittable. It is ordered out at rest.
        backgroundColor = .black.withAlphaComponent(0.01)
        isOpaque = false
        hasShadow = false
        level = NSWindow.Level(rawValue: NSWindow.Level.statusBar.rawValue + 1)
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        hidesOnDeactivate = false
        isReleasedWhenClosed = false
        animationBehavior = .none
        contentView = destination
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
    override func constrainFrameRect(_ frameRect: NSRect, to screen: NSScreen?) -> NSRect { frameRect }
}

@MainActor
final class NotchFileDropView: NSView {
    var acceptFiles: ([URL]) -> Bool = { _ in false }
    var sessionEnded: () -> Void = {}
    private(set) var isPreviewVisible = false
    private let preview: NSHostingView<NotchFileDropPreview>

    init(layout: NotchLayout) {
        preview = NSHostingView(rootView: NotchFileDropPreview(layout: layout))
        super.init(frame: CGRect(origin: .zero, size: layout.fileDropFrame.size))
        registerForDraggedTypes([.fileURL])
        preview.safeAreaRegions = []
        preview.frame = bounds
        preview.autoresizingMask = [.width, .height]
        preview.isHidden = true
        addSubview(preview)
    }

    required init?(coder: NSCoder) { nil }
    override func hitTest(_ point: NSPoint) -> NSView? { bounds.contains(point) ? self : nil }
    override func wantsPeriodicDraggingUpdates() -> Bool { false }

    static func fileURLs(from sender: NSDraggingInfo) -> [URL] {
        guard sender.draggingSourceOperationMask.contains(.copy) else { return [] }
        return (sender.draggingPasteboard.readObjects(forClasses: [NSURL.self],
            options: [.urlReadingFileURLsOnly: true]) as? [URL] ?? []).filter(\.isFileURL)
    }

    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation { update(sender) }
    override func draggingUpdated(_ sender: NSDraggingInfo) -> NSDragOperation { update(sender) }

    private func update(_ sender: NSDraggingInfo) -> NSDragOperation {
        let accepts = !Self.fileURLs(from: sender).isEmpty
        isPreviewVisible = accepts
        preview.isHidden = !accepts
        return accepts ? .copy : []
    }

    override func draggingExited(_ sender: NSDraggingInfo?) { reset() }
    override func draggingEnded(_ sender: NSDraggingInfo) { reset(); sessionEnded() }
    override func prepareForDragOperation(_ sender: NSDraggingInfo) -> Bool { !Self.fileURLs(from: sender).isEmpty }

    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        let urls = Self.fileURLs(from: sender)
        guard !urls.isEmpty else { reset(); return false }
        let accepted = acceptFiles(urls)
        reset()
        return accepted
    }

    override func concludeDragOperation(_ sender: NSDraggingInfo?) { reset(); sessionEnded() }

    func reset() {
        isPreviewVisible = false
        preview.isHidden = true
    }
}

/// Static feedback keeps a drag preview quiet, including when Reduce Motion is enabled.
struct NotchFileDropPreview: View {
    let layout: NotchLayout

    var body: some View {
        VStack(spacing: 8) {
            Color.clear.frame(height: layout.headerSize.height)
            Label("Drop to add to shelf", systemImage: "tray.and.arrow.down")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(.white)
            Text("Files stay in their original locations")
                .font(.system(size: 10))
                .foregroundStyle(.white.opacity(0.55))
        }
        .padding(.bottom, 16)
        .frame(width: layout.fileDropSize.width, height: layout.fileDropSize.height)
        .background(.black, in: UnevenRoundedRectangle(bottomLeadingRadius: 24, bottomTrailingRadius: 24))
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .allowsHitTesting(false)
        .accessibilityLabel("Drop files to add to shelf")
    }
}
