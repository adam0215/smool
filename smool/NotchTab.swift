import SwiftUI

enum NotchTab: Int, CaseIterable, Hashable {
    case home, spotify, codex, music

    var title: String {
        switch self {
        case .home: "Hem"
        case .spotify: "Spotify"
        case .codex: "Codex"
        case .music: "Musik"
        }
    }

    var contentHeight: CGFloat {
        switch self {
        case .home: 120
        case .spotify: 156
        case .codex: 156
        case .music: 144
        }
    }

    var tint: Color {
        switch self {
        case .home: .blue
        case .spotify: .green
        case .codex: .purple
        case .music: .pink
        }
    }

    func neighbor(_ offset: Int) -> NotchTab {
        let tabs = Self.allCases
        return tabs[(rawValue + offset % tabs.count + tabs.count) % tabs.count]
    }
}

/// Long lists stop at their edges; pages use cyclingPage instead.
func adjacentPage<Page: Equatable>(in pages: [Page], to selection: Page, offset: Int) -> Page {
    guard let index = pages.firstIndex(of: selection) else { return selection }
    return pages[min(max(index + offset, 0), pages.count - 1)]
}

/// Circular navigation for pages and small collections.
func cyclingPage<Page: Equatable>(in pages: [Page], to selection: Page, offset: Int) -> Page {
    guard let index = pages.firstIndex(of: selection) else { return selection }
    return pages[(index + offset % pages.count + pages.count) % pages.count]
}
