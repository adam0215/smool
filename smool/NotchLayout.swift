import AppKit

/// Panel dimensions in points. Display coordinates are AppKit's bottom-up coordinates.
struct NotchLayout {
    let screenFrame: CGRect
    let notch: ScreenNotch

    var headerSize: CGSize { notch.size ?? ScreenNotch.referenceSize }

    var collapsedSize: CGSize {
        notch.size ?? CGSize(width: headerSize.width, height: 0)
    }

    var expandedSize: CGSize {
        CGSize(
            width: min(max(480, headerSize.width + 100), screenFrame.width - 40),
            height: headerSize.height + 120
        )
    }

    var windowFrame: CGRect {
        let size = CGSize(width: expandedSize.width + 48, height: expandedSize.height + 48)
        return CGRect(x: screenFrame.midX - size.width / 2, y: screenFrame.maxY - size.height, width: size.width, height: size.height)
    }

    init(screenFrame: CGRect, notch: ScreenNotch = .none) {
        self.screenFrame = screenFrame
        self.notch = notch
    }

    @MainActor
    init(screen: NSScreen, demoNotch: Bool = false) {
        self.init(screenFrame: screen.frame, notch: ScreenNotch(screen: screen).simulatingIfAbsent(demoNotch))
    }

    func headerRegions(in width: CGFloat) -> NotchHeaderRegions {
        NotchHeaderRegions(width: width, centerSize: headerSize)
    }
}

/// Local top-down coordinates. Equal side regions keep the center fixed regardless of content.
struct NotchHeaderRegions {
    let leading: CGRect
    let center: CGRect
    let trailing: CGRect

    init(width: CGFloat, centerSize: CGSize) {
        let width = max(0, width)
        let centerWidth = min(width, centerSize.width)
        let sideWidth = (width - centerWidth) / 2

        leading = CGRect(x: 0, y: 0, width: sideWidth, height: centerSize.height)
        center = CGRect(x: sideWidth, y: 0, width: centerWidth, height: centerSize.height)
        trailing = CGRect(x: center.maxX, y: 0, width: sideWidth, height: centerSize.height)
    }
}
