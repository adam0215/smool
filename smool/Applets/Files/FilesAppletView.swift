import QuickLook
import SwiftUI
import UniformTypeIdentifiers

struct FilesAppletView: View {
    @Bindable var applet: FilesApplet
    @State private var isDropTarget = false

    private var store: FileShelfStore { applet.store }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("\(store.files.count) filer").foregroundStyle(.secondary)
                Spacer()
                Button("Lägg till", systemImage: "plus") { applet.showsImporter = true }
                    .keyboardShortcut("o", modifiers: .command)
            }
            .font(.system(size: 11))
            .buttonStyle(.plain)

            if store.files.isEmpty {
                VStack(spacing: 6) {
                    Image(systemName: "tray.and.arrow.down").font(.system(size: 22)).foregroundStyle(.secondary)
                    Text(store.isLoading ? "Hämtar filhyllan…" : "Dra hit filer att ha nära till hands")
                        .font(.system(size: 12))
                    Text("Originalen ligger kvar där de finns.")
                        .font(.system(size: 10)).foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(spacing: 3) {
                            ForEach(store.files) { file in row(file).id(file.id) }
                        }
                    }
                    .onChange(of: store.selection) { _, id in
                        if let id { proxy.scrollTo(id) }
                    }
                }
            }

            if let error = store.error {
                Text(error).font(.system(size: 10)).foregroundStyle(.orange).lineLimit(2)
                    .help(error)
            }
            HStack(spacing: 5) {
                Image(systemName: "arrow.down.to.line")
                Text(isDropTarget ? "Släpp för att lägga till" : "Släpp filer här · Mellanslag förhandsvisar")
                Spacer(minLength: 0)
            }
            .font(.system(size: 10)).foregroundStyle(isDropTarget ? .primary : .secondary)
            .padding(.vertical, 6)
        }
        .padding(.horizontal, 20).padding(.vertical, 12)
        .background(isDropTarget ? Color.white.opacity(0.07) : .clear, in: .rect(cornerRadius: 18))
        .contentShape(Rectangle())
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
        .background {
            Button("Ta bort från hyllan") {
                if let file = store.selectedFile { store.remove(id: file.id) }
            }
            .keyboardShortcut(.delete, modifiers: .command).hidden()
            Button("Uppdatera filhyllan") { store.refresh() }
                .keyboardShortcut("r", modifiers: .command).hidden()
        }
        .task { store.refresh() }
        .preferredColorScheme(.dark)
    }

    private func row(_ file: ResolvedShelfFile) -> some View {
        HStack(spacing: 9) {
            Image(nsImage: store.icon(for: file)).resizable().scaledToFit().frame(width: 24, height: 24)
            VStack(alignment: .leading, spacing: 2) {
                Text(file.reference.name).font(.system(size: 12)).lineLimit(1).truncationMode(.middle)
                if file.url == nil {
                    Text("Filen kan inte hittas. Lägg till den igen.")
                        .font(.system(size: 9)).foregroundStyle(.orange)
                }
            }
            Spacer(minLength: 0)
            Button {
                store.remove(id: file.id)
            } label: {
                Image(systemName: "minus.circle").foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .help("Ta bort referensen från hyllan. Originalfilen behålls.")
            .accessibilityLabel("Ta bort \(file.reference.name) från hyllan")
        }
        .padding(.horizontal, 8).padding(.vertical, 7)
        .background(.white.opacity(store.selectedFile?.id == file.id ? 0.09 : 0), in: .rect(cornerRadius: 9))
        .contentShape(Rectangle())
        .onTapGesture { store.selection = file.id }
        .accessibilityElement(children: .contain)
        .accessibilityAddTraits(store.selectedFile?.id == file.id ? .isSelected : [])
        .accessibilityAction(named: "Förhandsvisa") { applet.previewURL = file.url }
        .contextMenu {
            if let url = file.url {
                Button("Förhandsvisa", systemImage: "eye") { applet.previewURL = url }
                Button("Visa i Finder", systemImage: "folder") { NSWorkspace.shared.activateFileViewerSelecting([url]) }
            }
            Button("Ta bort från hyllan", systemImage: "minus.circle") { store.remove(id: file.id) }
        }
        .modifier(ShelfFileDrag(url: file.url))
    }
}

private struct ShelfFileDrag: ViewModifier {
    let url: URL?

    @ViewBuilder func body(content: Content) -> some View {
        if let url {
            content.onDrag { NSItemProvider(object: url as NSURL) }
        } else {
            content
        }
    }
}
