@testable import SmoolChecksSupport
import SwiftUI

@main
struct ActionAppletsChecks {
    @MainActor static func main() async throws {
        _ = NSApplication.shared
        NSApp.appearance = NSAppearance(named: .darkAqua)
        let folder = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let dataFolder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: dataFolder) }
        let launcher = ActionLauncher(openURL: { _ in preconditionFailure("Rendering must not launch") }, runShortcut: { _ in preconditionFailure("Rendering must not run shortcuts") })
        let quick = QuickActionsApplet(store: QuickActionStore(url: dataFolder.appendingPathComponent("quick.json"), launcher: launcher))
        let spaces = WorkspacesApplet(store: WorkspaceStore(url: dataFolder.appendingPathComponent("spaces.json"), launcher: launcher))
        precondition(quick.id.rawValue == "quick-actions" && spaces.id.rawValue == "workspaces")
        precondition(quick.handleArrow(.down, command: false) && !spaces.handleArrow(.right, command: false))
        try render(quick, name: "quick-empty", folder: folder)
        try render(spaces, name: "workspaces-empty", folder: folder)
        let first = SavedAction(name: "Designsystem", destination: try .web("https://developer.apple.com/design/"))
        let second = SavedAction(name: "Projektets dokumentation", destination: try .web("https://example.com/docs"))
        let savedFirst = await quick.store.save(first)
        let savedSecond = await quick.store.save(second)
        precondition(savedFirst && savedSecond)
        quick.highlightedID = nil
        precondition(quick.handleArrow(.down, command: false) && quick.selectedID == first.id)
        precondition(quick.handleArrow(.down, command: false) && quick.selectedID == second.id)
        quick.editor = ActionEditorRequest(action: first)
        precondition(quick.hasPresentedOverlay && !quick.handleArrow(.up, command: false))
        quick.dismissOverlay()
        precondition(!quick.hasPresentedOverlay)
        let workspace = SavedWorkspace(name: "smool", resources: [first, second], selectedResourceIDs: [first.id])
        let savedWorkspace = await spaces.store.save(workspace)
        precondition(savedWorkspace)
        let savedNextWorkspace = await spaces.store.save(SavedWorkspace(name: "Nästa projekt"))
        precondition(savedNextWorkspace)
        precondition(spaces.handleArrow(.right, command: false) && spaces.selected?.name == "Nästa projekt")
        precondition(spaces.handleArrow(.left, command: false) && spaces.selected?.id == workspace.id)
        spaces.editor = WorkspaceDraft(workspace)
        precondition(spaces.hasPresentedOverlay && !spaces.handleArrow(.right, command: false))
        spaces.dismissOverlay()
        precondition(!spaces.hasPresentedOverlay)
        try render(quick, name: "quick-populated", folder: folder)
        try render(spaces, name: "workspaces-populated", folder: folder)
        print("Passed: action applet identities, arrow navigation, editor focus isolation, empty and populated renders without launches.")
    }

    @MainActor private static func render(_ applet: any Applet, name: String, folder: URL) throws {
        let context = AppletContext(layout: NotchLayout(screenFrame: CGRect(x: 0, y: 0, width: 1440, height: 900)))
        let content = applet.makeView(context: context, artwork: nil)
            .frame(width: 520, height: applet.contentHeight)
            .background(.black).environment(\.colorScheme, .dark)
        let host = NSHostingView(rootView: content)
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 520, height: applet.contentHeight), styleMask: [.borderless], backing: .buffered, defer: false)
        window.contentView = host
        window.orderFrontRegardless()
        defer { window.orderOut(nil) }
        host.layoutSubtreeIfNeeded()
        RunLoop.current.run(until: Date().addingTimeInterval(0.3))
        host.displayIfNeeded()
        guard let bitmap = host.bitmapImageRepForCachingDisplay(in: host.bounds) else { fatalError("Could not render action applet") }
        host.cacheDisplay(in: host.bounds, to: bitmap)
        try bitmap.representation(using: .png, properties: [:])!.write(to: folder.appendingPathComponent(name + ".png"))
    }
}
