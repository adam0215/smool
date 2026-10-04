@testable import SmoolChecksSupport
import Foundation
import Observation

@main
struct CodexServiceActivityChecks {
    @MainActor static func main() async {
        // No lifecycle is started. Following a disconnected desktop is a no-op,
        // and every stream event below is supplied by these local fixtures.
        let service = CodexService()
        service.selectThread("selected")
        service.receive(event("selected", snapshot("selected", revision: 1)))
        service.receive(event("status-only", snapshot("status-only", revision: 1)))
        precondition(service.activities.isEmpty, "Activity publication must be coalesced.")
        precondition(service.attentionByThread["status-only"] == .working)
        await service.publishActivities()
        precondition(service.activities["selected"]?.latestMessage?.text == "Pågår")
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
        await service.publishActivities()
        precondition(service.activities["selected"]?.latestMessage?.text == "Nytt svar")

        service.receive(event("selected", patches(base: 8, revision: 9, [])))
        precondition(service.threads.first { $0.id == "selected" }?.isConnected == false)
        precondition(service.activities["selected"]?.latestMessage?.text == "Nytt svar", "A revision gap preserves the last complete presentation.")
        service.receive(event("selected", patches(base: 2, revision: 3, [
            patch("replace", [.string("title")], .string("Untrusted patch after gap"))
        ])))
        precondition(service.threads.first { $0.id == "selected" }?.isConnected == false, "A patch cannot reconnect without a snapshot.")
        service.receive(event("selected", snapshot("selected", revision: 10, active: false, text: "Slutsvar")))
        await service.publishActivities()
        precondition(service.activities["selected"]?.latestMessage?.text == "Slutsvar")
        precondition(service.attentionByThread["selected"] == .idle)
        service.receive(event("selected", snapshot("selected", revision: 9, text: "Äldre svar")))
        await service.publishActivities()
        precondition(service.activities["selected"]?.latestMessage?.text == "Slutsvar", "An older snapshot cannot undo a completed answer.")

        let state = CodexAppletState()
        state.page = .active
        state.selection[.active] = "selected"
        state.retainedActiveThreadIDs.insert("selected")
        precondition(state.threadSelection(in: service.threads, projects: []).selectedThread?.id == "selected",
                     "Completion must not remove the selected result while it is being read.")

        service.receive(event("selected", snapshot("selected", revision: 1, text: "Ny ägare"), owner: "owner-b"))
        await service.publishActivities()
        precondition(service.activities["selected"]?.latestMessage?.text == "Ny ägare")
        service.receive(event("selected", snapshot("selected", revision: 50, text: "Pensionerad ägare")))
        await service.publishActivities()
        precondition(service.activities["selected"]?.latestMessage?.text == "Ny ägare", "A retired owner cannot overwrite the new owner's snapshot.")

        for id in ["second", "third", "fourth"] {
            service.selectThread(id)
            service.receive(event(id, snapshot(id, revision: 1)))
        }
        await service.publishActivities()
        precondition(service.activities.count == 4)
        service.selectThread("selected")
        service.selectThread("fifth")
        service.receive(event("fifth", snapshot("fifth", revision: 1)))
        await service.publishActivities()
        precondition(Set(service.activities.keys) == ["selected", "third", "fourth", "fifth"],
                     "Keep at most four full streams, evicting the least recently selected.")
        precondition(service.attentionByThread["second"] == .working, "Eviction of a timeline must retain inexpensive status.")
        precondition(service.drafts["selected"] == "Följdfråga\nmed bevarad radbrytning")
        precondition(service.drafts["status-only"] == "Ett annat utkast")

        service.receive(event("fifth", patches(base: 1, revision: 2, [
            patch("replace", [.string("turns"), .number(0), .string("items"), .number(1), .string("text")], .string("Sista uppdateringen"))
        ])))
        service.stop()
        precondition(service.activities["fifth"]?.latestMessage?.text == "Pågår", "Closing keeps the last presentation without projecting hidden content.")
        precondition(service.threads.allSatisfy { !$0.isConnected })
        precondition(service.activities.count == 4 && service.drafts.count == 2, "Closing preserves presentations and drafts.")
        await service.publishActivities()
        precondition(service.activities["fifth"]?.latestMessage?.text == "Sista uppdateringen", "Reopening can publish the update retained before disconnection.")
        precondition(service.activities["fifth"]?.revision == 2, "Disconnecting must not reset the retained content's revision.")
        service.stop()
        precondition(service.activities["fifth"]?.latestMessage?.text == "Sista uppdateringen")

        await checkProjectionIsolation()
        await checkImmediateToolCompletion()
        await checkHistoryPreviews()
        checkCancelledHandoff()
        print("Codex service activity checks passed")
    }

    @MainActor private static func checkImmediateToolCompletion() async {
        let started = AsyncStream<Void>.makeStream()
        var starts = started.stream.makeAsyncIterator()
        let release = DispatchSemaphore(value: 0)
        let service = CodexService(projectActivity: { stream in
            started.continuation.yield(())
            release.wait()
            return stream.presentation
        })
        func toolSnapshot(_ revision: Int, status: String) -> CodexJSON {
            var change = snapshot("tools", revision: revision).object
            var state = change["conversationState"]!.object
            var turn = state["turns"]!.array[0].object
            turn["items"] = .array([.object([
                "id": .string("mcp"), "type": .string("mcpToolCall"), "server": .string("fixture"),
                "tool": .string("read"), "status": .string(status)
            ])])
            state["turns"] = .array([.object(turn)])
            change["conversationState"] = .object(state)
            return .object(change)
        }
        service.selectThread("tools")
        service.receive(event("tools", toolSnapshot(1, status: "inProgress")))
        release.signal()
        await service.publishActivities()
        await starts.next()
        precondition(service.activities["tools"]?.runningTools.count == 1)

        service.receive(event("tools", toolSnapshot(2, status: "inProgress")))
        let oldProjection = Task { await service.publishActivities() }
        await starts.next()
        service.receive(event("tools", toolSnapshot(3, status: "failed")))
        precondition(service.activities["tools"]?.runningTools.isEmpty == true,
                     "Completion hides tools synchronously, before the throttled projection")
        release.signal()
        await oldProjection.value
        precondition(service.activities["tools"]?.runningTools.isEmpty == true,
                     "An in-flight projection cannot resurrect the failed tool")
        release.signal()
        await service.publishActivities()
        await starts.next()
        precondition(service.activities["tools"]?.revision == 3)
        service.receive(.object(["type": .string("broadcast"), "method": .string("ipc-connection-reset")]))
        precondition(service.threads.first { $0.id == "tools" }?.isConnected == false)
        service.receive(event("tools", patches(base: 3, revision: 4, [])))
        precondition(service.threads.first { $0.id == "tools" }?.isConnected == false,
                     "An IPC reset requires a new snapshot before deltas reconnect")
        service.receive(event("tools", toolSnapshot(1, status: "completed"), owner: "replacement"))
        release.signal()
        await service.publishActivities()
        precondition(service.activities["tools"]?.runningTools.isEmpty == true)
        started.continuation.finish()
    }

    @MainActor private static func checkHistoryPreviews() async {
        func thread(_ id: String, updatedAt: Double = 1) -> CodexThread {
            CodexThread(json: .object(["id": .string(id), "preview": .string("Opening prompt"), "updatedAt": .number(updatedAt)]))!
        }
        func page(_ text: String) -> CodexJSON {
            .object(["data": .array([.object([
                "turnId": .string("latest"), "item": .object([
                    "type": .string("agentMessage"), "id": .string("answer"), "text": .string(text)
                ])
            ])]), "nextCursor": .null])
        }
        var requests = 0
        let service = CodexService(historyRequest: { method, params in
            precondition(method == "thread/items/list")
            precondition(params["sortDirection"].string == "desc" && params["limit"].number == 50)
            requests += 1
            if params["cursor"].string == nil {
                return .object(["data": .array([.object([
                    "turnId": .string("latest"), "item": .object([
                        "type": .string("reasoning"), "summary": .array([.string("Public note")]), "content": .array([.string("PRIVATE")])
                    ])
                ])]), "nextCursor": .string("older")])
            }
            return page("Latest answer")
        })
        await service.loadHistoryPreview(thread("history"))
        precondition(requests == 2 && service.historyPreviews["history"]?.message?.text == "Latest answer")
        precondition(service.selectedThreadID == nil && service.activities.isEmpty && service.threads.isEmpty,
                     "Reading a preview does not connect, resume, select, or retain a live transcript")
        await service.loadHistoryPreview(thread("history"))
        precondition(requests == 2, "An unchanged thread uses the bounded cache")
        await service.loadHistoryPreview(thread("history", updatedAt: 2))
        precondition(requests == 4, "New thread metadata invalidates the preview")
        await service.loadHistoryPreview(thread("history", updatedAt: 2), force: true)
        precondition(requests == 6)
        var active = thread("history", updatedAt: 2)
        active.status = "active"
        active.isConnected = true
        await service.loadHistoryPreview(active)
        precondition(requests == 8)
        active.status = "idle"
        await service.loadHistoryPreview(active)
        precondition(requests == 10, "Completion invalidates a preview even before updatedAt changes")
        for index in 0..<15 { await service.loadHistoryPreview(thread("cached-\(index)")) }
        precondition(service.historyPreviews.count == 12 && service.historyPreviews["history"] == nil)

        var pages = 0
        let bounded = CodexService(historyRequest: { _, _ in
            pages += 1
            return .object(["data": .array([]), "nextCursor": .string("page-\(pages)")])
        })
        await bounded.loadHistoryPreview(thread("bounded"))
        precondition(pages == 4 && bounded.historyPreviews["bounded"]?.error != nil)
        let failed = CodexService(historyRequest: { _, _ in throw CodexConnectionError(message: "Read failed") })
        await failed.loadHistoryPreview(thread("failed"))
        precondition(failed.historyPreviews["failed"]?.error == "Read failed")
        precondition(failed.historyPreviews["failed"]?.isLoading == false)
        let empty = CodexService(historyRequest: { _, _ in .object(["data": .array([]), "nextCursor": .null]) })
        await empty.loadHistoryPreview(thread("empty"))
        precondition(empty.historyPreviews["empty"]?.isLoading == false && empty.historyPreviews["empty"]?.error == nil)
        precondition(empty.historyPreviews["empty"]?.message == nil)

        for response: CodexJSON in [
            .object([:]), .object(["data": .array([]), "nextCursor": .number(3)]),
            .object(["data": .array([.object(["item": .object(["type": .string("agentMessage")])])])])
        ] {
            let malformed = CodexService(historyRequest: { _, _ in response })
            await malformed.loadHistoryPreview(thread("malformed"))
            precondition(malformed.historyPreviews["malformed"]?.error != nil,
                         "Malformed history must show an error, rather than an empty preview")
        }

        let started = AsyncStream<Void>.makeStream()
        var starts = started.stream.makeAsyncIterator()
        var pending: CheckedContinuation<CodexJSON, any Error>?
        let delayed = CodexService(historyRequest: { _, params in
            if params["threadId"].string != "delayed" { return page("Current preview") }
            return try await withCheckedThrowingContinuation { continuation in
                pending = continuation
                started.continuation.yield(())
            }
        })
        let obsolete = Task { await delayed.loadHistoryPreview(thread("delayed")) }
        await starts.next()
        precondition(delayed.historyPreviews["delayed"]?.isLoading == true)
        await delayed.loadHistoryPreview(thread("current"))
        pending?.resume(returning: page("Stale preview"))
        await obsolete.value
        precondition(delayed.historyPreviews["delayed"] == nil && delayed.historyPreviews["current"]?.message?.text == "Current preview")

        let firstRead = Task { await delayed.loadHistoryPreview(thread("delayed")) }
        await starts.next()
        let firstResponse = pending!
        let replacementRead = Task { await delayed.loadHistoryPreview(thread("delayed")) }
        await starts.next()
        firstResponse.resume(returning: page("Superseded preview"))
        await firstRead.value
        precondition(delayed.historyPreviews["delayed"]?.isLoading == true)
        pending?.resume(returning: page("Replacement preview"))
        await replacementRead.value
        precondition(delayed.historyPreviews["delayed"]?.message?.text == "Replacement preview")

        let cancelled = Task { await delayed.loadHistoryPreview(thread("delayed"), force: true) }
        await starts.next()
        cancelled.cancel()
        pending?.resume(returning: page("Cancelled preview"))
        await cancelled.value
        precondition(delayed.historyPreviews["delayed"] == nil)
        let stopped = Task { await delayed.loadHistoryPreview(thread("delayed")) }
        await starts.next()
        delayed.stop()
        pending?.resume(returning: page("Stopped preview"))
        await stopped.value
        precondition(delayed.historyPreviews["delayed"] == nil)
        started.continuation.finish()

        service.selectThread("selected")
        service.receive(event("selected", snapshot("selected", revision: 1)))
        await service.publishActivities()
        service.selectThread(nil)
        service.receive(event("selected", snapshot("selected", revision: 2, active: false, text: "New hidden body")))
        await service.publishActivities()
        precondition(service.activities["selected"]?.latestMessage?.text == "Pågår",
                     "History selection stops projecting full live transcripts")
        precondition(service.attentionByThread["selected"] == .idle, "Lightweight status subscriptions remain available")
    }

    @MainActor private static func checkProjectionIsolation() async {
        let started = AsyncStream<Void>.makeStream()
        let release = DispatchSemaphore(value: 0)
        let service = CodexService(projectActivity: { stream in
            precondition(!Thread.isMainThread, "Transcript formatting must run away from the UI thread.")
            started.continuation.yield(())
            release.wait()
            return stream.presentation
        })
        var starts = started.stream.makeAsyncIterator()
        service.selectThread("isolated")
        service.receive(event("isolated", snapshot("isolated", revision: 1)))
        let first = Task { await service.publishActivities() }
        await starts.next()
        // This actor remains responsive while the deliberately blocked projector runs.
        service.receive(event("isolated", snapshot("isolated", revision: 2, active: false, text: "Klart")))
        await service.publishActivities()
        precondition(service.activities.isEmpty, "Concurrent publication must not create a second worker.")
        release.signal()
        await first.value
        precondition(service.attentionByThread["isolated"] == .idle, "An older projection cannot revert newer attention.")
        precondition(service.activities["isolated"]?.revision == 1)

        let second = Task { await service.publishActivities() }
        await starts.next()
        service.stop()
        release.signal()
        await second.value
        precondition(service.activities["isolated"]?.revision == 1, "Closing invalidates an in-flight projection.")

        let reopened = Task { await service.publishActivities() }
        await starts.next()
        release.signal()
        await reopened.value
        precondition(service.activities["isolated"]?.revision == 2, "Cancelled projection work remains dirty for reopening.")
        precondition(service.activities["isolated"]?.latestMessage?.text == "Klart")
        service.receive(event("isolated", snapshot("isolated", revision: 3, text: "Old owner")))
        let staleOwner = Task { await service.publishActivities() }
        await starts.next()
        service.receive(event("isolated", snapshot("isolated", revision: 1, text: "New owner"), owner: "owner-b"))
        release.signal()
        await staleOwner.value
        precondition(service.activities["isolated"]?.latestMessage?.text == "Klart", "A replaced owner cannot publish stale content.")
        let newOwner = Task { await service.publishActivities() }
        await starts.next()
        release.signal()
        await newOwner.value
        precondition(service.activities["isolated"]?.latestMessage?.text == "New owner")
        service.receive(event("isolated", snapshot("isolated", revision: 2, active: false, text: "Final answer before disconnect"), owner: "owner-b"))
        let disconnected = Task { await service.publishActivities() }
        await starts.next()
        service.receive(.object([
            "type": .string("broadcast"), "method": .string("client-status-changed"),
            "params": .object(["clientId": .string("owner-b"), "status": .string("disconnected")])
        ]))
        release.signal()
        await disconnected.value
        precondition(service.threads.first { $0.id == "isolated" }?.isConnected == false)
        precondition(service.activities["isolated"]?.latestMessage?.text == "New owner", "The invalidated worker cannot publish directly.")
        // No replacement snapshot arrives. Reopening must project the retained final answer.
        release.signal()
        await service.publishActivities()
        precondition(service.activities["isolated"]?.latestMessage?.text == "Final answer before disconnect",
                     "A disconnected in-flight projection must stay dirty until its retained content is published.")
        precondition(service.activities["isolated"]?.revision == 2)
        started.continuation.finish()
    }

    @MainActor private static func checkCancelledHandoff() {
        let state = CodexAppletState()
        state.pendingText = "Text från anteckningen"
        state.presentation = .recipientPicker
        precondition(state.pendingText == "Text från anteckningen")
        state.presentation = .deck
        precondition(state.presentation == .deck, "Dismissing the recipient picker restores applet navigation.")
        precondition(state.pendingText == "Text från anteckningen", "Dismissing the picker preserves the text handoff for a later recipient.")
        state.presentation = .recipientPicker
        precondition(state.pendingText == "Text från anteckningen", "Reopening the picker resumes its draft.")
        state.pendingText = "Ny överföring"
        let chosenText = state.pendingText
        state.pendingText = nil
        state.presentation = .deck
        precondition(chosenText == "Ny överföring" && state.pendingText == nil)
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
