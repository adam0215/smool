import Foundation

@main
struct CodexNewThreadChecks {
    @MainActor static func main() async throws {
        let project = CodexProject(id: "project", name: "Project", roots: ["/tmp/smool-project", "/tmp/second-root"])
        var thread = CodexThread(json: .object(["id": .string(UUID().uuidString), "cwd": .string(project.roots[0])]))!
        thread.project = project
        let parameters = try CodexNewThreadDraft.startParameters(project: project)
        precondition(parameters["cwd"].string == project.roots[0])
        precondition(parameters["threadSource"].string == "user")
        precondition(parameters["model"].string == nil, "The configured model must be inherited")
        do {
            _ = try CodexNewThreadDraft.startParameters(project: .unassigned)
            preconditionFailure("An unassigned history filter is not a creation destination")
        } catch { }

        let draft = CodexNewThreadDraft()
        draft.text = "Start here"
        var creations = 0
        var sends = 0
        let create: (CodexProject) async throws -> CodexThread = { selected in
            precondition(selected == project)
            creations += 1
            return thread
        }
        var result = await draft.submit(project: project, create: create) { text, target in
            sends += 1
            precondition(text == "Start here" && target.id == thread.id)
            throw CodexNewThreadError(message: "Desktop unavailable")
        }
        precondition(result == nil && draft.text == "Start here" && draft.thread?.id == thread.id)
        precondition(!draft.needsReview && draft.error == "Desktop unavailable")
        result = await draft.submit(project: nil, create: create) { _, _ in sends += 1 }
        precondition(result?.id == thread.id && creations == 1 && sends == 2)
        precondition(draft.text.isEmpty && draft.thread == nil && draft.error == nil)

        draft.text = "A delivery with an unknown outcome"
        result = await draft.submit(project: project, create: create) { _, _ in
            throw CodexNewThreadError(message: "Check Codex", needsReview: true)
        }
        precondition(result == nil && draft.needsReview && draft.thread != nil)
        let countBeforeRetry = creations
        result = await draft.submit(project: project, create: create) { _, _ in preconditionFailure("Unsafe retry") }
        precondition(result == nil && creations == countBeforeRetry)
        draft.allowRetryAfterReview()
        result = await draft.submit(project: project, create: create) { _, _ in }
        precondition(result != nil && creations == countBeforeRetry)

        draft.text = "Creation timed out"
        result = await draft.submit(project: project, create: { _ in
            throw CodexNewThreadError(message: "Check for a created thread", needsReview: true)
        }, send: { _, _ in preconditionFailure("Nothing to send to") })
        precondition(result == nil && draft.needsReview && draft.thread == nil && draft.text == "Creation timed out")
        result = await draft.submit(project: project, create: create, send: { _, _ in preconditionFailure("Unsafe duplicate") })
        precondition(result == nil && creations == countBeforeRetry)
        draft.allowRetryAfterReview()

        var resume: CheckedContinuation<Void, Never>?
        let first = Task { @MainActor in
            await draft.submit(project: project, create: create) { _, _ in
                await withCheckedContinuation { resume = $0 }
            }
        }
        while resume == nil { await Task.yield() }
        precondition(draft.isSubmitting)
        result = await draft.submit(project: project, create: create) { _, _ in preconditionFailure("Double submit") }
        precondition(result == nil)
        draft.text = "An edit made while sending"
        resume?.resume()
        result = await first.value
        precondition(result != nil && !draft.isSubmitting && draft.text == "An edit made while sending")

        draft.text = String(repeating: "a", count: 65_537)
        result = await draft.submit(project: project, create: { _ in preconditionFailure("Oversized draft") }, send: { _, _ in })
        precondition(result == nil && draft.error != nil)
        draft.text = " \n "
        result = await draft.submit(project: project, create: { _ in preconditionFailure("Empty draft") }, send: { _, _ in })
        precondition(result == nil)
        print("Passed: project payload, creation and delivery uncertainty, reconnect retry, double-submit, draft retention, validation.")
    }
}
