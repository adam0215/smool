@testable import SmoolChecksSupport
import AppKit

@main
struct NotchFileDropChecks {
    @MainActor static func main() {
        _ = NSApplication.shared
        let layout = NotchLayout(screenFrame: CGRect(x: -1920, y: 982, width: 1920, height: 1080))
        let view = NotchFileDropView(layout: layout)
        let drag = FileDragInfo()
        var accepted: [[URL]] = []
        var ended = 0
        view.acceptFiles = { accepted.append($0); return true }
        view.sessionEnded = { ended += 1 }

        precondition(!view.isPreviewVisible && !view.wantsPeriodicDraggingUpdates())
        drag.draggingPasteboard.writeObjects(["ordinary text" as NSString])
        precondition(view.draggingEntered(drag).isEmpty && !view.isPreviewVisible)
        precondition(!view.performDragOperation(drag) && accepted.isEmpty)

        drag.draggingPasteboard.clearContents()
        drag.draggingPasteboard.writeObjects([URL(string: "https://example.com")! as NSURL])
        precondition(view.draggingEntered(drag).isEmpty && !view.isPreviewVisible)

        let files = [URL(fileURLWithPath: "/tmp/first file.txt"), URL(fileURLWithPath: "/tmp/second.txt")]
        drag.draggingPasteboard.clearContents()
        drag.draggingPasteboard.writeObjects(files.map { $0 as NSURL })
        precondition(!view.isPreviewVisible, "Pasteboard contents alone cannot trigger a preview")
        precondition(view.draggingEntered(drag) == .copy && view.isPreviewVisible)
        view.draggingExited(drag)
        precondition(!view.isPreviewVisible && accepted.isEmpty)
        precondition(view.draggingEntered(drag) == .copy && view.isPreviewVisible)
        view.draggingEnded(drag)
        precondition(!view.isPreviewVisible && accepted.isEmpty && ended == 1, "Cancellation must not import files")

        precondition(view.draggingEntered(drag) == .copy)
        precondition(view.prepareForDragOperation(drag) && view.performDragOperation(drag))
        precondition(!view.isPreviewVisible && accepted == [files])
        view.concludeDragOperation(drag)
        precondition(ended == 2)

        drag.draggingSourceOperationMask = .move
        precondition(view.draggingEntered(drag).isEmpty && !view.isPreviewVisible)
        precondition(!view.prepareForDragOperation(drag), "Never promise a destructive move")
        drag.draggingSourceOperationMask = .copy
        precondition(view.draggingEntered(drag) == .copy)
        view.reset()
        precondition(!view.isPreviewVisible, "Screen changes and shutdown clear drag state")

        let panel = NotchFileDropPanel(layout: layout)
        precondition(!panel.canBecomeKey && !panel.canBecomeMain && !panel.isVisible)
        precondition(panel.frame == layout.fileDropFrame)
        for layout in [layout, NotchLayout(screenFrame: CGRect(x: 0, y: 0, width: 400, height: 600)),
                       NotchLayout(screenFrame: CGRect(x: 0, y: 0, width: 1512, height: 982), notch: .physical(CGSize(width: 192, height: 32)))] {
            precondition(layout.fileDropFrame.midX == layout.screenFrame.midX)
            precondition(layout.fileDropFrame.maxY == layout.screenFrame.maxY)
            precondition(layout.fileDropFrame.minX >= layout.screenFrame.minX && layout.fileDropFrame.maxX <= layout.screenFrame.maxX)
            precondition(layout.fileDropSize.height > layout.headerSize.height)
            precondition(layout.fileDropSize.width <= layout.expandedSize.width)
        }
        drag.draggingPasteboard.releaseGlobally()
        print("Passed: native file drag validation, entry/exit/re-entry, cancellation, completion, display geometry and non-key panels")
    }
}

@MainActor
private final class FileDragInfo: NSObject, NSDraggingInfo {
    var draggingDestinationWindow: NSWindow?
    var draggingSourceOperationMask: NSDragOperation = .copy
    var draggingLocation = NSPoint.zero
    var draggedImageLocation = NSPoint.zero
    nonisolated var draggedImage: NSImage? { nil }
    let draggingPasteboard = NSPasteboard.withUniqueName()
    var draggingSource: Any? { nil }
    var draggingSequenceNumber = 1
    var draggingFormation = NSDraggingFormation.none
    var animatesToDestination = false
    var numberOfValidItemsForDrop = 0
    var springLoadingHighlight = NSSpringLoadingHighlight.none
    func slideDraggedImage(to screenPoint: NSPoint) {}
    nonisolated override func namesOfPromisedFilesDropped(atDestination dropDestination: URL) -> [String]? { nil }
    func resetSpringLoading() {}
    func enumerateDraggingItems(options: NSDraggingItemEnumerationOptions, for view: NSView?, classes: [AnyClass],
                                searchOptions: [NSPasteboard.ReadingOptionKey: Any],
                                using block: (NSDraggingItem, Int, UnsafeMutablePointer<ObjCBool>) -> Void) {}
}
