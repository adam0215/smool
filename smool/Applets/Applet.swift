import SwiftUI

struct AppletID: RawRepresentable, Hashable, Codable, Sendable {
    let rawValue: String

    static let home = AppletID(rawValue: "home")

    var isHostTool: Bool { rawValue == "quick-actions" || rawValue == "workspaces" }
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
        image(size: 11)
    }

    @ViewBuilder func image(size: CGFloat) -> some View {
        switch self {
        case .symbol(let name):
            Image(systemName: name).font(.system(size: size, weight: .medium))
        case .asset(let name):
            Image(name).resizable().renderingMode(.template)
                .scaledToFit().frame(width: size, height: size)
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

struct AppletDestination: Identifiable {
    let id: AppletID
    let title: String
    let icon: AppletIcon
    let tint: Color
    var shortcutNumber: Int?
}

/// A snapshot for the host to display. Applets own the work and update this value.
struct AppletStatus: Equatable {
    enum Kind { case working, needsAttention, completed }

    let kind: Kind
    let label: String
    var symbol = "circle.fill"
    var countdownDeadline: Date? = nil
}

/// Host capabilities available to applet views. Services and state stay in the applet.
struct AppletContext {
    let layout: NotchLayout
    var restoreFocus: () -> Void = {}
    var frontApplets: [AppletDestination] = []
    var hostActions: [AppletAction] = []
    var openApplet: (AppletID) -> Void = { _ in }
    /// Opens the destination with editable text. This capability must never send it.
    var composeInCodex: ((String) -> Void)?
    var openSettings: () -> Void = {}
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
    var status: AppletStatus? { get }

    func makeView(context: AppletContext, artwork: NSImage?) -> AnyView
    func handleArrow(_ arrow: AppletArrow, command: Bool) -> Bool
    func deactivate()
    func dismissOverlay()
    func activateStatus()
}

extension Applet {
    var homeShortcut: HomeApp? { nil }
    var pages: [AppletPage] { [] }
    var actions: [AppletAction] { [] }
    var background: AppletBackground? { nil }
    var hasPresentedOverlay: Bool { false }
    var status: AppletStatus? { nil }

    func handleArrow(_ arrow: AppletArrow, command: Bool) -> Bool { false }
    func deactivate() { dismissOverlay() }
    func dismissOverlay() {}
    func activateStatus() {}
}

private struct AppletFocusGenerationKey: EnvironmentKey {
    static let defaultValue = 0
}

extension EnvironmentValues {
    var appletFocusGeneration: Int {
        get { self[AppletFocusGenerationKey.self] }
        set { self[AppletFocusGenerationKey.self] = newValue }
    }
}

extension View {
    /// Restore the visible navigation focus after the host releases a text editor.
    func onAppletFocusRestore(_ restore: @escaping () -> Void) -> some View {
        modifier(AppletFocusRestoration(restore: restore))
    }
}

private struct AppletFocusRestoration: ViewModifier {
    @Environment(\.appletFocusGeneration) private var generation
    let restore: () -> Void

    func body(content: Content) -> some View {
        content.onChange(of: generation) { restore() }
    }
}
