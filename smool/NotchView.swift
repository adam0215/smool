import SwiftUI

@MainActor
@Observable
final class NotchPresentation {
    let registeredApplets: AppletRegistry
    let settings: AppSettings
    var openSettings: () -> Void = {}
    var composeInCodex: ((String) -> Void)?
    var capturedSelection: SelectionPreview?

    var registry: AppletRegistry {
        let ids = settings.orderedIDs(in: registeredApplets.applets.map(\.id))
        let enabled = ids.compactMap { id in
            settings.isEnabled(id) ? registeredApplets.applet(for: id) : nil
        }
        // Keep custom registries usable even when every optional applet is disabled.
        return AppletRegistry(enabled.isEmpty ? [registeredApplets.applets[0]] : enabled)
    }

    var frontApplets: [AppletDestination] {
        settings.frontIDs(in: registeredApplets.applets.map(\.id)).compactMap { id in
            guard let applet = registry.applet(for: id) else { return nil }
            return AppletDestination(id: id, title: applet.title, icon: applet.icon,
                                     tint: applet.tint, shortcutNumber: registry.shortcutNumber(for: id))
        }
    }
    private(set) var selection: AppletID
    var isExpanded = false
    var usesExpandedFrame = false
    var showsActions = false
    var showsSettings = false
    var settingsSection = SettingsSection.general
    var settingsRow = 0
    var terminationError: String?
    let audio = SystemAudioLevel()
    var layout = NotchLayout(screenFrame: CGRect(x: 0, y: 0, width: 1440, height: 900))

    init(registry: AppletRegistry = builtInApplets(), settings: AppSettings = AppSettings()) {
        self.registeredApplets = registry
        self.settings = settings
        selection = registry.applets[0].id
    }

    var activeApplet: any Applet { registeredApplets.applet(for: selection)! }

    func reconcileSettings() {
        if registry.applet(for: selection) == nil {
            let wasShowingSettings = showsSettings
            select(registry.applets[0].id)
            showsSettings = wasShowingSettings
        }
    }
    var contentHeight: CGFloat {
        if showsSettings { return 360 }
        return max(activeApplet.contentHeight, capturedSelection == nil ? 0 : 250, terminationError == nil ? 0 : 280)
    }

    var collapsedSize: CGSize { layout.collapsedSize(statusCount: statusItems.count) }

    func presentCapturedSelection(_ preview: SelectionPreview) {
        showsSettings = false
        showsActions = false
        activeApplet.dismissOverlay()
        capturedSelection = preview
    }

    func select(_ id: AppletID) {
        guard registry.applet(for: id) != nil else { return }
        showsSettings = false
        guard selection != id else { return }
        showsActions = false
        capturedSelection = nil
        activeApplet.deactivate()
        selection = id
    }
}

struct NotchView: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    let presentation: NotchPresentation
    let selectApplet: (AppletID) -> Void
    var close: () -> Void = {}
    var restoreFocus: () -> Void = {}
    var resizeContent: () -> Void = {}
    var activateStatus: (AppletID) -> Void = { _ in }
    var acceptFiles: ([URL]) -> Bool = { _ in false }
    var open: () -> Void = {}

    private var size: CGSize {
        presentation.isExpanded ? presentation.layout.expandedSize : presentation.collapsedSize
    }

    private var shape: NotchShape {
        NotchShape(
            shoulderRadius: presentation.isExpanded ? 0 : 4,
            bottomRadius: presentation.isExpanded ? NotchLayout.bottomRadius : 8
        )
    }

    private var horizontalAnimation: Animation? {
        guard !reduceMotion else { return nil }
        return presentation.isExpanded
            ? .spring(response: 0.48, dampingFraction: 0.78)
            : .spring(response: 0.42, dampingFraction: 0.86).delay(0.03)
    }

    private var verticalAnimation: Animation? {
        guard !reduceMotion else { return nil }
        return presentation.isExpanded
            ? .spring(response: 0.54, dampingFraction: 0.76).delay(0.025)
            : .spring(response: 0.4, dampingFraction: 0.86)
    }

    var body: some View {
        Color.clear
            .background {
                NotchGlass(shape: shape, darkHeight: presentation.layout.navigationHeight)
            }
            .overlay(alignment: .top) {
                if presentation.isExpanded {
                    NotchContentView(presentation: presentation, selectApplet: selectApplet, restoreFocus: restoreFocus)
                        .frame(width: presentation.layout.expandedSize.width, height: presentation.layout.expandedSize.height)
                        .transition(.asymmetric(insertion: .identity, removal: .opacity.animation(.easeOut(duration: 0.16))))
                } else if !presentation.statusItems.isEmpty {
                    NotchStatusView(items: presentation.statusItems, layout: presentation.layout, activate: activateStatus)
                }
            }
            .overlay {
                NotchGlassEdge(shape: shape, darkHeight: presentation.layout.navigationHeight)
            }
            .compositingGroup()
            .clipShape(shape)
            .frame(width: size.width)
            .animation(horizontalAnimation, value: presentation.isExpanded)
            .frame(height: size.height, alignment: .top)
            .animation(verticalAnimation, value: presentation.isExpanded)
            .shadow(color: .black.opacity(presentation.isExpanded ? 0.22 : 0), radius: 14, y: 8)
            .contentShape(shape)
            .dropDestination(for: URL.self, action: { (urls: [URL], _: CGPoint) -> Bool in
                acceptFiles(urls.filter(\.isFileURL))
            })
            .onTapGesture { if !presentation.isExpanded { open() } }
            .offset(x: !presentation.isExpanded && presentation.usesExpandedFrame
                    ? presentation.layout.collapsedOffset(statusCount: presentation.statusItems.count) : 0)
            .animation(horizontalAnimation, value: presentation.isExpanded)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .ignoresSafeArea()
            .preferredColorScheme(.dark)
            .environment(\.locale, AppSettings.displayLocale())
            .accessibilityElement(children: .contain)
            .accessibilityLabel("smool")
            .onChange(of: presentation.contentHeight) { _, _ in resizeContent() }
            .onExitCommand(perform: close)
    }
}

// Concave shoulders join the screen edge; the lower corners curve inward.
struct NotchShape: Shape {
    var shoulderRadius: CGFloat
    var bottomRadius: CGFloat

    var animatableData: AnimatablePair<CGFloat, CGFloat> {
        get { AnimatablePair(shoulderRadius, bottomRadius) }
        set {
            shoulderRadius = newValue.first
            bottomRadius = newValue.second
        }
    }

    func path(in rect: CGRect) -> Path {
        let shoulder = min(shoulderRadius, rect.height / 3)
        let corner = min(bottomRadius, rect.height / 2)
        let left = rect.minX + shoulder
        let right = rect.maxX - shoulder
        let top = rect.minY

        var path = UnevenRoundedRectangle(
            topLeadingRadius: 0,
            bottomLeadingRadius: corner,
            bottomTrailingRadius: corner,
            topTrailingRadius: 0,
            style: .circular
        ).path(in: CGRect(x: left, y: top, width: right - left, height: rect.height))

        path.move(to: CGPoint(x: rect.minX, y: top))
        path.addLine(to: CGPoint(x: left, y: top))
        path.addLine(to: CGPoint(x: left, y: top + shoulder))
        path.addQuadCurve(to: CGPoint(x: rect.minX, y: top), control: CGPoint(x: left, y: top))
        path.closeSubpath()

        path.move(to: CGPoint(x: right, y: top))
        path.addLine(to: CGPoint(x: rect.maxX, y: top))
        path.addQuadCurve(to: CGPoint(x: right, y: top + shoulder), control: CGPoint(x: right, y: top))
        path.closeSubpath()

        return path
    }
}
