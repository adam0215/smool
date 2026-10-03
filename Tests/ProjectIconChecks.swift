import Foundation

@main
struct ProjectIconChecks {
    static func main() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let loader = ProjectIconFiles()
        let web = root.appendingPathComponent("web")
        try FileManager.default.createDirectory(at: web.appendingPathComponent("public"), withIntermediateDirectories: true)
        let icon = Data([1, 2, 3])
        try icon.write(to: web.appendingPathComponent("public/favicon.ico"))
        let favicon = await loader.load(web.path)
        precondition(favicon == icon, "Web favicons come from the thread's project root.")

        let app = root.appendingPathComponent("app")
        let assets = app.appendingPathComponent("App/Assets.xcassets/AppIcon.appiconset")
        try FileManager.default.createDirectory(at: assets, withIntermediateDirectories: true)
        try Data(#"{"images":[{"filename":"icon.png"}]}"#.utf8).write(to: assets.appendingPathComponent("Contents.json"))
        try icon.write(to: assets.appendingPathComponent("icon.png"))
        let appIcon = await loader.load(app.path)
        precondition(appIcon == icon, "Native apps resolve filenames through the asset catalog.")

        let linked = root.appendingPathComponent("linked")
        try FileManager.default.createDirectory(at: linked.appendingPathComponent("public"), withIntermediateDirectories: true)
        try FileManager.default.createSymbolicLink(at: linked.appendingPathComponent("public/favicon.ico"), withDestinationURL: web.appendingPathComponent("public/favicon.ico"))
        let outside = await loader.load(linked.path)
        precondition(outside == nil, "An icon symlink must not escape its project.")
        let relative = await loader.load("relative/path")
        precondition(relative == nil)
        print("Passed: project favicon, asset catalog icons, missing paths, and symlink boundaries.")
    }
}
