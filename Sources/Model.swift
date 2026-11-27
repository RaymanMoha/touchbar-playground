import AppKit
import CryptoKit

enum Tool: String, Codable, CaseIterable {
    case codex, claude, antigravity
    var title: String { switch self { case .codex: return "Codex"; case .claude: return "Claude Code"; case .antigravity: return "Antigravity" } }
    var color: NSColor { switch self {
        case .codex: return NSColor(srgbRed: 0.65, green: 0.65, blue: 1, alpha: 1)
        case .claude: return NSColor(srgbRed: 0.843, green: 0.463, blue: 0.333, alpha: 1)
        case .antigravity: return NSColor(srgbRed: 0.61, green: 0.56, blue: 0.94, alpha: 1)
    } }
}
enum Mood: String, Codable, CaseIterable { case idle, resting, working, attention, finished
    var title: String { switch self { case .idle: return "Sleeping"; case .resting: return "App open · idle"; case .working: return "Working"; case .attention: return "Needs you"; case .finished: return "Finished" } }
}
struct Activity: Codable {
    var tool: Tool
    var session: String
    var state: Mood
    var time: Double
    var modelName: String? = nil
    var modelSource: String? = nil
    var effort: String? = nil
    var progress: WorkProgress? = nil
    var sessionOpen: Bool? = nil
}

func cleanModelName(_ value: String?) -> String? {
    guard let value = value?.trimmingCharacters(in: .whitespacesAndNewlines),
          !value.isEmpty, value.count <= 128, !value.hasPrefix("<"),
          !value.unicodeScalars.contains(where: { CharacterSet.controlCharacters.contains($0) }) else { return nil }
    return value
}

// Read only the newest bounded transcript segment and retain a model identifier.
// A newer human message makes an older assistant's model ineligible.
func claudeResponseModel(at path: String) -> String? {
    guard let handle = try? FileHandle(forReadingFrom: URL(fileURLWithPath: path)) else { return nil }
    defer { try? handle.close() }
    guard let size = try? handle.seekToEnd() else { return nil }
    let offset = size > 1_048_576 ? size - 1_048_576 : 0
    try? handle.seek(toOffset: offset)
    guard let data = try? handle.read(upToCount: 1_048_576) else { return nil }
    let lines = data.split(separator: 10)
    for (index, line) in lines.enumerated().reversed() {
        if offset > 0 && index == 0 { continue }
        guard let object = try? JSONSerialization.jsonObject(with: Data(line)) as? [String: Any],
              let message = object["message"] as? [String: Any] else { continue }
        if object["type"] as? String == "assistant", let name = cleanModelName(message["model"] as? String) { return name }
        if object["type"] as? String == "user" {
            if message["content"] is String { return nil }
            if let blocks = message["content"] as? [[String: Any]], blocks.contains(where: { $0["type"] as? String == "text" }) { return nil }
        }
    }
    return nil
}
// An explicit state root lets verification run without touching a real profile.
let support = ProcessInfo.processInfo.environment["TOUCHBAR_PLAYGROUND_STATE_DIR"].map { URL(fileURLWithPath: $0, isDirectory: true) }
    ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support/TouchBarPlayground")
let eventDirectory = support.appendingPathComponent("events")

func writeActivity(_ incoming: Activity, directory: URL = eventDirectory, observation: ActionObservation? = nil) throws {
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
    let hash = SHA256.hash(data: Data(incoming.session.utf8)).map { String(format: "%02x", $0) }.joined().prefix(20)
    let path = directory.appendingPathComponent("\(incoming.tool.rawValue)-\(hash).json")
    let previous = (try? Data(contentsOf: path)).flatMap { try? JSONDecoder().decode(Activity.self, from: $0) }
    let activity = advanceActivity(incoming, previous: previous, observation: observation)
    try JSONEncoder().encode(activity).write(to: path, options: .atomic)
    try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: path.path)
}

// Session aggregation prevents one completed chat from putting another working
// chat to sleep. Completion is a brief celebration, attention persists.
func aggregate(_ activities: [Activity], tool: Tool, now: Double) -> Mood {
    let current = activities.filter { $0.tool == tool && now - $0.time < 8 * 3600 }
    if current.contains(where: { $0.state == .attention }) { return .attention }
    if current.contains(where: { $0.state == .working }) { return .working }
    if current.contains(where: { $0.state == .finished && now - $0.time < 16 }) { return .finished }
    return .idle
}

struct PlaygroundLayout {
    var lanes: [Tool: ClosedRange<Double>] = [:]
    var docks: [Tool: Double] = [:]
    init(width: Double, moods: [Tool: Mood]) {
        let active = Tool.allCases.filter { moods[$0, default: .idle] != .idle }
        let sleeping = Tool.allCases.filter { !active.contains($0) }
        // Sleeping characters take only 28pt each, all remaining width is shared.
        let dockWidth = Double(sleeping.count) * 28
        let usable = max(90, width - 20 - dockWidth)
        let totalWeight = active.reduce(0.0) { $0 + (moods[$1] == .resting ? 0.45 : 1) }
        var start = 10.0
        for tool in active {
            let lane = usable * (moods[tool] == .resting ? 0.45 : 1) / totalWeight
            let lo = start + 12
            lanes[tool] = lo ... max(lo, start + lane - 34)
            start += lane
        }
        for (i, tool) in sleeping.enumerated() {
            docks[tool] = active.isEmpty ? width / 2 + Double(i - 1) * 42 : width - dockWidth + Double(i) * 28 + 6
        }
    }
}

final class PlaygroundModel {
    var activities: [String: Activity] = [:]
    var demo = false
    var demoMoods: [Tool: Mood] = [.codex: .working, .claude: .idle, .antigravity: .idle]
    var demoAction: WorkAction?
    var openTools: Set<Tool> = []
    let animationOrigin = ProcessInfo.processInfo.systemUptime
    var animationTime: Double { ProcessInfo.processInfo.systemUptime - animationOrigin }
    var changed: (() -> Void)?
    private(set) var hasLoadedActivity = false
    private var cursors: [String: UInt64] = [:]
    private var partial: [String: Data] = [:]
    private var codexFiles: [URL] = []
    private var codexMetadata: [String: (String?, String?)] = [:]
    private var codexActivities: [String: Activity] = [:]
    private var lastDiscovery = Date.distantPast
    private let queue = DispatchQueue(label: "playground.activity", qos: .utility)
    private var polling = false
    var moods: [Tool: Mood] {
        if demo { return demoMoods }
        let now = Date().timeIntervalSince1970
        return Dictionary(uniqueKeysWithValues: Tool.allCases.map { tool in
            let mood = aggregate(Array(activities.values), tool: tool, now: now)
            let openSession = tool == .claude && activities.values.contains { $0.tool == tool && $0.sessionOpen == true && now - $0.time < 8 * 3600 }
            return (tool, mood == .idle && (openTools.contains(tool) || openSession) ? .resting : mood)
        })
    }
    func relevantActivities(for tool: Tool) -> [Activity] {
        let now = Date().timeIntervalSince1970
        let recent = activities.values.filter { $0.tool == tool && now - $0.time < 8 * 3600 }
        let active = recent.filter { $0.state == .working || $0.state == .attention }
        if !active.isEmpty { return active.sorted { $0.time == $1.time ? $0.session < $1.session : $0.time > $1.time } }
        let celebrating = recent.filter { $0.state == .finished && now - $0.time < 16 }
        if !celebrating.isEmpty { return celebrating.sorted { $0.time > $1.time } }
        return Array(recent.sorted { $0.time > $1.time }.prefix(1))
    }
    func displayActivity(for tool: Tool, time: Double) -> Activity? {
        let sessions = relevantActivities(for: tool)
        if let waiting = sessions.first(where: { $0.state == .attention }) { return waiting }
        return sessions.isEmpty ? nil : sessions[Int(time / 5) % sessions.count]
    }
    func modelNames(for tool: Tool) -> [String] {
        if demo { return ["example-model"] }
        return Array(Set(relevantActivities(for: tool).compactMap { cleanModelName($0.modelName) })).sorted()
    }
    func modelLabel(for tool: Tool, time: Double = 0) -> String {
        if demo { return "example-model" }
        guard let name = displayActivity(for: tool, time: time)?.modelName else { return "Model unavailable" }
        return name.lowercased() == "auto" ? "Auto (reported)" : name
    }
    func workProgress(for tool: Tool, time: Double) -> WorkProgress? {
        if !demo { return displayActivity(for: tool, time: time)?.progress }
        if [.idle, .resting].contains(moods[tool, default: .idle]) { return nil }
        if moods[tool] == .attention { return WorkProgress(action: .waiting, detail: "approval") }
        let examples: [WorkAction] = [.reading, .searching, .editing, .command, .testing, .building, .thinking, .browsing]
        let action = demoAction ?? examples[(Int(time / 4) + Tool.allCases.firstIndex(of: tool)!) % examples.count]
        let now = Date().timeIntervalSince1970
        return WorkProgress(turnStartedAt: now - 74, turnEndedAt: moods[tool] == .finished ? now : nil, action: action, detail: [.reading, .editing].contains(action) ? "App.swift" : nil, actionStartedAt: now - time.truncatingRemainder(dividingBy: 4), changedFileIDs: ["example-1", "example-2"], lastTestPassed: true)
    }
    func actionCaption(for tool: Tool, time: Double) -> String {
        let mood = moods[tool, default: .idle]
        if mood == .resting { return !demo && !openTools.contains(tool) ? "Idle · session open" : "Idle · app open" }
        if mood == .idle { return "Sleeping" }
        guard let progress = workProgress(for: tool, time: time) else { return mood == .attention ? "Waiting · your input" : mood.title }
        if mood == .finished { return completionRecap(progress) }
        if mood == .attention { return progress.actionFailed ? "Stopped · error" : "Waiting · \(progress.detail ?? "your input")" }
        var title = progress.actionEndedAt != nil ? progress.action.pastTitle : progress.action.title
        if progress.action == .command && progress.detail == "tools" { title = progress.actionEndedAt != nil ? "Tools finished" : "Using tools" }
        if progress.actionFailed {
            switch progress.action {
            case .reading: title = "Read failed"; case .searching: title = "Search failed"; case .editing: title = "Edit failed"
            case .command: title = progress.detail == "tools" ? "Tool failed" : "Command failed"
            case .testing: title = "Tests failed"; case .building: title = "Build failed"; case .browsing: title = "Check failed"
            default: title = "Action failed"
            }
        }
        var parts = [title]
        if let detail = progress.detail, !["tools", "command", "build", "tests"].contains(detail) { parts.append(detail) }
        if let start = progress.actionStartedAt { parts.append(elapsedText((progress.actionEndedAt ?? Date().timeIntervalSince1970) - start)) }
        return parts.joined(separator: " · ")
    }
    func modelDetail(for tool: Tool) -> String {
        if demo { return "Example model · preview only" }
        let sessions = relevantActivities(for: tool)
        let details = sessions.map { activity -> String in
            let name = activity.modelName ?? "Model unavailable"
            let effort = activity.effort.map { " · \($0) effort" } ?? ""
            let source: String
            switch activity.modelSource {
            case "response": source = "response metadata"
            case "turn": source = "turn metadata"
            case "hook": source = "reported by tool"
            default: source = "awaiting model metadata"
            }
            return "\(name)\(effort) — \(source)"
        }
        return details.isEmpty ? "Model unavailable · waiting for activity" : details.joined(separator: "\n")
    }
    func poll() {
        openTools = ToolPresence.openApps()
        guard !polling else { return }; polling = true
        queue.async { [self] in
            let now = Date()
            var updates: [Activity] = []
            // Only status metadata is retained. Prompt and response text is discarded.
            if let files = try? FileManager.default.contentsOfDirectory(at: eventDirectory, includingPropertiesForKeys: [.contentModificationDateKey]) {
                for path in files where path.pathExtension == "json" {
                    if let data = try? Data(contentsOf: path), let event = try? JSONDecoder().decode(Activity.self, from: data) { updates.append(event) }
                }
            }
            if now.timeIntervalSince(lastDiscovery) > 8 {
                lastDiscovery = now
                var discovered: [URL] = []
                let formatter = DateFormatter(); formatter.locale = Locale(identifier: "en_US_POSIX"); formatter.calendar = Calendar(identifier: .gregorian); formatter.dateFormat = "yyyy/MM/dd"; formatter.timeZone = TimeZone(secondsFromGMT: 0)
                let base = ProcessInfo.processInfo.environment["CODEX_HOME"].map { URL(fileURLWithPath: $0) } ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".codex")
                for offset in 0...1 {
                    let day = formatter.string(from: now.addingTimeInterval(-Double(offset) * 86400))
                    if let files = try? FileManager.default.contentsOfDirectory(at: base.appendingPathComponent("sessions/\(day)"), includingPropertiesForKeys: [.contentModificationDateKey]) {
                        discovered += files.filter { $0.pathExtension == "jsonl" && ((try? $0.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate)?.timeIntervalSinceNow ?? -999999) > -8 * 3600 }
                    }
                }
                codexFiles = discovered
            }
            for path in codexFiles {
                func appendCodex(_ activity: Activity, _ observation: ActionObservation?) {
                    let next = advanceActivity(activity, previous: codexActivities[path.path], observation: observation)
                    codexActivities[path.path] = next; updates.append(next)
                }
                guard let handle = try? FileHandle(forReadingFrom: path) else { continue }
                defer { try? handle.close() }
                guard let size = try? handle.seekToEnd() else { continue }
                let old = cursors[path.path]
                var offset = old ?? (size > 8_388_608 ? size - 8_388_608 : 0)
                if offset > size { offset = 0; partial[path.path] = nil }
                guard offset < size else { continue }
                try? handle.seek(toOffset: offset)
                guard let incoming = try? handle.read(upToCount: Int(min(size - offset, 8 * 1024 * 1024))) else { continue }
                cursors[path.path] = offset + UInt64(incoming.count)
                var data = partial[path.path] ?? Data(); data.append(incoming)
                let lines = data.split(separator: 10, omittingEmptySubsequences: false)
                partial[path.path] = Data(lines.last ?? Data.SubSequence())
                for (index, line) in lines.dropLast().enumerated() {
                    if old == nil && offset > 0 && index == 0 { continue }
                    guard let obj = try? JSONSerialization.jsonObject(with: Data(line)) as? [String: Any], let payload = obj["payload"] as? [String: Any] else { continue }
                    let stamp = (obj["timestamp"] as? String).flatMap(Self.date) ?? now
                    if obj["type"] as? String == "turn_context" {
                        let modelName = cleanModelName(payload["model"] as? String)
                        let effort = cleanModelName(payload["effort"] as? String)
                        codexMetadata[path.path] = (modelName, effort)
                        appendCodex(Activity(tool: .codex, session: path.lastPathComponent, state: .working, time: stamp.timeIntervalSince1970, modelName: modelName, modelSource: "turn", effort: effort), nil)
                        continue
                    }
                    if obj["type"] as? String == "response_item", ["function_call", "custom_tool_call"].contains(payload["type"] as? String ?? "") {
                        let plainName = payload["name"] as? String ?? "tool"
                        let name = (payload["namespace"] as? String == "mcp__cua_repl") ? "cua_repl.\(plainName)" : plainName
                        let argumentData = (payload["arguments"] as? String)?.data(using: .utf8)
                        let args = argumentData.flatMap { try? JSONSerialization.jsonObject(with: $0) as? [String: Any] } ?? [:]
                        var observation = toolObservation(name: name, input: args, source: payload["input"] as? String)
                        observation.id = (payload["call_id"] as? String).map { "start:" + $0 }
                        let metadata = codexMetadata[path.path]
                        appendCodex(Activity(tool: .codex, session: path.lastPathComponent, state: observation.action == .waiting ? .attention : .working, time: stamp.timeIntervalSince1970, modelName: metadata?.0, modelSource: metadata?.0 == nil ? "pending" : "turn", effort: metadata?.1), observation)
                        continue
                    }
                    guard obj["type"] as? String == "event_msg", let type = payload["type"] as? String else { continue }
                    let state: Mood
                    var observation: ActionObservation?
                    switch type {
                    case "task_started": state = .working; codexMetadata[path.path] = nil; observation = ActionObservation(action: .thinking, beginsTurn: true)
                    case "item_completed":
                        state = .working
                        if let item = payload["item"] as? [String: Any] { observation = codexItemObservation(item) }
                    case "task_complete": state = .finished; observation = ActionObservation(action: .done, endsTurn: true, completed: true, reportedDuration: (payload["duration_ms"] as? Double).map { $0 / 1000 })
                    case "turn_aborted", "task_interrupted": state = .idle
                    case "approval_request", "request_user_input": state = .attention; observation = ActionObservation(action: .waiting, detail: "your input")
                    default: continue
                    }
                    let metadata = codexMetadata[path.path]
                    appendCodex(Activity(tool: .codex, session: path.lastPathComponent, state: state, time: stamp.timeIntervalSince1970, modelName: metadata?.0, modelSource: metadata?.0 == nil ? "pending" : "turn", effort: metadata?.1), observation)
                }
            }
            DispatchQueue.main.async { [self] in
                for update in updates {
                    let key = "\(update.tool.rawValue):\(update.session)"
                    if update.time >= (activities[key]?.time ?? 0) { activities[key] = update }
                }
                activities = activities.filter { now.timeIntervalSince1970 - $0.value.time < 8 * 3600 }
                hasLoadedActivity = true; polling = false; changed?()
            }
        }
    }
    // Reuse immutable formatters when replaying a bounded session tail. Creating
    // one for every JSONL record makes the first live update unnecessarily slow.
    private static let fractionalDate: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter(); formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]; return formatter
    }()
    private static let wholeDate = ISO8601DateFormatter()
    static func date(_ string: String) -> Date? {
        fractionalDate.date(from: string) ?? wholeDate.date(from: string)
    }
}
