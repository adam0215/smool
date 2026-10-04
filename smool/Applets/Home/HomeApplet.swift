import SwiftUI

@MainActor @Observable
final class HomeApplet: Applet {
    let id = AppletID.home
    let title = "Home"
    let icon = AppletIcon.symbol("house.fill")
    let tint = Color.blue
    let calendar: CalendarService
    private let now: () -> Date
    private(set) var showCalendar = false
    var selectedEventIndex = 0
    var showsEventDetails = false

    init(calendar: CalendarService = CalendarService(), now: @escaping () -> Date = { .now }) {
        self.calendar = calendar
        self.now = now
    }

    var contentHeight: CGFloat { showCalendar ? 168 : 120 }

    var actions: [AppletAction] {
        [
            AppletAction(id: "toggle-calendar", title: showCalendar ? "Back to clock" : "Show calendar", symbol: showCalendar ? "clock" : "calendar") { if self.showCalendar { self.showCalendar = false } else { self.openCalendar() } },
            AppletAction(id: "open-calendar", title: "Open Calendar", symbol: "arrow.up.right") { self.calendar.openCalendar() }
        ]
    }

    func makeView(context: AppletContext, artwork: NSImage?) -> AnyView {
        AnyView(Group {
            if showCalendar {
                CalendarAppletView(applet: self)
            } else {
                TimelineView(.everyMinute) { timeline in
                    NotchHomeView(
                        layout: context.layout,
                        date: timeline.date,
                        applets: context.frontApplets,
                        openApplet: context.openApplet,
                        openCalendar: self.openCalendar
                    )
                }
            }
        })
    }

    func openCalendar() {
        calendar.showDay(containing: now())
        selectedEventIndex = 0
        showsEventDetails = false
        showCalendar = true
    }

    func handleBack() -> Bool {
        guard showCalendar else { return false }
        if showsEventDetails { showsEventDetails = false }
        else { showCalendar = false }
        return true
    }

    func deactivate() {
        showCalendar = false
        showsEventDetails = false
    }
}
