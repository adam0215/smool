import SwiftUI

@MainActor @Observable
private final class SizingApplet: Applet {
    let id = AppletID(rawValue: "sizing")
    let title = "Codex layout check"
    let icon = AppletIcon.symbol("terminal")
    let tint = Color.purple
    var revision = 0
    var contentHeight: CGFloat { revision.isMultiple(of: 3) ? 340 : 256 }

    func makeView(context: AppletContext, artwork: NSImage?) -> AnyView {
        let activity = CodexActivityPresentation(state: .object([
            "turns": .array([.object([
                "turnId": .string("fixture"), "status": .string("inProgress"),
                "items": .array([
                    .object(["id": .string("message"), "type": .string("agentMessage"),
                             "text": .string(String(repeating: "A changing message with **Markdown**. ", count: revision % 8 + 1))]),
                    .object(["id": .string("tool"), "type": .string("commandExecution"),
                             "command": .string("Check layout"),
                             "status": .string(revision.isMultiple(of: 2) ? "inProgress" : "completed")])
                ])
            ])])
        ]), revision: revision)
        return AnyView(CodexActivityView(presentation: activity, isLive: true)
            .padding(24)
            .overlay(alignment: .bottom) {
                if revision.isMultiple(of: 4) {
                    FloatingComposer(text: .constant(""), recipient: "Codex", isEditing: false,
                                     onSend: {}, onClose: {})
                        .padding(24)
                }
            })
    }
}

@main
struct NotchSizingChecks {
    @MainActor static func main() {
        let app = NSApplication.shared
        app.setActivationPolicy(.accessory)
        let suite = "smool.notch-sizing.\(UUID())"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let applet = SizingApplet()
        let presentation = NotchPresentation(registry: AppletRegistry([applet]), settings: AppSettings(defaults: defaults))
        let controller = NotchPanelController(presentation: presentation)
        defer { controller.stop() }
        controller.open()
        let panel = app.windows.compactMap { $0 as? NotchPanel }.first!
        let host = panel.contentView!.subviews.first as! NSHostingView<NotchView>
        if CommandLine.arguments.contains("--automatic-sizing") {
            host.removeFromSuperview()
            host.sizingOptions = .standardBounds
            panel.contentView = host
        }
        // Let the initial attachment and opening animation establish the window.
        RunLoop.current.run(until: Date(timeIntervalSinceNow: 1))
        let originalMinimum = panel.contentMinSize
        let originalMaximum = panel.contentMaxSize

        for index in 0..<120 {
            applet.revision = index
            if index.isMultiple(of: 20) { controller.close() }
            if index % 20 == 2 { controller.open() }
            RunLoop.current.run(until: Date(timeIntervalSinceNow: 0.025))
            panel.contentView?.layoutSubtreeIfNeeded()
            panel.displayIfNeeded()
        }
        controller.open()
        RunLoop.current.run(until: Date(timeIntervalSinceNow: 1))
        precondition(panel.contentMinSize == originalMinimum && panel.contentMaxSize == originalMaximum,
                     "Content changed window limits from \(originalMinimum)/\(originalMaximum) to \(panel.contentMinSize)/\(panel.contentMaxSize)")
        precondition(panel.frame == presentation.layout.windowFrame,
                     "The window must settle at the notch controller's requested frame")
        precondition(panel.contentView?.bounds.size == panel.frame.size)
        precondition(host.frame.size == panel.contentView?.bounds.size,
                     "The hosted content must fill the manually sized window")
        controller.restoreFocus()
        precondition(panel.firstResponder === host, "Leaving an editor must restore the SwiftUI keyboard responder")
        print("Passed: 120 live Codex layout updates, height changes and close/reopen transitions without window sizing feedback")
    }
}
