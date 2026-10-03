import QuickLookUI
import SwiftUI

struct FilesAppletView: View {
    @Bindable var applet: FilesApplet
    @State private var isDropTarget = false
    @FocusState private var isFocused: Bool

    private var store: FileShelfStore { applet.store }
    private var selectionTitle: String {
        if store.selectedIDs.count > 1 { return "\(store.selectedIDs.count) selected" }
        if store.files.isEmpty { return "Files" }
        return store.files.count == 1 ? "1 file" : "\(store.files.count) files"
    }

    var body: some View {
        Group {
            if applet.showsPathEntry {
                FilePathEntry(applet: applet)
            } else if let url = applet.previewURL {
                preview(url)
            } else {
                shelf
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(isDropTarget ? Color.white.opacity(0.05) : .clear, in: .rect(cornerRadius: 24))
        .contentShape(Rectangle())
        .focusable(!applet.showsPathEntry)
        .focusEffectDisabled()
        .focused($isFocused)
        .dropDestination(for: URL.self) { urls, _ in
            let files = urls.filter(\.isFileURL)
            guard !files.isEmpty else { return false }
            applet.add(urls: files)
            applet.dismissOverlay()
            return true
        } isTargeted: { isDropTarget = $0 }
        .onKeyPress(.space) {
            guard !applet.showsPathEntry else { return .ignored }
            if applet.previewURL != nil {
                applet.dismissOverlay()
            } else {
                guard let url = store.selectedFile?.url else { return .ignored }
                applet.showPreview(url)
            }
            return .handled
        }
        .onKeyPress(keys: [.upArrow, .downArrow], phases: [.down, .repeat]) { press in
            guard !applet.hasPresentedOverlay, press.modifiers.intersection([.command, .control, .option, .shift]) == .shift else { return .ignored }
            store.moveSelection(press.key == .upArrow ? -1 : 1, extending: true)
            return .handled
        }
        .background {
            Button("Add files") { applet.openPathEntry() }
                .keyboardShortcut("o", modifiers: .command).hidden()
            Button("Remove from shelf") { store.removeSelected() }
                .keyboardShortcut(.delete, modifiers: .command)
                .disabled(applet.hasPresentedOverlay).hidden()
            Button("Select all files") { store.selectAll() }
                .keyboardShortcut("a", modifiers: .command)
                .disabled(applet.hasPresentedOverlay).hidden()
            Button("Refresh shelf") { store.refresh() }
                .keyboardShortcut("r", modifiers: .command).hidden()
        }
        .task {
            isFocused = !applet.showsPathEntry
            store.refresh()
        }
        .onChange(of: applet.hasPresentedOverlay) { _, isPresented in
            if !isPresented { isFocused = true }
        }
        .onChange(of: applet.showsPathEntry) { _, isPresented in
            isFocused = !isPresented
        }
        .onAppletFocusRestore {
            if !applet.showsPathEntry { isFocused = true }
        }
        .onKeyPress(.escape) {
            guard applet.hasPresentedOverlay else { return .ignored }
            applet.dismissOverlay()
            return .handled
        }
        .preferredColorScheme(.dark)
    }

    private var shelf: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(selectionTitle)
                    .foregroundStyle(.secondary)
                Spacer()
                Button { applet.openPathEntry() } label: {
                    Text("Add files  ⌘O")
                        .padding(.vertical, 4)
                        .contentShape(Rectangle())
                }
                .foregroundStyle(.secondary)
            }
            .font(.system(size: 11, weight: .medium))
            .buttonStyle(.plain)

            if store.files.isEmpty {
                emptyState
            } else {
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(spacing: 4) {
                            ForEach(store.files) { file in row(file).id(file.id) }
                        }
                        .dragContainer(for: URL.self, itemID: \.self) { (urls: [URL]) in urls }
                        .dragContainerSelection(store.selectedURLs)
                    }
                    .onChange(of: store.selection) { _, id in
                        if let id { proxy.scrollTo(id) }
                    }
                }
            }

            if let error = store.error {
                Text(error)
                    .font(.system(size: 11))
                    .foregroundStyle(.orange)
                    .lineLimit(2)
                    .help(error)
            }

            if !store.files.isEmpty {
                HStack(spacing: 12) {
                    Text(isDropTarget ? "Drop to add" : "↑↓ Select")
                    Button("Space Preview") { applet.showPreview(store.selectedFile?.url) }
                        .buttonStyle(.plain)
                        .disabled(store.selectedFile?.url == nil)
                    Text("⌘K Actions")
                }
                .font(.system(size: 11))
                .foregroundStyle(isDropTarget ? .primary : .secondary)
                .frame(maxWidth: .infinity)
            }
        }
        .padding(.horizontal, 32)
        .padding(.top, 14)
        .padding(.bottom, 28)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func preview(_ url: URL) -> some View {
        VStack(spacing: 12) {
            HStack(spacing: 12) {
                Text(url.lastPathComponent)
                    .font(.system(size: 12, weight: .medium))
                    .lineLimit(1)
                    .truncationMode(.middle)
                Spacer(minLength: 0)
                Button("Close  esc") { applet.dismissOverlay() }
                    .buttonStyle(.plain)
                    .keyboardShortcut(.space, modifiers: [])
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }

            ShelfFilePreview(url: url)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .clipShape(.rect(cornerRadius: 20))

            Text("Space Close preview · ⌘K Actions")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 32)
        .padding(.top, 16)
        .padding(.bottom, 28)
    }

    private var emptyState: some View {
        VStack(spacing: 10) {
            Image(systemName: "tray.and.arrow.down")
                .font(.system(size: 24, weight: .light))
                .foregroundStyle(.secondary)
            VStack(spacing: 4) {
                Text(store.isLoading ? "Loading your shelf…" : (isDropTarget ? "Drop to add files" : "Drop files here"))
                    .font(.system(size: 14, weight: .medium))
                Text("Your files stay in their original locations.")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
        }
        .multilineTextAlignment(.center)
        .padding(.horizontal, 16)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func row(_ file: ResolvedShelfFile) -> some View {
        let isSelected = store.selectedIDs.contains(file.id)

        return HStack(spacing: 10) {
            Image(nsImage: store.icon(for: file))
                .resizable()
                .scaledToFit()
                .frame(width: 26, height: 26)
            VStack(alignment: .leading, spacing: 3) {
                Text(file.reference.name)
                    .font(.system(size: 12, weight: .medium))
                    .lineLimit(1)
                    .truncationMode(.middle)
                if file.url == nil {
                    Text("File unavailable. Add it again.")
                        .font(.system(size: 11))
                        .foregroundStyle(.orange)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .frame(minHeight: 42)
        .background(.white.opacity(isSelected ? 0.09 : 0), in: .rect(cornerRadius: 14))
        .contentShape(.rect(cornerRadius: 14))
        .onTapGesture {
            let modifiers = NSEvent.modifierFlags
            store.select(file.id, extending: modifiers.contains(.shift), toggling: modifiers.contains(.command))
            isFocused = true
        }
        .accessibilityElement(children: .contain)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
        .accessibilityAction(named: "Select") { store.select(file.id) }
        .accessibilityAction(named: "Preview") { applet.showPreview(file.url) }
        .accessibilityAction(named: "Remove from shelf") { store.remove(id: file.id) }
        .modifier(ShelfFileDrag(url: file.url))
    }
}

private struct ShelfFileDrag: ViewModifier {
    let url: URL?

    @ViewBuilder func body(content: Content) -> some View {
        if let url {
            content.draggable(containerItemID: url)
        } else {
            content
        }
    }
}

private struct FilePathEntry: View {
    private enum Focus { case navigation, path }

    @Bindable var applet: FilesApplet
    @FocusState private var focus: Focus?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Add files")
                    .font(.system(size: 13, weight: .semibold))
                Spacer()
                Button("Back  esc") { applet.dismissOverlay() }
                    .buttonStyle(.plain)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }

            TextField("~/Downloads/report.pdf", text: $applet.pathDraft, axis: .vertical)
                .textFieldStyle(.plain)
                .font(.system(size: 14))
                .lineLimit(2...4)
                .focused($focus, equals: .path)
                .accessibilityLabel("File paths, one per line")

            if let error = applet.pathError {
                Text(error)
                    .font(.system(size: 11))
                    .foregroundStyle(.orange)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 0)

            HStack(alignment: .bottom, spacing: 16) {
                Text(focus == .navigation ? "↵ Edit paths · draft kept\nYou can also drop files here." : "One path per line, or drop files here.\nEsc leaves your draft here.")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                Spacer(minLength: 0)
                Button("Add  ⌘↵") { applet.addPaths() }
                    .buttonStyle(.plain)
                    .font(.system(size: 12, weight: .medium))
                    .keyboardShortcut(.return, modifiers: .command)
                    .disabled(applet.pathDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(.horizontal, 32)
        .padding(.vertical, 24)
        .focusable()
        .focusEffectDisabled()
        .focused($focus, equals: .navigation)
        .onAppletFocusRestore { focus = .navigation }
        .onKeyPress(keys: [.return]) { key in
            guard focus == .navigation, key.modifiers.intersection([.command, .control, .option, .shift]).isEmpty else { return .ignored }
            focus = .path
            return .handled
        }
        .task {
            await Task.yield()
            guard !Task.isCancelled else { return }
            focus = .path
        }
    }
}

private struct ShelfFilePreview: NSViewRepresentable {
    let url: URL

    func makeNSView(context: Context) -> QLPreviewView {
        let view = QLPreviewView(frame: .zero, style: .compact)!
        view.shouldCloseWithWindow = false
        view.autostarts = false
        return view
    }

    func updateNSView(_ view: QLPreviewView, context: Context) {
        if view.previewItem?.previewItemURL != url {
            view.previewItem = url as NSURL
        }
    }

    static func dismantleNSView(_ view: QLPreviewView, coordinator: ()) {
        view.close()
    }
}
