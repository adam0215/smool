import SwiftUI

enum NotchTab: Int, CaseIterable, Hashable {
    case home, spotify, codex

    var title: String {
        switch self {
        case .home: "Hem"
        case .spotify: "Spotify"
        case .codex: "Codex"
        }
    }

    var contentHeight: CGFloat { self == .home ? 120 : 320 }

    var tint: Color {
        switch self {
        case .home: .blue
        case .spotify: .green
        case .codex: .purple
        }
    }

    func neighbor(_ offset: Int) -> NotchTab {
        let tabs = Self.allCases
        return tabs[(rawValue + offset % tabs.count + tabs.count) % tabs.count]
    }
}

/// Long lists stop at their edges; card stacks use cyclingPage instead.
func adjacentPage<Page: Equatable>(in pages: [Page], to selection: Page, offset: Int) -> Page {
    guard let index = pages.firstIndex(of: selection) else { return selection }
    return pages[min(max(index + offset, 0), pages.count - 1)]
}

/// Circular navigation for card stacks and small collections.
func cyclingPage<Page: Equatable>(in pages: [Page], to selection: Page, offset: Int) -> Page {
    guard let index = pages.firstIndex(of: selection) else { return selection }
    return pages[(index + offset % pages.count + pages.count) % pages.count]
}
