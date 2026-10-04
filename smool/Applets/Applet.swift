import SwiftUI

struct AppletID: RawRepresentable, Hashable, Codable, Sendable {
    let rawValue: String

    static let home = AppletID(rawValue: "home")

    var isHostTool: Bool { rawValue == "quick-actions" || rawValue == "workspaces" }
}

struct AppletShortcut: Equatable {
    let key: KeyEquivalent
    var modifiers: EventModifiers = .command

    var keyboardShortcut: KeyboardShortcut { KeyboardShortcut(key, modifiers: modifiers) }

    /// Return activates the highlighted row; Command-arrows are handled by the host.
    var paletteShortcut: KeyboardShortcut? {
        if key == .return && modifiers.isEmpty { return nil }
        if modifiers == .command && (key == .leftArrow || key == .rightArrow) { return nil }
        return keyboardShortcut
    }

    var label: String {
        var result = ""
        if modifiers.contains(.control) { result += "⌃" }
        if modifiers.contains(.option) { result += "⌥" }
        if modifiers.contains(.shift) { result += "⇧" }
        if modifiers.contains(.command) { result += "⌘" }
        switch key {
        case .return: result += "↵"
        case .delete: result += "⌫"
        case .space: result += "Space"
        case .leftArrow: result += "←"
        case .rightArrow: result += "→"
        default: result += String(key.character).uppercased()
        }
        return result
    }
}

struct AppletAction: Identifiable {
    let id: String
    let title: String
    let symbol: String
    var shortcut: AppletShortcut?
    var selected = false
    var detail = ""
    let perform: () -> Void
}

/// Installed at composition. Providers read current host state without depending on rendering.
@MainActor
struct AppletCommandContext {
    var hostActions: () -> [AppletAction] = { [] }
    var composeInCodex: () -> ((String) -> Void)? = { nil }
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
    var openApplet: (AppletID) -> Void = { _ in }
    var openSettings: () -> Void = {}
}

@MainActor
protocol Applet: AnyObject {
    var id: AppletID { get }
    var title: String { get }
    var icon: AppletIcon { get }
    var tint: Color { get }
    var contentHeight: CGFloat { get }
    var pages: [AppletPage] { get }
    var actions: [AppletAction] { get }
    var background: AppletBackground? { get }
    var hasPresentedOverlay: Bool { get }
    var status: AppletStatus? { get }

    func makeView(context: AppletContext, artwork: NSImage?) -> AnyView
    func handleArrow(_ arrow: AppletArrow, command: Bool) -> Bool
    func handleEditingArrow(_ arrow: AppletArrow) -> Bool
    func handleBack() -> Bool
    func deactivate()
    func dismissOverlay()
    func activateStatus()
}

extension Applet {
    var pages: [AppletPage] { [] }
    var actions: [AppletAction] { [] }
    var background: AppletBackground? { nil }
    var hasPresentedOverlay: Bool { false }
    var status: AppletStatus? { nil }

    func handleArrow(_ arrow: AppletArrow, command: Bool) -> Bool { false }
    func handleEditingArrow(_ arrow: AppletArrow) -> Bool { false }
    func handleBack() -> Bool {
        guard hasPresentedOverlay else { return false }
        dismissOverlay()
        return true
    }
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
