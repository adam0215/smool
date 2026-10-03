import SwiftUI

@MainActor @Observable
final class AudioApplet: Applet {
    let id = AppletID(rawValue: "audio")
    let title = "Audio"
    let icon = AppletIcon.symbol("speaker.wave.2")
    let tint = Color.cyan
    let service: AudioService
    var selectedControl = 0
    var picker: AudioDirection?

    init(service: AudioService = AudioService()) {
        self.service = service
    }

    var hasPresentedOverlay: Bool { picker != nil }
    var contentHeight: CGFloat { service.error == nil ? 156 : 184 }

    func makeView(context: AppletContext, artwork: NSImage?) -> AnyView {
        AnyView(AudioAppletView(applet: self, restoreFocus: context.restoreFocus))
    }

    func handleArrow(_ arrow: AppletArrow, command: Bool) -> Bool {
        guard !command, picker == nil else { return false }
        if arrow.isVertical {
            selectedControl = (selectedControl + arrow.offset + 3) % 3
        } else if selectedControl == 2 {
            service.setVolume(service.state.volume.value + Float32(arrow.offset) * 0.05)
        } else {
            return false
        }
        return true
    }

    func dismissOverlay() { picker = nil }

    func deactivate() {
        dismissOverlay()
        service.stop()
    }
}
