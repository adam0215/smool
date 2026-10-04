import SwiftUI

@main
struct CodexActivityViewChecks {
    @MainActor static func main() throws {
        _ = NSApplication.shared
        let running = presentation(toolStatus: "inProgress", turnStatus: "inProgress")
        let toolsCompleted = presentation(toolStatus: "completed", turnStatus: "inProgress")
        let completed = presentation(toolStatus: "completed", turnStatus: "completed")

        precondition(running.latestMessage?.text == "The keyboard paths are connected. I’m checking Escape and Return next.")
        precondition(running.runningTools.map(\.title) == ["Terminal"])
        precondition(running.workingSummary?.text == "Checking focus restoration before running the regression suite.")
        precondition(!running.items.contains { $0.text.contains("PRIVATE_CONTENT") })
        precondition(toolsCompleted.runningTools.isEmpty, "A completed tool disappears before the turn ends.")
        precondition(completed.runningTools.isEmpty && completed.workingSummary == nil)
        precondition(completed.latestMessage?.text == "Escape and Return now work throughout the applet.")

        let disconnected = CodexActivityView(presentation: running, isLive: false, unavailableReason: "Live activity is unavailable.")
        let awaitingFinal = CodexActivityView(presentation: running, isLive: false)
        precondition(disconnected.runningTools.isEmpty && disconnected.workingSummary == nil)
        precondition(awaitingFinal.runningTools.isEmpty && awaitingFinal.workingSummary == nil)

        let thinking = CodexActivityPresentation(state: .object([
            "turns": .array([.object(["turnId": .string("thinking"), "status": .string("inProgress"), "items": .array([
                .object(["id": .string("reasoning"), "type": .string("reasoning"), "summary": .array([]), "content": .array([.string("PRIVATE_CONTENT")])])
            ])])])
        ]), revision: 1)
        precondition(thinking.isThinking && thinking.workingSummary == nil)
        let mixed = CodexActivityPresentation(state: .object([
            "turns": .array([.object(["turnId": .string("mixed"), "status": .string("inProgress"), "items": .array([
                .object(["id": .string("update"), "type": .string("agentMessage"), "text": .string("Checking the design and the latest documentation.")]),
                .object(["id": .string("custom"), "type": .string("dynamicToolCall"), "namespace": .string("figma"), "tool": .string("use_figma"),
                         "arguments": .object(["title": .string("Inspect notch components")]), "status": .string("inProgress")]),
                .object(["id": .string("search"), "type": .string("webSearch"), "query": .string("SwiftUI keyboard focus")])
            ])])])
        ]), revision: 1)
        precondition(mixed.runningTools.map(\.title) == ["figma.use_figma", "Search"])

        let directory = URL(fileURLWithPath: CommandLine.arguments.dropFirst().first ?? ".build/Checks/renders", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        for (name, activity) in [("active-running", running), ("active-tools-completed", toolsCompleted), ("active-completed", completed)] {
            try render(VStack(alignment: .leading, spacing: 12) {
                Text("Polish keyboard navigation").font(.system(size: 17, weight: .medium))
                CodexActivityView(presentation: activity, isLive: activity.attention == .working)
            }, name: name, in: directory)
        }
        try render(CodexActivityView(presentation: thinking, isLive: true), name: "thinking", in: directory)
        try render(CodexActivityView(presentation: mixed, isLive: true), name: "mixed-tools", in: directory)
        try render(disconnected, name: "active-disconnected", in: directory)
        try render(awaitingFinal, name: "active-awaiting-final", in: directory)
        try render(CodexHistoryPreviewView(title: "Polish keyboard navigation", message: completed.latestMessage), name: "history-latest", in: directory)
        try render(CodexHistoryPreviewView(title: "A thread with unavailable history", message: nil, error: "Latest message is unavailable. Open this thread in Codex."), name: "history-unavailable", in: directory)
        try render(ShimmeringText("Sending…", isActive: false).font(.system(size: 12)).foregroundStyle(.secondary), name: "sending-static", in: directory)
        print("Codex active/history selection checks passed; offscreen fixtures rendered")
    }

    private static func presentation(toolStatus: String, turnStatus: String) -> CodexActivityPresentation {
        var items: [CodexJSON] = [
            .object(["type": .string("userMessage"), "id": .string("prompt"), "content": .array([
                .object(["type": .string("text"), "text": .string("The original prompt must not become the latest-message preview.")])
            ])]),
            .object(["type": .string("agentMessage"), "id": .string("update"), "text": .string("The keyboard paths are connected. I’m checking Escape and Return next.")]),
            .object(["type": .string("reasoning"), "id": .string("summary"), "summary": .array([
                .string("Checking focus restoration before running the regression suite.")
            ]), "content": .array([.string("PRIVATE_CONTENT")])]),
            .object(["type": .string("commandExecution"), "id": .string("tool"), "command": .string("swift test --filter KeyboardChecks"), "status": .string(toolStatus)])
        ]
        if turnStatus == "completed" {
            items.append(.object(["type": .string("agentMessage"), "id": .string("answer"), "text": .string("Escape and Return now work throughout the applet.")]))
        }
        return CodexActivityPresentation(state: .object([
            "turns": .array([.object(["turnId": .string("turn"), "status": .string(turnStatus), "items": .array(items)])])
        ]), revision: 1)
    }

    @MainActor private static func render(_ content: some View, name: String, in directory: URL) throws {
        let view = content
            .padding(.horizontal, 32)
            .padding(.vertical, 24)
            .frame(width: 560, height: 256, alignment: .topLeading)
            .foregroundStyle(.white)
            .background(.black)
            .environment(\.colorScheme, .dark)
        let host = NSHostingView(rootView: view)
        let window = NSWindow(contentRect: CGRect(x: 0, y: 0, width: 560, height: 256),
                              styleMask: .borderless, backing: .buffered, defer: false)
        window.appearance = NSAppearance(named: .darkAqua)
        window.isReleasedWhenClosed = false
        window.contentView = host
        host.layoutSubtreeIfNeeded()
        RunLoop.main.run(until: Date().addingTimeInterval(0.1))
        host.layoutSubtreeIfNeeded()
        guard let bitmap = host.bitmapImageRepForCachingDisplay(in: host.bounds) else {
            fatalError("Could not render \(name)")
        }
        host.cacheDisplay(in: host.bounds, to: bitmap)
        try bitmap.representation(using: .png, properties: [:])!.write(to: directory.appendingPathComponent("codex-\(name).png"))
        window.close()
    }
}
