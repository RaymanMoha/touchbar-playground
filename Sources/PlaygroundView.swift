import AppKit

// Pixel adaptations drawn as native rectangles. References are the installed
// Codex's bundled humanoid pet and Claude's Clawd animation. Antigravity uses
// the user's selected Gemini-chan community sprite atlas.
enum PixelArt {
    static let codexHead = [
        ".....########.....", "...############...", "..##############..", ".################.",
        "##################", "##################", "##################", "##################",
        ".################.", "..##############..", "...############...", ".....########....."
    ]
    static func draw(_ tool: Tool, mood: Mood, x: Double, y: Double, time: Double, walking: Bool, facingLeft: Bool = false, failed: Bool = false) {
        let opacity: CGFloat = mood == .idle ? 0.43 : 1
        let bob = tool == .codex && mood != .idle ? sin(time * (walking ? 5 : 2)) * 0.65 : 0
        let origin = NSPoint(x: x.rounded(), y: (y + bob).rounded())
        func pixel(_ column: Double, _ row: Double, _ width: Double = 1, _ height: Double = 1, _ color: NSColor, unit: Double = 1.3) {
            color.withAlphaComponent(opacity).setFill()
            NSRect(x: origin.x + column * unit, y: origin.y + row * unit, width: width * unit, height: height * unit).fill()
        }
        switch tool {
        case .codex:
            // The built-in Codex pet: cloud-shaped head, dark terminal visor,
            // small blue body, arms, legs and the second >_ on its chest.
            for (row, line) in codexHead.enumerated() {
                let fraction = CGFloat(row) / 12
                let top = NSColor(srgbRed: 0.54, green: 0.67, blue: 1, alpha: 1)
                let bottom = NSColor(srgbRed: 0.30, green: 0.44, blue: 0.93, alpha: 1)
                let fill = top.blended(withFraction: fraction, of: bottom)!
                for (column, char) in line.enumerated() where char == "#" { pixel(Double(column), Double(row), 1, 1, fill, unit: 1.2) }
            }
            let blue = NSColor(srgbRed: 0.37, green: 0.53, blue: 1, alpha: 1)
            let visor = NSColor(srgbRed: 0.10, green: 0.18, blue: 0.40, alpha: 1)
            let terminal = NSColor(srgbRed: 0.56, green: 0.97, blue: 1, alpha: 1)
            pixel(4, 4, 10, 5, visor, unit: 1.2); pixel(3, 5, 12, 3, visor, unit: 1.2)
            if mood == .idle || Int(time * 2) % 13 == 0 {
                pixel(5, 6, 2, 0.8, terminal, unit: 1.2); pixel(11, 6, 2, 0.8, terminal, unit: 1.2)
            } else if mood == .finished {
                for (c, r) in [(5,6),(6,5),(7,6),(10,6),(11,5),(12,6)] { pixel(Double(c), Double(r), 1, 1, terminal, unit: 1.2) }
            } else if mood == .attention {
                pixel(6, 5, 1, 2, terminal, unit: 1.2); pixel(11, 5, 1, 2, terminal, unit: 1.2)
            } else {
                for (c, r) in [(5,5),(6,6),(5,7)] { pixel(Double(c), Double(r), 1, 1, terminal, unit: 1.2) }
                if Int(time * 2) % 3 != 0 { pixel(10, 7, 3, 0.8, terminal, unit: 1.2) }
            }
            pixel(6, 12, 6, 4, blue, unit: 1.2)
            for (index, arm) in [3.0, 13.0].enumerated() {
                let raised = mood == .finished || (mood == .attention && index == 0)
                pixel(arm, raised ? 10 : 12, 2, 3, blue, unit: 1.2)
            }
            for (index, leg) in [6.0, 10.0].enumerated() {
                let step = walking && (Int(time * 6) + index) % 2 == 0 ? 1.0 : 0
                pixel(leg, 16 - step, 2, 2, blue, unit: 1.2)
            }
            pixel(7, 13, 0.8, 0.8, terminal, unit: 1.2); pixel(7.8, 13.8, 0.8, 0.8, terminal, unit: 1.2)
            pixel(7, 14.6, 0.8, 0.8, terminal, unit: 1.2); pixel(9.5, 14.6, 1.5, 0.8, terminal, unit: 1.2)
        case .claude:
            // Clawd's copper rectangular body, side nubs, two eyes and four legs.
            let copper = NSColor(srgbRed: 0.843, green: 0.463, blue: 0.333, alpha: 1)
            let darkCopper = NSColor(srgbRed: 0.72, green: 0.37, blue: 0.27, alpha: 1)
            pixel(2, 1, 14, 9, copper, unit: 1.2)
            pixel(0, 4, 2, 3, copper, unit: 1.2)
            pixel(16, 4, 2, 3, copper, unit: 1.2)
            pixel(2, 1, 1, 9, darkCopper, unit: 1.2)
            let asleepOrBlinking = mood == .idle || Int(time * 2) % 13 == 0
            for eye in [5.0, 12.0] { pixel(eye, asleepOrBlinking ? 4 : 3, 1.5, asleepOrBlinking ? 0.7 : 2, .black, unit: 1.2) }
            for (index, leg) in [3.0, 6.0, 11.0, 14.0].enumerated() {
                let step = walking && (Int(time * 6) + index) % 2 == 0 ? 1.0 : 0
                pixel(leg, 10, 1.5, 3 - step, copper, unit: 1.2)
            }
        case .antigravity:
            GeminiSprite.draw(mood: mood, x: x, y: y, time: time, walking: walking, facingLeft: facingLeft, failed: failed)
        }
    }
}

final class PlaygroundView: NSView {
    let model: PlaygroundModel
    var onTap: ((Tool) -> Void)?
    var battle: CompanionBattle?
    var onExitBattle: (() -> Void)?
    var positions: [Tool: Double] = [:]
    var petUntil: [Tool: Double] = [:]
    var timeOverride: Double?
    override var isFlipped: Bool { true }
    override var intrinsicContentSize: NSSize { NSSize(width: 685, height: 30) }
    init(model: PlaygroundModel) {
        self.model = model
        super.init(frame: NSRect(x: 0, y: 0, width: 685, height: 30))
        wantsLayer = true; layer?.backgroundColor = NSColor.black.cgColor
        setAccessibilityElement(true); setAccessibilityRole(.button)
        setAccessibilityLabel("Companion playground. Tap a companion to visit its coding app.")
        let click = NSClickGestureRecognizer(target: self, action: #selector(tapped(_:)))
        click.allowedTouchTypes = [.direct]; addGestureRecognizer(click)
    }
    required init?(coder: NSCoder) { fatalError() }
    func text(_ value: String, at point: NSPoint, size: CGFloat = 8, color: NSColor = .white) {
        NSGraphicsContext.saveGraphicsState()
        defer { NSGraphicsContext.restoreGraphicsState() }
        NSGraphicsContext.current?.shouldAntialias = true
        (value as NSString).draw(at: point, withAttributes: [.font: NSFont.monospacedSystemFont(ofSize: size, weight: .medium), .foregroundColor: color])
    }
    override func draw(_ dirtyRect: NSRect) {
        NSColor.black.setFill(); bounds.fill()
        guard let context = NSGraphicsContext.current else { return }
        context.saveGraphicsState(); defer { context.restoreGraphicsState() }
        let scale = bounds.height / 30
        NSAffineTransform.scale(by: scale)
        let width = bounds.width / scale
        context.imageInterpolation = .none
        context.shouldAntialias = false
        if let battle { drawBattle(battle, width: width); return }
        let t = timeOverride ?? model.animationTime
        let moods = model.moods
        let layout = PlaygroundLayout(width: width, moods: moods)
        let active = Tool.allCases.filter { moods[$0, default: .idle] != .idle }
        if active.isEmpty {
            text("all quiet", at: NSPoint(x: 12, y: 10), color: NSColor.white.withAlphaComponent(0.32))
        }
        for (index, tool) in Tool.allCases.enumerated() {
            let mood = moods[tool, default: .idle]
            let phase = t + Double(index) * 4.3
            let cycle = phase.truncatingRemainder(dividingBy: 15)
            let progress = model.workProgress(for: tool, time: t)
            let action = progress?.action ?? .thinking
            let walking = mood == .resting || (mood == .working && [.thinking, .searching].contains(action) && cycle < 7)
            let subtitle = model.actionCaption(for: tool, time: t)
            let shortTitle = tool == .claude ? "Claude" : tool.title
            let modelName = model.modelLabel(for: tool, time: t)
            let name = mood == .resting ? shortTitle : (active.count == 3 ? modelName : "\(shortTitle) · \(modelName)")
            let font = NSFont.monospacedSystemFont(ofSize: 8.5, weight: .medium)
            let smallFont = NSFont.monospacedSystemFont(ofSize: 7.2, weight: .medium)
            let naturalWidth = max((subtitle as NSString).size(withAttributes: [.font: font]).width, (("• " + name) as NSString).size(withAttributes: [.font: smallFont]).width)
            let lane = layout.lanes[tool]
            let labelWidth = min(naturalWidth + 5, max(25, (lane.map { $0.upperBound - $0.lowerBound } ?? 150) + 5))
            let target: Double
            if let lane = layout.lanes[tool] {
                let p = (sin(phase * (mood == .resting ? 0.10 : 0.27)) + 1) / 2
                target = lane.lowerBound + p * max(0, lane.upperBound - labelWidth - lane.lowerBound)
            } else { target = layout.docks[tool] ?? 10 }
            let old = positions[tool] ?? target
            let x = timeOverride != nil ? target : old + (target - old) * (mood == .idle ? 0.08 : walking ? 0.035 : 0.012)
            positions[tool] = x
            var y = mood == .idle ? 7.0 : 5.0
            if tool == .antigravity { y = 2 }
            else {
                if mood == .finished { y -= abs(sin(phase * 5)) * 3 }
                if walking { y += sin(phase * (mood == .resting ? 4 : 12)) * 0.6 }
            }
            PixelArt.draw(tool, mood: mood, x: x, y: y, time: mood == .resting ? phase * 0.45 : phase, walking: walking, facingLeft: target < old, failed: progress?.actionFailed == true)
            if mood == .working || mood == .finished { drawProp(action: mood == .finished ? .done : action, progress: progress, x: x, y: y, time: phase, color: tool.color) }
            if (petUntil[tool] ?? 0) > ProcessInfo.processInfo.systemUptime {
                text("♥", at: NSPoint(x: x + 19, y: 0), size: 10, color: tool.color)
            } else if mood == .idle {
                text(Int(phase) % 2 == 0 ? "z" : "·", at: NSPoint(x: x + 20, y: 0), size: 7, color: tool.color.withAlphaComponent(0.6))
            } else {
                let color = mood == .attention ? NSColor.systemOrange : tool.color
                let status: String
                switch mood {
                case .working: status = "•"
                case .resting: status = "◦"
                case .attention: status = "!"
                case .finished: status = "✓"
                case .idle: status = ""
                }
                let labelX = x + 29
                let paragraph = NSMutableParagraphStyle(); paragraph.lineBreakMode = .byTruncatingMiddle
                context.shouldAntialias = true
                ("\(status) \(name)" as NSString).draw(in: NSRect(x: labelX, y: 2, width: labelWidth, height: 11), withAttributes: [.font: smallFont, .foregroundColor: color.withAlphaComponent(0.78), .paragraphStyle: paragraph])
                (subtitle as NSString).draw(in: NSRect(x: labelX, y: 15, width: labelWidth, height: 13), withAttributes: [.font: font, .foregroundColor: NSColor.white.withAlphaComponent(0.95), .paragraphStyle: paragraph])
                context.shouldAntialias = false
                if mood == .attention {
                    let handY = y + 5 + sin(phase * 7) * 2
                    color.setFill(); NSRect(x: x + 21, y: handY, width: 3, height: 3).fill()
                    text("!", at: NSPoint(x: x + 24, y: 0), size: 9, color: color)
                }
                if tool == .antigravity && mood == .working {
                    text("·", at: NSPoint(x: x - 5, y: y + 2), color: tool.color.withAlphaComponent(0.6))
                    text("+", at: NSPoint(x: x + 22, y: y - 3), size: 6, color: tool.color)
                }
                if mood == .finished {
                    for i in 0..<4 {
                        tool.color.withAlphaComponent(0.8).setFill()
                        let px = x + 10 + sin(phase * 2 + Double(i) * 1.7) * 20
                        let py = 2 + (phase * 9 + Double(i) * 6).truncatingRemainder(dividingBy: 23)
                        NSRect(x: px, y: py, width: 1.5, height: 1.5).fill()
                    }
                }
            }
        }
    }
    func drawProp(action: WorkAction, progress: WorkProgress?, x: Double, y: Double, time: Double, color: NSColor) {
        color.setFill(); color.setStroke()
        switch action {
        case .reading:
            NSRect(x: x + 6, y: y + 13, width: 17, height: 10).fill()
            NSColor.black.setFill(); NSRect(x: x + 14, y: y + 13, width: 1, height: 10).fill()
            NSRect(x: x + 8, y: y + 15, width: 4, height: 1).fill()
            NSRect(x: x + 17, y: y + 15 + Double(Int(time * 2) % 3), width: 4, height: 1).fill()
        case .searching:
            let shift = sin(time * 2)
            let lens = NSBezierPath(ovalIn: NSRect(x: x + 17 + shift, y: y + 9, width: 7, height: 7)); lens.lineWidth = 1.5; lens.stroke()
            let handle = NSBezierPath(); handle.move(to: NSPoint(x: x + 23 + shift, y: y + 15)); handle.line(to: NSPoint(x: x + 25 + shift, y: y + 20)); handle.lineWidth = 2; handle.stroke()
        case .editing, .building:
            for i in 0..<3 {
                let bob = i == Int(time * 2) % 3 ? -2.0 : 0
                NSRect(x: x + 15 + Double(i % 2) * 5, y: y + 20 - Double(i) * 5 + bob, width: 5, height: 4).fill()
            }
        case .command, .browsing:
            NSColor(srgbRed: 0.12, green: 0.17, blue: 0.2, alpha: 1).setFill()
            let frame = NSRect(x: x + 12, y: y + 13, width: 15, height: 10); frame.fill(); color.setStroke(); NSBezierPath(rect: frame).stroke()
            text(action == .command ? ">_" : "≡", at: NSPoint(x: x + 14, y: y + 13), size: 6, color: color)
        case .testing:
            NSRect(x: x - 2, y: 27, width: 29, height: 1).fill()
            for i in 0..<3 {
                let offset = (time * 6 + Double(i) * 8).truncatingRemainder(dividingBy: 25)
                (progress?.actionFailed == true ? NSColor.systemOrange : color).setFill()
                NSRect(x: x - 2 + offset, y: 23, width: 3, height: 3).fill()
            }
        case .thinking:
            for i in 0..<3 { color.withAlphaComponent(Int(time * 3) % 3 == i ? 1 : 0.25).setFill(); NSRect(x: x + 19 + Double(i) * 3, y: 3, width: 2, height: 2).fill() }
        case .replying:
            NSRect(x: x + 15, y: y + 12, width: 10, height: 10).fill()
            NSColor.black.setFill(); for i in 0..<3 { NSRect(x: x + 17, y: y + 14 + Double(i) * 2, width: 6, height: 1).fill() }
        case .done:
            NSRect(x: x + 16, y: y + 14, width: 10, height: 9).fill()
            NSColor.black.setFill(); NSRect(x: x + 20, y: y + 14, width: 1, height: 9).fill()
        case .waiting: break
        }
    }
    @objc func tapped(_ gesture: NSClickGestureRecognizer) {
        let point = gesture.location(in: self)
        let x = point.x / (bounds.height / 30)
        if let battle {
            let width = bounds.width / (bounds.height / 30)
            if x > width - 42 { onExitBattle?(); return }
            if let tool = Tool.allCases.min(by: { abs((positions[$0] ?? 0)+11-x) < abs((positions[$1] ?? 0)+11-x) }), abs((positions[tool] ?? 0)+11-x) < 24 {
                battle.cheer(tool)
            } else { battle.dash(to: (x-112)/max(80,width-160)) }
            needsDisplay = true; return
        }
        if let tool = Tool.allCases.min(by: { abs((positions[$0] ?? 0) + 10 - x) < abs((positions[$1] ?? 0) + 10 - x) }) {
            petUntil[tool] = ProcessInfo.processInfo.systemUptime + 2
            if abs((positions[tool] ?? 0) + 10 - x) < 65 { onTap?(tool) }
            else { positions[tool] = max(10, min(bounds.width / (bounds.height / 30) - 30, x)) }
            needsDisplay = true
        }
    }
    func snapshot(to path: String) throws {
        guard let rep = bitmapImageRepForCachingDisplay(in: bounds) else { return }
        cacheDisplay(in: bounds, to: rep)
        try rep.representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: path))
    }
}

extension NSAffineTransform {
    static func scale(by value: CGFloat) { let transform = NSAffineTransform(); transform.scale(by: value); transform.concat() }
}
