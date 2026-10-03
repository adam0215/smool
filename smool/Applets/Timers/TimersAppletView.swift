import SwiftUI

struct TimersAppletView: View {
    @Bindable var applet: TimersApplet
    var restoreFocus: () -> Void = {}
    @FocusState private var focus: Focus?

    private enum Focus: Hashable { case deck, duration }
    private let presets = ["0:30", "1", "5", "15", "25", "30", "60"]
    private let presetLabels = ["30 sec", "1 min", "5 min", "15 min", "25 min", "30 min", "1 hour"]

    var body: some View {
        VStack(spacing: 8) {
            if applet.showsForm {
                timerForm
            } else if let timer = applet.selectedTimer {
                timerDeck(timer)
            }
            if let error = applet.store.persistenceError {
                Text(error).font(.system(size: 11)).foregroundStyle(.orange).lineLimit(2)
            }
        }
        .padding(.horizontal, 28)
        .padding(.top, 8)
        .padding(.bottom, 16)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .focusable(interactions: .edit)
        .focused($focus, equals: .deck)
        .focusEffectDisabled()
        .onAppletFocusRestore { focus = .deck }
        .task {
            applet.store.refresh()
            await Task.yield()
            focus = applet.showsForm ? .duration : .deck
        }
        .onChange(of: applet.showsForm) { focus = applet.showsForm ? .duration : .deck }
        .onKeyPress(.space, phases: .down) { key in
            guard focus != .duration, !applet.showsForm, key.modifiers.isEmpty else { return .ignored }
            applet.toggleSelectedTimer()
            return .handled
        }
        .onKeyPress(.return, phases: .down) { key in
            guard focus != .duration, key.modifiers.isEmpty else { return .ignored }
            if applet.showsForm { focus = .duration }
            else { applet.toggleSelectedTimer() }
            return .handled
        }
        .onKeyPress(.escape) {
            guard focus == .duration || applet.isCreating else { return .ignored }
            applet.isCreating = false
            focus = .deck
            restoreFocus()
            return .handled
        }
        .background {
            Button("New timer") { applet.isCreating = true; focus = .duration }
                .keyboardShortcut("n", modifiers: .command)
                .disabled(!applet.store.canAddTimer).hidden()
        }
        .preferredColorScheme(.dark)
    }

    private var timerForm: some View {
        VStack(spacing: 12) {
            VStack(spacing: 0) {
                TextField("25", text: $applet.durationInput)
                    .textFieldStyle(.plain)
                    .multilineTextAlignment(.center)
                    .font(.system(size: 48, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .focused($focus, equals: .duration)
                    .accessibilityLabel("Timer duration")
                    .accessibilityHint("Minutes, or minutes and seconds separated by a colon. Up and down adjust duration.")
                    .onSubmit { applet.startTimer() }
                    .onKeyPress(keys: [.upArrow, .downArrow]) { key in
                        guard key.modifiers.isEmpty else { return .ignored }
                        applet.adjustDuration(by: key.key == .upArrow ? 60 : -60)
                        return .handled
                    }
                Text(applet.durationInput.contains(":") ? "min : sec" : "min")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.secondary)
            }

            HStack(spacing: 0) {
                ForEach(presets.indices, id: \.self) { index in
                    Button {
                        applet.durationInput = presets[index]
                        applet.inputError = nil
                        focus = .duration
                    } label: {
                        VStack(spacing: 4) {
                            Text(presetLabels[index]).font(.system(size: 11, weight: .medium))
                            Text("⌥\(index + 1)").font(.system(size: 9)).foregroundStyle(.tertiary)
                        }
                        .frame(maxWidth: .infinity, minHeight: 34)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .focusable(false)
                    .keyboardShortcut(KeyEquivalent(Character(String(index + 1))), modifiers: .option)
                    .accessibilityLabel("Set timer to \(presetLabels[index])")
                }
            }
            Text(applet.inputError ?? (focus == .duration ? "↑↓ Adjust · ↵ Start · Esc Done editing" : "↵ Edit duration · ⌘K Actions"))
                .font(.system(size: 11))
                .foregroundStyle(applet.inputError == nil ? .secondary : Color.orange)
                .multilineTextAlignment(.center)
                .lineLimit(2)
                .padding(.horizontal, 12)
        }
    }

    private func timerDeck(_ timer: SmoolTimer) -> some View {
        VStack(spacing: 6) {
            TimerCountdownView(timer: timer)
                .font(.system(size: 48, weight: .bold, design: .rounded))
                .minimumScaleFactor(0.65)
                .lineLimit(1)
            Text(timer.isExpired ? "Time’s up" : timer.isPaused ? "Paused" : "Remaining")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(timer.isExpired ? Color.orange : .secondary)

            HStack(spacing: 18) {
                if applet.store.timers.count > 1 { timerNavigation(.left, symbol: "backward.end.fill") }
                Button(action: applet.toggleSelectedTimer) {
                    Image(systemName: timer.isExpired ? "checkmark" : timer.isPaused ? "play.fill" : "pause.fill")
                        .font(.system(size: 22, weight: .medium))
                        .frame(width: 48, height: 44)
                        .contentShape(.rect(cornerRadius: 14))
                }
                .buttonStyle(.plain)
                .focusable(false)
                .accessibilityLabel(timer.isExpired ? "Dismiss timer" : timer.isPaused ? "Resume timer" : "Pause timer")
                if applet.store.timers.count > 1 { timerNavigation(.right, symbol: "forward.end.fill") }
            }
            Text(applet.store.timers.count > 1
                 ? "←→ Timer \(timerPosition) of \(applet.store.timers.count) · Space \(timer.isExpired ? "Dismiss" : "Pause/resume") · ⌘K Actions"
                 : "Space \(timer.isExpired ? "Dismiss" : "Pause/resume") · ⌘K Actions")
                .font(.system(size: 11)).foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 12)
        }
    }

    private var timerPosition: Int {
        (applet.store.timers.firstIndex { $0.id == applet.selectedTimer?.id } ?? 0) + 1
    }

    private func timerNavigation(_ arrow: AppletArrow, symbol: String) -> some View {
        Button { _ = applet.handleArrow(arrow, command: false) } label: {
            Image(systemName: symbol)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(.secondary)
                .frame(width: 32, height: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .focusable(false)
        .accessibilityLabel(arrow == .left ? "Previous timer" : "Next timer")
    }
}

/// Only running countdowns redraw. The host removes the applet view when the notch closes.
struct TimerCountdownView: View {
    let timer: SmoolTimer

    var body: some View {
        if timer.deadline != nil {
            TimelineView(.periodic(from: .now, by: 1)) { context in
                countdown(at: context.date)
            }
        } else {
            countdown(at: .now)
        }
    }

    private func countdown(at date: Date) -> some View {
        Text(TimerDuration.display(timer.remaining(at: date)))
            .monospacedDigit()
            .contentTransition(.identity)
            .accessibilityLabel("\(TimerDuration.display(timer.remaining(at: date))) remaining")
    }
}
