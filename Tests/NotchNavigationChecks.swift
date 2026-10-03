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
            precondition(tab.neighbor(-10) == tab.neighbor(-10 % tabs.count))
            precondition(tab.neighbor(10) == tab.neighbor(10 % tabs.count))
        }
        precondition(NotchTab.home.neighbor(-1) == .music)
        precondition(NotchTab.music.neighbor(1) == .home)

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

        for offset in -100...100 {
            let result = cyclingPage(in: pages, to: "Playing", offset: offset)
            precondition(cyclingPage(in: pages, to: result, offset: -offset) == "Playing")
        }
        precondition(cyclingPage(in: pages, to: "Playing", offset: -1) == "Queue")
        precondition(cyclingPage(in: pages, to: "Queue", offset: 1) == "Playing")
        precondition(cyclingPage(in: [], to: "Missing", offset: 1) == "Missing")
        precondition(cyclingPage(in: ["Only"], to: "Only", offset: Int.min) == "Only")
        print("Passed: circular stacks in both directions, bounded lists, and stale selections.")
    }
}
