import Foundation

@main
struct CodexActivityViewChecks {
    @MainActor static func main() {
        var reading = CodexReadingPosition()
        reading.receive(revision: 10)
        precondition(!reading.hasNewActivity)

        reading.userScrolled(to: 140, atBottom: false)
        reading.anchorID = "answer-1"
        reading.receive(revision: 11)
        precondition(reading.hasNewActivity && !reading.followsLatest)
        precondition(reading.contentOffset == 140 && reading.anchorID == "answer-1")

        var positions = ["thread-a": reading, "thread-b": CodexReadingPosition()]
        positions["thread-b"]?.receive(revision: 40)
        positions["thread-b"]?.receive(revision: 41)
        precondition(positions["thread-a"] == reading)
        precondition(positions["thread-b"]?.hasNewActivity == false)

        // Reopening an older reading position with a new snapshot must advertise unseen activity.
        reading.hasNewActivity = false
        reading.receive(revision: 11)
        precondition(!reading.hasNewActivity)
        reading.receive(revision: 15)
        precondition(reading.hasNewActivity)
        reading.userScrolled(to: 520, atBottom: true)
        precondition(reading.followsLatest && !reading.hasNewActivity)
        reading.receive(revision: 16)
        precondition(!reading.hasNewActivity)

        let initial = [item("prompt", .user), item("tool-1", .tool), item("tool-2", .tool)]
        let groups = CodexActivityGroup.make(from: initial)
        precondition(groups.count == 2 && groups[1].items.count == 2)

        // Streaming another tool preserves the group identity and its disclosure state.
        reading.expandedGroups.insert(groups[1].id)
        let extended = CodexActivityGroup.make(from: initial + [item("tool-3", .tool), item("answer", .assistant), item("tool-4", .tool)])
        precondition(extended.map(\.id) == ["prompt", "tool-1", "answer", "tool-4"])
        precondition(extended[1].items.map(\.id) == ["tool-1", "tool-2", "tool-3"])
        precondition(reading.expandedGroups.contains(extended[1].id))
        precondition(CodexActivityGroup.make(from: []).isEmpty)

        print("Codex activity reading and grouping checks passed")
    }

    private static func item(_ id: String, _ kind: CodexActivityItem.Kind) -> CodexActivityItem {
        CodexActivityItem(id: id, kind: kind, title: id, text: "", details: "", links: [], isRunning: false, isError: false)
    }
}
