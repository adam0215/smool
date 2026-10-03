import SwiftUI

struct AppletID: RawRepresentable, Hashable {
    let rawValue: String
}

struct AppletAction: Identifiable {
    let id: String
    let symbol: String
    var shortcut = ""
    var selected = false
    let perform: () -> Void
}

enum AppletIcon {
    case symbol(String)
    case asset(String)

    @ViewBuilder var view: some View {
        switch self {
        case .symbol(let name):
            Image(systemName: name).font(.system(size: 11, weight: .medium))
        case .asset(let name):
            Image(name).resizable().renderingMode(.template)
                .scaledToFit().frame(width: 11, height: 11)
        }
    }
}

struct AppletPage: Identifiable {
    let id: String
    let isSelected: Bool
    let select: () -> Void
}

struct AppletBackground {
    let color: Color
    var horizontalPosition = 0.5
    var artworkSource: AlbumArtwork.Source?
    var isPlaying = false
}

enum AppletArrow: UInt16 {
    case left = 123, right = 124, down = 125, up = 126

    var isVertical: Bool { self == .up || self == .down }
    var offset: Int { self == .left || self == .up ? -1 : 1 }
}

/// Host capabilities available to applet views. Services and state stay in the applet.
struct AppletContext {
    let layout: NotchLayout
    var restoreFocus: () -> Void = {}
    var openShortcut: (HomeApp) -> Void = { _ in }
    var canOpenShortcut: (HomeApp) -> Bool = { _ in true }
    var shortcutNumber: (HomeApp) -> Int? = { _ in nil }
}

@MainActor
protocol Applet: AnyObject {
    var id: AppletID { get }
    var title: String { get }
    var icon: AppletIcon { get }
    var tint: Color { get }
    var homeShortcut: HomeApp? { get }
    var contentHeight: CGFloat { get }
    var pages: [AppletPage] { get }
    var actions: [AppletAction] { get }
    var background: AppletBackground? { get }
    var hasPresentedOverlay: Bool { get }

    func makeView(context: AppletContext, artwork: NSImage?) -> AnyView
    func handleArrow(_ arrow: AppletArrow, command: Bool) -> Bool
    func deactivate()
    func dismissOverlay()
}

extension Applet {
    var homeShortcut: HomeApp? { nil }
    var pages: [AppletPage] { [] }
    var actions: [AppletAction] { [] }
    var background: AppletBackground? { nil }
    var hasPresentedOverlay: Bool { false }

    func handleArrow(_ arrow: AppletArrow, command: Bool) -> Bool { false }
    func deactivate() { dismissOverlay() }
    func dismissOverlay() {}
}
