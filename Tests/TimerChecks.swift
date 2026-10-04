@testable import SmoolChecksSupport
import Foundation

@main
struct TimerChecks {
    @MainActor static func main() throws {
        let examples: [(String, TimeInterval)] = [
            ("25", 1500), ("25 min", 1500), ("90 s", 90), ("2 h", 7200),
            ("1:30", 90), ("0:01", 1), (" 25 MIN \n", 1500), ("168 h", 604800)
        ]
        for (input, expected) in examples { precondition(TimerDuration.parse(input) == expected, input) }
        for input in ["", " ", "0", "-5", "1.5", "1:60", "1:3", ":30", "1:", "1:30:00", "25m", "2 h 30 min", "nan", "inf", "999999999999999999999999999999 h", "169 h", "1 2", "+1", "١"] {
            precondition(TimerDuration.parse(input) == nil, input)
        }
        precondition(TimerDuration.display(89.1) == "1:30")
        precondition(TimerDuration.display(3601) == "1:00:01")

        let directory = FileManager.default.temporaryDirectory.appending(path: "smool-timer-checks-\(UUID())")
        let file = directory.appending(path: "Timers.json")
        defer { try? FileManager.default.removeItem(at: directory) }
        var date = Date(timeIntervalSince1970: 1_800_000_000)
        var signals = 0
        let store = TimerStore(storageURL: file, now: { date }, automaticallySchedules: false, completion: { signals += 1 })
        let tea = try store.start(input: "2 min", name: "  Te  ")
        let bread = try store.start(input: "1 h", name: "Bröd")
        precondition(store.importantTimer?.id == tea && store.nextDeadline == date.addingTimeInterval(120))
        precondition(store.timers[0].title == "Te")

        date += 30
        store.pause(tea)
        precondition(store.timers[0].remaining(at: date) == 90 && store.timers[0].isPaused)
        precondition(store.importantTimer?.id == bread)
        date += 300
        precondition(store.timers[0].remaining(at: date) == 90)
        store.extend(tea)
        precondition(store.timers[0].isPaused && store.timers[0].remaining(at: date) == 150)

        let restored = TimerStore(storageURL: file, now: { date }, automaticallySchedules: false, completion: { signals += 1 })
        precondition(restored.timers == store.timers, "Paused and running state must survive restart")
        restored.resume(tea)
        precondition(restored.timers[0].deadline == date.addingTimeInterval(150))
        date += 20
        restored.extend(tea, by: 30)
        precondition(restored.timers[0].remaining(at: date) == 160)
        restored.extend(tea, by: .infinity)
        restored.extend(tea, by: -60)
        precondition(restored.timers[0].remaining(at: date) == 160)

        // Jump past both deadlines as if the machine slept. No ticks or real waiting.
        date += 7200
        restored.refresh()
        precondition(restored.timers.allSatisfy(\.isExpired) && restored.hasExpiredTimers)
        precondition(restored.nextDeadline == nil && signals == 1)
        restored.refresh()
        restored.pause(tea)
        restored.resume(tea)
        precondition(signals == 1, "Completion is delivered once per expiry batch")
        let expiredRestart = TimerStore(storageURL: file, now: { date }, automaticallySchedules: false, completion: { signals += 1 })
        precondition(expiredRestart.hasExpiredTimers && signals == 1, "Persisted expired timers stay visible without replaying sound")
        expiredRestart.remove(bread)
        expiredRestart.extend(tea)
        precondition(!expiredRestart.hasExpiredTimers && expiredRestart.timers[0].deadline == date.addingTimeInterval(60))

        // Close the app before the deadline, then restart after it.
        date += 61
        let overdueRestart = TimerStore(storageURL: file, now: { date }, automaticallySchedules: false, completion: { signals += 1 })
        precondition(overdueRestart.hasExpiredTimers && signals == 2)
        overdueRestart.remove(tea)
        precondition(overdueRestart.timers.isEmpty && overdueRestart.importantTimer == nil)
        let emptyRestart = TimerStore(storageURL: file, now: { date }, automaticallySchedules: false, completion: {})
        precondition(emptyRestart.timers.isEmpty)

        let multiple = TimerStore(storageURL: nil, now: { date }, automaticallySchedules: false, completion: {})
        for _ in 0..<TimerStore.maximumCount { try multiple.start(input: "1") }
        precondition(!multiple.canAddTimer)
        do { try multiple.start(input: "1"); preconditionFailure("Limit not enforced") }
        catch TimerStore.InputError.limit {}
        let first = multiple.timers[0].id
        multiple.pause(first)
        multiple.extend(first, by: TimerDuration.maximum)
        precondition(multiple.timers[0].remaining(at: date) == TimerDuration.maximum)
        multiple.remove(first)
        precondition(multiple.canAddTimer && multiple.timers.count == TimerStore.maximumCount - 1)
        do { try multiple.start(input: "nonsense"); preconditionFailure("Invalid input accepted") }
        catch TimerStore.InputError.invalidDuration {}

        let corrupt = Data("not json".utf8)
        try corrupt.write(to: file)
        let broken = TimerStore(storageURL: file, automaticallySchedules: false, completion: {})
        precondition(broken.persistenceError != nil && !broken.canAddTimer)
        do { try broken.start(input: "1"); preconditionFailure("Corrupt data was overwritten") }
        catch TimerStore.InputError.storageUnavailable {}
        let unchanged = try Data(contentsOf: file)
        precondition(unchanged == corrupt)

        let unwritable = TimerStore(storageURL: file.appending(path: "child"), automaticallySchedules: false, completion: {})
        try unwritable.start(input: "1")
        precondition(unwritable.persistenceError != nil, "Write failures must be visible")
        print("Passed: timer syntax, pause/resume/extend, deadlines, sleep, restart, expiry signal, acknowledgement, multiple timers, limits, and persistence errors.")
    }
}
