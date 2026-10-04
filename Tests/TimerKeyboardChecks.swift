@testable import SmoolChecksSupport
import SwiftUI

@main
struct TimerKeyboardChecks {
    @MainActor static func main() {
        _ = NSApplication.shared
        let store = TimerStore(storageURL: nil, automaticallySchedules: false, completion: {})
        let applet = TimersApplet(store: store)
        var restoredFocus = 0
        let window = NSWindow(contentRect: CGRect(x: 0, y: 0, width: 560, height: 212),
                              styleMask: [.titled], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        defer { window.close() }

        func showTimer() {
            window.contentView = NSHostingView(rootView: TimersAppletView(applet: applet) { restoredFocus += 1 })
            window.makeKeyAndOrderFront(nil)
            settle()
        }

        func press(_ code: UInt16, _ characters: String, modifiers: NSEvent.ModifierFlags = []) {
            let event = NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: modifiers,
                                        timestamp: 0, windowNumber: window.windowNumber, context: nil,
                                        characters: characters, charactersIgnoringModifiers: characters,
                                        isARepeat: false, keyCode: code)!
            if modifiers.intersection([.command, .option]).isEmpty || !window.performKeyEquivalent(with: event) {
                window.sendEvent(event)
            }
            settle()
        }

        func isEditing() -> Bool { window.firstResponder is NSTextView }

        showTimer()
        precondition(!isEditing(), "Entering Timers must leave applet navigation available")
        press(48, "\t")
        precondition(isEditing(), "Tab must enter the duration field")
        press(23, "5")
        precondition(applet.durationInput == "5")
        press(53, "\u{1b}")
        precondition(!isEditing() && restoredFocus == 1, "Escape must leave duration editing")
        precondition(applet.durationInput == "5", "Escape must preserve the draft")

        showTimer()
        precondition(!isEditing() && applet.durationInput == "5", "Returning to Timers preserves an unfocused draft")
        press(48, "\t")
        precondition(isEditing())
        press(36, "\r")
        precondition(store.timers.count == 1 && !applet.showsForm, "Return starts the edited duration")
        precondition(!isEditing(), "Starting must restore navigation focus")

        applet.actions.first { $0.id == "new-timer" }!.perform()
        settle()
        precondition(applet.showsForm && !isEditing(), "Opening New timer must not focus its input")
        press(48, "\t")
        precondition(isEditing())
        press(20, "3")
        press(53, "\u{1b}")
        precondition(!isEditing() && !applet.showsForm && applet.durationInput == "3")

        applet.actions.first { $0.id == "new-timer" }!.perform()
        settle()
        precondition(!isEditing())
        press(36, "\r")
        precondition(store.timers.count == 2, "Return can start the retained duration from navigation")
        press(45, "n", modifiers: .command)
        precondition(applet.showsForm && !isEditing(), "Command-N opens the form without focusing input")
        press(20, "3", modifiers: .option)
        precondition(applet.durationInput == "5" && !isEditing(), "Presets must not pull focus into editing")
        press(53, "\u{1b}")
        precondition(!applet.showsForm && applet.durationInput == "5")
        store.timers.forEach { store.remove($0.id) }
        settle()
        precondition(applet.showsForm && !isEditing(), "Returning to the empty form must not focus its input")
        print("Passed: timer entry, Tab editing, typing, Escape and drafts, re-entry, Return start, Command-N, presets, and new-timer focus.")
    }

    @MainActor private static func settle() {
        RunLoop.main.run(until: Date().addingTimeInterval(0.15))
    }
}
