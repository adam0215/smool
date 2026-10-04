import SwiftUI

struct CodexAppletView: View {
    @State private var service: CodexService
    @State private var state: CodexAppletState
    @State private var connectionTask: Task<Void, Never>?
    @State private var isVisible = false
    @State private var recipientQuery = ""
    @State private var recipientIndex = 0
    private let restoreFocus: () -> Void

    private enum Focus: Hashable { case deck, search, composer, recipient, recipientList }
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
    private var liveThreadID: String? { state.page == .active ? threadSelection.selectedThread?.id : nil }
    private var historyThread: CodexThread? { state.page == .history ? threadSelection.selectedThread : nil }
    private var localRequests: [CodexSessionRequest] {
        guard let thread = threadSelection.selectedThread else { return [] }
        return service.localRequests(for: thread.id)
    }
    private var selectedRequest: CodexSessionRequest? {
        localRequests.first { $0.id == state.requestID } ?? localRequests.first
    }
    private var previewThread: CodexThread? {
        guard let thread = threadSelection.selectedThread else { return nil }
        if state.page == .history { return thread }
        guard state.page == .active, service.activities[thread.id]?.latestMessage == nil,
              activityIssue(for: thread.id) != nil else { return nil }
        return service.threads.first { $0.id == thread.id } ?? thread
    }

    private func activityIssue(for id: String) -> String? {
        service.activityErrors[id]
            ?? (service.threads.first { $0.id == id }?.isConnected != true
                ? service.liveError ?? "Live activity is unavailable." : nil)
    }

    private var editingHint: String {
        switch state.scope {
        case .composer, .newThread: "⇧↵ New line"
        case .search: "Search titles or content"
        case .deck, .request: ""
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            if state.showsProjects {
                projectPicker
            } else if state.showsRecipientPicker {
                recipientPicker
            } else if state.scope == .request, let request = selectedRequest {
                sessionRequest(request)
            } else {
                AppletPages(
                    pages: CodexPage.allCases,
                    selection: $state.page,
                    title: { $0.rawValue },
                    isNavigating: state.scope == .deck && !state.showsProjects && !state.showsRecipientPicker,
                    editingHint: editingHint,
                    navigationHint: state.page == .usage ? "⌘K Actions" : "⌘N Write · ⌘F Search · ⌘P Choose project"
                ) { page in
                    if page == .usage {
                        CodexUsageView(service: service)
                    } else if page == .newThread {
                        newThreadPage
                    } else {
                        threadList
                    }
                }
                .focusable(interactions: .edit)
                .focused($focus, equals: .deck)
                .focusEffectDisabled()
                .onAppletFocusRestore {
                    guard !state.showsProjects, !state.showsRecipientPicker else { return }
                    if case .composer = state.scope { return }
                    if state.scope == .newThread { return }
                    focus = .deck
                }
                .overlay(alignment: .bottom) {
                    if case .composer(let thread) = state.scope {
                        composer(thread)
                            .id(thread.id)
                            .padding(.horizontal, 40)
                            .padding(.bottom, 40)
                            .transition(.move(edge: .bottom).combined(with: .opacity))
                    }
                }
            }
        }
        .onChange(of: threadSelection.selectedThread?.id, initial: true) { _, id in
            if let id {
                state.selection[state.page] = id
                if state.page == .active { state.retainedActiveThreadIDs = [id] }
            }
        }
        .onChange(of: liveThreadID, initial: true) { _, id in service.selectThread(id) }
        .onChange(of: selectedRequest?.id) { _, id in
            if id == nil, state.scope == .request { returnToDeck() }
        }
        .task(id: previewThread) {
            guard let thread = previewThread else { return }
            await service.loadHistoryPreview(thread)
            if !Task.isCancelled, historyThread?.id == thread.id, service.historyPreviews[thread.id]?.message != nil {
                service.markRead(thread.id)
            }
        }
        .onKeyPress(keys: [.leftArrow, .rightArrow], phases: [.down, .repeat]) { key in
            guard state.scope == .deck, !state.showsProjects, !state.showsRecipientPicker, (state.page == .active || state.page == .history), unmodified(key) else { return .ignored }
            moveThread(key.key == .leftArrow ? -1 : 1)
            return .handled
        }
        .onKeyPress(keys: [.upArrow, .downArrow], phases: [.down, .repeat]) { key in
            guard state.scope == .deck, !state.showsProjects, !state.showsRecipientPicker else { return .ignored }
            guard unmodified(key) else { return .ignored }
            let offset = key.key == .upArrow ? -1 : 1
            state.page = cyclingPage(in: CodexPage.allCases, to: state.page, offset: offset)
            return .handled
        }
        .onKeyPress(.return, phases: .down) { key in
            guard state.page != .usage, !state.showsProjects, !state.showsRecipientPicker, unmodified(key) else { return .ignored }
            if state.page == .newThread, state.scope == .deck {
                state.scope = .newThread
                return .handled
            }
            if state.scope == .search, focus == .deck {
                focus = .search
                return .handled
            }
            if state.scope == .deck, let thread = threadSelection.selectedThread {
                open(thread)
                return .handled
            }
            return .ignored
        }
        .onKeyPress(.escape) {
            switch state.scope {
            case .deck: return .ignored
            case .composer, .newThread, .request: returnToDeck()
            case .search: returnToDeck()
            }
            return .handled
        }
        .background {
            Button("Choose project") { state.openProjects() }.keyboardShortcut("p", modifiers: .command).hidden()
            Button("Search threads", action: beginSearch)
                .keyboardShortcut("f", modifiers: .command)
                .disabled(state.showsProjects || state.showsRecipientPicker).hidden()
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
            Button("Write to thread") {
                if state.page == .newThread { state.scope = .newThread }
                else if let thread = threadSelection.selectedThread { compose(thread) }
            }
            .keyboardShortcut("n", modifiers: .command)
            .disabled(state.page == .usage || (state.page != .newThread && threadSelection.selectedThread == nil) || state.showsProjects || state.showsRecipientPicker)
            .hidden()
            Button("Next thread") { moveThread(1) }.keyboardShortcut("]", modifiers: .command).hidden()
            Button("Previous thread") { moveThread(-1) }.keyboardShortcut("[", modifiers: .command).hidden()
            Button("Refresh", action: refreshOrConnect).keyboardShortcut("r", modifiers: .command).hidden()
            Button("Open in Codex") {
                if let id = threadSelection.selectedThread?.id, !service.isLocallyOwned(id),
                   let url = CodexDesktopProtocol.threadURL(id) {
                    NSWorkspace.shared.open(url)
                }
            }.keyboardShortcut("o", modifiers: [.command, .shift]).hidden()
            Button("Stop turn") {
                guard let thread = threadSelection.selectedThread else { return }
                Task { await service.cancelLocalTurn(thread.id) }
            }
            .keyboardShortcut(".", modifiers: .command)
            .disabled(threadSelection.selectedThread.map { !service.isLocallyOwned($0.id) } ?? true)
            .hidden()
        }
        .onChange(of: state.scope) { _, scope in
            if scope == .search { Task { await Task.yield(); focus = .search } }
            else if scope == .deck { focus = nil; restoreFocus() }
        }
        .onAppear {
            isVisible = true
            restoreLocalFocus()
            service.setVisible(true)
        }
        .onDisappear {
            isVisible = false
            connectionTask?.cancel()
            service.selectThread(nil)
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
                        .onSubmit { if let thread = threadSelection.selectedThread { open(thread) } }
                        .onKeyPress(.downArrow, phases: .down) { key in
                            guard unmodified(key) else { return .ignored }
                            returnToDeck()
                            return .handled
                        }
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
                let currentThread = service.threads.first { $0.id == thread.id }
                let isWorking = currentThread?.isConnected == true && currentThread?.isActive == true
                VStack(alignment: .leading, spacing: 10) {
                    if state.page == .history {
                        let preview = service.historyPreviews[thread.id]
                        CodexHistoryPreviewView(
                            title: thread.title,
                            message: preview?.message,
                            isLoading: preview == nil || preview?.isLoading == true,
                            isWorking: isWorking,
                            error: preview?.error
                        )
                    } else {
                        ShimmeringText(thread.title, isActive: isWorking)
                            .font(.system(size: 17, weight: .medium))
                            .foregroundStyle(isWorking ? .secondary : .primary)
                            .lineLimit(1)
                        let issue = activityIssue(for: thread.id)
                        if let presentation = service.activities[thread.id], presentation.latestMessage != nil || issue == nil {
                            CodexActivityView(
                                presentation: presentation,
                                isLive: currentThread?.isConnected == true && issue == nil
                                    && (service.attentionByThread[thread.id] == .working || service.isLocallyOwned(thread.id)),
                                unavailableReason: issue
                            )
                        } else if let issue {
                            let preview = service.historyPreviews[thread.id]
                            VStack(alignment: .leading, spacing: 14) {
                                CodexMessagePreviewView(message: preview?.message,
                                                        isLoading: preview == nil || preview?.isLoading == true,
                                                        error: preview?.error)
                                Text(issue)
                                    .font(.system(size: 11))
                                    .foregroundStyle(.secondary)
                                    .lineLimit(2)
                            }
                            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                        } else {
                            ShimmeringText("Reading activity…")
                                .font(.system(size: 12))
                                .foregroundStyle(.secondary)
                                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                        }
                    }

                    if state.scope == .deck, let request = localRequests.first {
                        Button {
                            state.requestID = request.id
                            state.scope = .request
                        } label: {
                            Label(request.title, systemImage: "bubble.left.and.exclamationmark.bubble.right")
                                .font(.system(size: 12, weight: .medium))
                                .foregroundStyle(.orange)
                        }
                        .buttonStyle(.plain)
                    } else if state.scope == .deck {
                        Text("⌘N Write")
                            .font(.system(size: 10))
                            .foregroundStyle(.secondary)
                            .padding(.top, 4)
                    }
                }
            } else {
                emptyState
            }
            if state.groupsByProject, let error = service.projectError {
                Text(error).font(.system(size: 10)).foregroundStyle(.secondary).lineLimit(1)
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 8) {
            ShimmeringText(emptyTitle, isActive: service.isLoading)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.secondary)
            if let error = service.error ?? (state.page == .active ? service.liveError : nil) {
                Text(error).font(.system(size: 10)).foregroundStyle(.secondary).lineLimit(2)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var emptyTitle: String {
        if service.isLoading { return "Loading threads…" }
        if !query.wrappedValue.isEmpty { return "No matching threads" }
        if service.error != nil { return "Threads are unavailable" }
        if state.page == .active, service.liveError != nil { return "Active threads are unavailable" }
        return state.page == .active ? "No threads are working right now" : "No previous threads"
    }

    private func composer(_ thread: CodexThread) -> some View {
        let draft = Binding(get: { service.drafts[thread.id] ?? "" }, set: { service.drafts[thread.id] = $0 })
        let connected = service.threads.contains { $0.id == thread.id && $0.isConnected }
        let connecting = service.isConnectingThreadID == thread.id
        return VStack(alignment: .leading, spacing: 10) {
            if let error = state.sendErrors[thread.id] {
                Text(error).font(.system(size: 11)).foregroundStyle(.orange).lineLimit(3)
                    .padding(.horizontal, 24)
            } else if !connected {
                ShimmeringText(connecting ? "Connecting thread… Your draft is saved." : "⌘R Connect thread", isActive: connecting)
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 24)
            }

            FloatingComposer(
                text: draft,
                recipient: thread.title,
                placeholder: "Write to Codex…",
                isSending: service.isSending,
                canSend: connected,
                onSend: {
                    let text = draft.wrappedValue
                    Task {
                        state.sendErrors[thread.id] = nil
                        if await service.send(text, to: thread) {
                            if draft.wrappedValue == text {
                                draft.wrappedValue = ""
                                if case .composer(let recipient) = state.scope, recipient.id == thread.id { returnToDeck() }
                            }
                        } else {
                            state.sendErrors[thread.id] = service.error
                        }
                    }
                },
                onClose: returnToDeck
            )
        }
    }

    private var pickerProjects: [CodexProject] {
        state.page == .newThread ? service.projects.filter { !$0.roots.isEmpty } : service.projects
    }

    private var newThreadPage: some View {
        @Bindable var draft = state.newThread
        let project = draft.thread?.project ?? state.selectedProject(in: service.projects)
        return VStack(alignment: .leading, spacing: 12) {
            Button { state.openProjects() } label: {
                HStack(spacing: 6) {
                    Image(systemName: "folder")
                    Text(project?.name ?? "Choose project").lineLimit(1)
                    Image(systemName: "chevron.down").font(.system(size: 8, weight: .semibold))
                }
                .font(.system(size: 12))
            }
            .buttonStyle(.plain)
            .disabled(draft.isSubmitting || draft.thread != nil)
            .help("Choose project · ⌘P")

            Spacer(minLength: 0)

            if let error = draft.error {
                Text(error).font(.system(size: 11)).foregroundStyle(.orange).lineLimit(3).help(error)
                if draft.needsReview {
                    Button("I checked Codex · Allow retry") { draft.allowRetryAfterReview() }
                        .font(.system(size: 11)).buttonStyle(.plain)
                }
            } else if draft.isSubmitting {
                ShimmeringText("Starting thread…")
                    .font(.system(size: 11)).foregroundStyle(.secondary)
            } else if project == nil {
                Text(service.projectError ?? "Add a local project in Codex to start a thread here.")
                    .font(.system(size: 11)).foregroundStyle(.secondary)
            }

            FloatingComposer(
                text: $draft.text,
                recipient: "Codex",
                placeholder: "Start a new thread…",
                isEditable: !draft.isSubmitting,
                isSending: draft.isSubmitting,
                canSend: project != nil && !draft.needsReview,
                isEditing: state.scope == .newThread,
                onBeginEditing: { state.scope = .newThread },
                onSend: {
                    Task {
                        let thread = await draft.submit(project: project, create: service.createThread, send: service.sendInitialMessage)
                        guard let thread else { return }
                        service.drafts[thread.id] = draft.text
                        if isVisible, state.page == .newThread {
                            state.page = .active
                            state.selection[.active] = thread.id
                            state.retainedActiveThreadIDs = [thread.id]
                            returnToDeck()
                        }
                    }
                },
                onClose: returnToDeck
            )
        }
        .padding(.horizontal, 12)
        .padding(.bottom, 16)
    }

    private var projectPicker: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Choose project").font(.system(size: 13, weight: .semibold))
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 4) {
                        ForEach(pickerProjects) { project in
                            Button {
                                state.selectProject(project)
                                state.showsProjects = false
                                restoreFocus()
                            } label: {
                                HStack {
                                    Label(project.name, systemImage: "folder")
                                    Spacer()
                                    if state.selectedProject(in: service.projects)?.id == project.id {
                                        Image(systemName: "checkmark")
                                    }
                                }
                                .font(.system(size: 12))
                                .padding(.vertical, 8)
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            .id(project.id)
                        }
                    }
                }
                .onChange(of: state.selectedProject(in: pickerProjects)?.id) { _, id in
                    if let id { proxy.scrollTo(id) }
                }
            }
        }
        .padding(.horizontal, 32)
        .padding(.top, 16)
        .padding(.bottom, 28)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .focusable(interactions: .edit)
        .focused($focus, equals: .recipientList)
        .focusEffectDisabled()
        .onAppletFocusRestore { focus = .recipientList }
        .task { await Task.yield(); focus = .recipientList }
        .onKeyPress(keys: [.upArrow, .downArrow]) { key in
            guard unmodified(key) else { return .ignored }
            state.moveProject(key.key == .upArrow ? -1 : 1, in: pickerProjects)
            return .handled
        }
        .onKeyPress(.return) { state.showsProjects = false; returnToDeck(); return .handled }
        .onKeyPress(.escape) { state.showsProjects = false; returnToDeck(); return .handled }
    }

    private var recipientPicker: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Choose recipient").font(.headline)
            TextField("Search threads…", text: $recipientQuery)
                .textFieldStyle(.plain)
                .padding(.vertical, 6)
                .focused($focus, equals: .recipient)
                .onSubmit { chooseHighlightedRecipient() }
            if state.choosesPendingRecipient, let text = state.pendingText {
                Text(text).font(.system(size: 11)).foregroundStyle(.secondary).lineLimit(2)
            }
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 8) {
                        ForEach(Array(recipientThreads.enumerated()), id: \.element.id) { index, thread in
                            Button { chooseRecipient(thread) } label: {
                                HStack {
                                    Label(thread.title, systemImage: thread.isActive ? "waveform" : "bubble.left")
                                    Spacer(minLength: 4)
                                    if index == recipientIndex { Image(systemName: "return") }
                                }
                                .font(.system(size: 12))
                                .lineLimit(1).frame(maxWidth: .infinity, minHeight: 32, alignment: .leading)
                                .foregroundStyle(index == recipientIndex ? .primary : .secondary)
                            }
                            .buttonStyle(.plain)
                            .id(index)
                        }
                    }
                }
                .onChange(of: recipientIndex) { _, index in proxy.scrollTo(index) }
            }
            .frame(maxHeight: .infinity)
            Text("⌘F Search")
                .font(.system(size: 10)).foregroundStyle(.secondary)
            if recipientThreads.isEmpty {
                Text(service.displayedThreads.isEmpty ? "Open a thread in Codex to choose a recipient." : "No matching threads")
                    .font(.system(size: 11)).foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 32)
        .padding(.top, 16)
        .padding(.bottom, 28)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .preferredColorScheme(.dark)
        .onChange(of: recipientQuery) { _, _ in recipientIndex = 0 }
        .focusable(interactions: .edit)
        .focused($focus, equals: .recipientList)
        .focusEffectDisabled()
        .onAppletFocusRestore { focus = .recipientList }
        .background {
            Button("Search recipients") { focus = .recipient }
                .keyboardShortcut("f", modifiers: .command).hidden()
        }
        .onKeyPress(keys: [.upArrow, .downArrow]) { key in
            guard unmodified(key) else { return .ignored }
            recipientIndex = min(max(recipientIndex + (key.key == .upArrow ? -1 : 1), 0), max(0, recipientThreads.count - 1))
            return .handled
        }
        .onKeyPress(.return) { chooseHighlightedRecipient(); return .handled }
        .task { await Task.yield(); focus = .recipient }
        .onKeyPress(.escape) {
            state.showsRecipientPicker = false
            focus = nil
            restoreFocus()
            return .handled
        }
    }

    private func chooseHighlightedRecipient() {
        guard recipientThreads.indices.contains(recipientIndex) else { return }
        chooseRecipient(recipientThreads[recipientIndex])
    }

    private var recipientThreads: [CodexThread] {
        Array(service.displayedThreads.filter {
            recipientQuery.isEmpty || $0.title.localizedStandardContains(recipientQuery)
        }.prefix(100))
    }

    private func chooseRecipient(_ thread: CodexThread) {
        if state.choosesPendingRecipient, let text = state.pendingText {
            let existing = service.drafts[thread.id] ?? ""
            service.drafts[thread.id] = existing.isEmpty ? text : existing + "\n\n" + text
            state.pendingText = nil
        }
        state.showsRecipientPicker = false
        recipientQuery = ""
        state.page = .history
        state.groupsByProject = false
        state.searches[.history] = ""
        compose(thread)
    }

    private func open(_ thread: CodexThread) {
        if service.isLocallyOwned(thread.id) {
            if let request = localRequests.first {
                state.requestID = request.id
                state.scope = .request
            } else {
                compose(thread)
            }
            return
        }
        if let url = CodexDesktopProtocol.threadURL(thread.id) { NSWorkspace.shared.open(url) }
    }

    private func sessionRequest(_ request: CodexSessionRequest) -> some View {
        let key = request.threadID + ":" + request.id
        return CodexSessionRequestView(
            request: request,
            answers: Binding(get: { state.requestAnswers[key] ?? [:] }, set: { state.requestAnswers[key] = $0 }),
            error: service.error,
            respond: { decision in
                service.respond(to: request, decision: decision)
                if !service.localRequests(for: request.threadID).contains(where: { $0.id == request.id }) {
                    state.requestAnswers[key] = nil
                    returnToDeck()
                }
            },
            close: returnToDeck
        )
        .id(key)
    }

    private func beginSearch() {
        connectionTask?.cancel()
        if state.page == .usage || state.page == .newThread { state.page = .history }
        state.scope = .search
        Task { await Task.yield(); focus = .search }
    }

    private func returnToDeck() {
        guard state.scope != .deck else { return }
        connectionTask?.cancel()
        state.scope = .deck
        if let thread = threadSelection.selectedThread { state.selection[state.page] = thread.id }
        focus = nil
        restoreFocus()
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
                state.sendErrors[thread.id] = nil
                let connected = await service.ensureConnected(to: thread)
                if !connected { state.sendErrors[thread.id] = service.error }
                guard connected, !Task.isCancelled, isVisible,
                      case .composer(let recipient) = state.scope, recipient.id == thread.id else { return }
                focus = .composer
            }
        } else {
            Task {
                await service.refresh()
                if let thread = previewThread { await service.loadHistoryPreview(thread, force: true) }
            }
        }
    }

    private func restoreLocalFocus() {
        switch state.scope {
        case .deck, .request: break
        case .search: focus = .search
        case .composer, .newThread: focus = .composer
        }
    }

    private func unmodified(_ key: KeyPress) -> Bool {
        key.modifiers.intersection([.command, .control, .option, .shift]).isEmpty
    }
}
