import SwiftUI

@MainActor @Observable
private final class ComposerFixture {
    var text = "A saved draft"
    var editing = true
    var sends = 0
    var closes = 0
    var focusGeneration = 0
}

private struct ComposerFixtureView: View {
    let fixture: ComposerFixture

    var body: some View {
        FloatingComposer(
            text: Binding(get: { fixture.text }, set: { fixture.text = $0 }),
            recipient: "Selected thread",
            isEditing: fixture.editing,
            onSend: { fixture.sends += 1 },
            onClose: { fixture.closes += 1; fixture.editing = false }
        )
        .environment(\.appletFocusGeneration, fixture.focusGeneration)
        .padding(20)
        .frame(width: 520)
        .preferredColorScheme(.dark)
    }
}

@main
struct CodexComposerChecks {
    @MainActor static func main() throws {
        _ = NSApplication.shared
        NSApp.setActivationPolicy(.accessory)
        NSApp.finishLaunching()
        NSApp.activate()
        let fixture = ComposerFixture()
        let host = NSHostingView(rootView: ComposerFixtureView(fixture: fixture))
        let window = NSWindow(contentRect: CGRect(x: 100, y: 100, width: 520, height: 100), styleMask: [.titled], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = host
        window.makeKeyAndOrderFront(nil)
        RunLoop.main.run(until: Date().addingTimeInterval(0.3))
        host.layoutSubtreeIfNeeded()
        precondition(host.fittingSize.height < 110, "The single-line composer should remain a narrow pill")
        guard let bitmap = host.bitmapImageRepForCachingDisplay(in: host.bounds) else { fatalError("No composer render") }
        host.cacheDisplay(in: host.bounds, to: bitmap)
        try bitmap.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: "/tmp/smool-codex-composer.png"))

        func key(_ code: UInt16, characters: String, modifiers: NSEvent.ModifierFlags = []) {
            let event = NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: modifiers, timestamp: 0,
                                        windowNumber: window.windowNumber, context: nil, characters: characters,
                                        charactersIgnoringModifiers: characters, isARepeat: false, keyCode: code)!
            window.sendEvent(event)
            RunLoop.main.run(until: Date().addingTimeInterval(0.1))
        }
        precondition(window.firstResponder is NSTextView, "The composer should initially focus its text input")
        key(36, characters: "\r")
        precondition(fixture.sends == 1 && fixture.text == "A saved draft", "Return sends without inserting a newline or clearing the draft")
        key(36, characters: "\r", modifiers: .shift)
        precondition(fixture.sends == 1 && fixture.text.contains("\n"), "Shift-Return inserts a newline")
        let saved = fixture.text
        key(53, characters: "\u{1b}")
        precondition(fixture.closes == 1 && fixture.text == saved, "Escape exits and preserves the draft")
        fixture.editing = true
        RunLoop.main.run(until: Date().addingTimeInterval(0.1))
        fixture.focusGeneration += 1
        RunLoop.main.run(until: Date().addingTimeInterval(0.1))
        precondition(fixture.closes == 2 && !fixture.editing && fixture.text == saved, "Host focus restoration exits editing without losing the draft")
        window.close()
        print("Passed: narrow composer render, input focus, Return sends, Shift-Return newline, Escape retains draft.")
    }
}
