import QuickLook
import SwiftUI
import UniformTypeIdentifiers

struct FilesAppletView: View {
    @Bindable var applet: FilesApplet
    @State private var isDropTarget = false
    @FocusState private var isFocused: Bool

    private var store: FileShelfStore { applet.store }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(store.selectedIDs.count > 1 ? "\(store.selectedIDs.count) selected" : "\(store.files.count) files")
                    .foregroundStyle(.secondary)
                Spacer()
                Button("Add files", systemImage: "plus") { applet.showsImporter = true }
                    .keyboardShortcut("o", modifiers: .command)
                    .foregroundStyle(.primary)
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

            Label(isDropTarget ? "Drop to add files" : "Drop files here · Space to preview", systemImage: "arrow.down.to.line")
                .font(.system(size: 11))
                .foregroundStyle(isDropTarget ? .primary : .secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, 24)
        .padding(.top, 14)
        .padding(.bottom, 20)
        .background(isDropTarget ? Color.white.opacity(0.05) : .clear, in: .rect(cornerRadius: 24))
        .contentShape(Rectangle())
        .focusable()
        .focusEffectDisabled()
        .focused($isFocused)
        .dropDestination(for: URL.self) { urls, _ in
            let files = urls.filter(\.isFileURL)
            guard !files.isEmpty else { return false }
            applet.add(urls: files)
            return true
        } isTargeted: { isDropTarget = $0 }
        .fileImporter(isPresented: $applet.showsImporter, allowedContentTypes: [.item], allowsMultipleSelection: true) { result in
            switch result {
            case .success(let urls): applet.add(urls: urls)
            case .failure(let error): store.reportImportError(error)
            }
        }
        .quickLookPreview($applet.previewURL)
        .onKeyPress(.space) {
            guard let url = store.selectedFile?.url else { return .ignored }
            applet.previewURL = url
            return .handled
        }
        .onKeyPress(keys: [.upArrow, .downArrow], phases: [.down, .repeat]) { press in
            guard press.modifiers == .shift else { return .ignored }
            store.moveSelection(press.key == .upArrow ? -1 : 1, extending: true)
            return .handled
        }
        .background {
            Button("Remove from shelf") { store.removeSelected() }
                .keyboardShortcut(.delete, modifiers: .command).hidden()
            Button("Select all files") { store.selectAll() }
                .keyboardShortcut("a", modifiers: .command).hidden()
            Button("Refresh shelf") { store.refresh() }
                .keyboardShortcut("r", modifiers: .command).hidden()
        }
        .task {
            isFocused = true
            store.refresh()
        }
        .onChange(of: applet.hasPresentedOverlay) { _, isPresented in
            if !isPresented { isFocused = true }
        }
        .preferredColorScheme(.dark)
    }

    private var emptyState: some View {
        VStack(spacing: 10) {
            Image(systemName: "tray.and.arrow.down")
                .font(.system(size: 24, weight: .light))
                .foregroundStyle(.secondary)
            VStack(spacing: 4) {
                Text(store.isLoading ? "Loading your shelf…" : "Drop files here to keep them handy")
                    .font(.system(size: 12, weight: .medium))
                Text("Your files stay in their original locations.")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
        }
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
            Button { store.remove(id: file.id) } label: {
                Image(systemName: "minus.circle")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .frame(width: 26, height: 26)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("Remove from shelf. The original file is kept.")
            .accessibilityLabel("Remove \(file.reference.name) from shelf")
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
        .accessibilityAction(named: "Preview") { applet.previewURL = file.url }
        .contextMenu {
            if let url = file.url {
                Button("Preview", systemImage: "eye") { applet.previewURL = url }
                Button("Show in Finder", systemImage: "folder") {
                    NSWorkspace.shared.activateFileViewerSelecting(isSelected ? store.selectedURLs : [url])
                }
            }
            Button("Remove from shelf", systemImage: "minus.circle") {
                if isSelected { store.removeSelected() } else { store.remove(id: file.id) }
            }
        }
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
