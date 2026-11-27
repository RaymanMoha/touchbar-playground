import AppKit
import ImageIO
import UniformTypeIdentifiers

// Export synthetic demo data using the app's real drawing code. This does not
// poll sessions, connect hooks, display a Touch Bar, or read live tool activity.
final class DemoBoard: NSView {
    let model = PlaygroundModel()
    lazy var playground = PlaygroundView(model: model)
    var time = 0.0
    override var isFlipped: Bool { true }
    init() {
        super.init(frame: NSRect(x: 0, y: 0, width: 1200, height: 430))
        model.demo = true
        playground.frame = NSRect(x: 40, y: 322, width: 1120, height: 1120 / 685 * 30)
        addSubview(playground)
    }
    required init?(coder: NSCoder) { fatalError() }
    func label(_ value: String, x: CGFloat, y: CGFloat, width: CGFloat, size: CGFloat, color: NSColor) {
        let style = NSMutableParagraphStyle(); style.alignment = .center
        (value as NSString).draw(in: NSRect(x: x, y: y, width: width, height: 35), withAttributes: [
            .font: NSFont.systemFont(ofSize: size, weight: .medium), .foregroundColor: color, .paragraphStyle: style
        ])
    }
    func configure(_ t: Double) {
        time = t
        switch Int(t / 3) % 4 {
        case 0:
            model.demoMoods = [.codex: .working, .claude: .working, .antigravity: .working]
            model.demoAction = .reading
        case 1:
            model.demoMoods = [.codex: .working, .claude: .attention, .antigravity: .working]
            model.demoAction = .testing
        case 2:
            model.demoMoods = [.codex: .finished, .claude: .finished, .antigravity: .finished]
        default:
            model.demoMoods = [.codex: .resting, .claude: .resting, .antigravity: .resting]
        }
        playground.timeOverride = t
        playground.needsDisplay = true; needsDisplay = true
    }
    override func draw(_ rect: NSRect) {
        NSColor(srgbRed: 0.055, green: 0.065, blue: 0.08, alpha: 1).setFill(); bounds.fill()
        label("Touch Bar Playground", x: 0, y: 18, width: bounds.width, size: 29, color: .white)
        label("Codex · Claude Code · Antigravity", x: 0, y: 58, width: bounds.width, size: 16, color: .lightGray)
        for (index, tool) in Tool.allCases.enumerated() {
            let center = CGFloat(200 + index * 400)
            let mood = model.moods[tool, default: .idle]
            let phase = time + Double(index) * 0.3
            NSGraphicsContext.saveGraphicsState()
            let height: CGFloat = tool == .antigravity ? 26 : tool == .claude ? 15.6 : 21.6
            let transform = NSAffineTransform(); transform.translateX(by: center - 36, yBy: 200 - height * 3.3); transform.scale(by: 3.3); transform.concat()
            NSGraphicsContext.current?.shouldAntialias = false
            PixelArt.draw(tool, mood: mood, x: 0, y: 0, time: phase, walking: mood == .resting)
            NSGraphicsContext.restoreGraphicsState()
            label(tool.title, x: center - 180, y: 216, width: 360, size: 21, color: tool.color)
            label(model.actionCaption(for: tool, time: time), x: center - 190, y: 249, width: 380, size: 14, color: .white)
        }
        label("The native Touch Bar surface", x: 0, y: 286, width: bounds.width, size: 13, color: .lightGray)
        label("Demo data · enlarged character studies above · native app renderer", x: 0, y: 390, width: bounds.width, size: 12, color: .gray)
    }
    func capture() -> CGImage? {
        guard let rep = bitmapImageRepForCachingDisplay(in: bounds) else { return nil }
        cacheDisplay(in: bounds, to: rep)
        return rep.cgImage
    }
}

guard CommandLine.arguments.count == 2 else { fatalError("Usage: render-demo OUTPUT_DIRECTORY") }
_ = NSApplication.shared
let directory = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
let gifURL = directory.appendingPathComponent("companions-demo.gif")
let posterURL = directory.appendingPathComponent("companions-preview.png")
let board = DemoBoard()
guard let destination = CGImageDestinationCreateWithURL(gifURL as CFURL, UTType.gif.identifier as CFString, 72, nil) else { fatalError("Cannot create GIF") }
CGImageDestinationSetProperties(destination, [kCGImagePropertyGIFDictionary: [kCGImagePropertyGIFLoopCount: 0]] as CFDictionary)
for index in 0..<72 {
    autoreleasepool {
        board.configure(Double(index) / 6)
        guard let image = board.capture() else { fatalError("Cannot capture native view") }
        CGImageDestinationAddImage(destination, image, [kCGImagePropertyGIFDictionary: [kCGImagePropertyGIFDelayTime: 1.0 / 6]] as CFDictionary)
        if index == 6 {
            if let png = CGImageDestinationCreateWithURL(posterURL as CFURL, UTType.png.identifier as CFString, 1, nil) {
                CGImageDestinationAddImage(png, image, nil); CGImageDestinationFinalize(png)
            }
        }
    }
}
guard CGImageDestinationFinalize(destination) else { fatalError("Cannot finalize GIF") }
print("Rendered \(gifURL.path) and \(posterURL.path)")
