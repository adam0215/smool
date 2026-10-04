@testable import SmoolChecksSupport
import SwiftUI

@main
struct HomeCalendarChecks {
    @MainActor static func main() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/Stockholm")!
        var now = calendar.date(from: DateComponents(year: 2026, month: 10, day: 24, hour: 23, minute: 59))!
        let service = CalendarService(calendar: calendar, date: now)
        let home = HomeApplet(calendar: service, now: { now })
        home.openCalendar()
        precondition(service.day == calendar.startOfDay(for: now))
        service.moveDay(-3)
        let browsedDay = service.day
        now = now.addingTimeInterval(120)
        precondition(service.day == browsedDay, "Crossing midnight must not interrupt intentional browsing.")
        precondition(home.handleBack() && !home.showCalendar)
        home.openCalendar()
        precondition(service.day == calendar.startOfDay(for: now), "Opening from the clock must use today's local date.")
        let daylightSavingDay = service.day
        service.moveDay(1)
        precondition(service.day.timeIntervalSince(daylightSavingDay) == 25 * 3600, "Day navigation follows local calendar days across daylight saving changes.")
        home.showsEventDetails = true
        precondition(home.handleBack() && home.showCalendar && !home.showsEventDetails)
        precondition(home.handleBack() && !home.showCalendar)
        precondition(!home.handleBack())
        home.actions[0].perform()
        precondition(home.showCalendar && service.day == calendar.startOfDay(for: now))
        home.dismissOverlay()
        precondition(home.showCalendar, "Closing the panel preserves the calendar page.")
        home.deactivate()
        precondition(!home.showCalendar)
        print("Passed: current-day opening, midnight while browsing, reopening and nested calendar back navigation.")
    }
}
