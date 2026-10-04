@testable import SmoolChecksSupport
import Foundation

@main
struct CodexActivityChecks {
    static func main() throws {
        // Shape fixtures transcribed from ChatGPT.app's v11 stream producer, Immer patch
        // consumer and transcript projector. They contain no private conversation content.
        let snapshot = json(#"""
        {"type":"snapshot","revision":4,"conversationState":{
          "id":"fixture","title":"Fixture","threadRuntimeStatus":{"type":"active","activeFlags":[]},"requests":[],
          "turns":[{"turnId":"t1","status":"inProgress","params":{"input":[{"type":"text","text":"Kontrollera filen."}]},"items":[
            {"id":"u1","type":"userMessage","content":[{"type":"text","text":"Kontrollera filen."}]},
            {"id":"a1","type":"agentMessage","phase":"commentary","text":"Jag läser filen."},
            {"id":"c1","type":"commandExecution","command":"cat example.swift","cwd":"/tmp","status":"inProgress","aggregatedOutput":"första raden\n","exitCode":null},
            {"id":"m1","type":"mcpToolCall","server":"fixture","tool":"read","arguments":{"path":"/tmp/example.swift"},"status":"completed","result":{"content":[{"type":"text","text":"andra raden"}]},"error":null}
          ]}]
        }}
        """#)
        var stream = CodexActivityStream()
        precondition(stream.apply(snapshot, owner: "owner-a") == .applied)
        let presentation = stream.presentation
        precondition(presentation.runningTools.first?.details == "första raden")
        precondition(presentation.attention == .working)
        precondition(presentation.latestMessage?.text == "Jag läser filen.")
        precondition(presentation.runningTools.map(\.id) == ["turn:t1/c1"])

        let complete = json(#"""
        {"type":"patches","baseRevision":4,"revision":7,"patches":[
          {"op":"replace","path":["turns",0,"items",2,"status"],"value":"completed"},
          {"op":"replace","path":["turns",0,"items",2,"aggregatedOutput"],"value":"första raden\nklart"},
          {"op":"replace","path":["turns",0,"items",2,"exitCode"],"value":0},
          {"op":"add","path":["turns",0,"items",4],"value":{"type":"agentMessage","id":"a2","phase":"final_answer","text":"Klar. [Rapport](/tmp/report.md) [PR](https://github.com/example/repo/pull/42)"}},
          {"op":"replace","path":["turns",0,"status"],"value":"completed"},
          {"op":"replace","path":["threadRuntimeStatus"],"value":{"type":"idle"}}
        ],"acceptedTextChanges":[{"type":"text","key":{"entityKey":"turn:t1","itemId":"a2"},"target":{"field":"text"},"edits":[]}]}
        """#)
        precondition(stream.apply(complete, owner: "owner-a") == .applied, "Revision increments may skip numbers when baseRevision matches.")
        let completed = stream.presentation
        precondition(completed.attention == .idle)
        precondition(completed.runningTools.isEmpty && completed.latestMessage?.text.hasPrefix("Klar.") == true)
        precondition(stream.apply(complete, owner: "owner-a") == .ignored)
        precondition(stream.apply(snapshot, owner: "owner-a") == .ignored, "A delayed snapshot must not erase a newer final answer.")

        expectResync(stream.apply(json(#"{"type":"patches","baseRevision":10,"revision":11,"patches":[]}"#), owner: "owner-a"))
        precondition(stream.revision == 7 && stream.presentation == completed)
        expectResync(stream.apply(json(#"{"type":"patches","baseRevision":7,"revision":8,"patches":[]}"#), owner: "owner-b"))
        precondition(stream.owner == "owner-a")

        let malformed = json(#"""
        {"type":"patches","baseRevision":7,"revision":8,"patches":[
          {"op":"replace","path":["title"],"value":"MUST NOT COMMIT"},
          {"op":"replace","path":["turns",0,"items",100,"text"],"value":"invalid"}
        ]}
        """#)
        expectResync(stream.apply(malformed, owner: "owner-a"))
        precondition(stream.state?["title"].string == "Fixture", "Patch batches are atomic.")

        stream.disconnect()
        precondition(stream.owner == nil && stream.revision == nil)
        precondition(stream.presentation.revision == completed.revision, "Connection resets must not move the displayed revision backwards.")
        precondition(stream.presentation.latestMessage == completed.latestMessage, "A disconnect keeps readable results.")
        expectResync(stream.apply(complete, owner: "owner-a"))
        precondition(stream.apply(snapshot, owner: "owner-b") == .applied, "A new connection accepts the owner's reset revision.")
        precondition(stream.apply(complete, owner: "owner-b") == .applied)
        precondition(stream.apply(snapshot, owner: "owner-c") == .applied)
        precondition(stream.apply(complete, owner: "owner-b") == .ignored, "Ignore delayed packets from a superseded owner.")

        let splice = json(#"""
        {"type":"patches","baseRevision":4,"revision":5,"patches":[
          {"op":"remove","path":["turns",0,"items",1]},
          {"op":"add","path":["turns",0,"items",1],"value":{"id":"inserted","type":"agentMessage","text":"Ny rad"}},
          {"op":"replace","path":["turns",0,"items",2,"aggregatedOutput"],"value":"Rätt kommando"},
          {"op":"add","path":["requests",0],"value":{"id":1,"method":"item/commandExecution/requestApproval","params":{"threadId":"fixture"}}}
        ]}
        """#)
        precondition(stream.apply(splice, owner: "owner-c") == .applied)
        precondition(stream.presentation.runningTools.first?.details == "Rätt kommando")
        precondition(stream.presentation.attention == .approval)
        let inputRequest = json(#"{"requests":[{"method":"item/tool/requestUserInput"}]}"#)
        precondition(CodexAttention.from(state: inputRequest) == .waitingForUser)
        precondition(CodexAttention.from(state: json(#"{"threadRuntimeStatus":{"type":"active","activeFlags":["waitingOnApproval"]}}"#)) == .approval)
        precondition(CodexAttention.from(state: json(#"{"threadRuntimeStatus":{"type":"active","activeFlags":["waitingOnUserInput"]}}"#)) == .waitingForUser)
        precondition(CodexAttention.from(state: json(#"{"requests":[{"method":"item/tool/requestUserInput","completed":true}],"threadRuntimeStatus":{"type":"idle"}}"#)) == .idle)

        let canonical = json(#"""
        {"type":"snapshot","revision":20,"conversationState":{"id":"canonical","turns":[],"turnHistory":{"kind":"canonical","history":{
          "isComplete":false,"islands":[{"entries":[{"value":"turn:old"}]},{"entries":[{"value":"turn:new"}]}],
          "entitiesByKey":{
            "turn:new":{"turnId":"new","status":"failed","error":{"message":"Verktyget misslyckades."},"items":[{"type":"agentMessage","id":"answer","text":"Senaste svaret"}]},
            "turn:old":{"turnId":"old","status":"completed","params":{"input":[{"type":"text","text":"Tidigare fråga"}]},"items":[]}
          }
        }}}}
        """#)
        precondition(stream.apply(canonical, owner: "owner-c") == .applied)
        precondition(stream.presentation.latestMessage?.text == "Senaste svaret")
        precondition(stream.presentation.attention == .failed("Verktyget misslyckades."))
        precondition(stream.apply(json(#"""
        {"type":"patches","baseRevision":20,"revision":21,"patches":[{"op":"replace","path":["turnHistory","history","entitiesByKey","turn:new","items",0,"text"],"value":"Uppdaterat 👋"}]}
        """#), owner: "owner-c") == .applied)
        precondition(stream.presentation.latestMessage?.text == "Uppdaterat 👋")

        let root = json(#"{"type":"patches","baseRevision":21,"revision":22,"patches":[{"op":"replace","path":[],"value":{"id":"canonical","title":"Replaced","turns":[]}}]}"#)
        precondition(stream.apply(root, owner: "owner-c") == .applied)
        precondition(stream.state?["title"].string == "Replaced")
        precondition(stream.presentation.latestMessage == nil && stream.presentation.runningTools.isEmpty)
        expectResync(stream.apply(json(#"{"type":"patches","baseRevision":22,"revision":23,"patches":[{"op":"replace","path":["turns",0.5],"value":{}}]}"#), owner: "owner-c"))
        expectResync(stream.apply(json(#"{"type":"snapshot","revision":1e100,"conversationState":{}}"#), owner: "owner-c"))

        var bounded = CodexActivityStream(maximumBytes: 12_000)
        precondition(bounded.apply(snapshot, owner: "owner") == .applied)
        let bigPatch: CodexJSON = .object(["type": .string("patches"), "baseRevision": .number(4), "revision": .number(5), "patches": .array([
            .object(["op": .string("replace"), "path": .array([.string("title")]), "value": .string(String(repeating: "x", count: 12_001))])
        ])])
        guard case .unavailable = bounded.apply(bigPatch, owner: "owner") else { preconditionFailure("Oversized threads must stop resubscription loops.") }
        precondition(bounded.state?["title"].string == "Fixture")
        precondition(bounded.revision == 4)

        let manyItems: [CodexJSON] = (0..<405).map { .object(["type": .string("agentMessage"), "id": .string("message-\($0)"), "text": .string("Text \($0)")]) }
        let many: CodexJSON = .object(["type": .string("snapshot"), "revision": .number(30), "conversationState": .object([
            "turns": .array([.object(["turnId": .string("many"), "status": .string("completed"), "items": .array(manyItems)])])
        ])])
        precondition(stream.apply(many, owner: "owner-c") == .applied)
        precondition(stream.presentation.latestMessage?.text == "Text 404")
        precondition(stream.state?["turns"].array[0]["items"].array.count == 405, "Window the presentation without corrupting patch indices.")
        precondition(stream.apply(json(#"{"type":"patches","baseRevision":30,"revision":31,"patches":[{"op":"replace","path":["turns",0,"items",404,"text"],"value":"Sista meddelandet"}]}"#), owner: "owner-c") == .applied)
        precondition(stream.presentation.latestMessage?.text == "Sista meddelandet")
        checkStatusProjection()
        checkProjectionBudget()
        checkCurrentActivity()
        checkInstalledProtocolActivity()
        print("Codex activity checks passed")
    }

    static func checkInstalledProtocolActivity() {
        // Verified against ChatGPT.app on 2026-10-04:
        // app-shared-b72e16382796.js K6t, A1, POn and the bundled codex CLI's
        // app-server generate-json-schema. Payload values are harmless fixtures.
        // In v11 webSearch/reasoning/imageView/sleep have NO status. MCP progress
        // notifications are discarded by K6t before the desktop stream is emitted.
        let state = json(#"""
        {"id":"tools","threadRuntimeStatus":{"type":"active"},"turns":[{
          "turnId":"live","status":"inProgress","interruptedCommandExecutionItemIds":["interrupted"],
          "hookRuns":[{"id":"hook-1","run":{"id":"hook-1","eventName":"preToolUse","status":"running","statusMessage":"Checking command","entries":[{"kind":"stdout","text":"Rule matched"}]}}],
          "items":[
            {"id":"terminal","type":"commandExecution","command":"swift test","commandActions":[],"status":"inProgress","aggregatedOutput":"Testing 1/3"},
            {"id":"interrupted","type":"commandExecution","command":"sleep 10","commandActions":[],"status":"inProgress"},
            {"id":"mcp","type":"mcpToolCall","server":"figma","tool":"use_figma","arguments":{"title":"Inspect components"},"status":"inProgress","result":{"content":[{"type":"text","text":"Found 12 components"}]},"error":null},
            {"id":"custom","type":"dynamicToolCall","namespace":"functions","tool":"exec","arguments":{"title":"Run verification"},"status":"inProgress","contentItems":null,"success":null},
            {"id":"agent","type":"collabAgentToolCall","tool":"wait","status":"inProgress","receiverThreadIds":["child"],"agentsStates":{"child":{"status":"running"}}},
            {"id":"patch","type":"fileChange","status":"inProgress","changes":[{"path":"/tmp/fixture.swift","diff":"+ let value = 1"}]},
            {"id":"image","type":"imageGeneration","status":"in_progress","result":"","src":null,"revisedPrompt":"A blue circle"},
            {"id":"compact","type":"contextCompaction","completed":false},
            {"id":"approval","type":"automaticApprovalReview","status":"inProgress","rationale":"Checking requested access"},
            {"id":"search","type":"webSearch","query":"","action":{"type":"search","queries":["Swift actor isolation","Swift concurrency"]}},
            {"id":"steering","type":"steeringUserMessage","input":[{"type":"text","text":"Keep going"}]}
          ]
        }]}
        """#)
        func snapshot(_ state: CodexJSON, revision: Int) -> CodexJSON {
            .object(["type": .string("snapshot"), "revision": .number(Double(revision)), "conversationState": state])
        }
        var stream = CodexActivityStream()
        precondition(stream.apply(snapshot(state, revision: 1), owner: "desktop") == .applied)
        let live = stream.presentation
        let expected: Set<String> = ["terminal", "mcp", "custom", "agent", "patch", "image", "compact", "approval", "search", "hook:hook-1"]
        precondition(Set(live.runningTools.map { String($0.id.split(separator: "/").last!) }) == expected)
        precondition(live.runningTools.first { $0.id.hasSuffix("/custom") }?.text == "Run verification")
        precondition(live.runningTools.first { $0.id.hasSuffix("/mcp") }?.text == "Found 12 components")
        precondition(live.runningTools.first { $0.id.hasSuffix("/search") }?.text == "Swift actor isolation, Swift concurrency")
        precondition(!live.isThinking)

        let changes = json(#"""
        {"type":"patches","baseRevision":1,"revision":2,"patches":[
          {"op":"replace","path":["turns",0,"items",0,"status"],"value":"completed"},
          {"op":"replace","path":["turns",0,"items",2,"status"],"value":"failed"},
          {"op":"replace","path":["turns",0,"items",3,"status"],"value":"completed"},
          {"op":"replace","path":["turns",0,"items",4,"status"],"value":"interrupted"},
          {"op":"replace","path":["turns",0,"items",5,"status"],"value":"declined"},
          {"op":"replace","path":["turns",0,"items",6,"status"],"value":"failed"},
          {"op":"replace","path":["turns",0,"items",7,"completed"],"value":true},
          {"op":"replace","path":["turns",0,"items",8,"status"],"value":"aborted"},
          {"op":"replace","path":["turns",0,"hookRuns",0,"run","status"],"value":"stopped"},
          {"op":"add","path":["turns",0,"items",11],"value":{"id":"thinking","type":"reasoning","summary":[],"content":["PRIVATE REASONING MUST NOT BE DISPLAYED"]}}
        ]}
        """#)
        precondition(stream.apply(changes, owner: "desktop") == .applied)
        precondition(stream.presentation.runningTools.isEmpty && stream.presentation.isThinking)
        precondition(stream.presentation.workingSummary == nil, "Thinking needs no invented summary")
        var stale = live
        stale.reconcileActivity(state: stream.state!)
        precondition(stale.runningTools.isEmpty, "An old projection cannot restore finished tools")

        let summaryDelta = json(#"""
        {"type":"patches","baseRevision":2,"revision":3,"patches":[
          {"op":"add","path":["turns",0,"items",11,"summary",0],"value":"Verifying tool completion."}
        ]}
        """#)
        precondition(stream.apply(summaryDelta, owner: "desktop") == .applied)
        precondition(stream.presentation.workingSummary?.text == "Verifying tool completion.")
        precondition(!visibleItems(stream.presentation).contains { ($0.text + $0.details).contains("PRIVATE") })
        var restored = CodexActivityStream()
        precondition(restored.apply(snapshot(stream.state!, revision: 3), owner: "desktop") == .applied)
        precondition(restored.presentation == stream.presentation, "Snapshot and patched state must present identically")
        restored.disconnect()
        expectResync(restored.apply(summaryDelta, owner: "desktop"))
        precondition(restored.apply(snapshot(stream.state!, revision: 1), owner: "new-desktop") == .applied)
        precondition(restored.presentation.isThinking)

        for type in ["imageView", "sleep", "webSearch"] {
            let item: CodexJSON = .object(["id": .string("statusless"), "type": .string(type), "path": .string("/tmp/image.png"), "durationMs": .number(1000)])
            let turn: CodexJSON = .object(["turnId": .string("statusless"), "status": .string("inProgress"), "items": .array([item])])
            let presentation = CodexActivityPresentation(state: .object(["turns": .array([turn])]), revision: 1)
            precondition(presentation.runningTools.count == 1)
            var ended = turn.object
            for status in ["completed", "interrupted", "failed", "cancelled"] {
                ended["status"] = .string(status)
                let result = CodexActivityPresentation(state: .object(["turns": .array([.object(ended)])]), revision: 2)
                precondition(result.runningTools.isEmpty && !result.isThinking && result.workingSummary == nil)
            }
        }
    }

    static func checkCurrentActivity() {
        let state = json(#"""
        {"turns":[
          {"turnId":"old","status":"inProgress","items":[
            {"type":"reasoning","id":"old-note","summary":["Old public note"],"content":["PRIVATE OLD CONTENT"]},
            {"type":"commandExecution","id":"old-tool","command":"old","status":"inProgress"}
          ]},
          {"turnId":"current","status":"inProgress","items":[
            {"type":"userMessage","id":"u","content":[{"type":"text","text":"New request"}]},
            {"type":"reasoning","id":"note","summary":["Checking the current file"],"content":["PRIVATE CURRENT CONTENT"]},
            {"type":"commandExecution","id":"done","command":"done","status":"completed"},
            {"type":"commandExecution","id":"running","command":"current","status":"inProgress"}
          ]}
        ]}
        """#)
        let current = CodexActivityPresentation(state: state, revision: 1)
        precondition(current.latestMessage?.text == "New request")
        precondition(current.runningTools.map(\.id) == ["turn:current/running"])
        precondition(current.workingSummary?.text == "Checking the current file")
        precondition(!visibleItems(current).contains { ($0.text + $0.details).contains("PRIVATE") })
        var changed = state.object
        var turns = state["turns"].array
        var last = turns[1].object
        var entries = last["items"]!.array
        var tool = entries[3].object
        tool["status"] = .string("completed")
        entries[3] = .object(tool)
        last["items"] = .array(entries)
        turns[1] = .object(last)
        changed["turns"] = .array(turns)
        let toolCompleted = CodexActivityPresentation(state: .object(changed), revision: 2)
        precondition(toolCompleted.runningTools.isEmpty && toolCompleted.workingSummary != nil,
                     "Finished tools disappear before the turn completes")
        entries.append(.object(["type": .string("agentMessage"), "id": .string("answer"), "text": .string("Current answer")]))
        last["items"] = .array(entries)
        last["status"] = .string("completed")
        turns[1] = .object(last)
        changed["turns"] = .array(turns)
        let completed = CodexActivityPresentation(state: .object(changed), revision: 2)
        precondition(completed.workingSummary == nil && completed.runningTools.isEmpty,
                     "Old in-progress turns must never supply current tools or summaries")
        precondition(completed.latestMessage?.text == "Current answer")
        last["status"] = .string("inProgress")
        last["items"] = .array([.object(["type": .string("userMessage"), "content": .array([])])])
        turns[1] = .object(last)
        changed["turns"] = .array(turns)
        precondition(CodexActivityPresentation(state: .object(changed), revision: 3).workingSummary == nil,
                     "A new turn cannot inherit an earlier public note")
    }

    private static func visibleItems(_ presentation: CodexActivityPresentation) -> [CodexActivityItem] {
        [presentation.latestMessage, presentation.workingSummary, presentation.currentNote].compactMap { $0 } + presentation.runningTools
    }

    static func checkProjectionBudget() {
        let historical: [CodexJSON] = (0..<3_000).map { index in
            .object([
                "id": .string("old-\(index)"), "type": .string("mcpToolCall"), "status": .string("completed"),
                "arguments": .object(["data": .string(String(repeating: "x", count: 500))]),
                "result": .object(["content": .array([.object(["type": .string("text"), "text": .string("Old result")])])])
            ])
        }
        let current: [CodexJSON] = [
            .object(["id": .string("message"), "type": .string("agentMessage"), "text": .string("Latest reply")]),
            .object(["id": .string("note"), "type": .string("todo-list"), "explanation": .string("Current plan")]),
            .object(["id": .string("tool"), "type": .string("commandExecution"), "status": .string("inProgress"),
                     "command": .string("verify"), "aggregatedOutput": .string(String(repeating: "old output\n", count: 10_000) + "penultimate\nlatest\n")])
        ]
        func project(_ entries: [CodexJSON]) -> CodexActivityPresentation {
            CodexActivityPresentation(state: .object(["turns": .array([.object([
                "turnId": .string("current"), "status": .string("inProgress"), "items": .array(entries)
            ])])]), revision: 1)
        }
        let compact = project(current)
        precondition(project(historical + current) == compact, "Completed history must never be retained in the compact presentation")
        precondition(compact.latestMessage?.text == "Latest reply" && compact.currentNote?.text == "Current plan")
        precondition(compact.runningTools.count == 1 && compact.runningTools[0].details == "penultimate\nlatest")
        let unicode = CodexActivityPresentation.message(.object([
            "type": .string("agentMessage"), "text": .string(String(repeating: "x", count: 32_767) + "🧭")
        ]), id: "unicode")!
        precondition(unicode.text.utf8.count < 33_000 && !unicode.text.contains("�"),
                     "Byte clipping must preserve complete Unicode scalars")

        for text in ["Short tool", String(repeating: "🧭", count: 10_000)] {
            let tools: [CodexJSON] = (0..<1_000).map {
                .object(["id": .string("active-\($0)"), "type": .string("commandExecution"),
                         "status": .string("inProgress"), "command": .string(text), "aggregatedOutput": .string(text)])
            }
            let bounded = project(current + tools)
            precondition(bounded.latestMessage == compact.latestMessage && bounded.currentNote == compact.currentNote)
            precondition(!bounded.runningTools.isEmpty && bounded.runningTools.count <= CodexActivityPresentation.maximumRunningTools)
            let bytes = visibleItems(bounded).reduce(0) {
                $0 + $1.id.utf8.count + $1.title.utf8.count + $1.text.utf8.count + $1.details.utf8.count
            }
            precondition(bytes <= CodexActivityPresentation.maximumBytes,
                         "Many active tools must obey the compact presentation's total byte budget")
            if text == "Short tool" {
                precondition(bounded.runningTools.count == CodexActivityPresentation.maximumRunningTools)
            } else {
                precondition(bounded.runningTools.count < CodexActivityPresentation.maximumRunningTools,
                             "Large active payloads must hit the byte budget before the item limit")
            }
        }
    }

    static func checkStatusProjection() {
        var full = CodexActivityStream()
        var status = CodexActivityStream()
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]

        func apply(_ source: String, attention: CodexAttention) {
            let change = json(source)
            precondition(full.apply(change, owner: "owner") == .applied)
            precondition(status.apply(CodexActivityStream.statusChange(change), owner: "owner") == .applied)
            let expected = CodexActivityStream.statusChange(.object(["type": .string("snapshot"), "conversationState": full.state!]))["conversationState"]
            precondition(try! encoder.encode(expected) == encoder.encode(status.state!), "Projected patches must match projection of the complete patched state.")
            precondition(CodexAttention.from(state: status.state!) == attention)
            let metadataText = String(decoding: try! encoder.encode(status.state!), as: UTF8.self)
            precondition(!metadataText.contains("\"items\"") && !metadataText.contains("\"params\""), "Background metadata must never retain transcript content.")
        }

        apply(#"""
        {"type":"snapshot","revision":1,"conversationState":{"id":"metadata","threadRuntimeStatus":{"type":"idle"},"turns":[
          {"turnId":"old","status":"failed","error":{"message":"Old failure"},"params":{"input":[{"type":"text","text":"Private prompt"}]},"items":[]},
          {"turnId":"latest","status":"completed","error":null,"items":[{"id":"answer","type":"agentMessage","text":"Private answer"}]}
        ]}}
        """#, attention: .idle)
        apply(#"""
        {"type":"patches","baseRevision":1,"revision":2,"patches":[
          {"op":"replace","path":["turns",0,"error","message"],"value":"Updated old failure"},
          {"op":"replace","path":["turns",1,"items",0,"text"],"value":"A newer private answer"}
        ]}
        """#, attention: .idle)
        apply(#"""
        {"type":"patches","baseRevision":2,"revision":3,"patches":[
          {"op":"replace","path":["turns",1,"status"],"value":"failed"},
          {"op":"replace","path":["turns",1,"error"],"value":{"message":"Latest failure"}}
        ]}
        """#, attention: .failed("Latest failure"))
        apply(#"""
        {"type":"patches","baseRevision":3,"revision":4,"patches":[
          {"op":"remove","path":["turns",1]},
          {"op":"add","path":["turns",1],"value":{"turnId":"new","status":"inProgress","params":{"input":[{"type":"text","text":"Private input"}]},"items":[{"id":"new-item","text":"Private text"}]}}
        ]}
        """#, attention: .working)
        apply(#"""
        {"type":"patches","baseRevision":4,"revision":5,"patches":[
          {"op":"replace","path":["turns"],"value":[]},
          {"op":"add","path":["turnHistory"],"value":{"kind":"canonical","history":{"generation":1,"islands":[{"entries":[{"value":"turn:old"},{"value":"turn:latest"}]}],"entitiesByKey":{
            "turn:old":{"turnId":"old","status":"failed","error":{"message":"Old canonical failure"},"items":[]},
            "turn:latest":{"turnId":"latest","status":"completed","error":null,"items":[{"id":"a","type":"agentMessage","text":"Private answer"}]}
          }}}}
        ]}
        """#, attention: .idle)
        apply(#"""
        {"type":"patches","baseRevision":5,"revision":6,"patches":[
          {"op":"replace","path":["turnHistory","history","entitiesByKey","turn:old","error","message"],"value":"Earlier failure changed"},
          {"op":"add","path":["turnHistory","history","entitiesByKey","turn:latest","items",1],"value":{"id":"b","type":"agentMessage","text":"More private text"}}
        ]}
        """#, attention: .idle)
        apply(#"""
        {"type":"patches","baseRevision":6,"revision":7,"patches":[
          {"op":"replace","path":["turnHistory","history","entitiesByKey","turn:latest"],"value":{"turnId":"latest","status":"failed","error":{"message":"Canonical failure"},"items":[]}},
          {"op":"replace","path":["turnHistory","history","generation"],"value":2}
        ]}
        """#, attention: .failed("Canonical failure"))
        apply(#"""
        {"type":"patches","baseRevision":7,"revision":8,"patches":[
          {"op":"add","path":["turnHistory","history","entitiesByKey","turn:new"],"value":{"turnId":"new","status":"completed","items":[]}},
          {"op":"add","path":["turnHistory","history","islands",0,"entries",2],"value":{"value":"turn:new"}}
        ]}
        """#, attention: .idle)
        apply(#"""
        {"type":"patches","baseRevision":8,"revision":9,"patches":[
          {"op":"remove","path":["turnHistory","history","entitiesByKey","turn:new"]},
          {"op":"remove","path":["turnHistory","history","islands",0,"entries",2]}
        ]}
        """#, attention: .failed("Canonical failure"))
        apply(#"""
        {"type":"patches","baseRevision":9,"revision":10,"patches":[
          {"op":"replace","path":["turnHistory","history","entitiesByKey"],"value":{"turn:latest":{"turnId":"latest","status":"completed","items":[]}}},
          {"op":"replace","path":["turnHistory","history","islands"],"value":[{"entries":[{"value":"turn:latest"}]}]}
        ]}
        """#, attention: .idle)
    }

    static func json(_ source: String) -> CodexJSON {
        try! JSONDecoder().decode(CodexJSON.self, from: Data(source.utf8))
    }

    static func expectResync(_ result: CodexStreamResult) {
        guard case .resync = result else { preconditionFailure("Expected an explicit resynchronization result, got \(result)") }
    }
}
