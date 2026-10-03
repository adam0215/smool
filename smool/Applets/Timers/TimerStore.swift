import AppKit
import Observation

@MainActor @Observable
final class TimerStore: NSObject {
    nonisolated static let maximumCount = 8

    private(set) var timers: [SmoolTimer] = []
    private(set) var persistenceError: String?

    @ObservationIgnored private let storageURL: URL?
    @ObservationIgnored private let now: () -> Date
    @ObservationIgnored private let completion: () -> Void
    @ObservationIgnored private let automaticallySchedules: Bool
    @ObservationIgnored private var deadlineTask: Task<Void, Never>?
    @ObservationIgnored private var canWrite = true

    /// The host can retain this store through TimersApplet.store. It never ticks observable state.
    /// Expired timers take priority, then the nearest running deadline, then a paused timer.
    var importantTimer: SmoolTimer? {
        timers.first(where: \.isExpired)
            ?? timers.filter { $0.deadline != nil }.min { $0.deadline! < $1.deadline! }
            ?? timers.first
    }

    var hasExpiredTimers: Bool { timers.contains(where: \.isExpired) }
    var nextDeadline: Date? { timers.compactMap(\.deadline).min() }
    var canAddTimer: Bool { timers.count < Self.maximumCount && canWrite }

    static var defaultStorageURL: URL {
        URL.applicationSupportDirectory.appending(path: "smool/Timers.json")
    }

    init(storageURL: URL? = TimerStore.defaultStorageURL,
         now: @escaping () -> Date = Date.init,
         automaticallySchedules: Bool = true,
         completion: @escaping () -> Void = { NSSound(named: "Glass")?.play() }) {
        self.storageURL = storageURL
        self.now = now
        self.automaticallySchedules = automaticallySchedules
        self.completion = completion
        super.init()
        load()
        refresh()

        if automaticallySchedules {
            NSWorkspace.shared.notificationCenter.addObserver(
                self, selector: #selector(systemTimeChanged), name: NSWorkspace.didWakeNotification, object: nil
            )
            for name in [Notification.Name.NSSystemClockDidChange, NSApplication.didBecomeActiveNotification] {
                NotificationCenter.default.addObserver(self, selector: #selector(systemTimeChanged), name: name, object: nil)
            }
        }
    }

    deinit { deadlineTask?.cancel() }

    enum InputError: LocalizedError {
        case invalidDuration, limit, storageUnavailable

        var errorDescription: String? {
            switch self {
            case .invalidDuration: "Ange en tid från 1 sekund till 7 dygn. \(TimerDuration.syntax)."
            case .limit: "Du kan ha högst \(TimerStore.maximumCount) timers. Ta bort en för att skapa en ny."
            case .storageUnavailable: "Sparade timers kunde inte läsas. Filen har lämnats orörd."
            }
        }
    }

    @discardableResult
    func start(input: String, name: String = "") throws -> UUID {
        guard let duration = TimerDuration.parse(input) else { throw InputError.invalidDuration }
        guard canWrite else { throw InputError.storageUnavailable }
        guard timers.count < Self.maximumCount else { throw InputError.limit }
        let timer = SmoolTimer(id: UUID(), name: String(name.trimmingCharacters(in: .whitespacesAndNewlines).prefix(80)),
                               state: .running(deadline: now().addingTimeInterval(duration)))
        timers.append(timer)
        save()
        scheduleDeadline()
        return timer.id
    }

    func pause(_ id: UUID) {
        refresh()
        guard let index = timers.firstIndex(where: { $0.id == id }), timers[index].deadline != nil else { return }
        let remaining = timers[index].remaining(at: now())
        guard remaining > 0 else { refresh(); return }
        timers[index].state = .paused(remaining: remaining)
        save()
        scheduleDeadline()
    }

    func resume(_ id: UUID) {
        guard let index = timers.firstIndex(where: { $0.id == id }),
              case .paused(let remaining) = timers[index].state else { return }
        timers[index].state = .running(deadline: now().addingTimeInterval(remaining))
        save()
        scheduleDeadline()
    }

    /// Extending a paused timer keeps it paused; extending an expired timer starts it again.
    func extend(_ id: UUID, by duration: TimeInterval = 60) {
        guard duration.isFinite, duration > 0, duration <= TimerDuration.maximum else { return }
        refresh()
        guard let index = timers.firstIndex(where: { $0.id == id }) else { return }
        let remaining = min(TimerDuration.maximum, timers[index].remaining(at: now()) + duration)
        timers[index].state = timers[index].isPaused
            ? .paused(remaining: remaining)
            : .running(deadline: now().addingTimeInterval(remaining))
        save()
        scheduleDeadline()
    }

    /// Removing an expired timer also acknowledges it.
    func remove(_ id: UUID) {
        guard timers.contains(where: { $0.id == id }) else { return }
        timers.removeAll { $0.id == id }
        save()
        scheduleDeadline()
    }

    /// Also called after wake and system clock changes; tests advance an injected clock then call this.
    func refresh() {
        let date = now()
        var didExpire = false
        for index in timers.indices {
            if let deadline = timers[index].deadline, deadline <= date {
                timers[index].state = .expired(at: deadline)
                didExpire = true
            }
        }
        if didExpire {
            save()
            completion()
        }
        scheduleDeadline()
    }

    @objc nonisolated private func systemTimeChanged() {
        Task { @MainActor [weak self] in self?.refresh() }
    }

    private func scheduleDeadline() {
        deadlineTask?.cancel()
        deadlineTask = nil
        guard automaticallySchedules, let deadline = nextDeadline else { return }
        let delay = min(TimerDuration.maximum, max(0.01, deadline.timeIntervalSince(now())))
        deadlineTask = Task { [weak self] in
            do { try await Task.sleep(for: .seconds(delay)) }
            catch { return }
            self?.refresh()
        }
    }

    private struct SavedTimers: Codable {
        var version = 1
        let timers: [SmoolTimer]
    }

    private func load() {
        guard let storageURL, FileManager.default.fileExists(atPath: storageURL.path) else { return }
        do {
            let saved = try JSONDecoder().decode(SavedTimers.self, from: Data(contentsOf: storageURL))
            guard saved.version == 1, saved.timers.count <= Self.maximumCount,
                  Set(saved.timers.map(\.id)).count == saved.timers.count,
                  saved.timers.allSatisfy(Self.isValid) else { throw CocoaError(.fileReadCorruptFile) }
            timers = saved.timers
        } catch {
            canWrite = false
            persistenceError = "Kunde inte läsa sparade timers. Filen har lämnats orörd."
        }
    }

    private static func isValid(_ timer: SmoolTimer) -> Bool {
        guard timer.name.count <= 80 else { return false }
        switch timer.state {
        case .running(let date), .expired(let date): return date.timeIntervalSinceReferenceDate.isFinite
        case .paused(let remaining): return remaining.isFinite && remaining > 0 && remaining <= TimerDuration.maximum
        }
    }

    private func save() {
        guard canWrite, let storageURL else { return }
        do {
            try FileManager.default.createDirectory(at: storageURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            let data = try JSONEncoder().encode(SavedTimers(timers: timers))
            try data.write(to: storageURL, options: .atomic)
            persistenceError = nil
        } catch {
            persistenceError = "Timers kunde inte sparas och kan försvinna vid omstart."
        }
    }
}
