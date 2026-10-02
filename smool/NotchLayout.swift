import AppKit

struct NotchLayout {
    // Reference preset for a 14-inch MacBook Pro at 1512 × 982 points.
    static let demoNotchSize = CGSize(width: 185, height: 32)

    let screenFrame: CGRect
    let notchSize: CGSize
    let expandedSize: CGSize
    let isDemo: Bool

    init(screenFrame: CGRect, topInset: CGFloat, leftArea: CGRect? = nil, rightArea: CGRect? = nil, demoNotch: Bool = false) {
        self.screenFrame = screenFrame
        isDemo = demoNotch && topInset == 0

        let notchWidth: CGFloat
        if topInset > 0, let leftArea, let rightArea {
            notchWidth = max(0, rightArea.minX - leftArea.maxX)
        } else {
            notchWidth = 0
        }

        notchSize = isDemo ? Self.demoNotchSize : CGSize(width: notchWidth > 0 ? notchWidth : 140, height: topInset)
        expandedSize = CGSize(
            width: min(max(440, notchSize.width + 100), screenFrame.width - 40),
            height: notchSize.height + 184
        )
    }

    init(screen: NSScreen, demoNotch: Bool = false) {
        self.init(
            screenFrame: screen.frame,
            topInset: screen.safeAreaInsets.top,
            leftArea: screen.auxiliaryTopLeftArea,
            rightArea: screen.auxiliaryTopRightArea,
            demoNotch: demoNotch
        )
    }

    var windowFrame: CGRect {
        let size = CGSize(width: expandedSize.width + 48, height: expandedSize.height + 48)
        return CGRect(x: screenFrame.midX - size.width / 2, y: screenFrame.maxY - size.height, width: size.width, height: size.height)
    }
}
