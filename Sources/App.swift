import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate, NSTouchBarDelegate, NSWindowDelegate {
    let model = PlaygroundModel()
    lazy var barView = PlaygroundView(model: model)
    lazy var preview = PlaygroundView(model: model)
    let bar = NSTouchBar()
    var window: NSWindow!
    var statusItem: NSStatusItem!
    var timer: Timer?
    var pollTimer: Timer?
    var statusText: NSTextField!
    var modeText: NSTextField!
    var hintText: NSTextField!
    var pickers: [NSPopUpButton] = []
    var modelLabels: [NSTextField] = []
    var actionLabels: [NSTextField] = []
    var battleStatsLabels: [NSTextField] = []
    var animationFrame = 0
    var shown = false
    var screenAsleep = false
    var battle: CompanionBattle?
    var cycle = false
    var cycleStarted = 0.0
    let identifier = NSTouchBarItem.Identifier("local.touchbarplayground.field")
    func applicationDidFinishLaunching(_ notification: Notification) {
        // A second launch just brings forward the existing app.
        if let id = Bundle.main.bundleIdentifier,
           NSRunningApplication.runningApplications(withBundleIdentifier: id).count > 1 {
            NSRunningApplication.runningApplications(withBundleIdentifier: id).first(where: { $0.processIdentifier != ProcessInfo.processInfo.processIdentifier })?.activate()
            NSApp.terminate(nil); return
        }
        NSApp.setActivationPolicy(.accessory)
        NSApp.appearance = NSAppearance(named: .darkAqua)
        makeMenu(); makeWindow()
        bar.delegate = self
        bar.defaultItemIdentifiers = [identifier]
        bar.principalItemIdentifier = identifier
        barView.onTap = { [weak self] in self?.activate($0) }
        preview.onTap = barView.onTap
        barView.onExitBattle = { [weak self] in self?.liveMode() }
        preview.onExitBattle = barView.onExitBattle
        model.changed = { [weak self] in self?.refresh() }
        model.poll()
        timer = Timer.scheduledTimer(withTimeInterval: 1.0 / 24.0, repeats: true) { [weak self] _ in
            guard let self, !self.screenAsleep else { return }
            self.animationFrame += 1
            if let battle = self.battle {
                battle.advance(1.0 / 24)
                if self.shown { self.barView.needsDisplay = true }
                if self.window.isVisible { self.preview.needsDisplay = true }
                if self.animationFrame % 8 == 0 { self.refresh() }
                return
            }
            if self.cycle {
                let elapsed = Int((ProcessInfo.processInfo.systemUptime - self.cycleStarted) / 8)
                let scenes: [[Tool: Mood]] = [
                    [.codex: .working, .claude: .idle, .antigravity: .idle],
                    [.codex: .working, .claude: .working, .antigravity: .idle],
                    [.codex: .working, .claude: .attention, .antigravity: .working],
                    [.codex: .finished, .claude: .idle, .antigravity: .idle],
                    [.codex: .resting, .claude: .resting, .antigravity: .resting],
                    [.codex: .idle, .claude: .idle, .antigravity: .idle]
                ]
                self.model.demoMoods = scenes[elapsed % scenes.count]
                if Int(ProcessInfo.processInfo.systemUptime * 24) % 24 == 0 { self.refresh() }
            }
            let allSleeping = self.model.moods.values.allSatisfy { $0 == .idle }
            if !allSleeping || self.animationFrame % 8 == 0 {
                if self.shown { self.barView.needsDisplay = true }
                if self.window.isVisible { self.preview.needsDisplay = true }
            }
        }
        timer?.tolerance = 0.008
        pollTimer = Timer.scheduledTimer(withTimeInterval: 1.5, repeats: true) { [weak self] _ in self?.model.poll() }
        pollTimer?.tolerance = 0.3
        NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.screensDidSleepNotification, object: nil, queue: .main) { [weak self] _ in self?.screenAsleep = true }
        NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.screensDidWakeNotification, object: nil, queue: .main) { [weak self] _ in self?.screenAsleep = false }
        if ProcessInfo.processInfo.arguments.contains("--demo") { startDemo() }
        if ProcessInfo.processInfo.arguments.contains("--battle") { startBattle() }
        showBar(); showWindow()
        if let i = ProcessInfo.processInfo.arguments.firstIndex(of: "--diagnostics"), ProcessInfo.processInfo.arguments.count > i + 1 {
            let path = ProcessInfo.processInfo.arguments[i + 1]
            DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
                try? self.barView.snapshot(to: path)
                let moods = Dictionary(uniqueKeysWithValues: self.model.moods.map { ($0.key.rawValue, $0.value.rawValue) })
                let models = Dictionary(uniqueKeysWithValues: Tool.allCases.map { ($0.rawValue, self.model.modelNames(for: $0)) })
                let actions = Dictionary(uniqueKeysWithValues: Tool.allCases.map { ($0.rawValue, self.model.actionCaption(for: $0, time: self.model.animationTime)) })
                let diagnostic: [String: Any] = ["presentationAccepted": self.shown, "hasTouchBarWindow": self.barView.window != nil, "renderedWidth": self.barView.bounds.width, "moods": moods, "models": models, "actions": actions]
                if let data = try? JSONSerialization.data(withJSONObject: diagnostic, options: [.prettyPrinted, .sortedKeys]) {
                    try? data.write(to: URL(fileURLWithPath: path + ".json"))
                }
            }
        }
    }
    func touchBar(_ touchBar: NSTouchBar, makeItemForIdentifier identifier: NSTouchBarItem.Identifier) -> NSTouchBarItem? {
        guard identifier == self.identifier else { return nil }
        let item = NSCustomTouchBarItem(identifier: identifier)
        item.customizationLabel = "Companion playground"
        item.view = barView
        // 685 points leaves Apple's native Control Strip visible on this Mac.
        barView.widthAnchor.constraint(equalToConstant: 685).isActive = true
        barView.heightAnchor.constraint(equalToConstant: 30).isActive = true
        return item
    }
    func makeMenu() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        let image = NSImage(size: NSSize(width: 22, height: 22), flipped: true) { rect in
            PixelArt.draw(.codex, mood: .working, x: 1, y: 0, time: 1, walking: false); return true
        }
        statusItem.button?.image = image
        statusItem.button?.toolTip = "Touch Bar Playground"
        let menu = NSMenu()
        for (title, selector) in [("Open playground", #selector(showWindow)), ("Show Touch Bar playground", #selector(showBar)), ("Hide Touch Bar playground", #selector(hideBar)), ("Try the animations", #selector(startDemo)), ("Use live activity", #selector(liveMode)), ("Companion battle", #selector(startBattle))] {
            let item = NSMenuItem(title: title, action: selector, keyEquivalent: ""); item.target = self; menu.addItem(item)
        }
        menu.addItem(.separator())
        let quit = NSMenuItem(title: "Quit Playground", action: #selector(quitApp), keyEquivalent: "q"); quit.target = self; menu.addItem(quit)
        statusItem.menu = menu
    }
    func label(_ string: String, x: CGFloat, y: CGFloat, width: CGFloat, size: CGFloat = 13, color: NSColor = .labelColor, weight: NSFont.Weight = .regular) -> NSTextField {
        let field = NSTextField(labelWithString: string)
        field.frame = NSRect(x: x, y: y, width: width, height: size > 20 ? 43 : 25)
        field.font = NSFont.systemFont(ofSize: size, weight: weight); field.textColor = color
        window.contentView!.addSubview(field); return field
    }
    func button(_ title: String, x: CGFloat, y: CGFloat, width: CGFloat, action: Selector) {
        let button = NSButton(title: title, target: self, action: action)
        button.bezelStyle = .rounded
        button.frame = NSRect(x: x, y: y, width: width, height: 32)
        window.contentView!.addSubview(button)
    }
    func makeWindow() {
        window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 900, height: 510), styleMask: [.titled, .closable, .miniaturizable], backing: .buffered, defer: false)
        window.title = "Touch Bar Playground"; window.isReleasedWhenClosed = false; window.delegate = self
        window.backgroundColor = NSColor(srgbRed: 0.065, green: 0.075, blue: 0.085, alpha: 1)
        window.center()
        _ = label("A little company while you code.", x: 32, y: 425, width: 840, size: 29, weight: .semibold)
        _ = label("They read, search, build and play. Open apps keep their companions awake.", x: 34, y: 397, width: 830, color: .secondaryLabelColor)
        modeText = label("LIVE ACTIVITY", x: 35, y: 349, width: 820, size: 10, color: Tool.codex.color, weight: .semibold)
        let backing = NSView(frame: NSRect(x: 32, y: 288, width: 836, height: 53))
        backing.wantsLayer = true; backing.layer?.cornerRadius = 10; backing.layer?.backgroundColor = NSColor.black.cgColor
        window.contentView!.addSubview(backing)
        preview.frame = NSRect(x: 12, y: 8.7, width: 812, height: 35.6)
        backing.addSubview(preview)
        for (i, tool) in Tool.allCases.enumerated() {
            let x = CGFloat(35 + i * 284)
            _ = label(tool.title, x: x, y: 245, width: 240, size: 15, color: tool.color, weight: .semibold)
            let picker = NSPopUpButton(frame: NSRect(x: x - 2, y: 215, width: 245, height: 28))
            picker.addItems(withTitles: Mood.allCases.map(\.title))
            picker.tag = i; picker.target = self; picker.action = #selector(selectMood(_:))
            picker.setAccessibilityLabel("\(tool.title) preview state")
            window.contentView!.addSubview(picker); pickers.append(picker)
            let modelLabel = label("Waiting for model…", x: x, y: 185, width: 252, size: 10, color: .secondaryLabelColor)
            modelLabel.lineBreakMode = .byTruncatingMiddle
            modelLabels.append(modelLabel)
            let actionLabel = label("Waiting for activity…", x: x, y: 157, width: 252, size: 11, color: tool.color)
            actionLabel.lineBreakMode = .byTruncatingMiddle; actionLabels.append(actionLabel)
            let stats = label("", x:x, y:133, width:260, size:9, color:.systemMint)
            stats.lineBreakMode = .byTruncatingMiddle; stats.isHidden = true; battleStatsLabels.append(stats)
        }
        statusText = label("Connecting to local activity…", x: 35, y: 126, width: 830, size: 11, color: .secondaryLabelColor)
        button("Try animations", x: 30, y: 78, width: 143, action: #selector(startDemo))
        button("Live activity", x: 180, y: 78, width: 127, action: #selector(liveMode))
        button("Battle!", x: 316, y: 78, width: 110, action: #selector(startBattle))
        button("Show on Touch Bar", x: 550, y: 78, width: 164, action: #selector(showBar))
        button("Hide", x: 724, y: 78, width: 145, action: #selector(hideBar))
        hintText = label("Tap a companion to visit its app. Tap empty space to call one over.", x: 35, y: 32, width: 830, size: 11, color: .secondaryLabelColor)
    }
    func refresh() {
        if let battle {
            battle.syncLive(from: model)
            statusText.frame.origin.y = 108
            hintText.stringValue = "Tap a fighter: shield + special. Empty ground: dash. Labels stay with their fighter; full details below. LIVE exits."
            modeText.stringValue = "LIVE BATTLE · ROUND \(battle.round) · \(shown ? "TOUCH BAR SHOWN" : "TOUCH BAR HIDDEN")"
            statusText.stringValue = battle.caption
            for (i, tool) in Tool.allCases.enumerated() {
                pickers[i].isEnabled = false
                let fighter = battle.fighters.first { $0.tool == tool }!
                let activity = battle.live[tool]!
                pickers[i].selectItem(at: Mood.allCases.firstIndex(of: activity.mood)!)
                let effort = activity.effort.map { " · " + $0 } ?? ""
                modelLabels[i].stringValue = activity.modelName + effort
                modelLabels[i].toolTip = model.modelDetail(for: tool)
                modelLabels[i].setAccessibilityLabel("\(tool.title) live model: \(activity.modelName + effort)")
                actionLabels[i].stringValue = activity.caption
                actionLabels[i].toolTip = activity.caption
                actionLabels[i].setAccessibilityLabel("\(tool.title) live action: \(activity.caption)")
                let stats = "HP \(fighter.health) · Energy \(Int(fighter.energy)) · Wins \(battle.scores[tool, default:0]) · Work \(elapsedText(fighter.workSeconds))"
                let idle = fighter.idleSeconds > 1 ? " · Idle \(elapsedText(fighter.idleSeconds))" : ""
                battleStatsLabels[i].isHidden = false
                battleStatsLabels[i].stringValue = stats + idle
                battleStatsLabels[i].setAccessibilityLabel("\(tool.title) game stats: \(stats + idle)")
                battleStatsLabels[i].toolTip = stats + idle + " (work and idle time observed while the arena is open; fictional game stats)"

            }
            preview.needsDisplay = true; barView.needsDisplay = true
            return
        }
        statusText.frame.origin.y = 126
        for stats in battleStatsLabels { stats.isHidden = true }
        hintText.stringValue = "Tap a companion to visit its app. Tap empty space to call one over."
        for picker in pickers { picker.isEnabled = true }
        let moods = model.moods
        for (i, tool) in Tool.allCases.enumerated() {
            pickers[i].selectItem(at: Mood.allCases.firstIndex(of: moods[tool, default: .idle])!)
            let sessions = model.relevantActivities(for: tool)
            let names = model.modelNames(for: tool)
            let effort = model.demo ? "" : (sessions.first?.effort.map { " · \($0)" } ?? "")
            let last = [.idle, .resting].contains(moods[tool, default: .idle]) && !model.demo ? "Last: " : ""
            modelLabels[i].stringValue = names.isEmpty ? "Model unavailable · waiting for activity" : last + names.joined(separator: " / ") + effort
            modelLabels[i].toolTip = model.modelDetail(for: tool)
            modelLabels[i].setAccessibilityLabel("\(tool.title) model: \(model.modelDetail(for: tool))")
            let caption = model.actionCaption(for: tool, time: model.animationTime)
            actionLabels[i].stringValue = caption; actionLabels[i].toolTip = caption
            actionLabels[i].setAccessibilityLabel("\(tool.title) action: \(caption)")
        }
        modeText.stringValue = model.demo ? "ANIMATION PREVIEW · \(cycle ? "AUTOPLAY" : "CUSTOM STATES")" : "LIVE ACTIVITY · \(shown ? "TOUCH BAR SHOWN" : "TOUCH BAR HIDDEN")"
        statusText.stringValue = model.demo ? "Preview mode. Choose a state above, or switch back to live activity." : Tool.allCases.map { "\($0.title): \(moods[$0, default: .idle].title.lowercased())" }.joined(separator: "    ·    ")
        preview.needsDisplay = true; barView.needsDisplay = true
    }
    @objc func selectMood(_ sender: NSPopUpButton) {
        if !model.demo { model.demoMoods = model.moods }
        cycle = false; model.demo = true
        model.demoMoods[Tool.allCases[sender.tag]] = Mood.allCases[sender.indexOfSelectedItem]
        refresh()
    }
    @objc func startDemo() { endBattle(); cycleStarted = ProcessInfo.processInfo.systemUptime; cycle = true; model.demo = true; refresh() }
    @objc func liveMode() { endBattle(); cycle = false; model.demo = false; model.poll(); refresh() }
    func endBattle() {
        battle = nil; barView.battle = nil; preview.battle = nil
        for view in [barView, preview] { view.setAccessibilityLabel("Companion playground. Tap a companion to visit its coding app.") }
    }
    @objc func startBattle() {
        cycle = false; model.demo = false; model.poll()
        let game = CompanionBattle(seed: UInt64(Date().timeIntervalSince1970 * 1000))
        game.syncLive(from: model)
        battle = game; barView.battle = game; preview.battle = game
        for view in [barView, preview] { view.setAccessibilityLabel("Companion battle. Tap a fighter to shield and attack. Tap empty ground to dash. Tap LIVE at the right to return to coding activity.") }
        refresh()
    }
    @objc func showBar() {
        shown = PlaygroundPresent(bar)
        refresh()
        if !shown { statusText.stringValue = "Touch Bar presentation is unavailable on this macOS version. The preview still works." }
    }
    @objc func hideBar() { PlaygroundDismiss(bar); shown = false; refresh() }
    @objc func showWindow() { window.makeKeyAndOrderFront(nil); NSApp.activate(ignoringOtherApps: true) }
    @objc func quitApp() { NSApp.terminate(nil) }
    func activate(_ tool: Tool) {
        if model.demo { return }
        let workspace = NSWorkspace.shared
        let candidates: [String]
        switch tool {
        case .codex: candidates = ["/Applications/Codex.app", "/Applications/ChatGPT.app"]
        case .claude: candidates = ["/Applications/Claude.app"]
        case .antigravity: candidates = ["/Applications/Antigravity IDE.app", "/Applications/Antigravity.app"]
        }
        if let path = candidates.first(where: { FileManager.default.fileExists(atPath: $0) }) {
            workspace.openApplication(at: URL(fileURLWithPath: path), configuration: NSWorkspace.OpenConfiguration())
        }
    }
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool { showWindow(); return true }
    func applicationWillTerminate(_ notification: Notification) { timer?.invalidate(); pollTimer?.invalidate(); PlaygroundDismiss(bar) }
}
