import QuickLook
import SwiftUI
import UniformTypeIdentifiers

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
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(selectionTitle)
                    .foregroundStyle(.secondary)
                Spacer()
                Button { applet.showsImporter = true } label: {
                    Text("Add files  ⌘O")
                        .padding(.vertical, 4)
                        .contentShape(Rectangle())
                }
                .keyboardShortcut("o", modifiers: .command)
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
                    Button("Space Preview") { applet.previewURL = store.selectedFile?.url }
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
        .accessibilityAction(named: "Preview") { applet.previewURL = file.url }
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
