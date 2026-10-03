import SwiftUI

@MainActor @Observable
final class HomeApplet: Applet {
    let id = AppletID.home
    let title = "Home"
    let icon = AppletIcon.symbol("house.fill")
    let tint = Color.blue
    private let calendar = CalendarService()
    var showCalendar = false

    var contentHeight: CGFloat { showCalendar ? 168 : 120 }

    var actions: [AppletAction] {
        [
            AppletAction(id: showCalendar ? "Back to clock" : "Show calendar", symbol: showCalendar ? "clock" : "calendar") { self.showCalendar.toggle() },
            AppletAction(id: "Open Calendar", symbol: "arrow.up.right") { self.calendar.openCalendar() }
        ]
    }

    func makeView(context: AppletContext, artwork: NSImage?) -> AnyView {
        AnyView(Group {
            if showCalendar {
                CalendarAppletView(service: calendar) { self.showCalendar = false }
            } else {
                TimelineView(.everyMinute) { timeline in
                    NotchHomeView(
                        layout: context.layout,
                        date: timeline.date,
                        applets: context.frontApplets,
                        openApplet: context.openApplet,
                        openCalendar: { self.showCalendar = true }
                    )
                }
            }
        })
    }

    func deactivate() { showCalendar = false }
}
