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
    var selectedDeviceIndex = 0

    init(service: AudioService = AudioService()) {
        self.service = service
    }

    var hasPresentedOverlay: Bool { picker != nil }
    var contentHeight: CGFloat { service.error == nil ? 204 : 232 }
    var background: AppletBackground? { AppletBackground(color: .cyan, horizontalPosition: 0.8) }

    var actions: [AppletAction] {
        var actions = [
            AppletAction(id: "Choose output", symbol: "speaker.wave.2") { self.openPicker(.output) },
            AppletAction(id: "Choose microphone", symbol: "mic") { self.openPicker(.input) }
        ]
        if service.state.volume.isAdjustable {
            actions.append(AppletAction(id: service.state.volume.value == 0 ? "Unmute" : "Mute", symbol: "speaker.slash", shortcut: "M") {
                self.service.toggleMute()
            })
        }
        return actions
    }

    func makeView(context: AppletContext, artwork: NSImage?) -> AnyView {
        AnyView(AudioAppletView(applet: self, restoreFocus: context.restoreFocus))
    }

    func handleArrow(_ arrow: AppletArrow, command: Bool) -> Bool {
        guard !command else { return false }
        if let picker {
            let count = service.state.devices(for: picker).count
            guard arrow.isVertical, count > 0 else { return false }
            selectedDeviceIndex = (selectedDeviceIndex + arrow.offset + count) % count
        } else if arrow.isVertical {
            service.setVolume(service.state.volume.value - Float32(arrow.offset) * 0.05)
        } else {
            selectedControl = (selectedControl + arrow.offset + 2) % 2
        }
        return true
    }

    func openPicker(_ direction: AudioDirection) {
        selectedControl = direction == .output ? 0 : 1
        selectedDeviceIndex = service.state.devices(for: direction).firstIndex {
            $0.id == service.state.selectedID(for: direction)
        } ?? 0
        picker = direction
    }

    func selectDevice() {
        guard let picker else { return }
        let devices = service.state.devices(for: picker)
        guard devices.indices.contains(selectedDeviceIndex) else { return }
        service.select(devices[selectedDeviceIndex].id, for: picker)
        if service.error == nil { dismissOverlay() }
    }

    func dismissOverlay() { picker = nil }

    func deactivate() {
        dismissOverlay()
        service.stop()
    }
}
