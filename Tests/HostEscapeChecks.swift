@testable import SmoolChecksSupport
import SwiftUI

@MainActor @Observable
private final class EscapeEditorApplet: Applet {
    let id = AppletID(rawValue: "escape-editor")
    let title = "Editor"
    let icon = AppletIcon.symbol("pencil")
    let tint = Color.orange
    let contentHeight: CGFloat = 150
    var draft = "A draft that survives Escape"
    var hasPresentedOverlay = true

    func makeView(context: AppletContext, artwork: NSImage?) -> AnyView {
        AnyView(EscapeEditorView(applet: self))
    }
    func dismissOverlay() { hasPresentedOverlay = false }
}

private struct EscapeEditorView: View {
    @Bindable var applet: EscapeEditorApplet
    var body: some View { TextEditor(text: $applet.draft).padding(24) }
}

@main
struct HostEscapeChecks {
    @MainActor static func main() throws {
        let app = NSApplication.shared
        app.setActivationPolicy(.accessory)
        let suite = "smool.host-escape.\(UUID())"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let home = HomeApplet()
        let editor = EscapeEditorApplet()
        let directory = FileManager.default.temporaryDirectory.appending(path: "smool-host-escape-\(UUID())")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let actions = QuickActionsApplet(store: QuickActionStore(url: directory.appending(path: "actions.json")))
        let workspaces = WorkspacesApplet(store: WorkspaceStore(url: directory.appending(path: "workspaces.json")))
        let presentation = NotchPresentation(registry: AppletRegistry([home, editor, actions, workspaces]), settings: AppSettings(defaults: defaults))
        let controller = NotchPanelController(presentation: presentation)
        defer { controller.stop() }

        home.openCalendar()
        controller.open()
        controller.restoreFocus()
        let panel = app.windows.compactMap { $0 as? NotchPanel }.first!
        func key(_ code: UInt16, _ characters: String, modifiers: NSEvent.ModifierFlags = []) {
            let event = NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: modifiers,
                                        timestamp: 0, windowNumber: panel.windowNumber, context: nil,
                                        characters: characters, charactersIgnoringModifiers: characters,
                                        isARepeat: false, keyCode: code)!
            app.sendEvent(event)
        }
        func settle() {
            RunLoop.current.run(until: Date(timeIntervalSinceNow: 0.15))
            panel.contentView?.layoutSubtreeIfNeeded()
        }

        // Exercise the original failure before SwiftUI has attached Calendar's handlers.
        key(53, "\u{1b}")
        precondition(controller.isOpen && !home.showCalendar)
        home.openCalendar()
        settle()
        controller.restoreFocus()
        settle()
        key(44, "?", modifiers: .shift)
        precondition(presentation.help.text != nil, "The actual Calendar help shortcut must open help.")
        home.showsEventDetails = true
        key(53, "\u{1b}")
        precondition(presentation.help.text == nil && home.showsEventDetails && controller.isOpen)
        key(53, "\u{1b}")
        precondition(!home.showsEventDetails && home.showCalendar && controller.isOpen)
        key(53, "\u{1b}")
        precondition(!home.showCalendar && controller.isOpen)

        key(18, "1", modifiers: .command)
        key(19, "2", modifiers: .command)
        settle()
        precondition(presentation.selection == editor.id)
        func textView(in view: NSView) -> NSTextView? {
            if let text = view as? NSTextView, text.isEditable { return text }
            return view.subviews.lazy.compactMap { textView(in: $0) }.first
        }
        let text = textView(in: panel.contentView!)!
        panel.makeFirstResponder(text)
        let draft = editor.draft
        key(53, "\u{1b}")
        precondition(!(panel.firstResponder is NSTextView) && editor.draft == draft)
        precondition(editor.hasPresentedOverlay && controller.isOpen)
        key(53, "\u{1b}")
        precondition(!editor.hasPresentedOverlay && controller.isOpen)
        panel.makeFirstResponder(text)
        key(18, "1", modifiers: .command)
        precondition(presentation.selection == home.id && editor.draft == draft)

        key(13, "w", modifiers: [.command, .shift])
        precondition(presentation.hostTool == .workspaces)
        key(40, "k", modifiers: .command)
        precondition(presentation.showsActions)
        key(53, "\u{1b}")
        precondition(presentation.hostTool == .workspaces && controller.isOpen)
        key(53, "\u{1b}")
        precondition(presentation.hostTool == nil && controller.isOpen)

        presentation.showTool(.actions)
        actions.edit()
        let actionDraft = actions.editor
        presentation.failedSaveAppletID = actions.id
        presentation.terminationError = "Changes to Actions could not be saved."
        controller.showTerminationFailure()
        precondition(presentation.hostTool == .actions && actions.editor === actionDraft,
                     "Showing a save failure must not toggle away from the current action editor.")
        key(53, "\u{1b}")
        precondition(presentation.terminationError == nil && actions.editor === actionDraft)
        presentation.dismissPresentation()

        presentation.showTool(.workspaces)
        workspaces.edit()
        let workspaceDraft = workspaces.editor
        presentation.failedSaveAppletID = workspaces.id
        presentation.terminationError = "Changes to Workspaces could not be saved."
        controller.showTerminationFailure()
        precondition(presentation.hostTool == .workspaces && workspaces.editor === workspaceDraft,
                     "Showing a save failure must keep the current workspace editor.")
        key(53, "\u{1b}")
        precondition(presentation.terminationError == nil && workspaces.editor === workspaceDraft)
        presentation.dismissPresentation()
        key(53, "\u{1b}")
        precondition(!controller.isOpen)
        print("Passed: real panel Escape routing through help, calendar details, calendar, editor focus, applet overlay, host tools and close; drafts and Command-number preserved.")
    }
}
