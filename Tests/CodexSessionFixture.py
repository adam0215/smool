"""A stdio app-server peer. Never loads Codex, credentials, tools or a model."""
import json
import sys

thread_id = "10000000-0000-0000-0000-000000000001"
turn_id = "fixture-turn"
started = False


def send(value):
    print(json.dumps(value), flush=True)


def notify(method, **params):
    send({"method": method, "params": {"threadId": thread_id, **params}})


for line in sys.stdin:
    message = json.loads(line)
    method = message.get("method")
    params = message.get("params", {})
    request_id = message.get("id")
    if method == "initialize":
        send({"id": request_id, "result": {}})
    elif method == "thread/start":
        assert params.get("model") is None and params.get("approvalPolicy") is None
        assert params["runtimeWorkspaceRoots"] == ["/tmp/fixture", "/tmp/second-root"]
        send({"id": request_id, "result": {"thread": {"id": thread_id, "cwd": params["cwd"]}}})
    elif method == "turn/start":
        assert not started, "The first input must only start once"
        started = True
        assert params["input"][0]["text"] == "Fixture prompt"
        turn = {"id": turn_id, "status": "inProgress", "items": []}
        notify("turn/started", turn=turn)
        send({"id": request_id, "result": {"turn": turn}})
        notify("item/started", turnId=turn_id, item={"id": "command", "type": "commandExecution", "command": "fixture command", "status": "inProgress"})
        send({"id": 101, "method": "item/commandExecution/requestApproval", "params": {"threadId": thread_id, "turnId": turn_id, "itemId": "command", "command": "fixture command", "reason": "Fixture permission", "availableDecisions": ["accept", "decline", "cancel"]}})
    elif request_id == 101:
        assert message["result"] == {"decision": "accept"}
        notify("item/completed", turnId=turn_id, item={"id": "command", "type": "commandExecution", "command": "fixture command", "status": "completed", "exitCode": 0})
        notify("item/started", turnId=turn_id, item={"id": "reasoning", "type": "reasoning", "summary": [], "content": ["PRIVATE"]})
        notify("item/reasoning/summaryTextDelta", turnId=turn_id, itemId="reasoning", summaryIndex=0, delta="Public summary")
        notify("item/reasoning/textDelta", turnId=turn_id, itemId="reasoning", contentIndex=0, delta="PRIVATE DELTA")
        notify("item/started", turnId=turn_id, item={"id": "answer", "type": "agentMessage", "text": ""})
        notify("item/agentMessage/delta", turnId=turn_id, itemId="answer", delta="Fixture completed")
        notify("item/completed", turnId=turn_id, item={"id": "answer", "type": "agentMessage", "text": "Fixture completed"})
        notify("turn/completed", turn={"id": turn_id, "status": "completed", "items": []})
    elif method == "thread/unsubscribe":
        assert started, "An empty thread must never be handed off"
        send({"id": request_id, "result": {"status": "unsubscribed"}})
    elif method == "initialized":
        pass
    else:
        raise AssertionError(message)
