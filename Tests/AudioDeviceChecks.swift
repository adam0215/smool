import CoreAudio
import Foundation

@main
struct AudioDeviceChecks {
    @MainActor static func main() throws {
        let stereo = AudioVolume(channels: [.init(element: 1, value: 0.8), .init(element: 2, value: 0.4)])
        precondition(stereo.isAdjustable && stereo.value == 0.8)
        let adjusted = stereo.setting(0.4)
        precondition(adjusted[0].value == 0.4 && adjusted[1].value == 0.2, "Preserve stereo balance")
        precondition(stereo.setting(2)[0].value == 1)
        precondition(stereo.setting(-1).allSatisfy { $0.value == 0 })
        precondition(stereo.setting(.nan).isEmpty)
        precondition(!AudioVolume(channels: []).isAdjustable)
        let silent = AudioVolume(channels: [.init(element: 1, value: 0), .init(element: 2, value: 0)])
        precondition(silent.setting(0.3).allSatisfy { $0.value == 0.3 })

        let hardware = AudioDeviceFixture()
        let service = AudioService(devices: hardware)
        service.start()
        service.start()
        precondition(hardware.starts == 1, "Starting observation must be idempotent")
        precondition(service.state.devices(for: .output).map(\.id) == [10, 20])
        precondition(service.state.devices(for: .input).map(\.id) == [30])
        precondition(service.state.selectedDevice(for: .output)?.name == "Högtalare")
        service.setVolume(2)
        precondition(hardware.writes.last == "volume:10:1.0")
        service.select(30, for: .output)
        precondition(hardware.writes.count == 1, "Reject devices without the selected direction")
        service.select(20, for: .output)
        precondition(service.state.outputID == 20)
        precondition(!service.state.volume.isAdjustable)
        let count = hardware.writes.count
        service.setVolume(0.5)
        precondition(hardware.writes.count == count, "Fixed volume must never write")
        hardware.fails = true
        service.select(30, for: .input)
        precondition(service.error != nil && service.state.inputID == 30)
        hardware.fails = false
        service.select(10, for: .output)
        precondition(service.error == nil && service.state.outputID == 10)
        service.toggleMute()
        precondition(service.state.volume.value == 0)
        service.toggleMute()
        precondition(service.state.volume.value == 0.4, "Unmute restores the output’s previous volume")
        service.select(20, for: .output)
        let beforeMute = hardware.writes.count
        service.toggleMute()
        precondition(hardware.writes.count == beforeMute, "Mute must not write to fixed-volume devices")
        service.select(10, for: .output)
        hardware.state.devices.removeAll { $0.id == 10 }
        hardware.state.outputID = 20
        hardware.state.volume = AudioVolume(channels: [])
        hardware.change?()
        precondition(service.state.outputID == 20 && service.state.devices.count == 2)
        service.stop()
        precondition(hardware.change == nil)
        service.start()
        precondition(hardware.starts == 2)
        service.stop()

        // Read-only hardware integration. Never select a device or set a volume here.
        let live = CoreAudioDevices()
        let state = try live.snapshot()
        precondition(Set(state.devices.map(\.id)).count == state.devices.count)
        precondition(state.devices.allSatisfy { $0.hasInput || $0.hasOutput })
        precondition((0...1).contains(state.volume.value))
        live.observe {}
        live.stopObserving()
        print("Passed audio fixtures, observation lifecycle, and read-only discovery: \(state.devices.count) devices, output \(state.outputID), input \(state.inputID), adjustable volume \(state.volume.isAdjustable).")
    }
}

@MainActor
private final class AudioDeviceFixture: AudioDeviceControlling {
    var state = AudioDeviceSnapshot(
        devices: [
            AudioDevice(id: 10, name: "Högtalare", hasOutput: true, hasInput: false),
            AudioDevice(id: 20, name: "Digital utgång", hasOutput: true, hasInput: false),
            AudioDevice(id: 30, name: "Mikrofon", hasOutput: false, hasInput: true)
        ], outputID: 10, inputID: 30,
        volume: AudioVolume(channels: [.init(element: 0, value: 0.4)])
    )
    var change: (@MainActor @Sendable () -> Void)?
    var starts = 0
    var writes: [String] = []
    var fails = false

    func snapshot() throws -> AudioDeviceSnapshot { state }
    func observe(_ change: @escaping @MainActor @Sendable () -> Void) { starts += 1; self.change = change }
    func stopObserving() { change = nil }

    func select(_ id: AudioDeviceID, for direction: AudioDirection) throws {
        if fails { throw CocoaError(.fileWriteUnknown) }
        writes.append("select:\(id)")
        if direction == .output {
            state.outputID = id
            state.volume = AudioVolume(channels: id == 10 ? [.init(element: 0, value: 0.4)] : [])
        } else {
            state.inputID = id
        }
    }

    func setVolume(_ value: Float32, for id: AudioDeviceID) throws {
        if fails { throw CocoaError(.fileWriteUnknown) }
        writes.append("volume:\(id):\(value)")
        state.volume = AudioVolume(channels: state.volume.setting(value))
    }
}
