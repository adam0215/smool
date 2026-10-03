import AppKit
import EventKit
import Observation

@MainActor @Observable
final class CalendarService {
    private let store = EKEventStore()
    private(set) var events: [EKEvent] = []
    private(set) var isLoading = false
    private(set) var message: String?
    private(set) var needsPermission = false
    var day = Calendar.current.startOfDay(for: .now)

    func load() async {
        isLoading = true
        defer { isLoading = false }
        do {
            let status = EKEventStore.authorizationStatus(for: .event)
            if status == .notDetermined {
                NSApp.activate()
                _ = try await store.requestFullAccessToEvents()
            }
            try Task.checkCancellation()
            needsPermission = EKEventStore.authorizationStatus(for: .event) != .fullAccess
            guard !needsPermission else {
                events = []
                message = "Tillåt kalenderåtkomst för smool i Systeminställningar."
                return
            }
            guard let end = Calendar.current.date(byAdding: .day, value: 1, to: day) else { return }
            events = store.events(matching: store.predicateForEvents(withStart: day, end: end, calendars: nil))
                .sorted { $0.startDate < $1.startDate }
            message = nil
        } catch is CancellationError {
            return
        } catch {
            message = "Kunde inte läsa kalendern. \(error.localizedDescription)"
        }
    }

    func moveDay(_ offset: Int) {
        day = Calendar.current.date(byAdding: .day, value: offset, to: day) ?? day
    }

    func openCalendar() {
        let date = Int(day.timeIntervalSinceReferenceDate)
        if let url = URL(string: "calshow:\(date)") { NSWorkspace.shared.open(url) }
    }
}
