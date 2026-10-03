import SwiftUI

@main
struct NotchNavigationChecks {
    static func main() {
        let tabs = NotchTab.allCases
        for tab in tabs {
            precondition(tab.neighbor(1).neighbor(-1) == tab)
            precondition(tab.neighbor(-1).neighbor(1) == tab)
            precondition(tab.neighbor(tabs.count) == tab)
            precondition(tab.neighbor(-tabs.count) == tab)
            precondition(tab.neighbor(-10) == tab.neighbor(-1))
            precondition(tab.neighbor(10) == tab.neighbor(1))
        }
        precondition(NotchTab.home.neighbor(-1) == .codex)
        precondition(NotchTab.codex.neighbor(1) == .home)

        let pages = ["Playing", "Playlists", "Queue"]
        precondition(adjacentPage(in: pages, to: "Playing", offset: -1) == "Playing")
        precondition(adjacentPage(in: pages, to: "Queue", offset: 1) == "Queue")
        precondition(adjacentPage(in: pages, to: "Playing", offset: 1) == "Playlists")
        precondition(adjacentPage(in: pages, to: "Queue", offset: -1) == "Playlists")
        precondition(adjacentPage(in: pages, to: "Playlists", offset: 100) == "Queue")
        precondition(adjacentPage(in: pages, to: "Playlists", offset: -100) == "Playing")
        precondition(adjacentPage(in: pages, to: "Removed", offset: 1) == "Removed")
        precondition(adjacentPage(in: [], to: "Removed", offset: -1) == "Removed")
        precondition(adjacentPage(in: ["Only"], to: "Only", offset: 1) == "Only")

        print("Passed: tab cycling, bounded page navigation, and empty or stale page selections.")
    }
}
