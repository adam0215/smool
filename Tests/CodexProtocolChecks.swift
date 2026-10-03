import Foundation
import Observation

@main
struct CodexProtocolChecks {
    @MainActor static func main() async throws {
        let projectThread = CodexThread(json: .object(["id": .string("fixture"), "cwd": .string("/tmp/fixture-project")]))!
        precondition(projectThread.projectPath == "/tmp/fixture-project")
        precondition(CodexThread(json: .object(["id": .string("no-project")]))?.projectPath == "")
        let validID = "01a0fe77-3272-7de3-a433-2271eec368ee"
        precondition(CodexDesktopProtocol.threadURL(validID)?.absoluteString == "codex://threads/\(validID)")
        precondition(CodexDesktopProtocol.threadURL("../other?prompt=unexpected") == nil, "Thread links must not accept extra routes or prompt parameters.")
        let text = "Förklara \"ändringen\"\nmed åäö och \\ utan att ändra filer."
        let turn = CodexDesktopProtocol.turn(text: text, threadID: "thread-a", messageID: "message-a")
        let request = CodexDesktopProtocol.request(id: "request-a", clientID: "smool-client",
                                                   method: "thread-follower-start-turn", params: turn, owner: "desktop-owner")
        let decoded = try JSONDecoder().decode(CodexJSON.self, from: JSONEncoder().encode(request))
        precondition(decoded["version"].number == 2)
        precondition(decoded["targetClientId"].string == "desktop-owner", "Route writes to the existing owner.")
        precondition(decoded["params"]["conversationId"].string == "thread-a")
        let submission = decoded["params"]["turnStart"]["request"]
        precondition(submission["threadId"].string == "thread-a")
        precondition(submission["clientUserMessageId"].string == "message-a")
        precondition(submission["input"].array.first?["text"].string == text, "Preserve exact Unicode and multiline prompts.")
        precondition(submission.object["approvalPolicy"] == nil, "Preserve the owner's approval and permission settings.")
        precondition(submission.object["model"] == nil, "Preserve the thread's model.")

        let discoveryRequest = CodexDesktopProtocol.request(id: "discovery-a", clientID: "smool-client",
            method: "thread-owner-discovery", params: .object([:]), timeoutMilliseconds: 750)
        precondition(discoveryRequest["timeoutMs"].number == 750, "Read-only discovery must use its shorter deadline.")
        precondition(request["timeoutMs"].number == 8_000, "Sending keeps the original delivery deadline.")

        let steer = CodexDesktopProtocol.steer(text: text, threadID: "thread-a", messageID: "message-a")
        let steerRequest = CodexDesktopProtocol.request(id: "request-s", clientID: "smool-client",
            method: "thread-follower-steer-turn", params: steer, owner: "desktop-owner")
        precondition(steerRequest["version"].number == 1)
        precondition(steer["input"].array.first?["text"].string == text)
        precondition(steer["restoreMessage"]["context"]["prompt"].string == text)
        precondition(steer.object["expectedTurnId"] == nil, "The existing desktop owner must resolve and check the active turn ID.")
        precondition(steer.object["serviceTier"] == nil, "Steering preserves the thread's settings.")

        func acknowledgment(steering: Bool, owner: String = "desktop-owner") -> CodexJSON {
            .object(["resultType": .string("success"), "handledByClientId": .string(owner),
                     "result": .object(["result": steering ? .object(["turnId": .string("turn-a")])
                        : .object(["turn": .object(["id": .string("turn-b")])])])])
        }
        var methods: [String] = []
        try await CodexDesktopProtocol.deliver(text: text, threadID: "thread-a", messageID: "message-a", owner: "desktop-owner") { method, params, owner in
            methods.append(method)
            precondition(owner == "desktop-owner")
            precondition(params["clientUserMessageId"].string == "message-a")
            return acknowledgment(steering: true)
        }
        precondition(methods == ["thread-follower-steer-turn"], "An active thread must receive steering, not a new turn.")

        methods = []
        try await CodexDesktopProtocol.deliver(text: text, threadID: "thread-a", messageID: "message-a", owner: "desktop-owner") { method, params, _ in
            methods.append(method)
            if method == "thread-follower-steer-turn" {
                throw CodexConnectionError(message: "Cannot steer conversation thread-a because its active turn already ended")
            }
            precondition(params["turnStart"]["request"]["clientUserMessageId"].string == "message-a", "The same message ID survives the inactive-turn fallback.")
            return acknowledgment(steering: false)
        }
        precondition(methods == ["thread-follower-steer-turn", "thread-follower-start-turn"], "An ended turn safely falls back to starting a new one.")

        for failure in ["timeout", "connection-closed", "Cannot steer conversation another-thread because its active turn already ended"] {
            methods = []
            do {
                try await CodexDesktopProtocol.deliver(text: text, threadID: "thread-a", messageID: "message-a", owner: "desktop-owner") { method, _, _ in
                    methods.append(method)
                    throw CodexConnectionError(message: failure)
                }
                preconditionFailure("An unconfirmed send must fail")
            } catch { precondition(methods == ["thread-follower-steer-turn"], "Ambiguous failures must never trigger a second submission.") }
        }
        do {
            try await CodexDesktopProtocol.deliver(text: text, threadID: "thread-a", messageID: "message-a", owner: "desktop-owner") { _, _, _ in
                acknowledgment(steering: true, owner: "wrong-owner")
            }
            preconditionFailure("Another owner's acknowledgment must not confirm delivery")
        } catch { }

        let fixture = #"{"rateLimits":{"primary":{"usedPercent":99,"windowDurationMins":300}},"rateLimitsByLimitId":{"codex":{"limitName":"Codex","primary":{"usedPercent":25,"windowDurationMins":300,"resetsAt":1800000000},"secondary":null},"unknown":{"primary":null}}}"#
        let response = try JSONDecoder().decode(CodexJSON.self, from: Data(fixture.utf8))
        let limits = CodexLimit.parse(response)
        precondition(limits.count == 1, "Missing windows must not appear as zero usage.")
        precondition(limits[0].usedPercent == 25, "Prefer the multi-bucket view over the legacy bucket.")
        precondition(limits[0].resetAt == Date(timeIntervalSince1970: 1_800_000_000))
        precondition(limits[0].durationMinutes == 300)
        precondition(!limits[0].isCodexWeek)
        let weeklyFixture = #"{"rateLimitsByLimitId":{"codex":{"secondary":{"usedPercent":22,"windowDurationMins":10080}},"gpt-reserve":{"secondary":{"usedPercent":7,"windowDurationMins":10080}}}}"#
        let weekly = CodexLimit.parse(try JSONDecoder().decode(CodexJSON.self, from: Data(weeklyFixture.utf8)))
        precondition(weekly.filter(\.isCodexWeek).map(\.id) == ["codex.secondary"], "Only Codex's seven-day window belongs in the ring.")


        let thread = CodexThread(json: .object(["id": .string("thread-a"), "name": .string("Original title"),
                                                "preview": .string("First prompt"), "updatedAt": .number(1_800_000_000_000)]))!
        precondition(thread.title == "Original title", "Retain the user's thread title.")
        precondition(thread.updatedAt == Date(timeIntervalSince1970: 1_800_000_000), "Desktop milliseconds differ from public API seconds.")
        precondition(!thread.isActive && !thread.isConnected, "A saved thread is never evidence of live activity.")
        let service = CodexService()
        service.drafts["thread-a"] = "Draft for A"
        service.drafts["thread-b"] = "Draft for B"
        service.drafts["thread-a"] = "Changed draft for A"
        precondition(service.drafts["thread-b"] == "Draft for B", "Drafts must stay attached to their intended recipient.")
        func event(_ change: CodexJSON, source: String = "owner-a", version: Int = 11) -> CodexJSON {
            .object(["type": .string("broadcast"), "method": .string("thread-stream-state-changed"),
                     "sourceClientId": .string(source), "version": .number(Double(version)),
                     "params": .object(["hostId": .string("local"), "conversationId": .string("live-a"), "change": change])])
        }
        let snapshot: CodexJSON = .object(["type": .string("snapshot"), "revision": .number(10),
            "conversationState": .object(["id": .string("live-a"), "title": .string("Live thread"),
                                           "threadRuntimeStatus": .object(["type": .string("active")])])])
        service.receive(event(snapshot))
        precondition(service.threads.first?.isActive == true)
        let duplicate = ObservationCheck()
        withObservationTracking {
            _ = service.threads
        } onChange: {
            MainActor.assumeIsolated { duplicate.changed = true }
        }
        service.receive(event(snapshot))
        precondition(!duplicate.changed, "An unchanged snapshot must not invalidate the thread view.")

        let patch: CodexJSON = .object(["type": .string("patches"), "baseRevision": .number(10), "revision": .number(11),
            "patches": .array([.object(["op": .string("replace"), "path": .array([.string("threadRuntimeStatus")]),
                                        "value": .object(["type": .string("idle")])])])])
        service.receive(event(patch))
        precondition(service.threads.first?.status == "idle", "Completion must remove active status.")
        service.receive(event(snapshot))
        service.receive(event(patch, source: "another-owner"))
        precondition(service.threads.first?.isConnected == false, "Never apply another owner's patch.")
        service.receive(event(snapshot))
        service.receive(event(.object(["type": .string("patches"), "baseRevision": .number(12), "revision": .number(13)])))
        precondition(service.threads.first?.isConnected == false, "Missing revisions invalidate live status.")
        service.receive(event(snapshot, version: 12))
        precondition(service.liveError != nil, "Unknown protocol versions must be visible.")

        service.receive(event(snapshot))
        service.stop()
        precondition(service.threads.first?.isConnected == false, "Closing must still disconnect the live service.")
        precondition(service.displayedThreads.first?.isActive == true, "Reopening should retain the last visible active thread.")
        service.stop()
        precondition(service.displayedThreads.first?.isActive == true, "Repeated cleanup must not overwrite the display snapshot.")
        print("Codex protocol checks passed")
    }
}

@MainActor private final class ObservationCheck {
    var changed = false
}
