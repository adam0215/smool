import SwiftUI
import ImageIO

struct ProjectIcon: View {
    let path: String
    var isActive = false
    @State private var image: NSImage?

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            Group {
                if let image { Image(nsImage: image).resizable().scaledToFit() }
                else { Image(systemName: path.isEmpty ? "bubble.left" : "folder").resizable().scaledToFit().padding(6).foregroundStyle(.secondary) }
            }
            .clipShape(.rect(cornerRadius: 8))
            if isActive {
                Circle().fill(.green).frame(width: 6, height: 6)
                    .overlay { Circle().strokeBorder(.black, lineWidth: 1) }
            }
        }
        .accessibilityHidden(true)
        .task(id: path) {
            image = nil
            guard let data = await ProjectIconFiles.shared.load(path), !Task.isCancelled,
                  let source = CGImageSourceCreateWithData(data as CFData, nil),
                  let thumbnail = CGImageSourceCreateThumbnailAtIndex(source, 0, [
                    kCGImageSourceCreateThumbnailFromImageAlways: true,
                    kCGImageSourceThumbnailMaxPixelSize: 128
                  ] as CFDictionary) else { return }
            image = NSImage(cgImage: thumbnail, size: .zero)
        }
    }
}

/// Reads only bounded icon files inside the thread's project; it never requests remote favicons.
actor ProjectIconFiles {
    static let shared = ProjectIconFiles()
    private var cache: [String: Data] = [:]
    private var missing: Set<String> = []

    func load(_ path: String) -> Data? {
        guard path.hasPrefix("/") else { return nil }
        if let data = cache[path] { return data }
        if missing.contains(path) { return nil }
        let root = URL(fileURLWithPath: path).standardizedFileURL.resolvingSymlinksInPath()
        let candidates = ["public/favicon.ico", "public/favicon.png", "app/icon.png", "src/app/icon.png",
                          "app/favicon.ico", "src/app/favicon.ico", "static/favicon.png", "static/favicon.ico",
                          "favicon.ico", "favicon.png", "Resources/AppIcon.icns"]
        for candidate in candidates {
            if let data = read(root.appendingPathComponent(candidate), inside: root) { return remember(data, path: path) }
        }
        let excluded: Set<String> = ["node_modules", "Pods", "Carthage", "build", "dist", "vendor", "DerivedData"]
        if let entries = FileManager.default.enumerator(at: root, includingPropertiesForKeys: [.isDirectoryKey, .isSymbolicLinkKey], options: [.skipsHiddenFiles]) {
            var visited = 0
            while let url = entries.nextObject() as? URL {
                visited += 1
                if visited > 1_000 { break }
                let depth = url.pathComponents.count - root.pathComponents.count
                if depth > 5 || excluded.contains(url.lastPathComponent) || (try? url.resourceValues(forKeys: [.isSymbolicLinkKey]).isSymbolicLink) == true {
                    entries.skipDescendants()
                    continue
                }
                if url.pathExtension == "appiconset" {
                    entries.skipDescendants()
                    let contents = url.appendingPathComponent("Contents.json")
                    guard let json = read(contents, inside: root),
                          let object = try? JSONSerialization.jsonObject(with: json) as? [String: Any],
                          let images = object["images"] as? [[String: Any]] else { continue }
                    for filename in images.compactMap({ $0["filename"] as? String }).reversed() {
                        if let data = read(url.appendingPathComponent(filename), inside: root) { return remember(data, path: path) }
                    }
                }
            }
        }
        if missing.count >= 128 { missing.removeAll() }
        missing.insert(path)
        return nil
    }

    private func read(_ url: URL, inside root: URL) -> Data? {
        let resolved = url.standardizedFileURL.resolvingSymlinksInPath()
        guard resolved.path.hasPrefix(root.path + "/"),
              let values = try? resolved.resourceValues(forKeys: [.fileSizeKey, .isRegularFileKey]),
              values.isRegularFile == true, let size = values.fileSize, size > 0, size <= 2_000_000 else { return nil }
        return try? Data(contentsOf: resolved)
    }

    private func remember(_ data: Data, path: String) -> Data {
        if cache.count >= 64 { cache.removeAll() }
        cache[path] = data
        return data
    }
}
