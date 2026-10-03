import CoreAudio
import Foundation

@MainActor
final class CoreAudioDevices: AudioDeviceControlling {
    private let system = AudioObjectID(kAudioObjectSystemObject)
    private var listeners: [PropertyListener] = []
    private var onChange: (@MainActor @Sendable () -> Void)?

    func snapshot() throws -> AudioDeviceSnapshot {
        let ids: [AudioDeviceID] = try array(system, address(kAudioHardwarePropertyDevices))
        let devices = ids.compactMap { id -> AudioDevice? in
            guard (try? scalar(id, address(kAudioDevicePropertyDeviceIsAlive), as: UInt32.self)) == 1 else { return nil }
            let output = canBeDefault(id, .output)
            let input = canBeDefault(id, .input)
            guard output || input else { return nil }
            var property = address(kAudioObjectPropertyName)
            var name: Unmanaged<CFString>?
            var size = UInt32(MemoryLayout.size(ofValue: name))
            let status = AudioObjectGetPropertyData(id, &property, 0, nil, &size, &name)
            let title = status == noErr ? name?.takeRetainedValue() as String? : nil
            return AudioDevice(id: id, name: title ?? "Ljudenhet", hasOutput: output, hasInput: input)
        }.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
        let output = try scalar(system, address(AudioDirection.output.defaultSelector), as: AudioDeviceID.self)
        let input = try scalar(system, address(AudioDirection.input.defaultSelector), as: AudioDeviceID.self)
        return AudioDeviceSnapshot(devices: devices, outputID: output, inputID: input, volume: volume(for: output))
    }

    func select(_ id: AudioDeviceID, for direction: AudioDirection) throws {
        guard canBeDefault(id, direction) else { throw AudioDeviceError(status: kAudioHardwareBadDeviceError) }
        try set(system, address(direction.defaultSelector), value: id)
    }

    func setVolume(_ value: Float32, for id: AudioDeviceID) throws {
        // Re-read controls: a device may have disconnected or changed its channel layout.
        let volume = volume(for: id)
        guard volume.isAdjustable, value.isFinite else { throw AudioDeviceError(status: kAudioHardwareUnsupportedOperationError) }
        for channel in volume.setting(value) {
            try set(id, address(kAudioDevicePropertyVolumeScalar, scope: kAudioDevicePropertyScopeOutput,
                                element: channel.element), value: channel.value)
        }
    }

    func observe(_ change: @escaping @MainActor @Sendable () -> Void) {
        stopObserving()
        onChange = change
        installListeners()
    }

    func stopObserving() {
        onChange = nil
        listeners.removeAll()
    }

    private func installListeners() {
        listeners.removeAll()
        guard onChange != nil else { return }
        for selector in [kAudioHardwarePropertyDevices, kAudioHardwarePropertyDefaultOutputDevice,
                         kAudioHardwarePropertyDefaultInputDevice] {
            listen(system, address(selector))
        }
        let ids: [AudioDeviceID] = (try? array(system, address(kAudioHardwarePropertyDevices))) ?? []
        for id in ids {
            for selector in [kAudioObjectPropertyName, kAudioDevicePropertyDeviceIsAlive, kAudioObjectPropertyControlList] {
                listen(id, address(selector))
            }
            for direction in [AudioDirection.output, .input] {
                listen(id, address(kAudioDevicePropertyDeviceCanBeDefaultDevice, scope: direction.scope))
                listen(id, address(kAudioDevicePropertyStreamConfiguration, scope: direction.scope))
            }
            listen(id, address(kAudioDevicePropertyVolumeScalar, scope: kAudioDevicePropertyScopeOutput,
                               element: kAudioObjectPropertyElementWildcard))
        }
    }

    private func listen(_ id: AudioObjectID, _ property: AudioObjectPropertyAddress) {
        let block: AudioObjectPropertyListenerBlock = { [weak self] _, _ in
            Task { @MainActor [weak self] in
                guard let self, let onChange = self.onChange else { return }
                if id == self.system {
                    let ids: [AudioDeviceID] = (try? self.array(self.system, self.address(kAudioHardwarePropertyDevices))) ?? []
                    let observed = self.listeners.filter { $0.id != self.system }.map(\.id)
                    if Set(ids) != Set(observed) { self.installListeners() }
                }
                onChange()
            }
        }
        if let listener = PropertyListener(id: id, address: property, block: block) { listeners.append(listener) }
    }

    private func canBeDefault(_ id: AudioDeviceID, _ direction: AudioDirection) -> Bool {
        (try? scalar(id, address(kAudioDevicePropertyDeviceCanBeDefaultDevice, scope: direction.scope), as: UInt32.self)) == 1
    }

    private func volume(for id: AudioDeviceID) -> AudioVolume {
        func channel(_ element: AudioObjectPropertyElement) -> AudioVolume.Channel? {
            var property = address(kAudioDevicePropertyVolumeScalar, scope: kAudioDevicePropertyScopeOutput, element: element)
            var writable = DarwinBoolean(false)
            guard AudioObjectHasProperty(id, &property),
                  AudioObjectIsPropertySettable(id, &property, &writable) == noErr, writable.boolValue,
                  let value = try? scalar(id, property, as: Float32.self), value.isFinite else { return nil }
            return .init(element: element, value: min(1, max(0, value)))
        }
        if let main = channel(kAudioObjectPropertyElementMain) { return AudioVolume(channels: [main]) }
        var property = address(kAudioDevicePropertyStreamConfiguration, scope: kAudioDevicePropertyScopeOutput)
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(id, &property, 0, nil, &size) == noErr,
              size >= MemoryLayout<AudioBufferList>.size else { return AudioVolume(channels: []) }
        let storage = UnsafeMutableRawPointer.allocate(byteCount: Int(size), alignment: MemoryLayout<AudioBufferList>.alignment)
        defer { storage.deallocate() }
        guard AudioObjectGetPropertyData(id, &property, 0, nil, &size, storage) == noErr else { return AudioVolume(channels: []) }
        let buffers = UnsafeMutableAudioBufferListPointer(storage.assumingMemoryBound(to: AudioBufferList.self))
        let count = buffers.reduce(0) { $0 + Int($1.mNumberChannels) }
        guard count > 0 else { return AudioVolume(channels: []) }
        let channels = (1...count).compactMap { channel(UInt32($0)) }
        // A partial volume control would leave some output channels at the old level.
        return AudioVolume(channels: channels.count == count ? channels : [])
    }

    private func address(_ selector: AudioObjectPropertySelector,
                         scope: AudioObjectPropertyScope = kAudioObjectPropertyScopeGlobal,
                         element: AudioObjectPropertyElement = kAudioObjectPropertyElementMain) -> AudioObjectPropertyAddress {
        AudioObjectPropertyAddress(mSelector: selector, mScope: scope, mElement: element)
    }

    private func scalar<T>(_ id: AudioObjectID, _ property: AudioObjectPropertyAddress, as: T.Type) throws -> T {
        var property = property
        let storage = UnsafeMutableRawPointer.allocate(byteCount: MemoryLayout<T>.size, alignment: MemoryLayout<T>.alignment)
        defer { storage.deallocate() }
        var size = UInt32(MemoryLayout<T>.size)
        try check(AudioObjectGetPropertyData(id, &property, 0, nil, &size, storage))
        guard size == MemoryLayout<T>.size else { throw AudioDeviceError(status: kAudioHardwareBadPropertySizeError) }
        return storage.load(as: T.self)
    }

    private func array<T>(_ id: AudioObjectID, _ property: AudioObjectPropertyAddress) throws -> [T] {
        var property = property
        var size: UInt32 = 0
        try check(AudioObjectGetPropertyDataSize(id, &property, 0, nil, &size))
        guard size > 0 else { return [] }
        let storage = UnsafeMutableRawPointer.allocate(byteCount: Int(size), alignment: MemoryLayout<T>.alignment)
        defer { storage.deallocate() }
        try check(AudioObjectGetPropertyData(id, &property, 0, nil, &size, storage))
        return Array(UnsafeBufferPointer(start: storage.assumingMemoryBound(to: T.self), count: Int(size) / MemoryLayout<T>.stride))
    }

    private func set<T>(_ id: AudioObjectID, _ property: AudioObjectPropertyAddress, value: T) throws {
        var property = property
        var value = value
        try check(withUnsafePointer(to: &value) {
            AudioObjectSetPropertyData(id, &property, 0, nil, UInt32(MemoryLayout<T>.size), $0)
        })
    }

    private func check(_ status: OSStatus) throws {
        if status != noErr { throw AudioDeviceError(status: status) }
    }
}

private struct AudioDeviceError: Error {
    let status: OSStatus
}

private final class PropertyListener {
    let id: AudioObjectID
    var address: AudioObjectPropertyAddress
    let block: AudioObjectPropertyListenerBlock

    init?(id: AudioObjectID, address: AudioObjectPropertyAddress, block: @escaping AudioObjectPropertyListenerBlock) {
        self.id = id
        self.address = address
        self.block = block
        guard AudioObjectAddPropertyListenerBlock(id, &self.address, .main, block) == noErr else { return nil }
    }

    deinit { AudioObjectRemovePropertyListenerBlock(id, &address, .main, block) }
}
