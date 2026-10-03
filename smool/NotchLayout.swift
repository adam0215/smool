import AppKit

/// Panel dimensions in points. Display coordinates are AppKit's bottom-up coordinates.
struct NotchLayout {
    static let bottomRadius: CGFloat = 64
    static let contentInset: CGFloat = 8

    let screenFrame: CGRect
    let notch: ScreenNotch
    var contentHeight: CGFloat = 120

    var headerSize: CGSize { notch.size ?? ScreenNotch.referenceSize }

    var navigationHeight: CGFloat { headerSize.height }

    var collapsedSize: CGSize {
        notch.size ?? CGSize(width: headerSize.width, height: 0)
    }

    // Status symbols sit to the right of the camera, with no empty mirrored region.
    func collapsedSize(statusCount: Int) -> CGSize {
        guard statusCount > 0 else { return collapsedSize }
        return CGSize(width: (notch.obscuresCenter ? headerSize.width : 0) + CGFloat(statusCount) * 28,
                      height: headerSize.height)
    }

    func collapsedOffset(statusCount: Int) -> CGFloat {
        notch.obscuresCenter ? CGFloat(statusCount) * 14 : 0
    }

    func collapsedFrame(statusCount: Int) -> CGRect {
        let size = collapsedSize(statusCount: statusCount)
        return CGRect(x: screenFrame.midX - size.width / 2 + collapsedOffset(statusCount: statusCount),
                      y: screenFrame.maxY - size.height, width: size.width, height: size.height)
    }

    var expandedSize: CGSize {
        CGSize(
            width: min(max(560, headerSize.width + 360), screenFrame.width - 40),
            height: navigationHeight + contentHeight
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
