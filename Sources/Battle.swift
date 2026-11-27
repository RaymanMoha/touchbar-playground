import AppKit

// A local toy arena. Health, scores and attacks are fictional game state and
// never modify coding-tool activity, hooks, permissions or running processes.
final class CompanionBattle {
    enum Phase { case ready, fighting, finished }
    enum Mode { case duel, boss }
    struct BugBoss {
        var health: Int
        let maxHealth: Int
        var nextAttack = 1.4
        var hitUntil = 0.0
        var exposedUntil = 0.0
        var defeated = false
        var attackIndex = 0
    }
    let mode: Mode
    private(set) var boss: BugBoss?
    private(set) var combo = 0
    private(set) var bestCombo = 0
    private(set) var comboUntil = 0.0
    private(set) var teamWins = 0
    private(set) var bossWins = 0
    private(set) var lastMove = "Work together to squash the bug"
    private var observedTools: Set<Tool> = []
    private var seenActionIDs: Set<String> = []
    private var actionIDOrder: [String] = []
    private var moveCooldown: [Tool: Double] = [:]
    var bossX: Double { 0.5 + sin(time * 0.31) * 0.32 }
    struct LiveActivity {
        var mood: Mood
        var modelName: String
        var caption: String
        var action: WorkAction
        var effort: String? = nil
        var isLoading = false
        var eventID: String? = nil
        var eventTime: Double? = nil
        var testPassed: Bool? = nil
        var actionCompleted = false
        var failed = false
    }
    struct Fighter {
        let tool: Tool
        var x: Double
        var health = 100
        var cooldown: Double
        var hitUntil = 0.0
        var shieldUntil = 0.0
        var boostReady = 0.0
        var attackUntil = 0.0
        var facingLeft = false
        var energy = 50.0
        var workSeconds = 0.0
        var idleSeconds = 0.0
        var moveUntil = 0.0
        var move = ""
    }
    struct Shot {
        let owner: Tool
        var x: Double
        let speed: Double
        let high: Bool
        let damage: Int
        var hostile = false
        var charged = false
    }
    struct Spark { let x: Double; let tool: Tool; let until: Double; let blocked: Bool }
    private(set) var fighters: [Fighter] = []
    private(set) var shots: [Shot] = []
    private(set) var sparks: [Spark] = []
    private(set) var phase = Phase.ready
    private(set) var time = 0.0
    private(set) var phaseTime = 0.0
    private(set) var round = 1
    private(set) var winner: Tool?
    private(set) var scores: [Tool: Int] = [:]
    private(set) var selected: Tool = .codex
    private(set) var live: [Tool: LiveActivity] = [:]
    // Shared geometry gives every fighter the full playable width and keeps taps
    // aligned between the physical strip and the scaled desktop preview.
    static func arena(width: Double) -> (left: Double, span: Double) { (12, max(80, width - 60)) }
    func syncLive(from model: PlaygroundModel) {
        let moods = model.moods
        let t = model.animationTime
        let loading = !model.hasLoadedActivity && model.activities.isEmpty
        var observations: [Tool: LiveActivity] = [:]
        for tool in Tool.allCases {
            let mood = moods[tool, default: .idle]
            let progress = model.workProgress(for: tool, time: t)
            var name = loading ? "Connecting…" : model.modelLabel(for: tool, time: t)
            if !loading, [.idle, .resting].contains(mood), name != "Model unavailable" { name = "Last: " + name }
            let session = model.displayActivity(for: tool, time: t)?.session ?? ""
            let eventTime = progress?.actionEndedAt ?? progress?.actionStartedAt
            let eventID = eventTime.map { "\(session):\(progress?.turnStartedAt ?? 0):\(progress?.action.rawValue ?? "unknown"):\($0):\(progress?.actionFailed ?? false):\(String(describing: progress?.currentTestPassed))" }
            observations[tool] = LiveActivity(mood: mood, modelName: name, caption: loading ? "Loading local activity…" : model.actionCaption(for: tool, time: t), action: progress?.action ?? .thinking, effort: model.displayActivity(for: tool, time: t)?.effort, isLoading: loading, eventID:eventID, eventTime:eventTime, testPassed:progress?.currentTestPassed, actionCompleted:progress?.actionEndedAt != nil, failed:progress?.actionFailed ?? false)
        }
        updateLive(observations)
    }
    func updateLive(_ observations: [Tool: LiveActivity], now: Double = Date().timeIntervalSince1970) {
        for i in fighters.indices {
            if live[fighters[i].tool]?.mood != observations[fighters[i].tool]?.mood { fighters[i].idleSeconds = 0 }
        }
        live = observations
        guard mode == .boss else { return }
        for tool in Tool.allCases {
            guard let activity=observations[tool], !activity.isLoading else { continue }
            let first=observedTools.insert(tool).inserted
            guard let id=activity.eventID else { continue }
            let key=tool.rawValue+":"+id
            guard seenActionIDs.insert(key).inserted else { continue }
            actionIDOrder.append(key)
            if actionIDOrder.count > 512 { seenActionIDs.remove(actionIDOrder.removeFirst()) }
            // First observations establish a baseline. Old concurrent sessions,
            // failed actions and approval waits never manufacture combos.
            guard !first, phase == .fighting, !activity.failed,
                  [.working,.finished].contains(activity.mood), let stamp=activity.eventTime,
                  now-stamp >= -1, now-stamp < 6,
                  time >= moveCooldown[tool,default:0] || (activity.action == .testing && activity.actionCompleted && activity.testPassed == true) else { continue }
            triggerMove(tool, activity:activity)
        }
    }
    func power(_ fighter: Fighter) -> Double {
        guard let activity = live[fighter.tool], !activity.isLoading else { return 1 }
        let workBoost = activity.mood == .working ? 1.15 : activity.mood == .finished ? 1.1 : 1
        return (0.65 + fighter.energy / 100 * 0.8) * workBoost
    }
    func incomingDamage(_ amount: Int, for fighter: Fighter) -> Int {
        guard let activity = live[fighter.tool], !activity.isLoading else { return max(1,Int((Double(amount)*0.2).rounded())) }
        let mood = activity.mood
        let multiplier = mood == .idle ? 1.6 : mood == .resting ? 1.35 : 1
        return max(1, Int((Double(amount) * multiplier * 0.2).rounded()))
    }
    private var seed: UInt64
    init(seed: UInt64 = 42, mode: Mode = .duel) { self.seed = seed; self.mode = mode; resetRound() }
    private func random() -> Double {
        seed = seed &* 6364136223846793005 &+ 1442695040888963407
        return Double(seed >> 11) / Double(UInt64.max >> 11)
    }
    private func resetRound() {
        phase = .ready; phaseTime = 0; winner = nil
        shots.removeAll(); sparks.removeAll()
        combo = 0; comboUntil = 0
        if mode == .boss {
            let health=600 + min(240,teamWins*35)
            boss=BugBoss(health:health,maxHealth:health)
            lastMove="Wave \(round) · the bug is waking up"
        }
        let previous = Dictionary(uniqueKeysWithValues: fighters.map { ($0.tool, $0) })
        fighters = Tool.allCases.enumerated().map {
            var fighter = Fighter(tool: $0.element, x: [0.15,0.5,0.85][$0.offset], cooldown: 0.15 + random() * 0.9)
            if let old = previous[fighter.tool] { fighter.energy = old.energy; fighter.workSeconds = old.workSeconds; fighter.idleSeconds = old.idleSeconds }
            return fighter
        }
    }
    func restart() { round += 1; resetRound() }
    var caption: String {
        if mode == .boss, let boss {
            switch phase {
            case .ready: return "BUG BOSS · Wave \(round) · \(boss.health) HP · work actions charge team combos"
            case .fighting: return "BUG \(boss.health)/\(boss.maxHealth) HP · \(Double(boss.health)/Double(boss.maxHealth)<0.3 ? "ENRAGED · " : "")Combo ×\(combo) · \(lastMove)"
            case .finished: return "\(boss.defeated ? "PARTY VICTORY!" : "Bug wins — regroup!") · Team \(teamWins) : Bug \(bossWins) · next wave in \(max(1,6-Int(phaseTime)))s"
            }
        }
        switch phase {
        case .ready: return "Round \(round) · ready… Tap a fighter to cheer and give a shield."
        case .fighting: return live.isEmpty ? "Practice battle · Tap a fighter to shield and attack." : "Live activity powers the game · working charges energy; idle takes extra damage · tap a fighter to boost."
        case .finished: return "\(winner?.title ?? "Everyone") wins round \(round)! Next round in \(max(1, 6 - Int(phaseTime)))s · Live activity exits the arena."
        }
    }
    func jump(_ index: Int) -> Double {
        guard phase == .fighting, fighters[index].health > 0 else { return 0 }
        return max(0, sin(time * 5.2 + Double(index) * 2.1)) * 5
    }
    private func fire(_ index: Int, special: Bool = false) {
        if mode == .boss {
            guard fighters[index].health > 0, boss?.defeated == false else { return }
            let direction=bossX < fighters[index].x ? -1.0 : 1.0
            fighters[index].facingLeft=direction<0; fighters[index].attackUntil=time+0.22
            let damage=max(3,Int(Double(special ? 15 : 7)*power(fighters[index])))
            shots.append(Shot(owner:fighters[index].tool,x:fighters[index].x+direction*0.025,speed:direction*(special ? 1.4 : 0.95),high:true,damage:damage,charged:special))
            return
        }
        guard fighters[index].health > 0,
              let target = fighters.indices.filter({ $0 != index && fighters[$0].health > 0 }).min(by: { abs(fighters[$0].x-fighters[index].x) < abs(fighters[$1].x-fighters[index].x) }) else { return }
        let direction = fighters[target].x < fighters[index].x ? -1.0 : 1.0
        let damage = max(3, Int((Double(7 + Int(random() * 5)) * power(fighters[index])).rounded()))
        fighters[index].facingLeft = direction < 0
        fighters[index].attackUntil = time + 0.22
        shots.append(Shot(owner: fighters[index].tool, x: fighters[index].x + direction * 0.025, speed: direction * (special ? 1.45 : 0.9), high: random() > 0.5, damage: damage))
        if special { shots.append(Shot(owner: fighters[index].tool, x: fighters[index].x + direction * 0.01, speed: direction * 1.15, high: true, damage: damage)) }
    }
    func cheer(_ tool: Tool) {
        selected = tool
        guard phase == .fighting, let i = fighters.firstIndex(where: { $0.tool == tool }), fighters[i].health > 0, time >= fighters[i].boostReady else { return }
        fighters[i].shieldUntil = time + 0.9; fighters[i].boostReady = time + 2
        fire(i, special: true)
    }
    func dash(to x: Double) {
        guard phase == .fighting, let i = fighters.firstIndex(where: { $0.tool == selected }), fighters[i].health > 0, time >= fighters[i].boostReady else { return }
        let goal = min(0.95, max(0.05, x))
        fighters[i].facingLeft = goal < fighters[i].x
        fighters[i].x += min(0.13, max(-0.13, goal - fighters[i].x))
        fighters[i].shieldUntil = time + 0.35; fighters[i].boostReady = time + 1
        fire(i)
    }
    func advance(_ delta: Double) {
        // Bounded simulation steps make fast tests and slow redraws consistent.
        var left = max(0, delta)
        while left > 0.000001 { let step = min(left, 1.0/60); tick(step); left -= step }
    }
    private func tick(_ dt: Double) {
        time += dt; phaseTime += dt
        sparks.removeAll { $0.until <= time }
        for i in fighters.indices {
            guard let activity = live[fighters[i].tool], !activity.isLoading else { continue }
            switch activity.mood {
            case .working:
                fighters[i].energy = min(100, fighters[i].energy + dt * 3)
                fighters[i].workSeconds += dt; fighters[i].idleSeconds = 0
            case .resting, .idle:
                fighters[i].idleSeconds += dt
                fighters[i].energy = max(0, fighters[i].energy - dt * (activity.mood == .idle ? 5 : 3))
            case .attention: break // Waiting for a human approval must not drain energy.
            case .finished: fighters[i].energy = min(100, fighters[i].energy + dt)
            }
        }
        if combo > 0 && time > comboUntil { combo = 0 }
        if phase == .ready { if phaseTime >= 1.5 { phase = .fighting; phaseTime = 0 }; return }
        if phase == .finished { if phaseTime >= 6 { restart() }; return }
        if mode == .boss { tickBoss(dt) }
        for i in fighters.indices where fighters[i].health > 0 {
            let enemy = fighters.indices.filter({ $0 != i && fighters[$0].health > 0 }).min(by: { abs(fighters[$0].x-fighters[i].x) < abs(fighters[$1].x-fighters[i].x) })
            guard mode == .boss || enemy != nil else { continue }
            let distance = mode == .boss ? bossX-fighters[i].x : fighters[enemy!].x-fighters[i].x
            let direction = (mode == .boss ? bossX-fighters[i].x : distance) < 0 ? -1.0 : 1.0
            // Independent roaming goals sweep from one edge to the other;
            // opponents can pass each other instead of being trapped in lanes.
            let goal = 0.5 + 0.47 * sin(time * 0.24 + Double(i) * 2.1)
            let velocity = min(0.23, max(-0.23, (goal - fighters[i].x) * 1.2))
            fighters[i].x = min(0.95, max(0.05, fighters[i].x + velocity * dt))
            fighters[i].facingLeft = direction < 0
            fighters[i].cooldown -= dt
            if fighters[i].cooldown <= 0 {
                fire(i); fighters[i].cooldown = (1.0 + random() * 0.8) / power(fighters[i])
            }
        }
        var remaining: [Shot] = []
        for var shot in shots {
            let old = shot.x; shot.x += shot.speed * dt
            var collided = false
            if mode == .boss && !shot.hostile {
                if let target=boss, target.health>0, min(old,shot.x)-0.025 <= bossX && max(old,shot.x)+0.025 >= bossX {
                    let bonus=target.exposedUntil>time ? 1.5 : 1.0
                    boss!.health=max(0,target.health-max(1,Int(Double(shot.damage)*bonus*0.32)))
                    boss!.hitUntil=time+0.2
                    sparks.append(Spark(x:bossX,tool:shot.owner,until:time+0.25,blocked:false))
                    collided=true
                }
                if !collided && (-0.05...1.05).contains(shot.x) { remaining.append(shot) }
                continue // Party projectiles can never damage another companion.
            }
            let targets = fighters.indices.filter { (shot.hostile || fighters[$0].tool != shot.owner) && fighters[$0].health > 0 }.sorted { abs(fighters[$0].x-old) < abs(fighters[$1].x-old) }
            for i in targets where min(old,shot.x)-0.016 <= fighters[i].x && max(old,shot.x)+0.016 >= fighters[i].x {
                let blocked = fighters[i].shieldUntil > time
                let dodged = !shot.high && jump(i) > 3.5 && (live[fighters[i].tool]?.mood != .idle)
                if dodged { continue }
                if !blocked { fighters[i].health = max(0, fighters[i].health - incomingDamage(shot.damage, for: fighters[i])); fighters[i].hitUntil = time + 0.2 }
                sparks.append(Spark(x:fighters[i].x,tool:shot.owner,until:time+0.25,blocked:blocked))
                collided = true; break
            }
            if !collided && (-0.05...1.05).contains(shot.x) { remaining.append(shot) }
        }
        shots = remaining
        let alive = fighters.filter { $0.health > 0 }
        if mode == .boss {
            if boss!.health == 0 || alive.isEmpty || phaseTime >= 90 {
                let won=boss!.health == 0
                boss!.defeated=won
                if won { teamWins += 1; for tool in Tool.allCases { scores[tool,default:0] += 1 } }
                else { bossWins += 1 }
                phase = .finished; phaseTime=0; shots.removeAll()
            }
            return
        }
        if alive.count <= 1 || phaseTime >= 75 {
            winner = fighters.max(by: { $0.health < $1.health })?.tool
            if let winner { scores[winner,default:0] += 1 }
            phase = .finished; phaseTime = 0; shots.removeAll()
        }
    }
    private func tickBoss(_ dt:Double) {
        guard boss != nil, boss!.health > 0 else { return }
        boss!.nextAttack -= dt
        guard boss!.nextAttack <= 0 else { return }
        let alive=fighters.filter { $0.health>0 }; guard !alive.isEmpty else { return }
        let target=alive[Int(random()*Double(alive.count)) % alive.count]
        boss!.attackIndex += 1
        let enraged=Double(boss!.health)/Double(boss!.maxHealth) < 0.3
        let spread=boss!.attackIndex % (enraged ? 2 : 3) == 0
        let directions:[Double] = spread ? [-1,1] : [target.x < bossX ? -1 : 1]
        let damage=(enraged ? 20 : 14)+min(6,teamWins*2)
        for direction in directions {
            // One shot per direction avoids an invisible stacked burst when
            // several companions happen to stand together on one side.
            shots.append(Shot(owner:.codex,x:bossX+direction*0.03,speed:direction*(enraged ? 0.95 : 0.72),high:spread || enraged || boss!.attackIndex%2==0,damage:damage,hostile:true))
        }
        boss!.nextAttack=enraged ? 0.95 : 1.15
    }
    private func triggerMove(_ tool:Tool, activity:LiveActivity) {
        guard let i=fighters.firstIndex(where: { $0.tool == tool }), fighters[i].health>0 else { return }
        let move:String
        switch activity.action {
        case .reading,.searching,.browsing:
            boss?.exposedUntil=time+4; move="SCAN"
        case .editing:
            fighters[i].shieldUntil=max(fighters[i].shieldUntil,time+2); move="PATCH SHIELD"
        case .building:
            for j in fighters.indices { fighters[j].shieldUntil=max(fighters[j].shieldUntil,time+0.8) }
            move="FORTIFY"
        case .testing:
            if activity.actionCompleted && activity.testPassed == true {
                move="TEST FINISHER"
                let direction=bossX < fighters[i].x ? -1.0 : 1.0
                shots.append(Shot(owner:tool,x:fighters[i].x+direction*0.025,speed:direction*1.6,high:true,damage:45+combo*6,charged:true))
            } else if !activity.actionCompleted { move="CHARGING" }
            else { return } // An unknown test result is never shown as a pass.
        case .command: move="TERMINAL BOLT"; fire(i,special:true)
        case .replying,.done:
            move="RALLY"
            for j in fighters.indices where fighters[j].health>0 { fighters[j].health=min(100,fighters[j].health+6) }
        default: return
        }
        combo=min(9,time <= comboUntil ? combo+1 : 1); bestCombo=max(bestCombo,combo); comboUntil=time+6
        fighters[i].energy=min(100,fighters[i].energy+5)
        fighters[i].move=move; fighters[i].moveUntil=time+2
        lastMove="\(tool == .claude ? "Claude" : tool.title): \(move) · ×\(combo)"
        moveCooldown[tool]=time+0.8
        if activity.action != .testing { fire(i,special:true) }
    }

}

extension PlaygroundView {
    func drawBugBoss(_ battle:CompanionBattle,width:Double) {
        guard let boss=battle.boss else { return }
        let area=CompanionBattle.arena(width:width), x=area.left+battle.bossX*area.span-12
        let enraged=Double(boss.health)/Double(boss.maxHealth)<0.3
        let exposed=boss.exposedUntil>battle.time
        let shell=boss.defeated ? NSColor.darkGray : exposed ? .systemYellow : enraged ? .systemOrange : .systemRed
        let dark=NSColor(srgbRed:0.22,green:0.035,blue:0.10,alpha:1)
        let edge=boss.hitUntil>battle.time ? NSColor.white : shell
        let eyes=exposed ? NSColor.white : NSColor(srgbRed:0.4,green:1,blue:0.72,alpha:1)
        // Three jointed legs per side, with alternating stepping motion.
        shell.setStroke()
        for n in 0..<3 {
            let step=sin(battle.time*(enraged ? 13 : 7)+Double(n)*2)>0 ? 1.5 : -0.5
            for side in [-1.0,1.0] {
                let inner=x+12+side*7, joint=x+12+side*14, foot=x+12+side*17
                let y=10+Double(n)*4
                let leg=NSBezierPath(); leg.move(to:NSPoint(x:inner,y:y)); leg.line(to:NSPoint(x:joint,y:y-2+step)); leg.line(to:NSPoint(x:foot,y:y+1+step)); leg.lineWidth=1.3; leg.stroke()
            }
        }
        // Split wing armour keeps a strong beetle silhouette even while hit.
        dark.setFill(); NSBezierPath(roundedRect:NSRect(x:x+2,y:8,width:20,height:14),xRadius:5,yRadius:5).fill()
        shell.setFill()
        NSBezierPath(roundedRect:NSRect(x:x+3,y:9,width:8,height:12),xRadius:3,yRadius:3).fill()
        NSBezierPath(roundedRect:NSRect(x:x+13,y:9,width:8,height:12),xRadius:3,yRadius:3).fill()
        edge.withAlphaComponent(0.8).setFill(); NSRect(x:x+4,y:10,width:2,height:6).fill(); NSRect(x:x+18,y:10,width:2,height:6).fill()
        dark.setFill(); NSRect(x:x+5,y:5,width:14,height:8).fill()
        edge.setStroke()
        for side in [-1.0,1.0] {
            let antenna=NSBezierPath(); antenna.move(to:NSPoint(x:x+12+side*4,y:6)); antenna.line(to:NSPoint(x:x+12+side*8,y:3)); antenna.lineWidth=1.2; antenna.stroke()
            eyes.setFill(); NSRect(x:x+11+side*8,y:2,width:2,height:2).fill()
        }
        eyes.setFill(); NSRect(x:x+7,y:7,width:3,height:2).fill(); NSRect(x:x+14,y:7,width:3,height:2).fill()
        shell.setFill(); let chomp=Int(battle.time*5)%2 == 0 ? 1.0 : 0
        NSRect(x:x+8-chomp,y:11,width:3,height:2).fill(); NSRect(x:x+13+chomp,y:11,width:3,height:2).fill()
        if exposed {
            NSColor.white.setStroke(); let target=NSBezierPath(ovalIn:NSRect(x:x+9,y:14,width:6,height:6)); target.lineWidth=1; target.stroke()
        }
        NSColor.darkGray.setFill(); NSRect(x:x-4,y:0,width:32,height:1.5).fill()
        shell.setFill(); NSRect(x:x-4,y:0,width:32*Double(boss.health)/Double(boss.maxHealth),height:1.5).fill()
        let caption=boss.defeated ? "BUG KO" : battle.combo>0 && Int(battle.time*2)%2==0 ? "BUG ×\(battle.combo)" : "BUG \(boss.health)"
        text(caption,at:NSPoint(x:x-2,y:23),size:6,color:shell)
        if battle.phase == .fighting && boss.nextAttack<0.45 { text("!",at:NSPoint(x:x+24,y:6),size:9,color:.systemYellow) }
    }
    func drawBattle(_ battle: CompanionBattle, width: Double) {
        let geometry = CompanionBattle.arena(width: width)
        let left = geometry.left, arena = geometry.span
        let t = battle.time
        func label(_ value: String, _ x: Double, _ y: Double, _ color: NSColor = .white, _ size: CGFloat = 7) {
            text(value, at:NSPoint(x:x,y:y),size:size,color:color)
        }
        NSColor(white:0.13,alpha:1).setFill(); NSRect(x:left,y:28,width:arena,height:1).fill()
        label("LIVE",width-31,9,.systemMint,8)
        if battle.mode == .boss { drawBugBoss(battle,width:width) }
        for i in battle.fighters.indices {
            let f = battle.fighters[i]
            let x = left + f.x * arena - 11
            let defeated = f.health <= 0
            let victorious = battle.phase == .finished && (battle.mode == .boss ? battle.boss?.defeated == true && !defeated : battle.winner == f.tool)
            let spriteScale = 0.8
            let spriteHeight = (f.tool == .antigravity ? 26.0 : f.tool == .claude ? 15.6 : 21.6) * spriteScale
            let y = 29 - spriteHeight
            let bounce = victorious ? abs(sin(t*8))*4 : battle.jump(i)
            if f.shieldUntil > t {
                NSColor.systemMint.withAlphaComponent(0.55).setStroke()
                let ring=NSBezierPath(ovalIn:NSRect(x:x-4,y:1,width:30,height:28)); ring.lineWidth=1; ring.stroke()
            }
            do {
                NSGraphicsContext.saveGraphicsState()
                let pose = NSAffineTransform(); pose.translateX(by: x+1, yBy: max(5, y-bounce)); pose.scale(by: spriteScale); pose.concat()
                PixelArt.draw(f.tool,mood:defeated ? .idle : victorious ? .finished : .working,x:0,y:0,time:t,walking:!defeated && battle.phase == .fighting,facingLeft:f.facingLeft,failed:f.hitUntil>t)
                NSGraphicsContext.restoreGraphicsState()
            }
            NSColor.darkGray.setFill(); NSRect(x:x-1,y:0,width:24,height:2).fill()
            (f.health < 30 ? NSColor.systemOrange : f.tool.color).setFill()
            NSRect(x:x-1,y:0,width:24*Double(f.health)/100,height:2).fill()
            NSColor.darkGray.setFill(); NSRect(x:x-1,y:3,width:24,height:1).fill()
            NSColor.systemMint.setFill(); NSRect(x:x-1,y:3,width:24*f.energy/100,height:1).fill()
            if f.tool == battle.selected { label("·",x-6,16,.systemMint,8) }
            if f.hitUntil > t { label("✦",x+19,10,.systemYellow,9) }
            if f.attackUntil > t { label(f.tool == .codex ? ">_" : f.tool == .claude ? "*" : "✧", x+(f.facingLeft ? -8 : 23),7,f.tool.color,8) }
            if victorious {
                label("★",x+5,0,.systemYellow,9)
                for n in 0..<5 {
                    f.tool.color.setFill(); NSRect(x:x+10+sin(t*3+Double(n)*2)*28,y:4+(t*13+Double(n)*5).truncatingRemainder(dividingBy:23),width:2,height:2).fill()
                }
            }
            positions[f.tool]=x
        }
        for shot in battle.shots {
            let x=left+shot.x*arena
            (shot.hostile ? NSColor.systemRed : shot.owner.color).setFill()
            NSRect(x:x,y:shot.high ? 13 : 19,width:shot.charged ? 9 : 4,height:shot.charged ? 3 : 2).fill()
            (shot.hostile ? NSColor.systemRed : shot.owner.color).withAlphaComponent(0.3).setFill(); NSRect(x:x-shot.speed*4,y:shot.high ? 13 : 19,width:4,height:2).fill()
        }
        for spark in battle.sparks {
            label(spark.blocked ? "◇" : "✦",left+spark.x*arena-5,10,spark.blocked ? .systemMint : .systemYellow,10)
        }
        let centers = Dictionary(uniqueKeysWithValues: battle.fighters.map { ($0.tool, left + $0.x * arena) })
        for tag in BattleTagLayout.make(centers:centers, width:width, reservedCenter:battle.mode == .boss ? left+battle.bossX*arena : nil) {
            let fighter = battle.fighters.first { $0.tool == tag.tool }!
            let activity = battle.live[tag.tool]
            let name = tag.tool == .antigravity ? "Anti" : tag.tool == .claude ? "Claude" : "Codex"
            if tag.width < 28 {
                // During a close pass, keep a tiny owner badge; the full live
                // model/action remains in the fixed desktop card for this tool.
                let badge = tag.tool == .codex ? "CX" : tag.tool == .claude ? "CL" : "AG"
                label(badge,centers[tag.tool]!-7,21,tag.tool.color,5)
                continue
            }
            tag.tool.color.withAlphaComponent(0.6).setStroke()
            let tether=NSBezierPath(); tether.move(to:NSPoint(x:tag.tetherStart,y:15)); tether.line(to:NSPoint(x:tag.tetherEnd,y:15)); tether.lineWidth=1; tether.stroke()
            func info(_ value:String, y:Double, color:NSColor, size:CGFloat = 7) {
                let paragraph=NSMutableParagraphStyle(); paragraph.lineBreakMode = .byTruncatingMiddle
                paragraph.alignment = tag.leftSide ? .right : .left
                NSGraphicsContext.current?.shouldAntialias = true
                (value as NSString).draw(in:NSRect(x:tag.x,y:y,width:tag.width,height:10),withAttributes:[.font:NSFont.monospacedSystemFont(ofSize:size,weight:.medium),.foregroundColor:color,.paragraphStyle:paragraph])
                NSGraphicsContext.current?.shouldAntialias = false
            }
            let won = battle.phase == .finished && (battle.mode == .boss ? battle.boss?.defeated == true && fighter.health>0 : battle.winner == tag.tool)
            let identity = (won ? "★ " : "") + name
            let moveBadge = ["TEST FINISHER":"FIN", "PATCH SHIELD":"SHLD", "TERMINAL BOLT":"BOLT", "FORTIFY":"FORT", "CHARGING":"CHRG", "SCAN":"SCAN", "RALLY":"HEAL"][fighter.move] ?? ""
            let stats = battle.mode == .boss && fighter.moveUntil > t && tag.width >= 60 ? " " + moveBadge : tag.width >= 90 ? " H\(fighter.health) E\(Int(fighter.energy))" : tag.width >= 55 ? " H\(fighter.health)" : ""
            info(identity+stats,y:0,color:tag.tool.color)
            let modelName = activity?.modelName == "Model unavailable" ? "no model reported" : activity?.modelName ?? "practice"
            info(modelName,y:10,color:.white,size:6.8)
            let caption = won ? (battle.mode == .boss ? "Party victory!" : "Round \(battle.round) winner!") : fighter.health == 0 ? "KO · next round" : activity?.caption ?? "Practice fight"
            info(caption,y:20,color:fighter.health == 0 ? .gray : .systemMint,size:6.8)
        }
        if battle.phase == .finished { drawSportsScoreboard(battle,width:width) }
    }
}

// Text stays adjacent to its owning avatar. Neighbour midpoints prevent labels
// from colliding; close passes collapse details instead of moving them elsewhere.
struct BattleTagLayout {
    let tool: Tool
    let x: Double
    let width: Double
    let leftSide: Bool
    let tetherStart: Double
    let tetherEnd: Double
    static func make(centers: [Tool:Double], width: Double, reservedCenter:Double? = nil) -> [BattleTagLayout] {
        let ordered=centers.sorted { $0.value < $1.value }
        return ordered.enumerated().map { index, entry in
            let center=entry.value
            var lower=index == 0 ? 3 : (ordered[index-1].value+center)/2
            var upper=index == ordered.count-1 ? width-44 : (ordered[index+1].value+center)/2
            if let boss=reservedCenter {
                if boss<center { lower=max(lower,boss+23) } else { upper=min(upper,boss-23) }
            }
            let before=max(0,center-18-lower-3)
            let after=max(0,upper-center-20-3)
            let isLeft=before > after
            let available=min(140,isLeft ? before : after)
            let x=isLeft ? center-18-available : center+20
            return BattleTagLayout(tool:entry.key,x:x,width:available,leftSide:isLeft,tetherStart:isLeft ? center-13 : center+13,tetherEnd:isLeft ? center-17 : center+19)
        }
    }
}

extension PlaygroundView {
    func drawSportsScoreboard(_ battle:CompanionBattle,width:Double) {
        let elapsed=battle.phaseTime, panelWidth=width-42
        let offset:Double
        if elapsed<0.6 { let p=elapsed/0.6; offset = -30*pow(1-p,3) }
        else if elapsed>5 { let p=min(1,elapsed-5); offset=30*p*p*p }
        else { offset=0 }
        NSGraphicsContext.saveGraphicsState()
        defer { NSGraphicsContext.restoreGraphicsState() }
        let translate=NSAffineTransform(); translate.translateX(by:0,yBy:offset); translate.concat()
        NSColor(srgbRed:0.045,green:0.055,blue:0.09,alpha:1).setFill()
        NSRect(x:0,y:0,width:panelWidth,height:30).fill()
        let partyWon=battle.boss?.defeated == true
        let accent=battle.mode == .boss ? (partyWon ? NSColor.systemMint : .systemOrange) : (battle.winner?.color ?? .systemYellow)
        accent.setFill(); NSRect(x:0,y:0,width:panelWidth,height:1).fill(); NSRect(x:0,y:29,width:panelWidth,height:1).fill()
        // A quiet LED stadium backdrop and restrained pixel confetti.
        accent.withAlphaComponent(0.10).setFill()
        for x in stride(from:4.0,to:panelWidth,by:10) { NSRect(x:x,y:4,width:1,height:1).fill(); NSRect(x:x,y:25,width:1,height:1).fill() }
        for n in 0..<12 {
            let x=(Double(n)*61+sin(elapsed*2+Double(n))*7).truncatingRemainder(dividingBy:panelWidth)
            let y=(elapsed*10+Double(n)*7).truncatingRemainder(dividingBy:27)+1
            accent.withAlphaComponent(0.6).setFill(); NSRect(x:x,y:y,width:1.5,height:1.5).fill()
        }
        let title:String
        if battle.mode == .boss { title=partyWon ? "PARTY WINS!" : "BUG WINS!" }
        else { title=(battle.winner == .antigravity ? "ANTI" : battle.winner == .claude ? "CLAUDE" : "CODEX")+" WINS!" }
        text("★ "+title,at:NSPoint(x:6,y:3),size:8,color:accent)
        text("SERIES · R\(battle.round)",at:NSPoint(x:6,y:18),size:6.5,color:.lightGray)
        let start=112.0, end=panelWidth-44
        if battle.mode == .duel {
            let cell=(end-start)/3
            for (i,tool) in Tool.allCases.enumerated() {
                let x=start+Double(i)*cell
                PixelArt.draw(tool,mood:tool == battle.winner ? .finished : .resting,x:x,y:tool == .antigravity ? 3 : 6,time:battle.time,walking:false)
                let name=tool == .antigravity ? "Anti" : tool == .claude ? "Claude" : "Codex"
                text(name,at:NSPoint(x:x+28,y:1),size:7.5,color:tool.color)
                let total=battle.scores[tool,default:0]
                let score=tool == battle.winner && elapsed<0.85 ? max(0,total-1) : total
                text("\(score)",at:NSPoint(x:x+31,y:10),size:15,color:.white)
                if tool == battle.winner && elapsed>=0.85 && elapsed<2 { text("+1",at:NSPoint(x:x+52,y:15),size:7,color:accent) }
            }
        } else {
            let cell=(end-start)/2
            for i in 0..<2 {
                let x=start+Double(i)*cell
                text(i==0 ? "CODING PARTY" : "BUG SWARM",at:NSPoint(x:x+5,y:1),size:8,color:i==0 ? .systemMint : .systemRed)
                let total=i==0 ? battle.teamWins : battle.bossWins
                let won=i==0 ? partyWon : !partyWon
                let score=won && elapsed<0.85 ? max(0,total-1) : total
                text("\(score)",at:NSPoint(x:x+32,y:10),size:15,color:.white)
                if won && elapsed>=0.85 && elapsed<2 { text("+1",at:NSPoint(x:x+54,y:15),size:7,color:accent) }
                if i==0 {
                    for (n,tool) in Tool.allCases.enumerated() {
                        NSGraphicsContext.saveGraphicsState()
                        let pose=NSAffineTransform(); pose.translateX(by:x+70+Double(n)*23,yBy:8); pose.scale(by:0.65); pose.concat()
                        PixelArt.draw(tool,mood:partyWon ? .finished : .resting,x:0,y:0,time:battle.time,walking:false)
                        NSGraphicsContext.restoreGraphicsState()
                    }
                }
            }
        }
        text("NEXT",at:NSPoint(x:panelWidth-34,y:2),size:6,color:.lightGray)
        text("\(max(1,6-Int(elapsed)))",at:NSPoint(x:panelWidth-26,y:10),size:14,color:accent)
    }
}
