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
            guard let thumbnail = await ProjectIconFiles.shared.thumbnail(path), !Task.isCancelled else { return }
            image = NSImage(cgImage: thumbnail, size: .zero)
        }
    }
}

/// Reads only bounded icon files inside the thread's project; it never requests remote favicons.
actor ProjectIconFiles {
    static let shared = ProjectIconFiles()
    private var cache: [String: Data] = [:]
    private var missing: Set<String> = []

    func thumbnail(_ path: String) -> CGImage? {
        guard let data = load(path), !Task.isCancelled,
              let source = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
        return CGImageSourceCreateThumbnailAtIndex(source, 0, [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceThumbnailMaxPixelSize: 128
        ] as CFDictionary)
    }

    func load(_ path: String) -> Data? {
        guard !Task.isCancelled, path.hasPrefix("/") else { return nil }
        if let data = cache[path] { return data }
        if missing.contains(path) { return nil }
        let root = URL(fileURLWithPath: path).standardizedFileURL.resolvingSymlinksInPath()
        let excluded: Set<String> = ["node_modules", "Pods", "Carthage", "build", "dist", "vendor", "DerivedData", "target", "coverage"]
        let keys: [URLResourceKey] = [.isDirectoryKey, .isSymbolicLinkKey]
        var directories = [(root, 0)]
        var next = 0
        var visited = 0

        // Breadth-first traversal finds the closest icon regardless of the workspace layout.
        while next < directories.count, visited < 1_000 {
            guard !Task.isCancelled else { return nil }
            let (directory, depth) = directories[next]
            next += 1
            let entries = (try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: keys, options: [.skipsHiddenFiles])) ?? []
            let bounded = entries.prefix(1_000 - visited)
            visited += bounded.count
            let sorted = bounded.sorted {
                let lhs = iconPriority($0), rhs = iconPriority($1)
                return lhs == rhs ? $0.lastPathComponent < $1.lastPathComponent : lhs < rhs
            }
            for url in sorted {
                guard !Task.isCancelled else { return nil }
                guard let values = try? url.resourceValues(forKeys: Set(keys)), values.isSymbolicLink != true else { continue }
                if values.isDirectory == true {
                    if url.pathExtension == "appiconset" {
                        if let data = assetIcon(in: url, root: root) { return remember(data, path: path) }
                    } else if depth < 6, !excluded.contains(url.lastPathComponent) {
                        directories.append((url, depth + 1))
                    }
                } else if iconPriority(url) < Int.max, let data = read(url, inside: root) {
                    return remember(data, path: path)
                }
            }
        }
        guard !Task.isCancelled else { return nil }
        if missing.count >= 128 { missing.removeAll() }
        missing.insert(path)
        return nil
    }

    private func iconPriority(_ url: URL) -> Int {
        let name = url.deletingPathExtension().lastPathComponent.lowercased()
        let ext = url.pathExtension.lowercased()
        if name == "favicon" || name.hasPrefix("favicon-") {
            switch ext {
            case "png": return 0
            case "ico": return 1
            case "jpg", "jpeg": return 2
            default: return .max
            }
        }
        if name == "apple-touch-icon", ext == "png" { return 3 }
        if name == "appicon", ext == "icns" { return 4 }
        if name == "icon", ext == "png", url.deletingLastPathComponent().lastPathComponent == "app" { return 5 }
        return .max
    }

    private func assetIcon(in directory: URL, root: URL) -> Data? {
        guard let json = read(directory.appendingPathComponent("Contents.json"), inside: root),
              let object = try? JSONSerialization.jsonObject(with: json) as? [String: Any],
              let images = object["images"] as? [[String: Any]] else { return nil }
        for filename in images.compactMap({ $0["filename"] as? String }).reversed() {
            if let data = read(directory.appendingPathComponent(filename), inside: root) { return data }
        }
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
