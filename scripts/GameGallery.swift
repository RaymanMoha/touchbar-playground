import AppKit
import ImageIO
import UniformTypeIdentifiers

// Reproducible example data only: no polling, sessions, hooks or desktop capture.
final class GameGallery: NSView {
    let game=CompanionBattle(seed:12,mode:.boss)
    let model=PlaygroundModel()
    lazy var field=PlaygroundView(model:model)
    var data:[Tool:CompanionBattle.LiveActivity]=[:]
    var event=0
    override var isFlipped:Bool { true }
    init() {
        super.init(frame:NSRect(x:0,y:0,width:1200,height:310))
        field.frame=NSRect(x:40,y:94,width:1120,height:1120/685*30)
        field.battle=game; addSubview(field)
        for tool in Tool.allCases {
            data[tool] = .init(mood:.working,modelName:"example-model",caption:"Reading · demo",action:.reading,eventID:"baseline",eventTime:1000)
        }
        game.updateLive(data,now:1000)
    }
    required init?(coder:NSCoder) { fatalError() }
    func action(_ tool:Tool,_ action:WorkAction,pass:Bool?=nil) {
        event += 1
        let stamp=1000+game.time
        data[tool]?.action=action; data[tool]?.caption=action == .testing && pass == true ? "Tests passed · demo" : action.title+" · demo"
        data[tool]?.eventID="demo-\(event)"; data[tool]?.eventTime=stamp
        data[tool]?.testPassed=pass; data[tool]?.actionCompleted=pass != nil
        game.updateLive(data,now:stamp)
    }
    func advance(_ dt:Double) {
        game.advance(dt); needsDisplay=true; field.needsDisplay=true
    }
    func label(_ s:String,_ x:Double,_ y:Double,_ size:CGFloat,_ color:NSColor) {
        (s as NSString).draw(at:NSPoint(x:x,y:y),withAttributes:[.font:NSFont.systemFont(ofSize:size,weight:.medium),.foregroundColor:color])
    }
    override func draw(_ dirty:NSRect) {
        NSColor(srgbRed:0.055,green:0.065,blue:0.08,alpha:1).setFill(); bounds.fill()
        label("Touch Bar Playground",40,14,28,.white)
        let subtitle=game.phase == .finished ? (game.boss!.defeated ? "Party victory → animated scoreboard → the next wave" : "The bug wins this round. Regroup for the next wave.") : "Your coding tools. A tiny co-op party."
        label(subtitle,41,54,14,.systemMint)
        for (i,tool) in Tool.allCases.enumerated() {
            let x=40.0+Double(i)*380
            NSColor(white:0.11,alpha:1).setFill()
            NSBezierPath(roundedRect:NSRect(x:x,y:170,width:360,height:84),xRadius:9,yRadius:9).fill()
            NSGraphicsContext.saveGraphicsState()
            let pose=NSAffineTransform(); pose.translateX(by:x+15,yBy:180); pose.scale(by:2.1); pose.concat()
            PixelArt.draw(tool,mood:game.phase == .finished && game.boss!.defeated ? .finished : .working,x:0,y:0,time:game.time,walking:false)
            NSGraphicsContext.restoreGraphicsState()
            label(tool.title,x+73,179,16,tool.color)
            label("example-model",x+73,204,11,.lightGray)
            label(data[tool]?.caption ?? "Example activity",x+73,225,12,.white)
        }
        label("Synthetic example data · time-compressed fight · actual native game renderer",40,279,11,.gray)
    }
    func capture() -> CGImage {
        let rep=bitmapImageRepForCachingDisplay(in:bounds)!
        cacheDisplay(in:bounds,to:rep); return rep.cgImage!
    }
}
_ = NSApplication.shared
let out=URL(fileURLWithPath:CommandLine.arguments[1],isDirectory:true)
try FileManager.default.createDirectory(at:out,withIntermediateDirectories:true)
let gallery=GameGallery()
var frames:[CGImage]=[]
func capture() { frames.append(gallery.capture()) }
// First show the actual action-triggered mechanics at readable speed.
for i in 0..<48 {
    if i==16 { gallery.action(.codex,.searching) }
    if i==24 { gallery.action(.claude,.editing) }
    if i==32 { gallery.action(.antigravity,.testing,pass:true) }
    if i==40 { gallery.action(.codex,.building) }
    gallery.advance(0.125); capture()
}
// Compress the long encounter using ordinary taps and fresh demo actions.
var step=0
while gallery.game.phase != .finished && step<70 {
    step += 1
    for tool in Tool.allCases { gallery.game.cheer(tool) }
    gallery.action(Tool.allCases[step%3], step%3==0 ? .testing : .searching,pass:step%3==0 ? true : nil)
    gallery.advance(0.8); capture()
}
guard gallery.game.phase == .finished else { fatalError("Demo encounter did not finish") }
let result=gallery.game.boss!.defeated ? "party victory" : "bug victory"
// Preserve the full animated scoreboard entrance, score update, hold and exit.
for _ in 0..<56 { gallery.advance(0.125); capture() }
let gif=out.appendingPathComponent("boss-and-scoreboard.gif")
let dest=CGImageDestinationCreateWithURL(gif as CFURL,UTType.gif.identifier as CFString,frames.count,nil)!
CGImageDestinationSetProperties(dest,[kCGImagePropertyGIFDictionary:[kCGImagePropertyGIFLoopCount:0]] as CFDictionary)
for frame in frames { CGImageDestinationAddImage(dest,frame,[kCGImagePropertyGIFDictionary:[kCGImagePropertyGIFDelayTime:0.125]] as CFDictionary) }
guard CGImageDestinationFinalize(dest) else { fatalError("GIF export failed") }
let png=CGImageDestinationCreateWithURL(out.appendingPathComponent("game-gallery.png") as CFURL,UTType.png.identifier as CFString,1,nil)!
CGImageDestinationAddImage(png,frames[36],nil); CGImageDestinationFinalize(png)
print("Rendered \(frames.count) frames, \(result), then round \(gallery.game.round)")
