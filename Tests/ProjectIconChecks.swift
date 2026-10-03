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

        for layout in ["packages/web", "apps/web", "packages/frontend", "apps/site", "web", "frontend", "custom/product/client"] {
            let repository = root.appendingPathComponent(UUID().uuidString)
            let publicDirectory = repository.appendingPathComponent(layout + "/public")
            try FileManager.default.createDirectory(at: publicDirectory, withIntermediateDirectories: true)
            try icon.write(to: publicDirectory.appendingPathComponent("favicon-96x96.png"))
            let monorepoIcon = await loader.load(repository.path)
            precondition(monorepoIcon == icon, "Find web favicons in \(layout) without scanning dependencies.")
        }

        let nearest = root.appendingPathComponent("nearest")
        try FileManager.default.createDirectory(at: nearest.appendingPathComponent("a/deep"), withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: nearest.appendingPathComponent("z"), withIntermediateDirectories: true)
        try Data([4]).write(to: nearest.appendingPathComponent("a/deep/favicon.png"))
        try icon.write(to: nearest.appendingPathComponent("z/favicon.png"))
        let nearestIcon = await loader.load(nearest.path)
        precondition(nearestIcon == icon, "Prefer the shallowest favicon, not the first depth-first match.")

        let dependencies = root.appendingPathComponent("dependencies")
        try FileManager.default.createDirectory(at: dependencies.appendingPathComponent("node_modules/package"), withIntermediateDirectories: true)
        try icon.write(to: dependencies.appendingPathComponent("node_modules/package/favicon.png"))
        let dependencyIcon = await loader.load(dependencies.path)
        precondition(dependencyIcon == nil, "A dependency's favicon must never become the project icon.")

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
        if let project = CommandLine.arguments.dropFirst().first {
            let thumbnail = await loader.thumbnail(project)
            precondition(thumbnail != nil, "The real project's favicon must decode successfully.")
            print("Passed: real project favicon decoded as a thumbnail.")
        }
        print("Passed: project and monorepo favicons, asset catalog icons, missing paths, and symlink boundaries.")
    }
}
