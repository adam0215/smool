import SwiftUI

@MainActor @Observable
final class HomeApplet: Applet {
    let id = AppletID(rawValue: "home")
    let title = "Hem"
    let icon = AppletIcon.symbol("house.fill")
    let tint = Color.blue
    private let calendar = CalendarService()
    var showCalendar = false

    var contentHeight: CGFloat { showCalendar ? 168 : 120 }

    var actions: [AppletAction] {
        [
            AppletAction(id: showCalendar ? "Till klockan" : "Visa kalender", symbol: showCalendar ? "clock" : "calendar") { self.showCalendar.toggle() },
            AppletAction(id: "Öppna Kalender", symbol: "arrow.up.right") { self.calendar.openCalendar() }
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
                        openApp: context.openShortcut,
                        canOpenApp: context.canOpenShortcut,
                        shortcutNumber: context.shortcutNumber,
                        openCalendar: { self.showCalendar = true }
                    )
                }
            }
        })
    }

    func deactivate() { showCalendar = false }
}
