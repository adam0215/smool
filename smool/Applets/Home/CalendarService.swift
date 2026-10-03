import AppKit
import EventKit
import Observation

@MainActor @Observable
final class CalendarService {
    private let store = EKEventStore()
    private var loadedDay: Date?
    private(set) var events: [EKEvent] = []
    private(set) var isLoading = false
    private(set) var isRequestingAccess = false
    private(set) var message: String?
    private(set) var needsPermission = false
    var day = Calendar.current.startOfDay(for: .now)

    func load(requestAccess: Bool = false) async {
        guard !isRequestingAccess else { return }
        isLoading = loadedDay != day
        defer { isLoading = false; isRequestingAccess = false }
        do {
            let status = EKEventStore.authorizationStatus(for: .event)
            if status == .notDetermined {
                guard requestAccess else {
                    needsPermission = true
                    message = "Connect your calendar"
                    return
                }
                isRequestingAccess = true
                NSApp.activate()
                _ = try await store.requestFullAccessToEvents()
            }
            try Task.checkCancellation()
            needsPermission = EKEventStore.authorizationStatus(for: .event) != .fullAccess
            guard !needsPermission else {
                events = []
                message = "Allow calendar access for smool in System Settings."
                return
            }
            guard let end = Calendar.current.date(byAdding: .day, value: 1, to: day) else { return }
            events = store.events(matching: store.predicateForEvents(withStart: day, end: end, calendars: nil))
                .sorted { $0.startDate < $1.startDate }
            loadedDay = day
            message = nil
        } catch is CancellationError {
            return
        } catch {
            message = "Could not load the calendar. \(error.localizedDescription)"
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
