@testable import SmoolChecksSupport
import SwiftUI

@main
struct TimerAppletChecks {
    @MainActor static func main() throws {
        let output = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
        try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
        var now = Date()
        let store = TimerStore(storageURL: nil, now: { now }, automaticallySchedules: false, completion: {})
        let applet = TimersApplet(store: store)
        precondition(applet.id.rawValue == "timers" && applet.title == "Timers" && applet.showsForm)
        precondition(!applet.handleArrow(.left, command: false))
        precondition(applet.background == nil, "The duration form stays unlit")
        precondition(!applet.handleEditingArrow(.left), "Editing preserves horizontal caret movement")
        precondition(applet.handleEditingArrow(.up))
        precondition(applet.durationInput == "26")
        applet.durationInput = "0:30"
        precondition(applet.handleEditingArrow(.down))
        precondition(applet.durationInput == "0:30")
        applet.durationInput = "59:30"
        precondition(applet.handleEditingArrow(.up))
        precondition(applet.durationInput == "60:30")
        precondition(TimerDuration.parse(applet.durationInput) == 3630)
        applet.adjustDuration(by: 60)
        precondition(applet.durationInput == "61:30")
        applet.startTimer()
        precondition(applet.inputError == nil && applet.selectedTimer?.remaining(at: now) == 3690)
        precondition(!applet.handleEditingArrow(.up), "Running timers do not handle duration editing keys")
        store.remove(applet.selectedTimer!.id)
        applet.durationInput = "10080"
        applet.adjustDuration(by: 60)
        precondition(applet.durationInput == "10080")
        applet.durationInput = ""
        try render(applet, name: "timer-empty", output: output)
        applet.durationInput = "no"
        applet.startTimer()
        precondition(applet.inputError != nil && applet.showsForm)
        applet.durationInput = "25 min"
        applet.startTimer()
        precondition(applet.inputError == nil && !applet.showsForm && store.timers.count == 1)
        let first = applet.selectedTimer!.id
        precondition(applet.background != nil, "A running timer lights its view")
        precondition(applet.actions.map(\.id) == ["new-timer", "add-one-minute", "stop-timer"])
        precondition(applet.status?.countdownDeadline == store.timers[0].deadline)
        try render(applet, name: "timer-running", output: output)
        applet.toggleSelectedTimer()
        precondition(applet.status?.countdownDeadline == nil && applet.status?.symbol == "pause.fill")
        precondition(applet.background == nil, "Pausing removes the timer glow")
        precondition(applet.status?.label.contains("25:00") == true)
        applet.toggleSelectedTimer()
        precondition(applet.background != nil, "Resuming restores the timer glow")
        applet.isCreating = true
        precondition(applet.background == nil, "A running timer must not light the new-timer form")
        applet.durationInput = "1:30"
        applet.startTimer()
        let second = applet.selectedTimer!.id
        precondition(second != first && store.timers.count == 2)
        precondition(applet.handleArrow(.left, command: false) && applet.selectedTimer?.id == first)
        precondition(!applet.handleArrow(.left, command: true))
        precondition(!applet.handleArrow(.up, command: false))
        applet.toggleSelectedTimer()
        precondition(applet.selectedTimer?.isPaused == true)
        precondition(applet.background == nil, "Another running timer must not light the selected paused timer")
        try render(applet, name: "timer-paused", output: output)
        applet.toggleSelectedTimer()
        precondition(applet.selectedTimer?.deadline != nil)
        applet.isCreating = true
        precondition(!applet.handleArrow(.right, command: false), "Editing retains native arrow navigation")
        applet.isCreating = false
        now += 1800
        store.refresh()
        precondition(applet.background == nil, "Completed timers stay unlit")
        precondition(applet.status?.kind == .needsAttention && applet.status?.countdownDeadline == nil)
        applet.selectedID = second
        applet.isCreating = true
        applet.activateStatus()
        precondition(applet.selectedTimer?.id == first && !applet.isCreating)
        try render(applet, name: "timer-expired", output: output)
        applet.toggleSelectedTimer()
        precondition(store.timers.count == 1 && applet.selectedTimer?.id == second)
        applet.toggleSelectedTimer()
        precondition(store.timers.isEmpty && applet.showsForm && applet.status == nil)
        print("Passed: timer applet navigation, editing, actions, status, and rendering of empty/running/paused/expired states.")
    }

    @MainActor private static func render(_ applet: TimersApplet, name: String, output: URL) throws {
        let view = TimersAppletView(applet: applet)
            .frame(width: 560, height: applet.contentHeight)
            .background(.black)
            .environment(\.colorScheme, .dark)
        let host = NSHostingView(rootView: view)
        let window = NSWindow(contentRect: CGRect(x: 0, y: 0, width: 560, height: applet.contentHeight),
                              styleMask: .borderless, backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = host
        host.layoutSubtreeIfNeeded()
        guard let bitmap = host.bitmapImageRepForCachingDisplay(in: host.bounds) else {
            fatalError("Could not render \(name)")
        }
        host.cacheDisplay(in: host.bounds, to: bitmap)
        precondition(bitmap.pixelsWide > 0 && bitmap.pixelsHigh > 0)
        try bitmap.representation(using: .png, properties: [:])!.write(to: output.appending(path: "\(name).png"))
        window.close()
    }
}
