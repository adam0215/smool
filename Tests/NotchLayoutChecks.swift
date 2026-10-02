import AppKit

@main
struct NotchLayoutChecks {
    static func main() {
        let screenFrame = CGRect(x: 0, y: 0, width: 1512, height: 982)
        let physical = ScreenNotch(
            topInset: 32,
            leftArea: CGRect(x: 0, y: 950, width: 660, height: 32),
            rightArea: CGRect(x: 852, y: 950, width: 660, height: 32)
        )
        precondition(physical.isPhysical && physical.obscuresCenter)
        precondition(physical.size == CGSize(width: 192, height: 32))
        precondition(physical.simulatingIfAbsent(true) == physical, "Hardware must take precedence over simulation.")

        let macBook = NotchLayout(screenFrame: screenFrame, notch: physical)
        precondition(macBook.expandedSize == CGSize(width: 480, height: 152))
        checkPlacement(macBook)

        let absent = ScreenNotch(topInset: 0, leftArea: nil, rightArea: nil)
        precondition(absent == .none && !absent.obscuresCenter)
        precondition(absent.simulatingIfAbsent(false) == .none)
        let external = NotchLayout(screenFrame: CGRect(x: -2560, y: 200, width: 2560, height: 1440), notch: absent)
        precondition(external.collapsedSize.height == 0, "A display without a notch must collapse completely.")
        precondition(external.headerSize.height == 32, "The notch-free header still has room for its center content.")
        checkPlacement(external)

        let upperDisplay = NotchLayout(screenFrame: CGRect(x: 100, y: 982, width: 1920, height: 1080))
        checkPlacement(upperDisplay)

        let offsetNotch = ScreenNotch(
            topInset: 32,
            leftArea: CGRect(x: -1512, y: 950, width: 660, height: 32),
            rightArea: CGRect(x: -660, y: 950, width: 660, height: 32)
        )
        precondition(offsetNotch == physical, "Notch detection must not depend on the display's origin.")

        let wideNotch = NotchLayout(screenFrame: screenFrame, notch: .physical(CGSize(width: 432, height: 38)))
        precondition(wideNotch.expandedSize.width == 532)
        precondition(wideNotch.headerSize.height == 38)
        checkPlacement(wideNotch)

        let compactDisplay = NotchLayout(screenFrame: CGRect(x: 0, y: 0, width: 400, height: 600))
        precondition(compactDisplay.expandedSize.width == 360)
        checkPlacement(compactDisplay)

        let simulated = absent.simulatingIfAbsent(true)
        precondition(simulated.isSimulated && !simulated.isPhysical && simulated.obscuresCenter)
        precondition(simulated.size == CGSize(width: 185, height: 32))
        checkPlacement(NotchLayout(screenFrame: external.screenFrame, notch: simulated))

        let incomplete = ScreenNotch(topInset: 38, leftArea: nil, rightArea: nil)
        precondition(incomplete.isPhysical && incomplete.obscuresCenter)
        precondition(incomplete.size?.height == 38, "Missing side rectangles must not erase a known camera area.")

        for layout in [macBook, external, wideNotch] {
            checkHeader(layout, width: 440)
            checkHeader(layout, width: 100)
            checkHeader(layout, width: 0)
        }

        print("Passed: notch detection, simulation, mixed displays, edge anchoring, and safe header regions.")
    }

    private static func checkPlacement(_ layout: NotchLayout) {
        precondition(layout.windowFrame.midX == layout.screenFrame.midX)
        precondition(layout.windowFrame.maxY == layout.screenFrame.maxY, "Panel must touch the physical screen edge.")
    }

    private static func checkHeader(_ layout: NotchLayout, width: CGFloat) {
        let regions = layout.headerRegions(in: width)
        precondition(regions.center.midX == width / 2, "The center must stay centered even in a narrow header.")
        precondition(regions.leading.width == regions.trailing.width)
        precondition(regions.leading.maxX == regions.center.minX)
        precondition(regions.trailing.minX == regions.center.maxX)
        precondition(regions.trailing.maxX == width)
        precondition(regions.center.height == layout.headerSize.height)
    }
}
