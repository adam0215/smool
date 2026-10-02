import AppKit

/// The cutout on one display. A simulated cutout follows the same UI rules as hardware.
enum ScreenNotch: Equatable {
    case none
    case physical(CGSize)
    case simulated(CGSize)

    // Reference for a 14-inch MacBook Pro at 1512 × 982 points.
    static let referenceSize = CGSize(width: 185, height: 32)

    var size: CGSize? {
        switch self {
        case .none: nil
        case .physical(let size), .simulated(let size): size
        }
    }

    var isPhysical: Bool {
        if case .physical = self { return true }
        return false
    }

    var isSimulated: Bool {
        if case .simulated = self { return true }
        return false
    }

    var obscuresCenter: Bool { size != nil }

    init(topInset: CGFloat, leftArea: CGRect?, rightArea: CGRect?) {
        guard topInset > 0 else {
            self = .none
            return
        }

        // Keep the camera area reserved even if macOS cannot supply its side rectangles.
        let measuredWidth: CGFloat
        if let leftArea, let rightArea {
            measuredWidth = rightArea.minX - leftArea.maxX
        } else {
            measuredWidth = 0
        }
        let width = measuredWidth > 0 ? measuredWidth : Self.referenceSize.width
        self = .physical(CGSize(width: width, height: topInset))
    }

    @MainActor
    init(screen: NSScreen) {
        self.init(
            topInset: screen.safeAreaInsets.top,
            leftArea: screen.auxiliaryTopLeftArea,
            rightArea: screen.auxiliaryTopRightArea
        )
    }

    func simulatingIfAbsent(_ enabled: Bool) -> ScreenNotch {
        self == .none && enabled ? .simulated(Self.referenceSize) : self
    }
}
