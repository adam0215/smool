import SwiftUI

struct TimersAppletView: View {
    @Bindable var applet: TimersApplet
    @FocusState private var focus: Focus?
    @State private var windowIsVisible = false

    private enum Focus: Hashable { case deck, duration, name }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if applet.showsForm {
                timerForm
            } else if let timer = applet.selectedTimer {
                timerDeck(timer)
            }
            if let error = applet.store.persistenceError {
                Text(error).font(.system(size: 10)).foregroundStyle(.orange).lineLimit(2)
            }
        }
        .padding(.horizontal, 28)
        .padding(.vertical, 14)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(.black)
        .background(TimerWindowVisibility { windowIsVisible = $0 }.frame(width: 0, height: 0))
        .focusable(interactions: .edit)
        .focused($focus, equals: .deck)
        .focusEffectDisabled()
        .task {
            applet.store.refresh()
            await Task.yield()
            restoreFocus()
        }
        .onChange(of: applet.showsForm) { restoreFocus() }
        .onChange(of: windowIsVisible) { _, visible in
            if visible { applet.store.refresh() }
        }
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
            Button("Ny timer") { applet.isCreating = true }
                .keyboardShortcut("n", modifiers: .command)
                .disabled(!applet.store.canAddTimer).hidden()
        }
        .preferredColorScheme(.dark)
    }

    private var timerForm: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Ny timer").font(.system(size: 13, weight: .medium))
                Spacer()
                if !applet.store.timers.isEmpty {
                    Button("Tillbaka") { applet.isCreating = false }
                        .buttonStyle(.plain).foregroundStyle(.secondary)
                        .help("Tillbaka · esc")
                }
            }
            HStack(spacing: 12) {
                TextField("25 min", text: $applet.durationInput)
                    .focused($focus, equals: .duration)
                    .accessibilityLabel("Tid, minuter eller minuter och sekunder")
                    .frame(width: 130)
                Divider().frame(height: 20)
                TextField("Namn, valfritt", text: $applet.nameInput)
                    .focused($focus, equals: .name)
                    .accessibilityLabel("Timerns namn, valfritt")
                Button(action: applet.startTimer) {
                    Image(systemName: "play.fill").frame(width: 24, height: 24)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Starta timer")
                .disabled(!applet.store.canAddTimer)
            }
            .textFieldStyle(.plain)
            .font(.system(size: 14))
            .padding(14)
            .modifier(FloatingGlass(cornerRadius: 20))
            .onSubmit { applet.startTimer() }

            Text(applet.inputError ?? TimerDuration.syntax)
                .font(.system(size: 10))
                .foregroundStyle(applet.inputError == nil ? .secondary : Color.orange)
                .fixedSize(horizontal: false, vertical: true)
            Text("Utan enhet = minuter · Högst 7 dygn · ↵ Starta")
                .font(.system(size: 10)).foregroundStyle(.secondary)
        }
    }

    private func timerDeck(_ timer: SmoolTimer) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Text(timer.title).font(.system(size: 13, weight: .medium)).lineLimit(1)
                Spacer()
                if applet.store.timers.count > 1 {
                    Button { _ = applet.handleArrow(.left, command: false) } label: {
                        Image(systemName: "chevron.left")
                    }
                    .accessibilityLabel("Föregående timer")
                    Text("\((applet.store.timers.firstIndex { $0.id == timer.id } ?? 0) + 1) / \(applet.store.timers.count)")
                        .monospacedDigit().foregroundStyle(.secondary)
                    Button { _ = applet.handleArrow(.right, command: false) } label: {
                        Image(systemName: "chevron.right")
                    }
                    .accessibilityLabel("Nästa timer")
                }
                Button { applet.isCreating = true } label: { Image(systemName: "plus") }
                    .accessibilityLabel("Ny timer").help("Ny timer · ⌘N")
                    .disabled(!applet.store.canAddTimer)
            }
            .buttonStyle(.plain).font(.system(size: 11))

            HStack(alignment: .firstTextBaseline, spacing: 14) {
                TimerCountdownView(timer: timer, isVisible: windowIsVisible)
                    .font(.system(size: 42, weight: .light, design: .rounded))
                Text(timer.isExpired ? "Klar" : timer.isPaused ? "Pausad" : "Återstår")
                    .font(.system(size: 12))
                    .foregroundStyle(timer.isExpired ? Color.orange : .secondary)
                Spacer()
            }

            HStack(spacing: 10) {
                Button(action: applet.toggleSelectedTimer) {
                    Label(timer.isExpired ? "Kvittera" : timer.isPaused ? "Fortsätt" : "Pausa",
                          systemImage: timer.isExpired ? "checkmark" : timer.isPaused ? "play.fill" : "pause.fill")
                }
                .buttonStyle(FloatingControlStyle(isProminent: true))
                .help("Mellanslag eller ↵")

                Button("+1 min") { applet.store.extend(timer.id) }
                    .buttonStyle(FloatingControlStyle())
                    .keyboardShortcut("e", modifiers: .command)
                    .help("Förläng med en minut · ⌘E")

                Spacer()
                if !timer.isExpired {
                    Button { applet.store.remove(timer.id) } label: {
                        Image(systemName: "trash")
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
                    .keyboardShortcut(.delete, modifiers: .command)
                    .accessibilityLabel("Avsluta och ta bort \(timer.title)")
                    .help("Avsluta och ta bort · ⌘⌫")
                }
            }
            .controlSize(.small)
            Text("←→ Välj timer · Mellanslag Pausa/fortsätt · ⌘N Ny")
                .font(.system(size: 10)).foregroundStyle(.secondary)
        }
    }

    private func restoreFocus() {
        focus = applet.showsForm ? .duration : .deck
    }
}

/// Only this small subtree redraws each second, and only while its window is visible.
struct TimerCountdownView: View {
    let timer: SmoolTimer
    var isVisible = true

    var body: some View {
        if isVisible && timer.deadline != nil {
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
            .accessibilityLabel("\(TimerDuration.display(timer.remaining(at: date))) återstår")
    }
}

/// An ordered-out notch keeps its SwiftUI hierarchy. Window visibility stops its countdown schedule.
private struct TimerWindowVisibility: NSViewRepresentable {
    let onChange: (Bool) -> Void

    func makeNSView(context: Context) -> VisibilityView { VisibilityView() }

    func updateNSView(_ view: VisibilityView, context: Context) {
        view.onChange = onChange
        view.reportVisibility()
    }

    final class VisibilityView: NSView {
        var onChange: ((Bool) -> Void)?
        private var lastVisibility: Bool?

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            NotificationCenter.default.removeObserver(self)
            if let window {
                NotificationCenter.default.addObserver(self, selector: #selector(reportVisibility),
                    name: NSWindow.didChangeOcclusionStateNotification, object: window)
            }
            reportVisibility()
        }

        @objc func reportVisibility() {
            let visible = window?.occlusionState.contains(.visible) == true
            guard visible != lastVisibility else { return }
            lastVisibility = visible
            Task { @MainActor [weak self] in self?.onChange?(visible) }
        }
    }
}
