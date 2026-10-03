import SwiftUI

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

    private var threadSelection: CodexThreadSelection { state.threadSelection(in: service.threads, projects: service.projects) }

    private var editingHint: String {
        switch state.scope {
        case .composer: "⌘↵ skicka   ·   esc tillbaka"
        case .search: "Sök efter titel eller innehåll   ·   ↓ trådar   ·   esc tillbaka"
        case .deck: ""
        }
    }

    var body: some View {
        AppletPages(
            pages: CodexPage.allCases,
            selection: $state.page,
            title: { $0.rawValue },
            isNavigating: state.scope == .deck && !state.showsProjects,
            editingHint: editingHint,
            navigationHint: state.page == .usage ? "↑↓ Byt sida · ⌘K Åtgärder" : "↑↓ Byt sida · ←→ Välj tråd · ↵ Skriv\n⌘P Välj projekt · ⌘←→ Byt projekt\n⌘F Sök · ? Stäng hjälpen"
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
            guard state.scope == .deck, !state.showsProjects, state.page != .usage, unmodified(key) else { return .ignored }
            moveThread(key.key == .leftArrow ? -1 : 1)
            return .handled
        }
        .onKeyPress(.return, phases: .down) { key in
            guard state.page != .usage, !state.showsProjects, unmodified(key) else { return .ignored }
            if state.scope == .deck, let thread = threadSelection.selectedThread {
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
            Button("Välj projekt") { state.openProjects() }.keyboardShortcut("p", modifiers: .command).hidden()
            Button("Sök trådar", action: beginSearch).keyboardShortcut("f", modifiers: .command).hidden()
            Button("Gruppera per projekt") {
                state.groupsByProject.toggle()
                state.page = .history
                state.scope = .deck
            }
                .keyboardShortcut("p", modifiers: [.command, .shift]).hidden()
            Button("Visa arkiverade") {
                state.page = .history
                state.scope = .deck
                Task { await service.setIncludesArchived(!service.includesArchived) }
            }.keyboardShortcut("a", modifiers: [.command, .shift]).hidden()
            Button("Uppdatera", action: refreshOrConnect).keyboardShortcut("r", modifiers: .command).hidden()
        }
        .onChange(of: state.scope) { _, scope in
            if scope == .search { Task { await Task.yield(); focus = .search } }
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
        let selection = threadSelection
        return VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 12) {
                if state.scope == .search {
                    Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                    TextField("Sök trådar", text: query)
                        .textFieldStyle(.plain)
                        .focused($focus, equals: .search)
                        .onSubmit { if let thread = threadSelection.selectedThread { compose(thread) } }
                        .onKeyPress(.downArrow) { returnToDeck(); return .handled }
                        .onKeyPress(.escape) { returnToDeck(); return .handled }
                } else {
                    if state.page == .history && state.groupsByProject {
                        Button { state.showsProjects = true } label: {
                            HStack(spacing: 5) {
                                Image(systemName: "folder")
                                Text(selection.project?.name ?? "Välj projekt").lineLimit(1)
                                Image(systemName: "chevron.down").font(.system(size: 8, weight: .semibold))
                            }
                        }
                        .help("Välj projekt · ⌘P · ⌘←→ byter projekt")
                        .accessibilityLabel("Projekt: \(selection.project?.name ?? "Välj projekt")")
                        .popover(isPresented: $state.showsProjects, arrowEdge: .bottom) {
                            ActionList(title: "Projekt", actions: service.projects.map { project in
                                NotchAction(id: project.name, symbol: "folder", selected: project.id == selection.project?.id) {
                                    state.selectProject(project)
                                }
                            }) { state.showsProjects = false }
                            .preferredColorScheme(.dark)
                        }
                    } else {
                        Text(state.page.rawValue).foregroundStyle(.secondary).lineLimit(1)
                    }
                    if !query.wrappedValue.isEmpty {
                        Text(query.wrappedValue).lineLimit(1).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Text(selection.selectedIndex.map { "\($0 + 1) / \(selection.threads.count)" } ?? "")
                    .monospacedDigit().foregroundStyle(.tertiary)
                    if service.includesArchived, state.page == .history {
                        Image(systemName: "archivebox").foregroundStyle(.secondary)
                            .accessibilityLabel("Inkluderar arkiverade trådar")
                    }
                }
            }
            .font(.system(size: 10)).buttonStyle(.plain)
            .focusable(false)

            if let thread = selection.selectedThread {
                Button { compose(thread) } label: {
                    HStack(spacing: 14) {
                        ProjectIcon(path: thread.project?.roots.first ?? thread.projectPath, isActive: thread.isActive)
                            .frame(width: 42, height: 42)
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
            if let error = service.error ?? (state.groupsByProject ? service.projectError : nil) {
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
        return VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                ProjectIcon(path: thread.project?.roots.first ?? thread.projectPath, isActive: thread.isActive).frame(width: 20, height: 20)
                Text(thread.title).font(.system(size: 12, weight: .medium)).lineLimit(1)
                Spacer()
            }
            HStack(alignment: .bottom, spacing: 10) {
                TextField("Skriv till Codex…", text: draft, axis: .vertical)
                    .textFieldStyle(.plain)
                    .font(.system(size: 13))
                    .lineLimit(1...5)
                    .focused($focus, equals: .composer)
                    .accessibilityLabel("Meddelande till \(thread.title)")
                    .onKeyPress(.escape) { returnToDeck(); return .handled }
                    .task { await Task.yield(); focus = .composer }
                Button {
                    let text = draft.wrappedValue
                    Task {
                        if await service.send(text, to: thread), draft.wrappedValue == text {
                            draft.wrappedValue = ""
                            if case .composer(let recipient) = state.scope, recipient.id == thread.id { returnToDeck() }
                        }
                    }
                } label: {
                    if service.isSending { ProgressView().controlSize(.mini).frame(width: 24, height: 24) }
                    else { Image(systemName: "arrow.up").font(.system(size: 13, weight: .semibold)).frame(width: 24, height: 24) }
                }
                .buttonStyle(.plain)
                .background(.white.opacity(0.09), in: .circle)
                .accessibilityLabel("Skicka meddelande").help("Skicka · ⌘↵")
                .keyboardShortcut(.return, modifiers: .command)
                .disabled(!connected || service.isSending || draft.wrappedValue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
            .padding(14)
            .modifier(CardGlass(shape: RoundedRectangle(cornerRadius: 18), isSelected: true))
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
            }
            .font(.system(size: 11))
        }
        .fixedSize(horizontal: false, vertical: true)
        .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { state.composerHeight = $0 }
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
        if let thread = threadSelection.selectedThread { state.selection[state.page] = thread.id }
        focus = nil
    }

    private func moveThread(_ offset: Int) {
        let selection = threadSelection
        guard let selectedThread = selection.selectedThread else { return }
        let ids = selection.threads.map(\.id)
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
