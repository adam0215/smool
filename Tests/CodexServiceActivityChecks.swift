import Foundation
import Observation

@main
struct CodexServiceActivityChecks {
    @MainActor static func main() {
        // No lifecycle is started. Following a disconnected desktop is a no-op,
        // and every stream event below is supplied by these local fixtures.
        let service = CodexService()
        service.selectThread("selected")
        service.receive(event("selected", snapshot("selected", revision: 1)))
        service.receive(event("status-only", snapshot("status-only", revision: 1)))
        precondition(service.activities.isEmpty, "Activity publication must be coalesced.")
        precondition(service.attentionByThread["status-only"] == .working)
        service.publishActivities()
        precondition(service.activities["selected"]?.items.last?.text == "Pågår")
        precondition(service.activities["status-only"] == nil, "Status subscriptions must not retain full timelines.")

        let approval: CodexJSON = .object([
            "id": .string("approval-a"), "method": .string("item/commandExecution/requestApproval"), "completed": .bool(false)
        ])
        service.receive(event("status-only", patches(base: 1, revision: 2, [
            patch("add", [.string("requests"), .number(0)], approval)
        ])))
        precondition(service.attentionByThread["status-only"] == .approval)
        precondition(service.unreadThreadIDs.contains("status-only"))
        service.receive(event("status-only", patches(base: 2, revision: 3, [
            patch("replace", [.string("requests"), .number(0), .string("completed")], .bool(true))
        ])))
        precondition(service.attentionByThread["status-only"] == .working)

        let question: CodexJSON = .object([
            "id": .string("question-a"), "method": .string("item/tool/requestUserInput"), "completed": .bool(false)
        ])
        service.receive(event("status-only", patches(base: 3, revision: 4, [
            patch("add", [.string("requests"), .number(1)], question)
        ])))
        precondition(service.attentionByThread["status-only"] == .waitingForUser)
        service.markRead("status-only")
        precondition(!service.unreadThreadIDs.contains("status-only"))

        let unchangedAttention = ActivityObservationCheck()
        withObservationTracking {
            _ = service.attentionByThread
        } onChange: {
            MainActor.assumeIsolated { unchangedAttention.changed = true }
        }
        service.receive(event("status-only", patches(base: 4, revision: 5, [
            patch("replace", [.string("turns"), .number(0), .string("items"), .number(1), .string("text")], .string("En till token"))
        ])))
        precondition(!unchangedAttention.changed, "Text tokens must not invalidate unchanged attention badges.")

        service.receive(event("failed-other", snapshot("failed-other", revision: 1, active: false)))
        service.receive(event("failed-other", patches(base: 1, revision: 2, [
            patch("replace", [.string("turns"), .number(0), .string("status")], .string("failed")),
            patch("add", [.string("turns"), .number(0), .string("error")], .object(["message": .string("Verktyget avbröts")]))
        ])))
        precondition(service.attentionByThread["failed-other"] == .failed("Verktyget avbröts"),
                     "A nonselected failed turn needs attention even when runtime status is idle.")
        precondition(service.activities["failed-other"] == nil)

        service.drafts["selected"] = "Följdfråga\nmed bevarad radbrytning"
        service.drafts["status-only"] = "Ett annat utkast"
        service.receive(event("selected", patches(base: 1, revision: 2, [
            patch("replace", [.string("turns"), .number(0), .string("items"), .number(1), .string("text")], .string("Nytt svar"))
        ])))
        service.publishActivities()
        precondition(service.activities["selected"]?.items.last?.text == "Nytt svar")

        service.receive(event("selected", patches(base: 8, revision: 9, [])))
        precondition(service.threads.first { $0.id == "selected" }?.isConnected == false)
        precondition(service.activities["selected"]?.items.last?.text == "Nytt svar", "A revision gap preserves the last complete presentation.")
        service.receive(event("selected", patches(base: 2, revision: 3, [
            patch("replace", [.string("title")], .string("Untrusted patch after gap"))
        ])))
        precondition(service.threads.first { $0.id == "selected" }?.isConnected == false, "A patch cannot reconnect without a snapshot.")
        service.receive(event("selected", snapshot("selected", revision: 10, active: false, text: "Slutsvar")))
        service.publishActivities()
        precondition(service.activities["selected"]?.items.last?.text == "Slutsvar")
        precondition(service.attentionByThread["selected"] == .idle)
        service.receive(event("selected", snapshot("selected", revision: 9, text: "Äldre svar")))
        service.publishActivities()
        precondition(service.activities["selected"]?.items.last?.text == "Slutsvar", "An older snapshot cannot undo a completed answer.")

        let state = CodexAppletState()
        state.page = .active
        state.selection[.active] = "selected"
        state.retainedActiveThreadIDs.insert("selected")
        precondition(state.threadSelection(in: service.threads, projects: []).selectedThread?.id == "selected",
                     "Completion must not remove the selected result while it is being read.")

        service.receive(event("selected", snapshot("selected", revision: 1, text: "Ny ägare"), owner: "owner-b"))
        service.publishActivities()
        precondition(service.activities["selected"]?.items.last?.text == "Ny ägare")
        service.receive(event("selected", snapshot("selected", revision: 50, text: "Pensionerad ägare")))
        service.publishActivities()
        precondition(service.activities["selected"]?.items.last?.text == "Ny ägare", "A retired owner cannot overwrite the new owner's snapshot.")

        for id in ["second", "third", "fourth"] {
            service.selectThread(id)
            service.receive(event(id, snapshot(id, revision: 1)))
        }
        service.publishActivities()
        precondition(service.activities.count == 4)
        service.selectThread("selected")
        service.selectThread("fifth")
        service.receive(event("fifth", snapshot("fifth", revision: 1)))
        service.publishActivities()
        precondition(Set(service.activities.keys) == ["selected", "third", "fourth", "fifth"],
                     "Keep at most four full streams, evicting the least recently selected.")
        precondition(service.attentionByThread["second"] == .working, "Eviction of a timeline must retain inexpensive status.")
        precondition(service.drafts["selected"] == "Följdfråga\nmed bevarad radbrytning")
        precondition(service.drafts["status-only"] == "Ett annat utkast")

        service.receive(event("fifth", patches(base: 1, revision: 2, [
            patch("replace", [.string("turns"), .number(0), .string("items"), .number(1), .string("text")], .string("Sista uppdateringen"))
        ])))
        service.stop()
        precondition(service.activities["fifth"]?.items.last?.text == "Pågår", "Closing keeps the last presentation without projecting hidden content.")
        precondition(service.threads.allSatisfy { !$0.isConnected })
        precondition(service.activities.count == 4 && service.drafts.count == 2, "Closing preserves presentations and drafts.")
        service.publishActivities()
        precondition(service.activities["fifth"]?.items.last?.text == "Sista uppdateringen", "Reopening can publish the update retained before disconnection.")
        precondition(service.activities["fifth"]?.revision == 2, "Disconnecting must not reset the retained content's revision.")
        service.stop()
        precondition(service.activities["fifth"]?.items.last?.text == "Sista uppdateringen")

        print("Codex service activity checks passed")
    }

    private static func event(_ id: String, _ change: CodexJSON, owner: String = "owner-a") -> CodexJSON {
        .object([
            "type": .string("broadcast"), "method": .string("thread-stream-state-changed"),
            "sourceClientId": .string(owner), "version": .number(11),
            "params": .object(["hostId": .string("local"), "conversationId": .string(id), "change": change])
        ])
    }

    private static func snapshot(_ id: String, revision: Int, active: Bool = true, text: String = "Pågår") -> CodexJSON {
        .object([
            "type": .string("snapshot"), "revision": .number(Double(revision)),
            "conversationState": .object([
                "id": .string(id), "title": .string(id), "cwd": .string("/tmp/fixture"), "requests": .array([]),
                "threadRuntimeStatus": .object(["type": .string(active ? "active" : "idle"), "activeFlags": .array([])]),
                "turns": .array([.object([
                    "turnId": .string("turn-a"), "status": .string(active ? "inProgress" : "completed"),
                    "items": .array([
                        .object(["id": .string("user-a"), "type": .string("userMessage"), "content": .array([
                            .object(["type": .string("text"), "text": .string("Frågan")])
                        ])]),
                        .object(["id": .string("agent-a"), "type": .string("agentMessage"), "text": .string(text)])
                    ])
                ])])
            ])
        ])
    }

    private static func patches(base: Int, revision: Int, _ values: [CodexJSON]) -> CodexJSON {
        .object(["type": .string("patches"), "baseRevision": .number(Double(base)),
                 "revision": .number(Double(revision)), "patches": .array(values)])
    }

    private static func patch(_ operation: String, _ path: [CodexJSON], _ value: CodexJSON) -> CodexJSON {
        .object(["op": .string(operation), "path": .array(path), "value": value])
    }
}

@MainActor private final class ActivityObservationCheck {
    var changed = false
}
