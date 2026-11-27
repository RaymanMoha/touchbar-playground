import AppKit

// A local toy arena. Health, scores and attacks are fictional game state and
// never modify coding-tool activity, hooks, permissions or running processes.
final class CompanionBattle {
    enum Phase { case ready, fighting, finished }
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
    }
    struct Shot {
        let owner: Tool
        var x: Double
        let speed: Double
        let high: Bool
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
    private var seed: UInt64
    init(seed: UInt64 = 42) { self.seed = seed; resetRound() }
    private func random() -> Double {
        seed = seed &* 6364136223846793005 &+ 1442695040888963407
        return Double(seed >> 11) / Double(UInt64.max >> 11)
    }
    private func resetRound() {
        phase = .ready; phaseTime = 0; winner = nil
        shots.removeAll(); sparks.removeAll()
        fighters = Tool.allCases.enumerated().map { Fighter(tool: $0.element, x: [0.15,0.5,0.85][$0.offset], cooldown: 0.15 + random() * 0.9) }
    }
    func restart() { round += 1; resetRound() }
    var caption: String {
        switch phase {
        case .ready: return "Round \(round) · ready… Tap a fighter to cheer and give a shield."
        case .fighting: return "Tap a fighter: shield + special attack. Tap empty ground: your fighter dashes and fires."
        case .finished: return "\(winner?.title ?? "Everyone") wins round \(round)! Next round in \(max(1, 4 - Int(phaseTime)))s · Live activity exits the arena."
        }
    }
    func jump(_ index: Int) -> Double {
        guard phase == .fighting, fighters[index].health > 0 else { return 0 }
        return max(0, sin(time * 5.2 + Double(index) * 2.1)) * 5
    }
    private func fire(_ index: Int, special: Bool = false) {
        guard fighters[index].health > 0,
              let target = fighters.indices.filter({ $0 != index && fighters[$0].health > 0 }).min(by: { abs(fighters[$0].x-fighters[index].x) < abs(fighters[$1].x-fighters[index].x) }) else { return }
        let direction = fighters[target].x < fighters[index].x ? -1.0 : 1.0
        fighters[index].facingLeft = direction < 0
        fighters[index].attackUntil = time + 0.22
        shots.append(Shot(owner: fighters[index].tool, x: fighters[index].x + direction * 0.025, speed: direction * (special ? 1.45 : 0.9), high: random() > 0.5))
        if special { shots.append(Shot(owner: fighters[index].tool, x: fighters[index].x + direction * 0.01, speed: direction * 1.15, high: true)) }
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
        if phase == .ready { if phaseTime >= 1.5 { phase = .fighting; phaseTime = 0 }; return }
        if phase == .finished { if phaseTime >= 4 { restart() }; return }
        for i in fighters.indices where fighters[i].health > 0 {
            guard let enemy = fighters.indices.filter({ $0 != i && fighters[$0].health > 0 }).min(by: { abs(fighters[$0].x-fighters[i].x) < abs(fighters[$1].x-fighters[i].x) }) else { continue }
            let distance = fighters[enemy].x - fighters[i].x
            let direction = distance < 0 ? -1.0 : 1.0
            let velocity = abs(distance) > 0.23 ? direction * 0.14 : sin(time * 2.5 + Double(i) * 2) * 0.045
            fighters[i].x = min(0.95, max(0.05, fighters[i].x + velocity * dt))
            fighters[i].facingLeft = direction < 0
            fighters[i].cooldown -= dt
            if fighters[i].cooldown <= 0 {
                fire(i); fighters[i].cooldown = 0.65 + random() * 0.65
            }
        }
        var remaining: [Shot] = []
        for var shot in shots {
            let old = shot.x; shot.x += shot.speed * dt
            var collided = false
            let targets = fighters.indices.filter { fighters[$0].tool != shot.owner && fighters[$0].health > 0 }.sorted { abs(fighters[$0].x-old) < abs(fighters[$1].x-old) }
            for i in targets where min(old,shot.x)-0.016 <= fighters[i].x && max(old,shot.x)+0.016 >= fighters[i].x {
                let blocked = fighters[i].shieldUntil > time
                let dodged = !shot.high && jump(i) > 3.5
                if dodged { continue }
                if !blocked { fighters[i].health = max(0, fighters[i].health - (7 + Int(random() * 5))); fighters[i].hitUntil = time + 0.2 }
                sparks.append(Spark(x:fighters[i].x,tool:shot.owner,until:time+0.25,blocked:blocked))
                collided = true; break
            }
            if !collided && (-0.05...1.05).contains(shot.x) { remaining.append(shot) }
        }
        shots = remaining
        let alive = fighters.filter { $0.health > 0 }
        if alive.count <= 1 || phaseTime >= 35 {
            winner = fighters.max(by: { $0.health < $1.health })?.tool
            if let winner { scores[winner,default:0] += 1 }
            phase = .finished; phaseTime = 0; shots.removeAll()
        }
    }
}

extension PlaygroundView {
    func drawBattle(_ battle: CompanionBattle, width: Double) {
        let left = 112.0, arena = max(80, width - 160)
        let t = battle.time
        func label(_ value: String, _ x: Double, _ y: Double, _ color: NSColor = .white, _ size: CGFloat = 7) {
            text(value, at:NSPoint(x:x,y:y),size:size,color:color)
        }
        NSColor(white:0.13,alpha:1).setFill(); NSRect(x:left,y:28,width:arena,height:1).fill()
        label("PIXEL ARENA",5,1,.systemYellow,8)
        let phase = battle.phase == .ready ? "READY" : battle.phase == .finished ? "WINNER!" : "FIGHT!"
        label("R\(battle.round) · \(phase)",5,12,.white,7)
        let scores = Tool.allCases.map { String(battle.scores[$0,default:0]) }.joined(separator:" / ")
        label(scores,5,22,.lightGray,6)
        label("LIVE",width-31,9,.systemMint,8)
        for i in battle.fighters.indices {
            let f = battle.fighters[i]
            let x = left + f.x * arena - 11
            let defeated = f.health <= 0
            let victorious = battle.phase == .finished && battle.winner == f.tool
            let spriteScale = 0.9
            let spriteHeight = (f.tool == .antigravity ? 26.0 : f.tool == .claude ? 15.6 : 21.6) * spriteScale
            let y = 29 - spriteHeight
            let bounce = victorious ? abs(sin(t*8))*4 : battle.jump(i)
            if f.shieldUntil > t {
                NSColor.systemMint.withAlphaComponent(0.55).setStroke()
                let ring=NSBezierPath(ovalIn:NSRect(x:x-4,y:1,width:30,height:28)); ring.lineWidth=1; ring.stroke()
            }
            if !defeated || Int(t*3)%2 == 0 {
                NSGraphicsContext.saveGraphicsState()
                let pose = NSAffineTransform(); pose.translateX(by: x+1, yBy: max(3, y-bounce)); pose.scale(by: spriteScale); pose.concat()
                PixelArt.draw(f.tool,mood:defeated ? .idle : victorious ? .finished : .working,x:0,y:0,time:t,walking:!defeated && battle.phase == .fighting,facingLeft:f.facingLeft,failed:f.hitUntil>t)
                NSGraphicsContext.restoreGraphicsState()
            }
            NSColor.darkGray.setFill(); NSRect(x:x-1,y:0,width:24,height:2).fill()
            (f.health < 30 ? NSColor.systemOrange : f.tool.color).setFill()
            NSRect(x:x-1,y:0,width:24*Double(f.health)/100,height:2).fill()
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
            shot.owner.color.setFill()
            NSRect(x:x,y:shot.high ? 13 : 19,width:4,height:2).fill()
            shot.owner.color.withAlphaComponent(0.3).setFill(); NSRect(x:x-shot.speed*4,y:shot.high ? 13 : 19,width:4,height:2).fill()
        }
        for spark in battle.sparks {
            label(spark.blocked ? "◇" : "✦",left+spark.x*arena-5,10,spark.blocked ? .systemMint : .systemYellow,10)
        }
    }
}
