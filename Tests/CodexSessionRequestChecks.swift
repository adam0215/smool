import SwiftUI

@MainActor @Observable
private final class RequestFixture {
    var answers: [String: String] = [:]
    var decisions: [CodexSessionDecision] = []
    var closes = 0
}

@main
struct CodexSessionRequestChecks {
    @MainActor static func main() throws {
        _ = NSApplication.shared
        NSApp.setActivationPolicy(.accessory)
        NSApp.finishLaunching()
        NSApp.activate()
        let fixture = RequestFixture()
        let window = NSWindow(contentRect: CGRect(x: 100, y: 100, width: 560, height: 340),
                              styleMask: [.titled], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        defer { window.close() }

        func request(_ json: String) throws -> CodexSessionRequest {
            let message = try JSONDecoder().decode(CodexJSON.self, from: Data(json.utf8))
            return CodexSessionRequest(message: message, threadID: "fixture-thread")!
        }

        func show(_ request: CodexSessionRequest) {
            window.contentView = NSHostingView(rootView: CodexSessionRequestView(
                request: request,
                answers: Binding(get: { fixture.answers }, set: { fixture.answers = $0 }),
                respond: { fixture.decisions.append($0) },
                close: { fixture.closes += 1 }
            ).preferredColorScheme(.dark))
            window.makeKeyAndOrderFront(nil)
            settle()
        }

        func press(_ code: UInt16, _ characters: String, modifiers: NSEvent.ModifierFlags = []) {
            let event = NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: modifiers,
                                        timestamp: 0, windowNumber: window.windowNumber, context: nil,
                                        characters: characters, charactersIgnoringModifiers: characters,
                                        isARepeat: false, keyCode: code)!
            window.sendEvent(event)
            settle()
        }

        let approval = try request(#"{"id":1,"method":"item/commandExecution/requestApproval","params":{"command":"swift test","cwd":"/tmp/fixture","reason":"Run the project checks."}}"#)
        show(approval)
        press(36, "\r")
        precondition(fixture.decisions.isEmpty, "Opening an approval must not preselect an approving action")
        press(48, "\t")
        press(36, "\r")
        guard case .decline = fixture.decisions.last else { fatalError("Tab then Return must support declining") }
        show(approval)
        press(48, "\t", modifiers: .shift)
        press(36, "\r")
        guard case .allowOnce = fixture.decisions.last else { fatalError("Shift-Tab then Return must support an explicit approval") }
        let count = fixture.decisions.count
        press(53, "\u{1b}")
        precondition(fixture.closes == 1 && fixture.decisions.count == count, "Escape leaves the request pending")

        let question = try request(#"{"id":2,"method":"item/tool/requestUserInput","params":{"questions":[{"id":"scope","header":"Scope","question":"Which project should change?","isSecret":false,"options":[{"label":"Current project","description":"Use the selected project."}]}]}}"#)
        show(question)
        press(48, "\t")
        press(36, "\r")
        precondition(fixture.answers["scope"] == "Current project", "Options must be selectable using the keyboard")
        precondition(fixture.decisions.count == count, "Choosing an option must not submit it")
        press(48, "\t")
        precondition(window.firstResponder is NSTextView, "Tab must enter the free-form answer")
        press(0, "a")
        precondition(fixture.answers["scope"] == "a")
        press(53, "\u{1b}")
        precondition(fixture.closes == 2 && fixture.answers["scope"] == "a", "Escape preserves a written answer")
        show(question)
        press(48, "\t", modifiers: .shift)
        press(36, "\r")
        guard case .answers(let answers) = fixture.decisions.last else { fatalError("Reopened answers must be submittable") }
        precondition(answers == ["scope": ["a"]])

        if let host = window.contentView,
           let bitmap = host.bitmapImageRepForCachingDisplay(in: host.bounds) {
            host.cacheDisplay(in: host.bounds, to: bitmap)
            try bitmap.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: "/tmp/smool-codex-request.png"))
        }
        print("Passed: explicit approval, keyboard choices and free text, Escape preserves pending request and answer, and resubmission.")
    }

    @MainActor private static func settle() {
        RunLoop.main.run(until: Date().addingTimeInterval(0.15))
    }
}
