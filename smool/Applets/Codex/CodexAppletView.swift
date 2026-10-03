import SwiftUI

struct CodexAppletView: View {
    @State private var service: CodexService
    @State private var state: CodexAppletState
    @State private var connectionTask: Task<Void, Never>?
    @State private var isVisible = false
    @State private var recipientQuery = ""
    private let restoreFocus: () -> Void

    private enum Focus: Hashable { case search, composer, recipient }
    @FocusState private var focus: Focus?

    init(service: CodexService? = nil, state: CodexAppletState? = nil, restoreFocus: @escaping () -> Void = {}) {
        _service = State(initialValue: service ?? CodexService())
        _state = State(initialValue: state ?? CodexAppletState())
        self.restoreFocus = restoreFocus
    }

    private var query: Binding<String> {
        Binding(get: { state.searches[state.page] ?? "" }, set: { state.searches[state.page] = $0 })
    }

    private var threadSelection: CodexThreadSelection { state.threadSelection(in: service.displayedThreads, projects: service.projects) }

    private var editingHint: String {
        switch state.scope {
        case .composer: "⌘↵ Send   ·   esc Back"
        case .search: "Search titles or content   ·   ↓ Threads   ·   esc Back"
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
            navigationHint: state.page == .usage ? "↑↓ Change page · ⌘K Actions" : "↑↓ Change page · ←→ Select thread · ↵ Write\n⌘P Choose project · ⌘←→ Change project\n⌘F Search · ? Close help"
        ) { page in
            if page == .usage {
                CodexUsageView(service: service)
            } else {
                threadList
            }
        }
        .overlay(alignment: .bottom) {
            if case .composer(let thread) = state.scope {
                composer(thread)
                    .id(thread.id)
                    .padding(NotchLayout.contentInset)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .popover(isPresented: $state.showsRecipientPicker, arrowEdge: .bottom) {
            recipientPicker
        }
        .onChange(of: threadSelection.selectedThread?.id, initial: true) { _, id in
            service.selectThread(id)
            if let id {
                state.selection[state.page] = id
                if state.page == .active { state.retainedActiveThreadIDs = [id] }
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
            Button("Choose project") { state.openProjects() }.keyboardShortcut("p", modifiers: .command).hidden()
            Button("Search threads", action: beginSearch).keyboardShortcut("f", modifiers: .command).hidden()
            Button("Group by project") {
                state.groupsByProject.toggle()
                state.page = .history
                state.scope = .deck
            }
                .keyboardShortcut("p", modifiers: [.command, .shift]).hidden()
            Button("Show archived") {
                state.page = .history
                state.scope = .deck
                Task { await service.setIncludesArchived(!service.includesArchived) }
            }.keyboardShortcut("a", modifiers: [.command, .shift]).hidden()
            Button("Expand") { state.isExpanded.toggle() }.keyboardShortcut("e", modifiers: .command).hidden()
            Button("Next thread") { moveThread(1) }.keyboardShortcut("]", modifiers: .command).hidden()
            Button("Previous thread") { moveThread(-1) }.keyboardShortcut("[", modifiers: .command).hidden()
            Button("Refresh", action: refreshOrConnect).keyboardShortcut("r", modifiers: .command).hidden()
        }
        .onChange(of: state.scope) { _, scope in
            if scope == .search { Task { await Task.yield(); focus = .search } }
        }
        .onAppear {
            isVisible = true
            restoreLocalFocus()
            service.setVisible(true)
        }
        .onDisappear {
            isVisible = false
            connectionTask?.cancel()
            service.setVisible(false)
        }
    }

    private var threadList: some View {
        let selection = threadSelection
        return VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 12) {
                if state.scope == .search {
                    Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                    TextField("Search threads", text: query)
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
                                Text(selection.project?.name ?? "Choose project").lineLimit(1)
                                Image(systemName: "chevron.down").font(.system(size: 8, weight: .semibold))
                            }
                        }
                        .help("Choose project · ⌘P · ⌘←→ Change project")
                        .accessibilityLabel("Project: \(selection.project?.name ?? "Choose project")")
                        .popover(isPresented: $state.showsProjects, arrowEdge: .bottom) {
                            ActionList(title: "Project", actions: service.projects.map { project in
                                AppletAction(id: project.name, symbol: "folder", selected: project.id == selection.project?.id) {
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
                            .accessibilityLabel("Includes archived threads")
                    }
                }
            }
            .font(.system(size: 11, weight: .medium)).buttonStyle(.plain)
            .focusable(false)

            if let thread = selection.selectedThread {
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 8) {
                        ProjectIcon(path: thread.project?.roots.first ?? thread.projectPath, isActive: thread.isActive)
                            .frame(width: 22, height: 22)
                        Text(thread.title).font(.system(size: 14, weight: .semibold)).lineLimit(1)
                        Spacer(minLength: 0)
                        if !service.unreadThreadIDs.subtracting([thread.id]).isEmpty {
                            Circle().fill(.purple).frame(width: 5, height: 5)
                                .accessibilityLabel("New activity in other threads")
                        }
                        Button { state.isExpanded.toggle() } label: {
                            Image(systemName: state.isExpanded ? "arrow.down.right.and.arrow.up.left" : "arrow.up.left.and.arrow.down.right")
                        }
                        .help(state.isExpanded ? "Collapse · ⌘E" : "Expand · ⌘E")
                        .accessibilityLabel(state.isExpanded ? "Collapse feed" : "Expand feed")
                        Button { compose(thread) } label: { Image(systemName: "square.and.pencil") }
                            .help("Write to thread · ↵")
                            .accessibilityLabel("Write to thread")
                    }
                    .buttonStyle(.plain)
                    if let presentation = service.activities[thread.id] {
                        CodexActivityView(presentation: presentation, readingPosition: Binding(
                            get: { state.readingPositions[thread.id] ?? CodexReadingPosition() },
                            set: { state.readingPositions[thread.id] = $0 }
                        ))
                        .id(thread.id)
                    } else {
                        VStack(alignment: .leading, spacing: 6) {
                            Text(thread.preview.isEmpty ? "No activity loaded" : thread.preview)
                                .font(.system(size: 12)).foregroundStyle(.secondary).lineLimit(3)
                            if !thread.isConnected {
                                Button("Connect thread in Codex") { connect(thread) }
                                    .buttonStyle(.plain).font(.system(size: 11))
                            } else { ProgressView().controlSize(.mini) }
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                    }
                    if let issue = service.activityErrors[thread.id] ?? service.liveError {
                        Text(issue).font(.system(size: 10)).foregroundStyle(.orange).lineLimit(2)
                    }
                    threadStatus(thread)
                }
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
        if service.isLoading { return "Loading threads…" }
        if !query.wrappedValue.isEmpty { return "No matching threads" }
        if state.page == .active, service.liveError != nil { return "Active threads are unavailable" }
        return state.page == .active ? "No threads are working right now" : "No previous threads"
    }

    private func composer(_ thread: CodexThread) -> some View {
        let draft = Binding(get: { service.drafts[thread.id] ?? "" }, set: { service.drafts[thread.id] = $0 })
        let connected = service.threads.contains { $0.id == thread.id && $0.isConnected }
        let connecting = service.isConnectingThreadID == thread.id
        return VStack(alignment: .leading, spacing: 10) {
            if let error = service.error {
                Text(error).font(.system(size: 11)).foregroundStyle(.orange).lineLimit(3)
                    .padding(.horizontal, 24)
            } else if !connected {
                HStack {
                    Text(connecting ? "Connecting thread… Your draft is saved." : "Connect the thread in Codex to send.")
                        .font(.system(size: 10)).foregroundStyle(.secondary)
                    Spacer()
                    Button(connecting ? "Connecting…" : "Connect") { connect(thread) }
                        .buttonStyle(NotchControlStyle(isSelected: true))
                        .disabled(service.isConnectingThreadID != nil)
                }
            }

            FloatingComposer(
                text: draft,
                recipient: thread.title,
                placeholder: "Write to Codex…",
                isSending: service.isSending,
                canSend: connected,
                onChooseRecipient: { state.showsRecipientPicker = true },
                onSend: {
                    let text = draft.wrappedValue
                    Task {
                        if await service.send(text, to: thread), draft.wrappedValue == text {
                            draft.wrappedValue = ""
                            if case .composer(let recipient) = state.scope, recipient.id == thread.id { returnToDeck() }
                        }
                    }
                },
                onClose: returnToDeck
            )
        }
    }

    private var recipientPicker: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Choose recipient").font(.headline)
            TextField("Search threads…", text: $recipientQuery)
                .textFieldStyle(.plain)
                .padding(12)
                .background(.white.opacity(0.055), in: .rect(cornerRadius: 12))
                .focused($focus, equals: .recipient)
                .onSubmit { if let thread = recipientThreads.first { chooseRecipient(thread) } }
            if let text = state.pendingText {
                Text(text).font(.system(size: 11)).foregroundStyle(.secondary).lineLimit(2)
            }
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 8) {
                    ForEach(recipientThreads) { thread in
                        Button { chooseRecipient(thread) } label: {
                            Label(thread.title, systemImage: thread.isActive ? "waveform" : "bubble.left")
                                .lineLimit(1).frame(maxWidth: .infinity, minHeight: 32, alignment: .leading)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .frame(maxHeight: 280)
            if service.displayedThreads.isEmpty { Text("Open a thread in Codex to choose a recipient.").foregroundStyle(.secondary) }
        }
        .padding(20).frame(width: 350).preferredColorScheme(.dark)
        .task { await Task.yield(); focus = .recipient }
        .onKeyPress(.escape) { state.showsRecipientPicker = false; return .handled }
    }

    private var recipientThreads: [CodexThread] {
        Array(service.displayedThreads.filter {
            recipientQuery.isEmpty || $0.title.localizedStandardContains(recipientQuery)
        }.prefix(100))
    }

    private func chooseRecipient(_ thread: CodexThread) {
        if let text = state.pendingText {
            let existing = service.drafts[thread.id] ?? ""
            service.drafts[thread.id] = existing.isEmpty ? text : existing + "\n\n" + text
        }
        state.pendingText = nil
        state.showsRecipientPicker = false
        recipientQuery = ""
        state.page = .history
        state.groupsByProject = false
        state.searches[.history] = ""
        compose(thread)
    }

    private func threadStatus(_ thread: CodexThread) -> some View {
        HStack(spacing: 6) {
            if service.threads.contains(where: { $0.id == thread.id && $0.isActive }) {
                ProgressView().controlSize(.mini)
            }
            Text(statusTitle(thread)).font(.system(size: 10)).foregroundStyle(.secondary)
            Spacer()
            if let url = CodexDesktopProtocol.threadURL(thread.id) {
                Link("Open in Codex", destination: url).font(.system(size: 10))
            }
        }
    }

    private func statusTitle(_ thread: CodexThread) -> String {
        guard service.threads.contains(where: { $0.id == thread.id && $0.isConnected }) else {
            return "Disconnected · saved activity"
        }
        switch service.attentionByThread[thread.id] ?? .idle {
        case .idle: return "Done · ↵ Follow up"
        case .working: return "Working"
        case .waitingForUser: return "Waiting for your reply in Codex"
        case .approval: return "Approval needed in Codex"
        case .failed: return "An error needs attention in Codex"
        }
    }

    private func connect(_ thread: CodexThread) {
        guard service.isConnectingThreadID == nil else { return }
        connectionTask = Task {
            _ = await service.ensureConnected(to: thread)
            guard !Task.isCancelled, isVisible else { return }
            restoreFocus()
            restoreLocalFocus()
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
        if let thread = threadSelection.selectedThread { state.selection[state.page] = thread.id }
        focus = nil
    }

    private func moveThread(_ offset: Int) {
        guard state.scope == .deck else { return }
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
