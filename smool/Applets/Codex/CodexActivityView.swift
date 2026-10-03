import SwiftUI

struct CodexActivityGroup: Identifiable {
    var items: [CodexActivityItem]
    var id: String { items[0].id }
    var isToolGroup: Bool { items[0].kind == .tool }

    static func make(from items: [CodexActivityItem]) -> [Self] {
        var groups: [Self] = []
        for item in items {
            if item.kind == .tool, let last = groups.indices.last, groups[last].isToolGroup {
                groups[last].items.append(item)
            } else {
                groups.append(Self(items: [item]))
            }
        }
        return groups
    }
}

/// The notch starts with one update. The full transcript keeps its own reading position.
struct CodexActivitySummary: View {
    let presentation: CodexActivityPresentation
    let selectedID: String?

    static func selectedGroup(in groups: [CodexActivityGroup], id: String?) -> CodexActivityGroup? {
        if let id, let selected = groups.first(where: { $0.id == id }) { return selected }
        return groups.last { !$0.isToolGroup } ?? groups.last
    }

    var body: some View {
        let groups = CodexActivityGroup.make(from: presentation.items)
        let selected = Self.selectedGroup(in: groups, id: selectedID)

        VStack(alignment: .leading, spacing: 10) {
            if let selected, let item = selected.items.last {
                HStack(spacing: 6) {
                    Text(selected.isToolGroup ? "Activity" : item.kind == .user ? "You" : item.title)
                    Spacer(minLength: 8)
                    if let index = groups.firstIndex(where: { $0.id == selected.id }) {
                        Text("\(index + 1) / \(groups.count)").monospacedDigit()
                    }
                }
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(.secondary)

                Text(activityMarkdown(item.text.isEmpty ? item.title : item.text))
                    .font(.system(size: 14))
                    .lineSpacing(3)
                    .lineLimit(3)
                    .frame(maxWidth: .infinity, alignment: .leading)

                if selectedID == nil, let latest = groups.last, latest.isToolGroup,
                   latest.id != selected.id, let tool = latest.items.last {
                    Label(tool.title, systemImage: tool.isError ? "exclamationmark.circle" : tool.isRunning ? "ellipsis" : "checkmark")
                        .font(.system(size: 10))
                        .foregroundStyle(tool.isError ? Color.orange : Color.secondary)
                        .lineLimit(1)
                }
            } else {
                Text("Activity appears when Codex shares this thread.")
                    .font(.system(size: 13)).foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .accessibilityElement(children: .combine)
    }
}

struct CodexActivityView: View {
    let presentation: CodexActivityPresentation
    @Binding var readingPosition: CodexReadingPosition
    var selectedActivityID: String? = nil
    let onFollowLatest: () -> Void
    @State private var scrollPosition = ScrollPosition(idType: String.self)
    @State private var scrollPhase = ScrollPhase.idle
    @State private var restoredPosition = false

    private var groups: [CodexActivityGroup] { CodexActivityGroup.make(from: presentation.items) }
    private var userIsScrolling: Bool {
        scrollPhase == .tracking || scrollPhase == .interacting || scrollPhase == .decelerating
    }

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 20) {
                if presentation.omittedItemCount > 0 {
                    Text("Older activity is available in Codex")
                        .font(.system(size: 10)).foregroundStyle(.tertiary)
                }
                ForEach(groups) { group in
                    if group.isToolGroup {
                        toolGroup(group)
                    } else if let item = group.items.first {
                        CodexActivityMessage(item: item)
                    }
                }
                if presentation.items.isEmpty {
                    Text("Activity appears when Codex shares the thread content.")
                        .font(.system(size: 12)).foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .scrollTargetLayout()
            .padding(.vertical, 8)
            .padding(.horizontal, 2)
        }
        .scrollPosition($scrollPosition)
        .scrollIndicators(.hidden)
        .defaultScrollAnchor(.bottom, for: .initialOffset)
        .onScrollGeometryChange(for: ActivityViewport.self) { geometry in
            ActivityViewport(
                offset: geometry.contentOffset.y,
                height: geometry.contentSize.height,
                atBottom: geometry.visibleRect.maxY >= geometry.contentSize.height - 24
            )
        } action: { previous, current in
            guard restoredPosition else { return }
            if userIsScrolling {
                readingPosition.userScrolled(to: current.offset, atBottom: current.atBottom)
            } else if readingPosition.followsLatest, previous.height != current.height {
                scrollPosition.scrollTo(edge: .bottom)
            }
        }
        .onScrollPhaseChange { previous, next, context in
            scrollPhase = next
            if next == .idle, previous == .interacting || previous == .decelerating, restoredPosition {
                let geometry = context.geometry
                readingPosition.userScrolled(
                    to: geometry.contentOffset.y,
                    atBottom: geometry.visibleRect.maxY >= geometry.contentSize.height - 24
                )
            }
        }
        .onScrollTargetVisibilityChange(idType: String.self, threshold: 0.01) { visibleIDs in
            guard restoredPosition, userIsScrolling else { return }
            readingPosition.anchorID = groups.first { visibleIDs.contains($0.id) }?.id
        }
        .onChange(of: selectedActivityID) { _, id in
            if let id {
                readingPosition.followsLatest = false
                readingPosition.anchorID = id
                scrollPosition.scrollTo(id: id, anchor: .top)
            }
        }
        .onChange(of: readingPosition.followsLatest) { _, followsLatest in
            guard followsLatest else { return }
            onFollowLatest()
            scrollPosition.scrollTo(edge: .bottom)
        }
        .onChange(of: presentation.items) { _, _ in
            readingPosition.receive(revision: presentation.revision)
            readingPosition.expandedGroups.formIntersection(groups.map(\.id))
            if restoredPosition, readingPosition.followsLatest, !userIsScrolling {
                scrollPosition.scrollTo(edge: .bottom)
            }
        }
        .onChange(of: presentation.omittedItemCount) { _, count in
            guard restoredPosition else { return }
            if !readingPosition.followsLatest, let anchor = readingPosition.anchorID {
                scrollPosition.scrollTo(id: anchor, anchor: .top)
            }
            readingPosition.omittedItemCount = count
        }
        .overlay(alignment: .bottom) {
            if readingPosition.hasNewActivity {
                Button {
                    onFollowLatest()
                    scrollPosition.scrollTo(edge: .bottom)
                } label: {
                    Label("New activity", systemImage: "arrow.down")
                        .font(.system(size: 11, weight: .medium))
                }
                .buttonStyle(FloatingControlStyle())
                .padding(.bottom, 4)
                .accessibilityHint("Jump to the latest activity and follow updates")
            }
        }
        .task(id: presentation.items.isEmpty) {
            guard !presentation.items.isEmpty, !restoredPosition else { return }
            await Task.yield()
            guard !Task.isCancelled else { return }
            if readingPosition.followsLatest {
                scrollPosition.scrollTo(edge: .bottom)
            } else if readingPosition.omittedItemCount != presentation.omittedItemCount,
                      let anchor = readingPosition.anchorID {
                scrollPosition.scrollTo(id: anchor, anchor: .top)
            } else {
                scrollPosition.scrollTo(y: readingPosition.contentOffset)
            }
            readingPosition.receive(revision: presentation.revision)
            readingPosition.omittedItemCount = presentation.omittedItemCount
            restoredPosition = true
        }
    }

    private func toolGroup(_ group: CodexActivityGroup) -> some View {
        let expanded = Binding(
            get: { readingPosition.expandedGroups.contains(group.id) },
            set: { value in
                if value { readingPosition.expandedGroups.insert(group.id) }
                else { readingPosition.expandedGroups.remove(group.id) }
            }
        )
        let running = group.items.last { $0.isRunning }
        let failed = group.items.contains { $0.isError }
        return DisclosureGroup(isExpanded: expanded) {
            VStack(alignment: .leading, spacing: 13) {
                ForEach(group.items) { item in
                    CodexActivityTool(item: item)
                }
            }
            .padding(.top, 7)
        } label: {
            HStack(spacing: 7) {
                if running != nil {
                    ProgressView().controlSize(.mini)
                } else {
                    Image(systemName: failed ? "exclamationmark.circle" : "checkmark")
                        .foregroundStyle(failed ? Color.orange : Color.secondary)
                }
                Text(running?.title ?? (group.items.count == 1 ? group.items[0].title : "\(group.items.count) tool calls"))
                    .lineLimit(1)
                Spacer(minLength: 0)
                if running != nil, group.items.count > 1 {
                    Text("\(group.items.count)").monospacedDigit().foregroundStyle(.tertiary)
                }
            }
            .font(.system(size: 11))
        }
        .tint(.secondary)
    }
}

private struct ActivityViewport: Equatable {
    let offset: CGFloat
    let height: CGFloat
    let atBottom: Bool
}

private struct CodexActivityMessage: View {
    let item: CodexActivityItem

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Text(item.kind == .user ? "You" : item.title)
                    .font(.system(size: 10, weight: .medium)).foregroundStyle(.secondary)
                if item.isRunning { ProgressView().controlSize(.mini) }
                if item.isError { Image(systemName: "exclamationmark.circle").foregroundStyle(.orange) }
            }
            if !item.text.isEmpty {
                Text(activityMarkdown(item.text))
                    .font(.system(size: 13)).lineSpacing(4)
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if !item.details.isEmpty {
                DisclosureGroup("Details") {
                    Text(item.details).font(.system(size: 11, design: .monospaced))
                        .textSelection(.enabled).padding(.top, 5)
                }
                .font(.system(size: 10)).tint(.secondary)
            }
            CodexActivityLinks(links: item.links)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct CodexActivityTool: View {
    let item: CodexActivityItem

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 6) {
                Text(item.title).font(.system(size: 11, weight: .medium))
                if item.isRunning { ProgressView().controlSize(.mini) }
                if item.isError { Image(systemName: "exclamationmark.circle").foregroundStyle(.orange) }
            }
            if !item.text.isEmpty {
                Text(item.text).font(.system(size: 11)).textSelection(.enabled)
            }
            if !item.details.isEmpty {
                Text(item.details).font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(.secondary).textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
            }
            CodexActivityLinks(links: item.links)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.leading, 6)
    }
}

private struct CodexActivityLinks: View {
    let links: [CodexActivityLink]

    var body: some View {
        ForEach(links) { link in
            Link(destination: link.url) {
                Label(link.title, systemImage: "arrow.up.right")
                    .font(.system(size: 11)).lineLimit(2)
            }
            .help(link.url.absoluteString)
        }
    }
}

private func activityMarkdown(_ text: String) -> AttributedString {
    (try? AttributedString(markdown: text, options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)))
        ?? AttributedString(text)
}
