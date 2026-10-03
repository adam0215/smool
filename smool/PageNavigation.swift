import Foundation

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
