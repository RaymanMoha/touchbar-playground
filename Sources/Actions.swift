import AppKit
import CryptoKit

enum WorkAction: String, Codable, CaseIterable {
    case thinking, reading, searching, editing, command, testing, building, browsing, replying, waiting, done
    var title: String {
        switch self {
        case .thinking: return "Thinking"; case .reading: return "Reading"; case .searching: return "Searching"
        case .editing: return "Editing"; case .command: return "Running"; case .testing: return "Testing"
        case .building: return "Building"; case .browsing: return "Checking screen"; case .replying: return "Replying"
        case .waiting: return "Waiting"; case .done: return "Done"
        }
    }
    var pastTitle: String {
        switch self {
        case .reading: return "Read"; case .searching: return "Searched"; case .editing: return "Edited"
        case .command: return "Ran"; case .testing: return "Test run"; case .building: return "Built"
        case .browsing: return "Checked screen"; case .thinking: return "Thought"; case .replying: return "Replied"; default: return title
        }
    }
}
struct WorkProgress: Codable {
    var turnStartedAt: Double?
    var turnEndedAt: Double?
    var action: WorkAction = .thinking
    var detail: String?
    var actionStartedAt: Double?
    var actionEndedAt: Double?
    var actionFailed = false
    var changedFileIDs: [String] = []
    var lastTestPassed: Bool?
    var currentTestPassed: Bool? = nil
    var observedIDs: [String] = []
}
struct ActionObservation {
    var action: WorkAction
    var detail: String? = nil
    var beginsTurn = false
    var endsTurn = false
    var completed = false
    var failed = false
    var id: String? = nil
    var changedPaths: [String] = []
    var testPassed: Bool? = nil
    var reportedDuration: Double? = nil
}
func safeFileName(_ value: String?) -> String? {
    guard let value, let name = cleanModelName(URL(fileURLWithPath: value).lastPathComponent), name.count <= 72 else { return nil }
    return name
}
func elapsedText(_ seconds: Double) -> String {
    let seconds = max(0, Int(seconds))
    if seconds >= 3600 { return "\(seconds / 3600)h \((seconds % 3600) / 60)m" }
    if seconds >= 60 { return "\(seconds / 60)m \(seconds % 60)s" }
    return "\(seconds)s"
}
func advanceActivity(_ incoming: Activity, previous: Activity?, observation: ActionObservation?) -> Activity {
    var next = incoming
    next.sessionOpen = incoming.sessionOpen ?? previous?.sessionOpen
    if incoming.modelName == nil && incoming.modelSource != "pending", let previous {
        next.modelName = previous.modelName; next.modelSource = previous.modelSource; next.effort = previous.effort
    }
    guard let observation else { next.progress = incoming.progress ?? previous?.progress; return next }
    let begins = observation.beginsTurn || (previous?.progress?.turnEndedAt != nil && incoming.state == .working && !observation.completed)
    var progress = begins ? WorkProgress(turnStartedAt: incoming.time) : (previous?.progress ?? WorkProgress())
    if let id = observation.id, progress.observedIDs.contains(id) { next.progress = progress; return next }
    if let id = observation.id { progress.observedIDs.append(id); progress.observedIDs = Array(progress.observedIDs.suffix(512)) }
    if !observation.completed { progress.actionStartedAt = incoming.time }
    else if progress.action != observation.action || progress.detail != observation.detail { progress.actionStartedAt = nil }
    progress.currentTestPassed = observation.action == .testing && observation.completed ? observation.testPassed : nil
    progress.action = observation.action; progress.detail = observation.detail
    progress.actionEndedAt = observation.completed ? incoming.time : nil
    progress.actionFailed = observation.failed
    for path in observation.changedPaths {
        let id = SHA256.hash(data: Data(path.utf8)).map { String(format: "%02x", $0) }.joined()
        if !progress.changedFileIDs.contains(id) { progress.changedFileIDs.append(id) }
    }
    if let passed = observation.testPassed { progress.lastTestPassed = passed }
    if observation.endsTurn {
        progress.turnEndedAt = incoming.time
        if progress.turnStartedAt == nil, let duration = observation.reportedDuration { progress.turnStartedAt = incoming.time - max(0, duration) }
    }
    next.progress = progress
    return next
}

func commandObservation(_ command: String) -> ActionObservation {
    let text = command.trimmingCharacters(in: .whitespacesAndNewlines)
    let checks: [(String, WorkAction, String)] = [
        (#"(^|[;&|]\s*)(?:npm|pnpm|yarn|bun)\s+(?:run\s+)?test(?:\s|:|$)"#, .testing, "tests"),
        (#"(^|[;&|]\s*)(?:swift|cargo|go)\s+test(?:\s|$)|(^|[;&|]\s*)(?:pytest|jest|vitest)(?:\s|$)|(^|[;&|]\s*)python[\d.]*\s+-m\s+pytest(?:\s|$)"#, .testing, "tests"),
        (#"(^|[;&|]\s*)xcodebuild\b[^\n]*\btest\b"#, .testing, "Xcode tests"),
        (#"(^|[;&|]\s*)(?:swift|cargo)\s+build\b|(^|[;&|]\s*)(?:npm|pnpm|yarn|bun)\s+(?:run\s+)?build\b|(^|[;&|]\s*)(?:xcodebuild|make)\b"#, .building, "build"),
        (#"(^|[;&|]\s*)(?:rg|grep|find|fd)\s"#, .searching, "files"),
        (#"(^|[;&|]\s*)(?:cat|head|tail|sed)\s"#, .reading, "files")
    ]
    for (pattern, action, detail) in checks where text.range(of: pattern, options: .regularExpression) != nil {
        return ActionObservation(action: action, detail: detail)
    }
    return ActionObservation(action: .command, detail: "command")
}

func toolObservation(name: String, input: [String: Any], source: String? = nil) -> ActionObservation {
    let lower = name.lowercased()
    let path = input["file_path"] as? String ?? input["path"] as? String ?? input["AbsolutePath"] as? String ?? input["TargetFile"] as? String ?? input["file"] as? String
    if lower.contains("request_user_input") || lower.contains("askuserquestion") || lower.contains("ask_permission") {
        return ActionObservation(action: .waiting, detail: "your input")
    }
    if ["read", "read_file", "view_file", "view_file_outline", "read_mcp_resource"].contains(lower) { return ActionObservation(action: .reading, detail: safeFileName(path)) }
    if lower.contains("search") || lower.contains("grep") || lower == "glob" || lower == "find_by_name" { return ActionObservation(action: .searching, detail: "files") }
    if lower.contains("edit") || lower == "write" || lower.contains("write_file") || lower == "write_to_file" || lower.contains("patch") || lower.contains("replace_file") {
        return ActionObservation(action: .editing, detail: safeFileName(path))
    }
    if lower.contains("browser") || lower.contains("screenshot") || lower.contains("cua_repl") || lower.contains("playwright") { return ActionObservation(action: .browsing) }
    if let command = input["command"] as? String ?? input["cmd"] as? String ?? input["CommandLine"] as? String { return commandObservation(command) }
    // Free-form orchestration code is not executed or retained. Only known
    // operation names, or literal JSON command arguments, inform the caption.
    if let source {
        if source.contains("tools.apply_patch(") { return ActionObservation(action: .editing, detail: "files") }
        if source.contains("tools.web__run(") { return ActionObservation(action: .searching, detail: "web") }
        if let regex = try? NSRegularExpression(pattern: #""cmd"\s*:\s*("(?:\\.|[^"\\])*")"#),
           let match = regex.firstMatch(in: source, range: NSRange(source.startIndex..., in: source)),
           let range = Range(match.range(at: 1), in: source),
           let data = "[\(source[range])]".data(using: .utf8),
           let values = try? JSONSerialization.jsonObject(with: data) as? [String], let command = values.first {
            return commandObservation(command)
        }
    }
    return ActionObservation(action: .command, detail: "tools")
}

func hookObservation(event: String, input: [String: Any], failed: Bool) -> ActionObservation {
    if event == "UserPromptSubmit" { return ActionObservation(action: .thinking, beginsTurn: true) }
    if event == "PreInvocation" { return ActionObservation(action: .thinking, beginsTurn: input["invocationNum"] as? Int == 0) }
    if event == "PermissionRequest" { return ActionObservation(action: .waiting, detail: "approval") }
    if event == "Notification" { return ActionObservation(action: .waiting, detail: "your input") }
    if event == "Stop" {
        if input["fullyIdle"] as? Bool == false { return ActionObservation(action: .command, detail: "background work") }
        return ActionObservation(action: .done, endsTurn: true, completed: true, failed: failed)
    }
    let call = input["toolCall"] as? [String: Any] ?? [:]
    let name = input["tool_name"] as? String ?? call["name"] as? String ?? ""
    let args = input["tool_input"] as? [String: Any] ?? call["args"] as? [String: Any] ?? [:]
    var result = toolObservation(name: name, input: args)
    result.id = (input["tool_use_id"] as? String ?? call["id"] as? String).map { event + ":" + $0 }
    result.completed = event == "PostToolUse" || event == "PostToolUseFailure"
    result.failed = failed
    if result.completed && !failed && result.action == .editing {
        if let path = args["file_path"] as? String ?? args["TargetFile"] as? String ?? args["path"] as? String { result.changedPaths = [path] }
    }
    // Only a reported exit code can determine a test-run result.
    if result.completed && result.action == .testing {
        let response = input["tool_response"] as? [String: Any] ?? [:]
        if let code = response["exit_code"] as? Int ?? response["exitCode"] as? Int { result.testPassed = code == 0 }
        else if failed { result.testPassed = false }
    }
    return result
}

func codexItemObservation(_ item: [String: Any]) -> ActionObservation? {
    let kind = item["type"] as? String ?? ""
    var observation: ActionObservation
    switch kind {
    case "CommandExecution":
        let command = item["command"] as? [String] ?? []
        observation = commandObservation(command.last ?? "")
        let parsed = item["parsed_cmd"] as? [[String: Any]] ?? []
        if let read = parsed.first(where: { $0["type"] as? String == "read" }) {
            observation = ActionObservation(action: .reading, detail: safeFileName(read["path"] as? String))
        } else if parsed.contains(where: { ["search", "list_files"].contains($0["type"] as? String ?? "") }) {
            observation = ActionObservation(action: .searching, detail: "files")
        }
        if observation.action == .testing, let exit = item["exit_code"] as? Int { observation.testPassed = exit == 0 }
    case "FileChange":
        let changes = item["changes"] as? [String: Any] ?? [:]
        let paths = Array(changes.keys).sorted()
        observation = ActionObservation(action: .editing, detail: paths.count == 1 ? safeFileName(paths.first) : "\(paths.count) files")
        if item["status"] as? String == "completed" { observation.changedPaths = paths }
    case "McpToolCall":
        let server = item["server"] as? String ?? ""
        let tool = item["tool"] as? String ?? ""
        let name = server.contains("cua_repl") || server.contains("playwright") ? "\(server).\(tool)" : tool
        observation = toolObservation(name: name, input: item["arguments"] as? [String: Any] ?? [:])
    case "Reasoning": observation = ActionObservation(action: .thinking)
    case "AgentMessage": observation = ActionObservation(action: .replying)
    case "ImageView": observation = ActionObservation(action: .reading, detail: safeFileName(item["path"] as? String))
    case "Extension":
        observation = (item["kind"] as? String ?? "").lowercased().contains("search") ? ActionObservation(action: .searching, detail: "web") : ActionObservation(action: .command, detail: "tools")
    default: return nil
    }
    observation.completed = true
    observation.failed = item["status"] as? String == "failed"
    observation.id = (item["id"] as? String).map { "end:" + $0 }
    return observation
}

func completionRecap(_ progress: WorkProgress) -> String {
    var parts: [String] = []
    if !progress.changedFileIDs.isEmpty { parts.append("\(progress.changedFileIDs.count) file\(progress.changedFileIDs.count == 1 ? "" : "s")") }
    if let passed = progress.lastTestPassed { parts.append(passed ? "tests ✓" : "tests !") }
    if let start = progress.turnStartedAt, let end = progress.turnEndedAt { parts.append(elapsedText(end - start)) }
    return parts.isEmpty ? "Done" : parts.joined(separator: " · ")
}

enum ToolPresence {
    static func openApps() -> Set<Tool> {
        var tools: Set<Tool> = []
        for app in NSWorkspace.shared.runningApplications {
            let name = app.bundleURL?.lastPathComponent.lowercased() ?? ""
            if ["codex.app", "codex (aperitif).app", "chatgpt.app"].contains(name) { tools.insert(.codex) }
            if name == "claude.app" { tools.insert(.claude) }
            if ["antigravity.app", "antigravity ide.app"].contains(name) { tools.insert(.antigravity) }
        }
        return tools
    }
}
