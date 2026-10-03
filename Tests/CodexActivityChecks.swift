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
        precondition(presentation.items.map(\.kind) == [.user, .assistant, .tool, .tool])
        precondition(presentation.items[2].isRunning)
        precondition(!presentation.items[1].isRunning)
        precondition(presentation.items[2].details == "första raden\n")
        precondition(presentation.items[3].details.contains("andra raden"))
        precondition(presentation.items[3].links.isEmpty, "Tool path arguments do not become artifact links.")
        precondition(presentation.attention == .working)

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
        precondition(completed.items.last?.text.hasPrefix("Klar.") == true)
        precondition(completed.items.last?.links.map(\.url.absoluteString) == ["file:///tmp/report.md", "https://github.com/example/repo/pull/42"])
        precondition(completed.items.allSatisfy { !$0.isRunning })
        precondition(completed.items.prefix(4).map(\.id) == presentation.items.map(\.id), "Stable item IDs preserve reading anchors across updates.")
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
        precondition(stream.presentation.items == completed.items, "A disconnect keeps readable results.")
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
        precondition(stream.presentation.items[2].details == "Rätt kommando")
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
        precondition(stream.presentation.items.map(\.text) == ["Tidigare fråga", "Senaste svaret", "Verktyget misslyckades."])
        precondition(stream.presentation.attention == .failed("Verktyget misslyckades."))
        precondition(stream.apply(json(#"""
        {"type":"patches","baseRevision":20,"revision":21,"patches":[{"op":"replace","path":["turnHistory","history","entitiesByKey","turn:new","items",0,"text"],"value":"Uppdaterat 👋"}]}
        """#), owner: "owner-c") == .applied)
        precondition(stream.presentation.items[1].text == "Uppdaterat 👋")

        let root = json(#"{"type":"patches","baseRevision":21,"revision":22,"patches":[{"op":"replace","path":[],"value":{"id":"canonical","title":"Replaced","turns":[]}}]}"#)
        precondition(stream.apply(root, owner: "owner-c") == .applied)
        precondition(stream.state?["title"].string == "Replaced")
        precondition(stream.presentation.items.isEmpty)
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
        precondition(stream.presentation.items.count == 400 && stream.presentation.omittedItemCount == 5)
        precondition(stream.state?["turns"].array[0]["items"].array.count == 405, "Window the presentation without corrupting patch indices.")
        precondition(stream.apply(json(#"{"type":"patches","baseRevision":30,"revision":31,"patches":[{"op":"replace","path":["turns",0,"items",404,"text"],"value":"Sista meddelandet"}]}"#), owner: "owner-c") == .applied)
        precondition(stream.presentation.items.last?.text == "Sista meddelandet")
        checkStatusProjection()
        print("Codex activity checks passed")
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
