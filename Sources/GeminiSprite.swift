import AppKit
import ImageIO

// Gemini-chan by Wlaeg, from the Antigravity Pet community pack.
// The original PNG is bundled intact; native nearest-neighbour rendering selects
// its existing frames without regenerating or altering the artwork.
enum GeminiSprite {
    static let frameCounts = [6, 8, 8, 4, 5, 8, 6, 6, 6, 8, 8]
    static let atlas: CGImage? = {
        let url = Bundle.main.url(forResource: "gemini-chan", withExtension: "png")
            ?? URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent("Assets/gemini-chan.png")
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
        guard let image = CGImageSourceCreateImageAtIndex(source, 0, [kCGImageSourceShouldCacheImmediately: true] as CFDictionary),
              let bitmap = CGContext(data: nil, width: image.width, height: image.height, bitsPerComponent: 8, bytesPerRow: 0,
                                     space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        // Decode the atlas once. Cropping a lazily decoded PNG can otherwise
        // decompress the entire atlas again on every tiny animated draw.
        bitmap.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
        return bitmap.makeImage()
    }()
    static var frames: [Int: NSImage] = [:]

    static func frame(row: Int, column: Int) -> NSImage? {
        let key = row * 8 + column
        if let image = frames[key] { return image }
        // A shared horizontal crop removes transparent gutters while preserving
        // a fixed foot anchor and all poses, hair, ears, hands and star effects.
        let crop = CGRect(x: column * 192 + 16, y: row * 208, width: 160, height: 208)
        guard let image = atlas?.cropping(to: crop) else { return nil }
        let result = NSImage(cgImage: image, size: NSSize(width: 160, height: 208))
        frames[key] = result
        return result
    }
    static func draw(mood: Mood, x: Double, y: Double, time: Double, walking: Bool, facingLeft: Bool, failed: Bool) {
        let row: Int
        if failed && [.working, .attention].contains(mood) { row = 5 }
        else {
            switch mood {
            case .idle: row = 0
            case .resting: row = walking ? (facingLeft ? 2 : 1) : 0
            case .working: row = walking ? (facingLeft ? 2 : 1) : 7
            case .attention: row = 3
            case .finished: row = 8
            }
        }
        let column = mood == .idle ? 3 : Int(time * 6) % frameCounts[row]
        guard let image = frame(row: row, column: column) else { return }
        NSGraphicsContext.saveGraphicsState()
        defer { NSGraphicsContext.restoreGraphicsState() }
        NSGraphicsContext.current?.imageInterpolation = .none
        image.draw(in: NSRect(x: x.rounded() + 1, y: y.rounded(), width: 20, height: 26), from: .zero,
                   operation: .sourceOver, fraction: mood == .idle ? 0.43 : 1, respectFlipped: true, hints: nil)
    }
}
