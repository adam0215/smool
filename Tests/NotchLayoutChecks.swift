import AppKit

@main
struct NotchLayoutChecks {
    static func main() {
        let macBook = NotchLayout(
            screenFrame: CGRect(x: 0, y: 0, width: 1512, height: 982),
            topInset: 32,
            leftArea: CGRect(x: 0, y: 950, width: 660, height: 32),
            rightArea: CGRect(x: 852, y: 950, width: 660, height: 32)
        )
        precondition(macBook.notchSize == CGSize(width: 192, height: 32))
        precondition(macBook.expandedSize == CGSize(width: 440, height: 216))
        checkPlacement(macBook)

        let external = NotchLayout(screenFrame: CGRect(x: -2560, y: 200, width: 2560, height: 1440), topInset: 0)
        precondition(external.notchSize.height == 0, "A display without a notch must collapse completely.")
        precondition(external.expandedSize.height == 184)
        checkPlacement(external)

        let upperDisplay = NotchLayout(screenFrame: CGRect(x: 100, y: 982, width: 1920, height: 1080), topInset: 0)
        checkPlacement(upperDisplay)

        let wideNotch = NotchLayout(
            screenFrame: CGRect(x: 0, y: 0, width: 1512, height: 982),
            topInset: 38,
            leftArea: CGRect(x: 0, y: 944, width: 540, height: 38),
            rightArea: CGRect(x: 972, y: 944, width: 540, height: 38)
        )
        precondition(wideNotch.expandedSize.width == 532, "The expanded panel must surround the notch.")
        checkPlacement(wideNotch)

        let compactDisplay = NotchLayout(screenFrame: CGRect(x: 0, y: 0, width: 400, height: 600), topInset: 0)
        precondition(compactDisplay.expandedSize.width == 360)
        checkPlacement(compactDisplay)

        let demo = NotchLayout(screenFrame: external.screenFrame, topInset: 0, demoNotch: true)
        precondition(demo.isDemo)
        precondition(demo.notchSize == CGSize(width: 185, height: 32))
        precondition(demo.expandedSize.height == 216)
        checkPlacement(demo)

        let hardwareWithDemoEnabled = NotchLayout(
            screenFrame: macBook.screenFrame,
            topInset: 32,
            leftArea: CGRect(x: 0, y: 950, width: 660, height: 32),
            rightArea: CGRect(x: 852, y: 950, width: 660, height: 32),
            demoNotch: true
        )
        precondition(!hardwareWithDemoEnabled.isDemo, "A real notch must take precedence over the demo.")
        precondition(hardwareWithDemoEnabled.notchSize == macBook.notchSize)

        print("Passed: hardware notch, notch-free collapse, demo notch, hardware precedence, and multiple-display placement.")
    }

    private static func checkPlacement(_ layout: NotchLayout) {
        precondition(layout.windowFrame.midX == layout.screenFrame.midX, "Panel must be horizontally centered.")
        precondition(layout.windowFrame.maxY == layout.screenFrame.maxY, "Panel must touch the physical screen edge.")
    }
}
