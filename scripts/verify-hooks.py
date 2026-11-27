#!/usr/bin/env python3
import importlib.util
import os
import json
import pathlib
import subprocess
import tempfile

root = pathlib.Path(__file__).resolve().parents[1]
spec = importlib.util.spec_from_file_location("connector", root / "scripts/connect-tools.py")
connector = importlib.util.module_from_spec(spec)
spec.loader.exec_module(connector)
original = {"permissions": {"deny": ["Bash(rm:*)"]}, "hooks": {"Stop": [{"hooks": [{"type": "command", "command": "existing-hook"}]}]}}
merged = connector.merge_claude(original, "'/space in path/TouchBarPlayground'")
connector.merge_claude(merged, "'/space in path/TouchBarPlayground'")
assert merged["permissions"] == {"deny": ["Bash(rm:*)"]}
assert len(merged["hooks"]["Stop"]) == 2
assert merged["hooks"]["Stop"][0]["hooks"][0]["command"] == "existing-hook"
agy = connector.merge_antigravity({"existing-hook": {"enabled": True}}, "binary")
assert "existing-hook" in agy and "PreToolUse" not in agy["touchbar-playground"]
binary = root / "Touch Bar Playground.app/Contents/MacOS/TouchBarPlayground"
test_state = tempfile.TemporaryDirectory(prefix="touchbar-playground-verification-")
test_env = {**os.environ, "TOUCHBAR_PLAYGROUND_STATE_DIR": test_state.name}
# Verify neutral stdout even when handed untrusted text or invalid JSON.
for tool, event, payload in [
    ("claude", "UserPromptSubmit", '{"session_id":"playground-verification","prompt":"private prompt"}'),
    ("claude", "Stop", '{"session_id":"playground-verification"}'),
    ("antigravity", "PreInvocation", '{"conversationId":"playground-verification","lastUserInput":"private prompt"}'),
    ("antigravity", "Stop", '{"conversationId":"playground-verification"}'),
    ("claude", "SessionEnd", "invalid JSON"),
]:
    result = subprocess.run([str(binary), "--event", tool, event], input=payload, text=True, capture_output=True, timeout=2, env=test_env)
    assert result.returncode == 0
    assert result.stdout.strip() == ("{}" if tool == "antigravity" else "")
directory = pathlib.Path(test_state.name) / "events"
def event(tool, kind, **extra):
    payload = {"session_id": "playground-verification", "conversationId": "playground-verification", **extra}
    result = subprocess.run([str(binary), "--event", tool, kind], input=json.dumps(payload), text=True, capture_output=True, timeout=2, env=test_env)
    assert result.returncode == 0 and result.stdout.strip() == ("{}" if tool == "antigravity" else "")
    return next(json.loads(p.read_text()) for p in directory.glob(f"{tool}-*.json") if json.loads(p.read_text()).get("session") == "playground-verification")

assert event("antigravity", "PreInvocation", modelName="gemini-test-model")["modelName"] == "gemini-test-model"
assert event("antigravity", "Stop")["modelName"] == "gemini-test-model"
assert event("antigravity", "PreInvocation", modelName="auto")["modelName"] == "auto"
assert event("claude", "SessionStart", model="claude-test-selected")["modelName"] == "claude-test-selected"
assert "modelName" not in event("claude", "UserPromptSubmit")
with tempfile.TemporaryDirectory() as temp:
    transcript = pathlib.Path(temp) / "transcript.jsonl"
    entries = [
        {"type": "user", "message": {"content": "private prompt"}},
        {"type": "assistant", "message": {"model": "claude-test-response", "content": "private response"}},
        {"type": "user", "message": {"content": [{"type": "tool_result", "content": "private tool result"}]}},
    ]
    transcript.write_text("\n".join(map(json.dumps, entries)) + "\n")
    observed = event("claude", "PreToolUse", transcript_path=str(transcript))
    assert observed["modelName"] == "claude-test-response" and observed["modelSource"] == "response"
    # A new human prompt must not be attributed to the previous response's model.
    entries.append({"type": "user", "message": {"content": "next prompt"}})
    transcript.write_text("\n".join(map(json.dumps, entries)) + "\n")
    event("claude", "UserPromptSubmit")
    assert "modelName" not in event("claude", "PreToolUse", transcript_path=str(transcript))
event("claude", "UserPromptSubmit")
reading = event("claude", "PreToolUse", tool_name="Read", tool_input={"file_path": "/private/example/App.swift"}, tool_use_id="read-check")
assert reading["progress"]["action"] == "reading" and reading["progress"]["detail"] == "App.swift"
assert "actionEndedAt" not in reading["progress"]
read = event("claude", "PostToolUse", tool_name="Read", tool_input={"file_path": "/private/example/App.swift"}, tool_use_id="read-check")
assert "actionEndedAt" in read["progress"]
for _ in range(2):
    edited = event("claude", "PostToolUse", tool_name="Edit", tool_input={"file_path": "/private/example/App.swift"}, tool_use_id="edit-check")
assert len(edited["progress"]["changedFileIDs"]) == 1
event("claude", "PreToolUse", tool_name="Bash", tool_input={"command": "swift test"}, tool_use_id="test-check")
tested = event("claude", "PostToolUse", tool_name="Bash", tool_input={"command": "swift test"}, tool_response={"exit_code": 0}, tool_use_id="test-check")
assert tested["progress"]["lastTestPassed"] is True
finished = event("claude", "Stop")
assert finished["progress"]["turnEndedAt"] >= finished["progress"]["turnStartedAt"]
assert len(finished["progress"]["changedFileIDs"]) == 1
event("claude", "UserPromptSubmit")
failed = event("claude", "PostToolUseFailure", tool_name="Bash", tool_input={"command": "swift test"}, tool_use_id="failed-test", error="reported failure")
assert failed["progress"]["lastTestPassed"] is False
assert failed["state"] == "working"  # A failed tool does not imply the agent needs user input.
event("antigravity", "PreInvocation", invocationNum=0)
after_read = event("antigravity", "PostToolUse", toolCall={"id": "agy-read", "name": "view_file", "args": {"AbsolutePath": "/private/example/Model.swift"}})
assert after_read["progress"]["action"] == "reading" and "actionStartedAt" not in after_read["progress"]
assert after_read["progress"]["detail"] == "Model.swift"
stopped = event("antigravity", "Stop", terminationReason="ERROR", error="reported error")
assert stopped["state"] == "attention" and stopped["progress"]["actionFailed"] is True
assert event("claude", "SessionStart")["sessionOpen"] is True
assert event("claude", "SessionEnd")["sessionOpen"] is False
for path in directory.glob("*.json"):
    data = json.loads(path.read_text())
    assert "prompt" not in data and "lastUserInput" not in data
    assert "/private/example" not in json.dumps(data)
    if data.get("session") in ("playground-verification", "default"):
        path.unlink()
print("PASS: hook merge, neutral output, models, action stages, truthful recap, failure handling and privacy")
test_state.cleanup()
