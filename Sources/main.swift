import AppKit

let arguments = CommandLine.arguments
if arguments.count >= 4 && arguments[1] == "--event", let tool = Tool(rawValue: arguments[2]) {
    // Hooks are observational. Never print a permission decision, continuation
    // request, prompt text or tool arguments, and always exit successfully.
    let data = FileHandle.standardInput.readDataToEndOfFile()
    let input = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] ?? [:]
    let event = arguments[3]
    let session = input["session_id"] as? String ?? input["conversationId"] as? String ?? "default"
    var mood: Mood = .idle
    switch event {
    case "UserPromptSubmit", "PreInvocation", "PreToolUse", "PostToolUse", "PostToolUseFailure": mood = .working
    case "PermissionRequest": mood = .attention
    case "Notification":
        let kind = input["notification_type"] as? String ?? ""
        mood = ["permission_prompt", "idle_prompt", "elicitation_dialog"].contains(kind) ? .attention : .idle
    case "Stop":
        let reason = input["terminationReason"] as? String ?? ""
        if input["fullyIdle"] as? Bool == false { mood = .working }
        else { mood = reason == "ERROR" ? .attention : reason == "USER_CANCELED" ? .idle : .finished }
    default: mood = .idle
    }
    if event != "Notification" || mood == .attention {
        var name = cleanModelName(input["model"] as? String ?? input["modelName"] as? String)
        var source: String? = name == nil ? nil : "hook"
        if tool == .claude, event != "UserPromptSubmit", event != "SessionStart",
           let path = input["transcript_path"] as? String, let response = claudeResponseModel(at: path) {
            name = response; source = "response"
        }
        if name == nil && event == "UserPromptSubmit" { source = "pending" }
        let failed = event == "PostToolUseFailure" || (input["error"] as? String).map { !$0.isEmpty } == true || input["terminationReason"] as? String == "ERROR"
        let observation = ["SessionStart", "SessionEnd"].contains(event) ? nil : hookObservation(event: event, input: input, failed: failed)
        let sessionOpen: Bool? = tool == .claude ? event != "SessionEnd" : nil
        try? writeActivity(Activity(tool: tool, session: session, state: mood, time: Date().timeIntervalSince1970, modelName: name, modelSource: source, sessionOpen: sessionOpen), observation: observation)
    }
    if tool == .antigravity { print("{}") }
    exit(0)
}
if arguments.contains("--self-test") {
    func check(_ condition: @autoclosure () -> Bool, _ message: String) { if !condition() { fputs("FAIL: \(message)\n", stderr); exit(1) } }
    let now = Date().timeIntervalSince1970
    let working = Activity(tool: .codex, session: "one", state: .working, time: now)
    let done = Activity(tool: .codex, session: "two", state: .finished, time: now)
    check(aggregate([working, done], tool: .codex, now: now) == .working, "simultaneous chats stay working")
    check(aggregate([done], tool: .codex, now: now + 17) == .idle, "celebration expires")
    check(aggregate([working], tool: .codex, now: now + 28801) == .idle, "stale work expires")
    let attention = Activity(tool: .codex, session: "three", state: .attention, time: now)
    check(aggregate([working, attention], tool: .codex, now: now) == .attention, "attention is visible during other work")
    let single = PlaygroundLayout(width: 685, moods: [.codex: .working])
    let triple = PlaygroundLayout(width: 685, moods: [.codex: .working, .claude: .working, .antigravity: .working])
    check(single.lanes[.codex]!.upperBound - single.lanes[.codex]!.lowerBound > 3 * (triple.lanes[.codex]!.upperBound - triple.lanes[.codex]!.lowerBound), "one companion gets the free space")
    for lane in triple.lanes.values { check(lane.lowerBound >= 0 && lane.upperBound <= 685, "lanes fit") }
    let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try writeActivity(working, directory: dir)
    let files = try FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil)
    let roundtrip = try JSONDecoder().decode(Activity.self, from: Data(contentsOf: files[0]))
    check(roundtrip.session == working.session && roundtrip.state == .working, "event roundtrip")
    var identified = working; identified.modelName = "gpt-6.1-sol"; identified.modelSource = "turn"
    try writeActivity(identified, directory: dir)
    try writeActivity(working, directory: dir)
    let preserved = try JSONDecoder().decode(Activity.self, from: Data(contentsOf: files[0]))
    check(preserved.modelName == "gpt-6.1-sol", "events without metadata preserve the known model")
    var pending = working; pending.modelSource = "pending"
    try writeActivity(pending, directory: dir)
    let reset = try JSONDecoder().decode(Activity.self, from: Data(contentsOf: files[0]))
    check(reset.modelName == nil, "new prompts do not reuse a previous turn's model")
    let legacy = Data("{\"tool\":\"codex\",\"session\":\"old\",\"state\":\"idle\",\"time\":0}".utf8)
    let decodedLegacy = try JSONDecoder().decode(Activity.self, from: legacy)
    check(decodedLegacy.modelName == nil, "v1 event compatibility")
    check(cleanModelName("<synthetic>") == nil && cleanModelName("fake\nmodel") == nil, "invalid model identifiers are ignored")
    let model = PlaygroundModel()
    var parallel = identified; parallel.session = "parallel"; parallel.modelName = "gpt-6.2-sol"
    model.activities = ["one": identified, "two": parallel]
    check(model.modelNames(for: .codex) == ["gpt-6.1-sol", "gpt-6.2-sol"], "concurrent model IDs are retained")
    check(model.modelLabel(for: .codex, time: 0) != model.modelLabel(for: .codex, time: 5), "concurrent models rotate")
    var task = Activity(tool: .codex, session: "action-check", state: .working, time: 1000)
    task = advanceActivity(task, previous: nil, observation: ActionObservation(action: .thinking, beginsTurn: true))
    var toolStart = task; toolStart.time = 1003
    task = advanceActivity(toolStart, previous: task, observation: ActionObservation(action: .testing, detail: "tests", id: "start:test-1"))
    var duplicateStart = toolStart; duplicateStart.time = 1004
    task = advanceActivity(duplicateStart, previous: task, observation: ActionObservation(action: .testing, detail: "tests", id: "start:test-1"))
    check(task.progress?.actionStartedAt == 1003, "duplicate notifications do not restart an action clock")
    var toolEnd = task; toolEnd.time = 1005
    task = advanceActivity(toolEnd, previous: task, observation: ActionObservation(action: .testing, detail: "tests", completed: true, id: "end:test-1", testPassed: true))
    check(task.progress?.actionEndedAt == 1005 && task.progress?.lastTestPassed == true, "reported test completion freezes its clock")
    var edit = task; edit.time = 1006
    let change = ActionObservation(action: .editing, completed: true, id: "edit-1", changedPaths: ["/one/App.swift", "/two/App.swift"])
    task = advanceActivity(edit, previous: task, observation: change)
    task = advanceActivity(edit, previous: task, observation: change)
    check(task.progress?.changedFileIDs.count == 2, "confirmed files deduplicate by full identity, not basename")
    var end = task; end.time = 1010; end.state = .finished
    task = advanceActivity(end, previous: task, observation: ActionObservation(action: .done, endsTurn: true, completed: true))
    check(completionRecap(task.progress!).contains("2 files") && completionRecap(task.progress!).contains("10s"), "recap uses measured duration and confirmed changes")
    var newTurn = task; newTurn.state = .working; newTurn.time = 1100
    task = advanceActivity(newTurn, previous: task, observation: ActionObservation(action: .thinking, beginsTurn: true))
    check(task.progress?.changedFileIDs.isEmpty == true && task.progress?.lastTestPassed == nil, "new turns clear old task counts")
    check(toolObservation(name: "write_stdin", input: [:]).action != .editing, "terminal polling is not reported as a file edit")
    check(commandObservation("echo 'pytest passed'").action != .testing, "quoted text does not fabricate a test run")
    let unknownTest = codexItemObservation(["type": "CommandExecution", "command": ["/bin/zsh", "-lc", "swift test"], "status": "completed"])
    check(unknownTest?.testPassed == nil, "missing exit status never becomes a passing test")
    let screenCall = codexItemObservation(["type": "McpToolCall", "server": "cua_repl", "tool": "js", "status": "completed", "arguments": [:]])
    check(screenCall?.action == .browsing, "screen actions retain their identity after completion")
    model.activities = [:]; model.openTools = [.codex]
    check(model.moods[.codex] == .resting && model.moods[.claude] == .idle, "open apps stay awake while closed apps sleep")
    let idleLayout = PlaygroundLayout(width: 685, moods: [.codex: .resting])
    check(idleLayout.lanes[.codex] != nil && idleLayout.docks[.codex] == nil, "an open idle app gets playground space")
    var idleSession = Activity(tool: .claude, session: "terminal-check", state: .idle, time: now, sessionOpen: true)
    model.activities = ["terminal-check": idleSession]
    check(model.moods[.claude] == .resting, "idle Claude terminal sessions remain awake")
    idleSession.sessionOpen = false; model.activities["terminal-check"] = idleSession
    check(model.moods[.claude] == .idle, "ended terminal sessions return to sleep")
    for seed in 1...30 {
        let game = CompanionBattle(seed: UInt64(seed))
        check(game.phase == .ready && game.fighters.allSatisfy { $0.health == 100 }, "round starts with full health and countdown")
        var steps = 0
        while game.phase != .finished && steps < 2400 {
            game.advance(1.0/60); steps += 1
            check(game.fighters.allSatisfy { (0...100).contains($0.health) && (0.05...0.95).contains($0.x) }, "fighters stay in bounds with valid health")
        }
        check(game.phase == .finished && game.winner != nil, "autonomous rounds always finish")
        check(game.fighters.contains { $0.health < 100 }, "shots actually damage fighters")
        check(game.scores.values.reduce(0,+) == 1, "one score awarded per round")
        game.advance(4.1)
        check(game.round == 2 && game.phase == .ready && game.fighters.allSatisfy { $0.health == 100 }, "next round resets health and retains score")
        check(game.scores.values.reduce(0,+) == 1, "winner celebration cannot award duplicate scores")
    }
    let boosted = CompanionBattle(seed: 9); boosted.advance(1.6)
    boosted.cheer(.codex)
    let hero = boosted.fighters.first { $0.tool == .codex }!
    check(hero.shieldUntil > boosted.time && boosted.selected == .codex, "tapping selects and shields a fighter")
    let shotCount = boosted.shots.count
    boosted.cheer(.codex)
    check(boosted.shots.count == shotCount, "special attacks respect cooldown")
    boosted.advance(2.1)
    let beforeDash = boosted.fighters.first { $0.tool == .codex }!.x
    boosted.dash(to: beforeDash < 0.5 ? 1 : 0)
    check(abs(boosted.fighters.first { $0.tool == .codex }!.x - beforeDash) <= 0.131, "dash is bounded")
    let first = CompanionBattle(seed: 123), second = CompanionBattle(seed: 123)
    for _ in 0..<300 { first.advance(1.0/60); second.advance(1.0/60) }
    check(first.fighters.map { $0.health } == second.fighters.map { $0.health } && first.fighters.map { $0.x } == second.fighters.map { $0.x }, "seeded battles reproduce deterministically")
    print("PASS: 30 autonomous battles, collision damage, winner scores, rematches, shields, cooldowns, dash bounds and deterministic replay")
    try FileManager.default.removeItem(at: dir)
    print("PASS: models, aggregation, layout, action clocks, recap evidence, deduplication and open-app idle presence")
    exit(0)
}
if let index = arguments.firstIndex(of: "--render-battle"), arguments.count > index + 1 {
    _ = NSApplication.shared
    let model = PlaygroundModel()
    let game = CompanionBattle(seed: 42)
    let seconds = arguments.firstIndex(of: "--at").flatMap { arguments.count > $0 + 1 ? Double(arguments[$0+1]) : nil } ?? 4
    game.advance(seconds)
    let view = PlaygroundView(model: model); view.battle = game
    view.frame = NSRect(x:0,y:0,width:1370,height:60)
    try view.snapshot(to: arguments[index+1])
    print("Battle frame: round \(game.round), phase \(game.phase), health \(game.fighters.map { $0.health })")
    exit(0)
}
if let index = arguments.firstIndex(of: "--render"), arguments.count > index + 1 {
    _ = NSApplication.shared
    let model = PlaygroundModel(); model.demo = true
    if let i = arguments.firstIndex(of: "--action"), arguments.count > i + 1 { model.demoAction = WorkAction(rawValue: arguments[i + 1]) }
    let view = PlaygroundView(model: model); view.frame = NSRect(x: 0, y: 0, width: 1370, height: 60); view.timeOverride = 4
    if arguments.contains("--three") { model.demoMoods = [.codex: .working, .claude: .attention, .antigravity: .working] }
    try view.snapshot(to: arguments[index + 1]); exit(0)
}
let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.run()
