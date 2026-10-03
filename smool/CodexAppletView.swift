import SwiftUI

enum CodexPage: String, CaseIterable {
    case active = "Aktiva trådar"
    case history = "Tidigare trådar"
    case usage = "Användning"
}

enum CodexScope: Equatable {
    case deck, threads, search
    case composer(CodexThread)
}

@MainActor @Observable
final class CodexAppletState {
    var page = CodexPage.active
    var scope = CodexScope.deck
    var selection: [CodexPage: String] = [:]
    var searches: [CodexPage: String] = [:]
    var usageIndex = 0
}

struct CodexAppletView: View {
    @State private var service: CodexService
    @State private var state: CodexAppletState
    @State private var connectionTask: Task<Void, Never>?
    @State private var isVisible = false
    private let restoreFocus: () -> Void

    private enum Focus: Hashable { case threads, search, composer }
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
        case .composer: "⌘↵ skicka   ·   esc trådar"
        case .search: "Sök efter titel eller innehåll   ·   ↓ trådar   ·   esc tillbaka"
        case .threads: "↑↓ välj tråd   ·   ↵ skriv   ·   ⌘F sök   ·   esc kort"
        case .deck: ""
        }
    }

    var body: some View {
        PageStack(
            pages: CodexPage.allCases,
            selection: $state.page,
            title: { $0.rawValue },
            isNavigating: state.scope == .deck,
            editingHint: editingHint,
            navigationHint: state.page == .usage ? "↑↓ kort   ·   ←→ gränser   ·   ⌘R uppdatera" : "↑↓ kort   ·   ↵ välj tråd   ·   ⌘F sök"
        ) { page in
            if case .composer(let thread) = state.scope {
                composer(thread)
            } else if page == .usage {
                CodexUsageView(service: service, index: $state.usageIndex)
            } else {
                threadList
            }
        }
        .onKeyPress(keys: [.upArrow, .downArrow]) { key in
            guard state.scope == .threads, unmodified(key) else { return .ignored }
            moveThread(key.key == .upArrow ? -1 : 1)
            return .handled
        }
        .onKeyPress(keys: [.leftArrow, .rightArrow]) { key in
            guard state.page == .usage, state.scope == .deck, unmodified(key) else { return .ignored }
            state.usageIndex = min(max(state.usageIndex + (key.key == .leftArrow ? -1 : 1), 0), max(0, (service.limits.count - 1) / 2))
            return .handled
        }
        .onKeyPress(keys: [.return, .tab], phases: .down) { key in
            guard state.page != .usage, unmodified(key) else { return .ignored }
            if state.scope == .deck {
                enterThreads()
                return .handled
            }
            if state.scope == .threads, key.key == .return, let thread = selectedThread {
                compose(thread)
                return .handled
            }
            return .ignored
        }
        .onKeyPress(.escape) {
            switch state.scope {
            case .deck: return .ignored
            case .composer: enterThreads()
            case .search: enterThreads()
            case .threads:
                focus = nil
                state.scope = .deck
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
        VStack(spacing: 6) {
            HStack(spacing: 8) {
                if state.scope == .search {
                    TextField("Sök trådar", text: query)
                        .textFieldStyle(.plain)
                        .font(.system(size: 11))
                        .focused($focus, equals: .search)
                        .onSubmit { if let thread = selectedThread { compose(thread) } }
                        .onKeyPress(keys: [.upArrow, .downArrow]) { key in
                            guard unmodified(key) else { return .ignored }
                            enterThreads()
                            if key.key == .upArrow { moveThread(-1) }
                            return .handled
                        }
                        .onExitCommand { enterThreads() }
                } else {
                    Button(action: beginSearch) {
                        ShortcutLabel(query.wrappedValue.isEmpty ? "Sök trådar" : query.wrappedValue, keys: "⌘F")
                            .lineLimit(1)
                    }
                    .buttonStyle(.plain)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
                if state.page == .history {
                    Button {
                        Task { await service.setIncludesArchived(!service.includesArchived) }
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: service.includesArchived ? "archivebox.fill" : "archivebox")
                            Text("⇧⌘A").font(.system(size: 9, design: .monospaced)).foregroundStyle(.secondary)
                        }
                    }
                    .keyboardShortcut("a", modifiers: [.command, .shift])
                    .buttonStyle(.plain)
                    .foregroundStyle(service.includesArchived ? .primary : .secondary)
                    .accessibilityLabel(service.includesArchived ? "Dölj arkiverade trådar" : "Visa arkiverade trådar")
                    .help("Inkludera arkiverade trådar")
                }
                Text("\(threads.count)")
                    .font(.system(size: 10).monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            .frame(height: 20)

            if threads.isEmpty {
                emptyState
            } else {
                ScrollViewReader { scroll in
                    ScrollView {
                        LazyVStack(spacing: 3) {
                            ForEach(threads) { thread in
                                threadRow(thread).id(thread.id)
                            }
                        }
                    }
                    .scrollIndicators(.hidden)
                    .frame(height: 123)
                    .focusable(state.scope == .threads, interactions: .edit)
                    .focused($focus, equals: .threads)
                    .focusEffectDisabled()
                    .onChange(of: selectedThread?.id) { _, id in
                        if let id { scroll.scrollTo(id) }
                    }
                    .onAppear { if let id = selectedThread?.id { scroll.scrollTo(id) } }
                }
            }
            if let error = service.error {
                Text(error).font(.system(size: 9)).foregroundStyle(.orange).lineLimit(1)
            }
        }
    }

    private func threadRow(_ thread: CodexThread) -> some View {
        let selected = selectedThread?.id == thread.id && state.scope == .threads
        return Button { compose(thread) } label: {
            HStack(spacing: 8) {
                Circle().fill(thread.isActive ? Color.green : .white.opacity(0.2)).frame(width: 4, height: 4)
                VStack(alignment: .leading, spacing: 2) {
                    Text(thread.title).font(.system(size: 11, weight: .medium)).lineLimit(1)
                    Text(thread.preview.isEmpty ? (thread.isArchived ? "Arkiverad tråd" : "Ingen förhandsvisning") : thread.preview)
                        .font(.system(size: 9)).foregroundStyle(.secondary).lineLimit(1)
                }
                Spacer(minLength: 2)
                Text(selected ? "↵" : "")
                    .font(.system(size: 10, design: .monospaced)).foregroundStyle(.secondary)
            }
            .padding(.horizontal, 8)
            .frame(height: 39)
            .background(.white.opacity(selected ? 0.065 : 0), in: .rect(cornerRadius: 10))
            .overlay { RoundedRectangle(cornerRadius: 10).strokeBorder(.white.opacity(selected ? 0.2 : 0), lineWidth: 0.5) }
            .contentShape(.rect(cornerRadius: 10))
        }
        .buttonStyle(.plain)
        .focusable(false)
        .accessibilityLabel("\(thread.title), \(thread.isActive ? "arbetar" : thread.isArchived ? "arkiverad" : "tidigare tråd")")
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    private var emptyState: some View {
        VStack(spacing: 8) {
            if service.isLoading { ProgressView().controlSize(.small) }
            Text(emptyTitle)
                .font(.system(size: 12, weight: .medium))
            if let error = service.liveError, state.page == .active {
                Text(error).font(.system(size: 10)).foregroundStyle(.secondary).lineLimit(2)
            }
            Button { Task { await service.refresh() } } label: {
                ShortcutLabel("Uppdatera", keys: "⌘R")
            }
                .buttonStyle(NotchControlStyle())
        }
        .frame(maxWidth: .infinity, minHeight: 123)
        .focusable(state.scope == .threads, interactions: .edit)
        .focused($focus, equals: .threads)
        .focusEffectDisabled()
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
            Text(thread.title).font(.system(size: 11, weight: .medium)).lineLimit(1)
            TextEditor(text: draft)
                .font(.system(size: 12))
                .scrollContentBackground(.hidden)
                .padding(5)
                .background(.white.opacity(0.035), in: .rect(cornerRadius: 10))
                .focused($focus, equals: .composer)
                .accessibilityLabel("Meddelande till \(thread.title)")
                .onExitCommand { enterThreads() }
                .task { await Task.yield(); focus = .composer }
            if let error = service.error {
                Text(error).font(.system(size: 9)).foregroundStyle(.orange).lineLimit(1)
            } else if !connected {
                Text(connecting ? "Ansluter tråden… Du kan skriva under tiden." : "Anslut tråden i Codex för att skicka.")
                    .font(.system(size: 9)).foregroundStyle(.secondary).lineLimit(1)
            }
            HStack {
                Button(action: enterThreads) { ShortcutLabel("Tillbaka", keys: "esc") }
                    .buttonStyle(.plain)
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
                            if case .composer(let recipient) = state.scope, recipient.id == thread.id { enterThreads() }
                        }
                    }
                } label: { ShortcutLabel(service.isSending ? "Skickar…" : "Skicka", keys: "⌘↵") }
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

    private func enterThreads() {
        connectionTask?.cancel()
        state.scope = .threads
        if let thread = selectedThread { state.selection[state.page] = thread.id }
        Task { await Task.yield(); focus = .threads }
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
        case .threads: focus = .threads
        case .search: focus = .search
        case .composer: focus = .composer
        }
    }

    private func unmodified(_ key: KeyPress) -> Bool {
        key.modifiers.intersection([.command, .control, .option, .shift]).isEmpty
    }
}
