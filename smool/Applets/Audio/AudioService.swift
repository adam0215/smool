import CoreAudio
import Observation

@MainActor @Observable
final class AudioService {
    private(set) var state = AudioDeviceSnapshot()
    private(set) var error: String?
    @ObservationIgnored private let devices: any AudioDeviceControlling
    @ObservationIgnored private var isObserving = false

    init(devices: any AudioDeviceControlling = CoreAudioDevices()) {
        self.devices = devices
    }

    func start() {
        guard !isObserving else { return }
        isObserving = true
        devices.observe { [weak self] in self?.refresh() }
        refresh()
    }

    func stop() {
        isObserving = false
        devices.stopObserving()
    }

    func select(_ id: AudioDeviceID, for direction: AudioDirection) {
        guard state.devices(for: direction).contains(where: { $0.id == id }) else { return }
        do {
            try devices.select(id, for: direction)
            error = nil
        } catch {
            self.error = "Kunde inte byta \(direction == .output ? "utgång" : "mikrofon"). Försök igen."
        }
        refresh()
    }

    func setVolume(_ value: Float32) {
        guard state.volume.isAdjustable, value.isFinite else { return }
        do {
            try devices.setVolume(min(1, max(0, value)), for: state.outputID)
            error = nil
        } catch {
            self.error = "Kunde inte ändra volymen. Kontrollera ljudenheten."
        }
        refresh()
    }

    private func refresh() {
        do { state = try devices.snapshot() }
        catch {
            state = AudioDeviceSnapshot()
            self.error = "Ljudenheterna kunde inte läsas."
        }
    }
}
