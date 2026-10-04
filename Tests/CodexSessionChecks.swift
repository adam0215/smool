import Foundation

@main
struct CodexSessionChecks {
    @MainActor static func main() async throws {
        checkResponses()
        checkActivity()
        let fixture = URL(fileURLWithPath: CommandLine.arguments[1])
        let service = CodexService(makeSessionClient: { CodexClient(desktop: false, endpoint: .appServer(fixture.path)) })
        let project = CodexProject(id: "fixture-project", name: "Fixture", roots: ["/tmp/fixture", "/tmp/second-root"])
        let thread = try await service.createThread(in: project)
        precondition(service.isLocallyOwned(thread.id))
        service.selectThread(thread.id)
        try await service.sendInitialMessage("Fixture prompt", to: thread)
        try await wait { !service.localRequests(for: thread.id).isEmpty }
        precondition(service.threads.first?.isActive == true)
        precondition(service.attentionByThread[thread.id] == .approval)
        service.stop()
        precondition(service.isLocallyOwned(thread.id) && service.threads.first?.isConnected == true,
                     "Closing the notch must not kill its first-turn owner or pending approval")
        let request = service.localRequests(for: thread.id)[0]
        precondition(request.message.contains("fixture command"))
        service.respond(to: request, decision: .allowOnce)
        try await wait { !service.isLocallyOwned(thread.id) }
        precondition(service.activities[thread.id]?.latestMessage?.text == "Fixture completed")
        precondition(service.activities[thread.id]?.runningTools.isEmpty == true)
        precondition(service.localRequests(for: thread.id).isEmpty)
        precondition(service.attentionByThread[thread.id] == .idle)
        print("Passed: persistent first-turn ownership, inherited configuration, approval routing, hidden-notch lifetime, activity and terminal release.")
    }

    @MainActor private static func wait(_ condition: () -> Bool) async throws {
        let deadline = ContinuousClock.now.advanced(by: .seconds(5))
        while !condition() {
            precondition(ContinuousClock.now < deadline, "Session fixture timed out")
            try await Task.sleep(for: .milliseconds(10))
        }
    }

    private static func request(_ method: String, params: [String: CodexJSON] = [:]) -> CodexSessionRequest {
        CodexSessionRequest(message: .object(["id": .number(7), "method": .string(method), "params": .object(params)]), threadID: "thread")!
    }

    private static func checkResponses() {
        let approval = request("item/commandExecution/requestApproval")
        precondition(approval.response(for: .allowOnce)?["decision"].string == "accept")
        precondition(approval.response(for: .decline)?["decision"].string == "decline")
        precondition(approval.response(for: .cancel)?["decision"].string == "cancel")
        let restricted = request("item/commandExecution/requestApproval", params: ["availableDecisions": .array([.string("cancel")])])
        precondition(!restricted.allowsApproval && restricted.response(for: .allowOnce) == nil)
        let permissions = request("item/permissions/requestApproval", params: ["permissions": .object(["network": .object(["enabled": .bool(true)])])])
        precondition(permissions.response(for: .allowOnce)?["scope"].string == "turn")
        precondition(permissions.response(for: .decline)?["permissions"].object.isEmpty == true)
        let question = request("item/tool/requestUserInput", params: ["questions": .array([.object([
            "id": .string("choice"), "header": .string("Choice"), "question": .string("Pick one"), "isSecret": .bool(true)
        ])])])
        precondition(question.kind == .questions && question.questions[0].isSecret)
        precondition(question.response(for: .answers([:])) == nil)
        precondition(question.response(for: .answers(["choice": [" "]])) == nil)
        precondition(question.response(for: .answers(["choice": ["One"]]))?["answers"]["choice"]["answers"].array.first?.string == "One")
        precondition(request("account/chatgptAuthTokens/refresh").kind == .unsupported)
        let duplicateQuestions = request("item/tool/requestUserInput", params: ["questions": .array([
            .object(["id": .string("same"), "question": .string("First")]),
            .object(["id": .string("same"), "question": .string("Second")])
        ])])
        precondition(duplicateQuestions.kind == .unsupported && duplicateQuestions.response(for: .answers(["same": ["One"]])) == nil)
    }

    @MainActor private static func checkActivity() {
        let session = CodexSession(threadID: "thread", client: CodexClient(desktop: false))
        func event(_ method: String, _ params: [String: CodexJSON]) { session.receive(.object(["method": .string(method), "params": .object(params)])) }
        event("turn/started", ["turn": .object(["id": .string("turn")])])
        event("item/started", ["item": .object(["id": .string("search"), "type": .string("webSearch"), "query": .string("A query")])])
        precondition(session.presentation.runningTools.count == 1)
        event("item/completed", ["item": .object(["id": .string("search"), "type": .string("webSearch"), "query": .string("A query")])])
        precondition(session.presentation.runningTools.isEmpty)
        event("item/started", ["item": .object(["id": .string("reasoning"), "type": .string("reasoning"), "content": .array([.string("PRIVATE")])])])
        event("item/reasoning/textDelta", ["itemId": .string("reasoning"), "delta": .string("PRIVATE")])
        event("item/reasoning/summaryTextDelta", ["itemId": .string("reasoning"), "summaryIndex": .number(0), "delta": .string("Public summary")])
        precondition(session.presentation.workingSummary?.text == "Public summary")
        precondition(!String(data: try! JSONEncoder().encode(session.state), encoding: .utf8)!.contains("PRIVATE"))
        event("item/completed", ["item": .object(["id": .string("reasoning"), "type": .string("reasoning"), "summary": .array([.string("Public summary")])])])
        precondition(!session.presentation.isThinking, "A completed reasoning item must stop its thinking indicator")
        event("turn/completed", ["turn": .object(["id": .string("turn"), "status": .string("completed")])])
        precondition(!session.isRunning && session.presentation.workingSummary == nil)
    }
}
