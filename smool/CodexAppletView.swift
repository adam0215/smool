import SwiftUI

enum CodexPage: String, CaseIterable {
    case active = "Aktiva trådar"
    case history = "Tidigare trådar"
    case usage = "Användning"
}

enum CodexScope: Equatable {
    case deck, search
    case composer(CodexThread)
}

@MainActor @Observable
final class CodexAppletState {
    var page = CodexPage.active
    var scope = CodexScope.deck
    var selection: [CodexPage: String] = [:]
    var searches: [CodexPage: String] = [:]
}

struct CodexAppletView: View {
    @State private var service: CodexService
    @State private var state: CodexAppletState
    @State private var connectionTask: Task<Void, Never>?
    @State private var isVisible = false
    private let restoreFocus: () -> Void

    private enum Focus: Hashable { case search, composer }
    @FocusState private var focus: Focus?

    init(service: CodexService? = nil, state: CodexAppletState? = nil, restoreFocus: @escaping () -> Void = {}) {
        _service = State(initialValue: service ?? .shared)
        _state = State(initialValue: state ?? CodexAppletState())
        self.restoreFocus = restoreFocus
    }

    private var query: Binding<String> {
        Binding(get: { state.searches[state.page] ?? "" }, set: { state.searches[state.page] = $0 })
    }

    private var threads: [CodexThread] {
        let query = query.wrappedValue.trimmingCharacters(in: .whitespacesAndNewlines)
        return service.threads.filter { thread in
            (state.page != .active || thread.isActive)
                && (query.isEmpty || thread.title.localizedStandardContains(query) || thread.preview.localizedStandardContains(query))
        }
    }

    private var selectedThread: CodexThread? {
        threads.first { $0.id == state.selection[state.page] } ?? threads.first
    }

    private var editingHint: String {
        switch state.scope {
        case .composer: "⌘↵ skicka   ·   esc tillbaka"
        case .search: "Sök efter titel eller innehåll   ·   ↓ trådar   ·   esc tillbaka"
        case .deck: ""
        }
    }

    var body: some View {
        PageStack(
            pages: CodexPage.allCases,
            selection: $state.page,
            title: { $0.rawValue },
            showsTitle: state.page != .usage && (state.scope == .deck || state.scope == .search),
            elevated: state.page != .usage,
            isNavigating: state.scope == .deck,
            editingHint: editingHint,
            navigationHint: state.page == .usage ? "↑↓ kort   ·   ⌘R uppdatera" : "↑↓ Byt kort\n←→ Välj tråd · ↵ Skriv\n⌘F Sök · ? Stäng hjälpen"
        ) { page in
            if case .composer(let thread) = state.scope {
                composer(thread)
            } else if page == .usage {
                CodexUsageView(service: service)
            } else {
                threadList
            }
        }
        .onKeyPress(keys: [.leftArrow, .rightArrow], phases: [.down, .repeat]) { key in
            guard state.scope == .deck, state.page != .usage, unmodified(key) else { return .ignored }
            moveThread(key.key == .leftArrow ? -1 : 1)
            return .handled
        }
        .onKeyPress(.return, phases: .down) { key in
            guard state.page != .usage, unmodified(key) else { return .ignored }
            if state.scope == .deck, let thread = selectedThread {
                compose(thread)
                return .handled
            }
            return .ignored
        }
        .onKeyPress(.escape) {
            switch state.scope {
            case .deck: return .ignored
            case .composer: returnToDeck()
            case .search: returnToDeck()
            }
            return .handled
        }
        .background {
            Button("Sök trådar", action: beginSearch).keyboardShortcut("f", modifiers: .command).hidden()
            Button("Uppdatera", action: refreshOrConnect).keyboardShortcut("r", modifiers: .command).hidden()
        }
        .onAppear { isVisible = true }
        .task {
            restoreLocalFocus()
            await service.start()
        }
        .onDisappear {
            isVisible = false
            connectionTask?.cancel()
            service.stop()
        }
    }

    private var threadList: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 12) {
                if state.scope == .search {
                    Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                    TextField("Sök trådar", text: query)
                        .textFieldStyle(.plain)
                        .focused($focus, equals: .search)
                        .onSubmit { if let thread = selectedThread { compose(thread) } }
                        .onKeyPress(.downArrow) { returnToDeck(); return .handled }
                        .onExitCommand { returnToDeck() }
                } else {
                    if !query.wrappedValue.isEmpty {
                        Text(query.wrappedValue).lineLimit(1).foregroundStyle(.secondary)
                    }
                    Text(selectedThread.map { thread in
                        "\((threads.firstIndex(where: { $0.id == thread.id }) ?? 0) + 1) / \(threads.count)"
                    } ?? "")
                    .monospacedDigit().foregroundStyle(.tertiary)
                    Spacer()
                    Button(action: beginSearch) { Image(systemName: "magnifyingglass") }
                        .help("Sök · ⌘F").accessibilityLabel("Sök trådar")
                }
                if state.page == .history {
                    Button { Task { await service.setIncludesArchived(!service.includesArchived) } } label: {
                        Image(systemName: service.includesArchived ? "archivebox.fill" : "archivebox")
                    }
                    .keyboardShortcut("a", modifiers: [.command, .shift])
                    .foregroundStyle(service.includesArchived ? .primary : .secondary)
                    .accessibilityLabel(service.includesArchived ? "Dölj arkiverade trådar" : "Visa arkiverade trådar")
                }
            }
            .font(.system(size: 10)).buttonStyle(.plain)
            .focusable(false)

            if let thread = selectedThread {
                Button { compose(thread) } label: {
                    HStack(spacing: 14) {
                        Image(systemName: thread.isActive ? "waveform" : "bubble.left")
                            .font(.system(size: 28, weight: .light))
                            .foregroundStyle(thread.isActive ? Color.green.opacity(0.8) : .white.opacity(0.4))
                            .frame(width: 36)
                        VStack(alignment: .leading, spacing: 5) {
                            Text(thread.title).font(.system(size: 17, weight: .medium)).lineLimit(2)
                            if !thread.preview.isEmpty {
                                Text(thread.preview).font(.system(size: 11)).foregroundStyle(.secondary).lineLimit(1)
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        Image(systemName: "arrow.turn.down.left").font(.system(size: 13)).foregroundStyle(.tertiary)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain).focusable(false)
                .accessibilityLabel("\(thread.title), \(thread.isActive ? "arbetar" : "tidigare tråd")")
            } else {
                emptyState
            }
            if let error = service.error {
                Text(error).font(.system(size: 10)).foregroundStyle(.orange).lineLimit(1)
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 8) {
            if service.isLoading { ProgressView().controlSize(.small) }
            Text(emptyTitle)
                .font(.system(size: 12, weight: .medium))
            if let error = service.liveError, state.page == .active {
                Text(error).font(.system(size: 10)).foregroundStyle(.secondary).lineLimit(2)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var emptyTitle: String {
        if service.isLoading { return "Hämtar trådar…" }
        if !query.wrappedValue.isEmpty { return "Inga matchande trådar" }
        if state.page == .active, service.liveError != nil { return "Aktiva trådar är inte tillgängliga" }
        return state.page == .active ? "Inga trådar arbetar just nu" : "Inga tidigare trådar"
    }

    private func composer(_ thread: CodexThread) -> some View {
        let draft = Binding(get: { service.drafts[thread.id] ?? "" }, set: { service.drafts[thread.id] = $0 })
        let connected = service.threads.contains { $0.id == thread.id && $0.isConnected }
        let connecting = service.isConnectingThreadID == thread.id
        return VStack(alignment: .leading, spacing: 7) {
            Text(thread.title).font(.system(size: 13, weight: .medium)).lineLimit(1)
            TextEditor(text: draft)
                .font(.system(size: 12))
                .scrollContentBackground(.hidden)
                .padding(5)
                .background(.white.opacity(0.035), in: .rect(cornerRadius: 10))
                .focused($focus, equals: .composer)
                .accessibilityLabel("Meddelande till \(thread.title)")
                .onExitCommand { returnToDeck() }
                .task { await Task.yield(); focus = .composer }
            if let error = service.error {
                Text(error).font(.system(size: 9)).foregroundStyle(.orange).lineLimit(1)
            } else if !connected {
                Text(connecting ? "Ansluter tråden… Du kan skriva under tiden." : "Anslut tråden i Codex för att skicka.")
                    .font(.system(size: 9)).foregroundStyle(.secondary).lineLimit(1)
            }
            HStack {
                Text("esc tillbaka").font(.system(size: 10)).foregroundStyle(.tertiary)
                Spacer()
                if !connected {
                    Button(action: refreshOrConnect) {
                        ShortcutLabel(connecting ? "Ansluter…" : "Anslut", keys: "⌘R")
                    }
                    .buttonStyle(NotchControlStyle())
                    .disabled(service.isConnectingThreadID != nil)
                    .help("Öppna tråden i Codex och anslut den. Utkastet skickas inte.")
                }
                Button {
                    let text = draft.wrappedValue
                    Task {
                        if await service.send(text, to: thread), draft.wrappedValue == text {
                            draft.wrappedValue = ""
                            if case .composer(let recipient) = state.scope, recipient.id == thread.id { returnToDeck() }
                        }
                    }
                } label: { Image(systemName: "arrow.up").font(.system(size: 14, weight: .semibold)) }
                .accessibilityLabel("Skicka meddelande")
                .help("Skicka · ⌘↵")
                .buttonStyle(NotchControlStyle())
                .keyboardShortcut(.return, modifiers: .command)
                .disabled(!connected || service.isSending || draft.wrappedValue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
            .font(.system(size: 11))
        }
    }

    private func beginSearch() {
        connectionTask?.cancel()
        if state.page == .usage { state.page = .history }
        state.scope = .search
        Task { await Task.yield(); focus = .search }
    }

    private func returnToDeck() {
        connectionTask?.cancel()
        state.scope = .deck
        if let thread = selectedThread { state.selection[state.page] = thread.id }
        focus = nil
    }

    private func moveThread(_ offset: Int) {
        guard let selectedThread else { return }
        let ids = threads.map(\.id)
        state.selection[state.page] = adjacentPage(in: ids, to: selectedThread.id, offset: offset)
    }

    private func compose(_ thread: CodexThread) {
        connectionTask?.cancel()
        state.selection[state.page] = thread.id
        state.scope = .composer(thread)
    }

    private func refreshOrConnect() {
        if case .composer(let thread) = state.scope {
            guard service.isConnectingThreadID == nil else { return }
            connectionTask = Task {
                let connected = await service.ensureConnected(to: thread)
                guard connected, !Task.isCancelled, isVisible,
                      case .composer(let recipient) = state.scope, recipient.id == thread.id else { return }
                restoreFocus()
                focus = .composer
            }
        } else {
            Task { await service.refresh() }
        }
    }

    private func restoreLocalFocus() {
        switch state.scope {
        case .deck: break
        case .search: focus = .search
        case .composer: focus = .composer
        }
    }

    private func unmodified(_ key: KeyPress) -> Bool {
        key.modifiers.intersection([.command, .control, .option, .shift]).isEmpty
    }
}
