import Accelerate
import CoreAudio
import Observation
import os

@MainActor @Observable
final class SystemAudioLevel {
    private(set) var envelope = AudioEnvelope()
    @ObservationIgnored private var observationID = UUID()

    func observe(enabled: Bool) async {
        let id = UUID()
        observationID = id
        envelope = AudioEnvelope()
        guard enabled, !Task.isCancelled else { return }

        let tap = AudioLevelTap()
        do {
            try await tap.start()
            let clock = ContinuousClock()
            var previous = clock.now
            while !Task.isCancelled, observationID == id {
                try await Task.sleep(for: .milliseconds(33))
                let rms = await tap.readLevel()
                guard !Task.isCancelled, observationID == id else { break }
                let now = clock.now
                let elapsed = previous.duration(to: now).components
                previous = now
                envelope.update(rms: rms, elapsed: Double(elapsed.seconds) + Double(elapsed.attoseconds) / 1e18)
            }
        } catch is CancellationError {
        } catch {
            Logger(subsystem: "se.smool.mac", category: "AudioGlow")
                .notice("System audio unavailable: \(String(describing: error), privacy: .public)")
        }
        await tap.stop()
        if observationID == id { envelope = AudioEnvelope() }
    }
}

private actor AudioLevelTap {
    private var tapID = AudioObjectID(kAudioObjectUnknown)
    private var deviceID = AudioObjectID(kAudioObjectUnknown)
    private var ioProc: AudioDeviceIOProcID?
    private let samples = OSAllocatedUnfairLock(initialState: (energy: 0.0, count: 0))

    func start() throws {
        do {
            let description = CATapDescription(stereoGlobalTapButExcludeProcesses: [])
            description.name = "smool gradient"
            description.isPrivate = true
            description.muteBehavior = .unmuted
            try check(AudioHardwareCreateProcessTap(description, &tapID))

            var format = AudioStreamBasicDescription()
            var size = UInt32(MemoryLayout.size(ofValue: format))
            var address = AudioObjectPropertyAddress(
                mSelector: kAudioTapPropertyFormat,
                mScope: kAudioObjectPropertyScopeGlobal,
                mElement: kAudioObjectPropertyElementMain
            )
            try check(AudioObjectGetPropertyData(tapID, &address, 0, nil, &size, &format))
            guard format.mFormatID == kAudioFormatLinearPCM,
                  format.mFormatFlags & kAudioFormatFlagIsFloat != 0,
                  format.mBitsPerChannel == 32 else {
                throw CaptureError(status: kAudioDeviceUnsupportedFormatError)
            }

            let device: [String: Any] = [
                kAudioAggregateDeviceNameKey: "smool gradient",
                kAudioAggregateDeviceUIDKey: UUID().uuidString,
                kAudioAggregateDeviceIsPrivateKey: true,
                kAudioAggregateDeviceTapAutoStartKey: false,
                kAudioAggregateDeviceTapListKey: [[
                    kAudioSubTapUIDKey: description.uuid.uuidString,
                    kAudioSubTapDriftCompensationKey: true
                ]]
            ]
            try check(AudioHardwareCreateAggregateDevice(device as CFDictionary, &deviceID))

            let samples = samples
            try check(AudioDeviceCreateIOProcIDWithBlock(&ioProc, deviceID, nil) { _, input, _, _, _ in
                var energy = 0.0
                var count = 0
                for buffer in UnsafeMutableAudioBufferListPointer(UnsafeMutablePointer(mutating: input)) {
                    guard let data = buffer.mData else { continue }
                    let length = Int(buffer.mDataByteSize) / MemoryLayout<Float>.size
                    guard length > 0 else { continue }
                    var sum: Float = 0
                    vDSP_svesq(data.assumingMemoryBound(to: Float.self), 1, &sum, vDSP_Length(length))
                    if sum.isFinite {
                        energy += Double(sum)
                        count += length
                    }
                }
                // Never block the audio thread, and never retain the audio buffers.
                _ = samples.withLockIfAvailable { [energy, count] in
                    $0.energy += energy
                    $0.count += count
                }
            })
            try check(AudioDeviceStart(deviceID, ioProc))
        } catch {
            stop()
            throw error
        }
    }

    func readLevel() -> Double {
        samples.withLock {
            let rms = $0.count > 0 ? sqrt($0.energy / Double($0.count)) : 0
            $0 = (0, 0)
            return rms
        }
    }

    func stop() {
        if let ioProc {
            AudioDeviceStop(deviceID, ioProc)
            AudioDeviceDestroyIOProcID(deviceID, ioProc)
            self.ioProc = nil
        }
        if deviceID != kAudioObjectUnknown {
            AudioHardwareDestroyAggregateDevice(deviceID)
            deviceID = AudioObjectID(kAudioObjectUnknown)
        }
        if tapID != kAudioObjectUnknown {
            AudioHardwareDestroyProcessTap(tapID)
            tapID = AudioObjectID(kAudioObjectUnknown)
        }
    }

    private func check(_ status: OSStatus) throws {
        if status != noErr { throw CaptureError(status: status) }
    }

    private struct CaptureError: Error {
        let status: OSStatus
    }
}
