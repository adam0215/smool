import CoreAudio

struct AudioDevice: Identifiable, Equatable {
    let id: AudioDeviceID
    let name: String
    let hasOutput: Bool
    let hasInput: Bool
}

enum AudioDirection {
    case output, input

    var title: String { self == .output ? "Output" : "Microphone" }
    var symbol: String { self == .output ? "speaker.wave.2" : "mic" }
    var scope: AudioObjectPropertyScope {
        self == .output ? kAudioDevicePropertyScopeOutput : kAudioDevicePropertyScopeInput
    }
    var defaultSelector: AudioObjectPropertySelector {
        self == .output ? kAudioHardwarePropertyDefaultOutputDevice : kAudioHardwarePropertyDefaultInputDevice
    }
}

struct AudioVolume: Equatable {
    struct Channel: Equatable {
        let element: AudioObjectPropertyElement
        let value: Float32
    }

    let channels: [Channel]
    var value: Float32 { channels.map(\.value).max() ?? 0 }
    var isAdjustable: Bool { !channels.isEmpty }

    func setting(_ value: Float32) -> [Channel] {
        guard value.isFinite else { return [] }
        let target = min(1, max(0, value))
        let peak = self.value
        return channels.map {
            Channel(element: $0.element, value: peak > 0 ? $0.value / peak * target : target)
        }
    }
}

struct AudioDeviceSnapshot {
    var devices: [AudioDevice] = []
    var outputID: AudioDeviceID = kAudioObjectUnknown
    var inputID: AudioDeviceID = kAudioObjectUnknown
    var volume = AudioVolume(channels: [])

    func devices(for direction: AudioDirection) -> [AudioDevice] {
        devices.filter { direction == .output ? $0.hasOutput : $0.hasInput }
    }

    func selectedID(for direction: AudioDirection) -> AudioDeviceID {
        direction == .output ? outputID : inputID
    }

    func selectedDevice(for direction: AudioDirection) -> AudioDevice? {
        devices.first { $0.id == selectedID(for: direction) }
    }
}

@MainActor
protocol AudioDeviceControlling: AnyObject {
    func snapshot() throws -> AudioDeviceSnapshot
    func select(_ id: AudioDeviceID, for direction: AudioDirection) throws
    func setVolume(_ value: Float32, for id: AudioDeviceID) throws
    func observe(_ change: @escaping @MainActor @Sendable () -> Void)
    func stopObserving()
}
