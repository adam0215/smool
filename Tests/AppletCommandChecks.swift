@testable import SmoolChecksSupport
import SwiftUI

@main
struct AppletCommandChecks {
    @MainActor static func main() {
        let save = AppletShortcut(key: .return)
        precondition(save.label == "⌘↵" && save.paletteShortcut?.key == .return)
        precondition(save.paletteShortcut?.modifiers == .command)
        let enter = AppletShortcut(key: .return, modifiers: [])
        precondition(enter.label == "↵" && enter.paletteShortcut == nil)
        precondition(enter.keyboardShortcut.key == .return && enter.keyboardShortcut.modifiers.isEmpty)
        for key in [KeyEquivalent.leftArrow, .rightArrow] {
            precondition(AppletShortcut(key: key).paletteShortcut == nil)
        }
        let modified = AppletShortcut(key: "n", modifiers: [.control, .option, .shift, .command])
        precondition(modified.label == "⌃⌥⇧⌘N")
        precondition(modified.paletteShortcut?.modifiers == [.control, .option, .shift, .command])
        precondition(AppletShortcut(key: .space, modifiers: []).label == "Space")
        precondition(AppletShortcut(key: .delete).label == "⌘⌫")

        let applet = CodexApplet()
        let state = applet.state
        let originalGrouping = state.groupsByProject
        defer { state.groupsByProject = originalGrouping }
        func perform(_ id: String) {
            guard let action = applet.actions.first(where: { $0.id == id }) else {
                preconditionFailure("Missing command: \(id)")
            }
            action.perform()
        }
        state.page = .usage
        perform("search-threads")
        precondition(state.page == .history && state.presentation == .search)
        let searchFocusRequest = state.searchFocusRequest
        perform("search-threads")
        precondition(state.presentation == .search && state.searchFocusRequest == searchFocusRequest + 1,
                     "Search must request focus even when the search presentation is already open")
        precondition(applet.actions.first { $0.id == "search-threads" }?.shortcut?.keyboardShortcut.key == "f")
        perform("new-thread")
        state.newThread.text = "Keep this initial prompt"
        perform("write-new-thread")
        precondition(state.presentation == .newThread)
        perform("choose-project")
        precondition(state.presentation == .projects && state.page == .newThread)
        precondition(!applet.actions.contains { $0.id == "write-new-thread" || $0.id == "search-threads" })
        applet.dismissOverlay()
        precondition(state.presentation == .deck && state.newThread.text == "Keep this initial prompt")

        applet.beginComposing("Saved handoff")
        precondition(state.presentation == .recipientPicker && applet.hasPresentedOverlay)
        applet.dismissOverlay()
        precondition(state.presentation == .deck && state.pendingText == "Saved handoff")
        perform("choose-recipient-for-saved-draft")
        precondition(state.presentation == .recipientPicker)
        state.openProjects()
        precondition(state.presentation == .projects && state.pendingText == "Saved handoff")
        applet.dismissOverlay()
        state.groupsByProject = false
        perform("group-by-project")
        precondition(state.groupsByProject && state.page == .history && state.presentation == .deck)
        precondition(applet.actions.first { $0.id == "group-by-project" }?.selected == true)
        precondition(applet.actions.first { $0.id == "next-project" }?.shortcut?.paletteShortcut == nil)
        perform("group-by-project")
        precondition(applet.actions.first { $0.id == "group-by-project" }?.selected == false)

        let thread = CodexThread(json: .object(["id": .string("draft"), "title": .string("Draft recipient")]))!
        applet.service.drafts[thread.id] = "Retained draft"
        applet.compose(thread)
        precondition(state.presentation == .composer(thread))
        precondition(applet.actions.contains { $0.id == "connect-thread" && $0.shortcut?.key == "r" })
        precondition(!applet.actions.contains { $0.id == "refresh" })
        perform("search-threads")
        precondition(state.presentation == .search && applet.service.drafts[thread.id] == "Retained draft")
        applet.deactivate()
        precondition(state.presentation == .deck && state.pendingText == "Saved handoff")

        let home = HomeApplet()
        let calendarAction = home.actions[0]
        calendarAction.perform()
        precondition(home.actions[0].id == calendarAction.id && home.actions[0].title != calendarAction.title)
        checkPaletteKeyboard(applet)
        checkPanelFocus()
        print("Passed: typed shortcuts, reserved navigation keys, stable IDs, selected commands, Codex presentation transitions and retained drafts.")
    }

    @MainActor private static func checkPaletteKeyboard(_ codex: CodexApplet) {
        _ = NSApplication.shared
        NSApp.setActivationPolicy(.accessory)
        NSApp.finishLaunching()
        NSApp.activate()
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let quick = QuickActionsApplet(store: QuickActionStore(url: directory.appendingPathComponent("actions.json")))
        quick.commandContext = AppletCommandContext(hostActions: { codex.actions })
        let layout = NotchLayout(screenFrame: CGRect(x: 0, y: 0, width: 1440, height: 900))
        let window = NotchPanel(contentRect: CGRect(x: 100, y: 100, width: 560, height: 220),
                                styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.allowsKeyboardFocus = true
        window.contentView = NSHostingView(rootView: quick.makeView(context: AppletContext(layout: layout), artwork: nil)
            .frame(width: 560, height: 220))
        window.makeKeyAndOrderFront(nil)
        defer { window.close() }
        RunLoop.main.run(until: Date().addingTimeInterval(0.3))

        func press(_ code: UInt16, modifiers: NSEvent.ModifierFlags = .command) {
            sendKey(code, modifiers: modifiers, to: window)
            RunLoop.main.run(until: Date().addingTimeInterval(0.3))
        }

        press(3)
        precondition(codex.state.presentation == .search, "The palette binds the shared typed Search command")
        press(35)
        precondition(codex.state.presentation == .projects)
        codex.dismissOverlay()
        codex.state.groupsByProject = false
        RunLoop.main.run(until: Date().addingTimeInterval(0.3))
        press(35, modifiers: [.command, .shift])
        precondition(codex.state.groupsByProject && codex.state.presentation == .deck)
        quick.highlightedID = "context:usage"
        press(36, modifiers: [])
        precondition(codex.state.page == .usage, "Return runs the highlighted action instead of an action's Return shortcut")
        codex.state.page = .newThread
        RunLoop.main.run(until: Date().addingTimeInterval(0.3))
        press(45)
        precondition(codex.state.presentation == .newThread && quick.editor == nil,
                     "Command-N invokes the current applet command without opening a saved-action editor")
    }


    @MainActor private static func checkPanelFocus() {
        let suite = "smool.command-focus.\(UUID())"
        let defaults = UserDefaults(suiteName: suite)!
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer {
            defaults.removePersistentDomain(forName: suite)
            try? FileManager.default.removeItem(at: directory)
        }
        let service = CodexService(
            catalog: CodexClient(desktop: false, endpoint: .appServer(directory.appendingPathComponent("missing-app-server").path)),
            desktop: CodexClient(desktop: true, endpoint: .desktop(directory.appendingPathComponent("missing-socket").path))
        )
        let codex = CodexApplet(service: service)
        let actions = QuickActionsApplet(store: QuickActionStore(url: directory.appendingPathComponent("actions.json")))
        let host = NotchPresentation(registry: AppletRegistry([codex, actions]), settings: AppSettings(defaults: defaults))
        let controller = NotchPanelController(presentation: host)
        controller.open()
        defer { controller.stop() }
        let panel = NSApp.windows.compactMap { $0 as? NotchPanel }.first { $0.isVisible }!

        func settle() {
            RunLoop.main.run(until: Date().addingTimeInterval(0.3))
            panel.contentView?.layoutSubtreeIfNeeded()
        }
        func press(_ code: UInt16, modifiers: NSEvent.ModifierFlags = []) {
            sendKey(code, modifiers: modifiers, to: panel)
            settle()
        }

        settle()
        let thread = CodexThread(json: .object(["id": .string("10000000-0000-0000-0000-000000000099"), "title": .string("Focus fixture")]))!
        codex.state.page = .history
        codex.service.drafts[thread.id] = "Keep the composer draft"
        codex.compose(thread)
        settle()
        press(40, modifiers: .command)
        precondition(host.showsActions && codex.state.presentation == .composer(thread))
        precondition(actions.entries.contains { $0.id.hasSuffix("connect-thread") },
                     "Opening Actions releases text focus without replacing Connect with Refresh")
        precondition(codex.service.drafts[thread.id] == "Keep the composer draft")
        press(53)
        precondition(!host.showsActions && codex.state.presentation == .composer(thread))

        codex.dismissOverlay()
        settle()
        press(3, modifiers: .command)
        precondition(codex.state.presentation == .search && panel.firstResponder is NSTextView)
        press(53)
        precondition(codex.state.presentation == .search && !(panel.firstResponder is NSTextView))
        press(3, modifiers: .command)
        precondition(codex.state.presentation == .search && panel.firstResponder is NSTextView,
                     "Command-F refocuses the existing search field after Escape")
        press(40, modifiers: .command)
        precondition(host.showsActions)
        actions.entries.first { $0.id.hasSuffix("search-threads") }!.perform()
        settle()
        precondition(!host.showsActions && codex.state.presentation == .search && panel.firstResponder is NSTextView,
                     "Search selected from Actions focuses the existing field")
    }


    @MainActor private static func sendKey(_ code: CGKeyCode, modifiers: NSEvent.ModifierFlags, to window: NSWindow) {
        precondition(NSApp.keyWindow === window, "Keyboard input must target the fixture window")
        // NSEvent.keyEvent omits native keyboard metadata and can match a shifted
        // SwiftUI shortcut for an unshifted key. Preserve CGEvent's layout data.
        for isDown in [true, false] {
            let keyboardEvent = CGEvent(keyboardEventSource: nil, virtualKey: code, keyDown: isDown)!
            keyboardEvent.flags = CGEventFlags(rawValue: UInt64(modifiers.rawValue))
            let event = NSEvent(cgEvent: keyboardEvent)!
            NSApp.postEvent(event, atStart: true)
            let queued = NSApp.nextEvent(matching: [.keyDown, .keyUp], until: .distantPast, inMode: .default, dequeue: true)!
            precondition(queued.type == event.type && queued.keyCode == code && queued.modifierFlags == modifiers)
            NSApp.sendEvent(queued)
        }
    }

}
