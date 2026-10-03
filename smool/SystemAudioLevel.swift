import CoreAudio
import Observation
import os

@MainActor @Observable
final class SystemAudioLevel {
    private(set) var spectrum = AudioSpectrum()
    @ObservationIgnored private var observationID = UUID()

    func observe(enabled: Bool) async {
        let id = UUID()
        observationID = id
        guard enabled, !Task.isCancelled else { return }
        spectrum = AudioSpectrum()

        let tap = AudioLevelTap()
        do {
            try await tap.start()
            let clock = ContinuousClock()
            var previous = clock.now
            while !Task.isCancelled, observationID == id {
                try await Task.sleep(for: .milliseconds(33))
                let bands = await tap.readBands()
                guard !Task.isCancelled, observationID == id else { break }
                let now = clock.now
                let elapsed = previous.duration(to: now).components
                previous = now
                spectrum.update(bands, elapsed: Double(elapsed.seconds) + Double(elapsed.attoseconds) / 1e18)
            }
        } catch is CancellationError {
        } catch {
            Logger(subsystem: "se.smool.mac", category: "AudioGlow")
                .notice("System audio unavailable: \(String(describing: error), privacy: .public)")
        }
        await tap.stop()
        // Retain the final frame while the view fades back to its static gradient.
    }
}

private actor AudioLevelTap {
    private var tapID = AudioObjectID(kAudioObjectUnknown)
    private var deviceID = AudioObjectID(kAudioObjectUnknown)
    private var ioProc: AudioDeviceIOProcID?
    private var analyzer: OSAllocatedUnfairLock<AudioSpectrumAnalyzer>?

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
                  format.mBitsPerChannel == 32, format.mSampleRate.isFinite, format.mSampleRate >= 8_000,
                  (1...8).contains(format.mChannelsPerFrame) else {
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

            let analyzer = OSAllocatedUnfairLock(initialState: AudioSpectrumAnalyzer(
                sampleRate: format.mSampleRate, channelCount: Int(format.mChannelsPerFrame)
            ))
            self.analyzer = analyzer
            try check(AudioDeviceCreateIOProcIDWithBlock(&ioProc, deviceID, nil) { _, input, _, _, _ in
                // Never wait on the audio thread. Only filter state and band energies survive this callback.
                // This synchronous closure consumes Core Audio's borrowed pointer before returning.
                _ = analyzer.withLockIfAvailableUnchecked { meter in
                    var firstChannel = 0
                    for buffer in UnsafeMutableAudioBufferListPointer(UnsafeMutablePointer(mutating: input)) {
                        let channels = Int(buffer.mNumberChannels)
                        defer { firstChannel += channels }
                        guard let data = buffer.mData else { continue }
                        let samples = UnsafeBufferPointer(start: data.assumingMemoryBound(to: Float.self),
                                                          count: Int(buffer.mDataByteSize) / MemoryLayout<Float>.size)
                        meter.process(samples, channelCount: channels, firstChannel: firstChannel)
                    }
                }
            })
            try check(AudioDeviceStart(deviceID, ioProc))
        } catch {
            stop()
            throw error
        }
    }

    func readBands() -> AudioBands {
        analyzer?.withLock { $0.read() } ?? AudioBands()
    }

    func stop() {
        if let ioProc {
            AudioDeviceStop(deviceID, ioProc)
            AudioDeviceDestroyIOProcID(deviceID, ioProc)
            self.ioProc = nil
            analyzer = nil
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
