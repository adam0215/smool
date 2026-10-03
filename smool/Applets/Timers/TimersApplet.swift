import SwiftUI

@MainActor @Observable
final class TimersApplet: Applet {
    let id = AppletID(rawValue: "timers")
    let title = "Timers"
    let icon = AppletIcon.symbol("timer")
    let tint = Color.orange
    let contentHeight: CGFloat = 212
    let store: TimerStore

    var selectedID: UUID?
    var isCreating = false
    var durationInput = ""
    var nameInput = ""
    var inputError: String?

    init(store: TimerStore = TimerStore()) { self.store = store }

    var selectedTimer: SmoolTimer? {
        store.timers.first { $0.id == selectedID } ?? store.importantTimer
    }

    var showsForm: Bool { isCreating || store.timers.isEmpty }

    var status: AppletStatus? {
        guard let timer = store.importantTimer else { return nil }
        let label: String
        let symbol: String
        switch timer.state {
        case .expired:
            label = "\(timer.title) is done"
            symbol = "bell.fill"
        case .paused(let remaining):
            label = "\(timer.title) · \(TimerDuration.display(remaining)) paused"
            symbol = "pause.fill"
        case .running:
            label = timer.title
            symbol = "timer"
        }
        return AppletStatus(kind: timer.isExpired ? .needsAttention : .working,
                            label: label, symbol: symbol, countdownDeadline: timer.deadline)
    }

    func activateStatus() {
        selectedID = store.importantTimer?.id
        isCreating = false
    }

    func makeView(context: AppletContext, artwork: NSImage?) -> AnyView {
        AnyView(TimersAppletView(applet: self))
    }

    func handleArrow(_ arrow: AppletArrow, command: Bool) -> Bool {
        guard !command, !showsForm, !arrow.isVertical, let timer = selectedTimer,
              let index = store.timers.firstIndex(where: { $0.id == timer.id }) else { return false }
        selectedID = store.timers[(index + arrow.offset + store.timers.count) % store.timers.count].id
        return true
    }

    func startTimer() {
        do {
            selectedID = try store.start(input: durationInput, name: nameInput)
            durationInput = ""
            nameInput = ""
            inputError = nil
            isCreating = false
        } catch {
            inputError = error.localizedDescription
        }
    }

    func toggleSelectedTimer() {
        guard !showsForm, let timer = selectedTimer else { return }
        if timer.isExpired { store.remove(timer.id) }
        else if timer.isPaused { store.resume(timer.id) }
        else { store.pause(timer.id) }
    }
}
