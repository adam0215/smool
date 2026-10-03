import SwiftUI

struct TimersAppletView: View {
    @Bindable var applet: TimersApplet
    @FocusState private var focus: Focus?

    private enum Focus: Hashable { case deck, duration, name }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if applet.showsForm {
                timerForm
            } else if let timer = applet.selectedTimer {
                timerDeck(timer)
            }
            if let error = applet.store.persistenceError {
                Text(error).font(.system(size: 11)).foregroundStyle(.orange).lineLimit(2)
            }
        }
        .padding(.horizontal, 24)
        .padding(.top, 8)
        .padding(.bottom, 16)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(.black)
        .focusable(interactions: .edit)
        .focused($focus, equals: .deck)
        .focusEffectDisabled()
        .task {
            applet.store.refresh()
            await Task.yield()
            restoreFocus()
        }
        .onChange(of: applet.showsForm) { restoreFocus() }
        .onKeyPress(.space, phases: .down) { key in
            guard focus == .deck, key.modifiers.isEmpty else { return .ignored }
            applet.toggleSelectedTimer()
            return .handled
        }
        .onKeyPress(.return, phases: .down) { key in
            guard focus == .deck, key.modifiers.isEmpty else { return .ignored }
            applet.toggleSelectedTimer()
            return .handled
        }
        .onKeyPress(.escape) {
            guard applet.isCreating, !applet.store.timers.isEmpty else { return .ignored }
            applet.isCreating = false
            return .handled
        }
        .background {
            Button("New timer") { applet.isCreating = true }
                .keyboardShortcut("n", modifiers: .command)
                .disabled(!applet.store.canAddTimer).hidden()
        }
        .preferredColorScheme(.dark)
    }

    private var timerForm: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("New timer").font(.system(size: 13, weight: .semibold))
                Spacer()
                if !applet.store.timers.isEmpty {
                    Button("Back") { applet.isCreating = false }
                        .buttonStyle(NotchControlStyle()).foregroundStyle(.secondary)
                        .help("Back · esc")
                }
            }
            HStack(spacing: 12) {
                TextField("25 min", text: $applet.durationInput)
                    .focused($focus, equals: .duration)
                    .accessibilityLabel("Duration, in minutes or minutes and seconds")
                    .font(.system(size: 20, weight: .light, design: .rounded))
                    .monospacedDigit()
                    .frame(width: 108)
                Divider().frame(height: 20)
                TextField("Name, optional", text: $applet.nameInput)
                    .focused($focus, equals: .name)
                    .accessibilityLabel("Timer name, optional")
                Button(action: applet.startTimer) {
                    Image(systemName: "play.fill")
                        .font(.system(size: 12, weight: .semibold))
                        .frame(width: 32, height: 32)
                        .background(.white.opacity(0.12), in: Circle())
                        .contentShape(Circle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Start timer")
                .disabled(!applet.store.canAddTimer)
            }
            .textFieldStyle(.plain)
            .font(.system(size: 13))
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .background(.white.opacity(0.055), in: .rect(cornerRadius: 14))
            .onSubmit { applet.startTimer() }

            Text(applet.inputError ?? TimerDuration.syntax)
                .font(.system(size: 11))
                .foregroundStyle(applet.inputError == nil ? .secondary : Color.orange)
                .fixedSize(horizontal: false, vertical: true)
            Text("No unit = minutes · Up to 7 days · ↵ Start")
                .font(.system(size: 11)).foregroundStyle(.secondary)
        }
    }

    private func timerDeck(_ timer: SmoolTimer) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Text(timer.title).font(.system(size: 13, weight: .semibold)).lineLimit(1)
                Spacer()
                if applet.store.timers.count > 1 {
                    Button { _ = applet.handleArrow(.left, command: false) } label: {
                        Image(systemName: "chevron.left").frame(width: 28, height: 28).contentShape(Circle())
                    }
                    .accessibilityLabel("Previous timer")
                    Text("\((applet.store.timers.firstIndex { $0.id == timer.id } ?? 0) + 1) / \(applet.store.timers.count)")
                        .monospacedDigit().foregroundStyle(.secondary)
                    Button { _ = applet.handleArrow(.right, command: false) } label: {
                        Image(systemName: "chevron.right").frame(width: 28, height: 28).contentShape(Circle())
                    }
                    .accessibilityLabel("Next timer")
                }
                Button { applet.isCreating = true } label: { Image(systemName: "plus").frame(width: 28, height: 28).contentShape(Circle()) }
                    .accessibilityLabel("New timer").help("New timer · ⌘N")
                    .disabled(!applet.store.canAddTimer)
            }
            .buttonStyle(.plain).font(.system(size: 11))

            HStack(alignment: .firstTextBaseline, spacing: 14) {
                TimerCountdownView(timer: timer)
                    .font(.system(size: 44, weight: .light, design: .rounded))
                Text(timer.isExpired ? "Done" : timer.isPaused ? "Paused" : "Remaining")
                    .font(.system(size: 12))
                    .foregroundStyle(timer.isExpired ? Color.orange : .secondary)
                Spacer()
            }

            HStack(spacing: 10) {
                Button(action: applet.toggleSelectedTimer) {
                    Label(timer.isExpired ? "Dismiss" : timer.isPaused ? "Resume" : "Pause",
                          systemImage: timer.isExpired ? "checkmark" : timer.isPaused ? "play.fill" : "pause.fill")
                }
                .buttonStyle(NotchControlStyle(isSelected: true))
                .help("Space or ↵")

                Button("+1 min") { applet.store.extend(timer.id) }
                    .buttonStyle(NotchControlStyle())
                    .keyboardShortcut("e", modifiers: .command)
                    .help("Add one minute · ⌘E")

                Spacer()
                if !timer.isExpired {
                    Button { applet.store.remove(timer.id) } label: {
                        Image(systemName: "trash")
                            .frame(width: 28, height: 28)
                            .contentShape(Circle())
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
                    .keyboardShortcut(.delete, modifiers: .command)
                    .accessibilityLabel("Stop and delete \(timer.title)")
                    .help("Stop and delete · ⌘⌫")
                }
            }
            .controlSize(.small)
            Text("←→ Choose timer · Space Pause/resume · ⌘N New")
                .font(.system(size: 11)).foregroundStyle(.secondary)
        }
    }

    private func restoreFocus() {
        focus = applet.showsForm ? .duration : .deck
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
