import CoreAudio
import SwiftUI

@main
struct AudioAppletRenderingChecks {
    @MainActor static func main() throws {
        _ = NSApplication.shared
        NSApp.appearance = NSAppearance(named: .darkAqua)
        let folder = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
        for adjustable in [true, false] {
            let hardware = RenderAudioDevices(adjustable: adjustable)
            let applet = AudioApplet(service: AudioService(devices: hardware))
            applet.service.start()
            precondition(applet.id.rawValue == "audio" && applet.title == "Audio")
            precondition(applet.handleArrow(.down, command: false) && applet.selectedControl == 1)
            precondition(applet.handleArrow(.down, command: false) && applet.selectedControl == 2)
            precondition(!applet.handleArrow(.left, command: true))
            _ = applet.handleArrow(.right, command: false)
            precondition(hardware.volumeWrites == (adjustable ? 1 : 0))
            applet.picker = .input
            precondition(applet.hasPresentedOverlay && !applet.handleArrow(.down, command: false))
            applet.dismissOverlay()
            precondition(!applet.hasPresentedOverlay)
            applet.selectedControl = 0
            let content = AudioAppletView(applet: applet)
                .frame(width: 440, height: applet.contentHeight)
                .background(.black)
                .environment(\.colorScheme, .dark)
            let host = NSHostingView(rootView: content)
            let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 440, height: applet.contentHeight),
                                  styleMask: [.borderless], backing: .buffered, defer: false)
            window.appearance = NSAppearance(named: .darkAqua)
            window.contentView = host
            window.orderFrontRegardless()
            host.layoutSubtreeIfNeeded()
            RunLoop.current.run(until: Date().addingTimeInterval(0.1))
            host.displayIfNeeded()
            guard let bitmap = host.bitmapImageRepForCachingDisplay(in: host.bounds) else {
                fatalError("Could not render audio applet")
            }
            host.cacheDisplay(in: host.bounds, to: bitmap)
            let name = adjustable ? "audio-adjustable.png" : "audio-fixed.png"
            try bitmap.representation(using: .png, properties: [:])!.write(to: folder.appendingPathComponent(name))
            window.orderOut(nil)
            applet.deactivate()
            precondition(!hardware.observing)
        }
        print("Passed audio keyboard navigation, fixed-volume behavior, lifecycle, and fixture renders.")
    }
}

@MainActor
private final class RenderAudioDevices: AudioDeviceControlling {
    let adjustable: Bool
    var observing = false
    var volumeWrites = 0
    init(adjustable: Bool) { self.adjustable = adjustable }
    func snapshot() throws -> AudioDeviceSnapshot {
        AudioDeviceSnapshot(devices: [
            AudioDevice(id: 1, name: adjustable ? "MacBook Pro-högtalare" : "Studio Display via digital ljudutgång", hasOutput: true, hasInput: false),
            AudioDevice(id: 2, name: "MacBook Pro-mikrofon", hasOutput: false, hasInput: true)
        ], outputID: 1, inputID: 2, volume: AudioVolume(channels: adjustable ? [.init(element: 0, value: 0.42)] : []))
    }
    func select(_ id: AudioDeviceID, for direction: AudioDirection) throws {}
    func setVolume(_ value: Float32, for id: AudioDeviceID) throws { volumeWrites += 1 }
    func observe(_ change: @escaping @MainActor @Sendable () -> Void) { observing = true }
    func stopObserving() { observing = false }
}
