import AppKit
import Foundation

let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
for platform in ["iOS", "macOS"] {
    let folder = root.appendingPathComponent("\(platform)/Assets.xcassets/AppIcon.appiconset")
    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    let sizes = platform == "iOS" ? [1024] : [16, 32, 64, 128, 256, 512, 1024]
    for pixels in sizes {
        let alpha = platform == "macOS"
        let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: pixels, bitsPerSample: 8, samplesPerPixel: alpha ? 4 : 3, hasAlpha: alpha, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)
        let scale = Double(pixels) / 1024
        let transform = NSAffineTransform(); transform.scale(by: scale); transform.concat()
        NSColor(calibratedRed: 0.80, green: 0.83, blue: 0.85, alpha: 1).setFill()
        NSBezierPath(rect: NSRect(x: 0, y: 0, width: 1024, height: 1024)).fill()
        let shape = NSBezierPath(roundedRect: NSRect(x: 104, y: 168, width: 816, height: 688), xRadius: 90, yRadius: 90)
        let shadow = NSShadow(); shadow.shadowColor = NSColor.black.withAlphaComponent(0.20); shadow.shadowBlurRadius = 34; shadow.shadowOffset = NSSize(width: 0, height: -18)
        NSGraphicsContext.saveGraphicsState(); shadow.set(); NSColor.white.setFill(); shape.fill(); NSGraphicsContext.restoreGraphicsState()
        NSGradient(starting: NSColor(white: 0.99, alpha: 1), ending: NSColor(white: 0.87, alpha: 1))!.draw(in: shape, angle: -65)
        NSColor.white.withAlphaComponent(0.9).setStroke(); shape.lineWidth = 5; shape.stroke()
        let inner = NSBezierPath(roundedRect: NSRect(x: 126, y: 190, width: 772, height: 644), xRadius: 72, yRadius: 72)
        NSColor(white: 0.7, alpha: 0.3).setStroke(); inner.lineWidth = 2; inner.stroke()
        for radius in [68.0, 112.0, 156.0] {
            let circle = NSBezierPath(ovalIn: NSRect(x: 512-radius, y: 512-radius, width: radius*2, height: radius*2))
            NSColor(white: 0.5, alpha: radius == 68 ? 0.38 : 0.18).setStroke(); circle.lineWidth = 4; circle.stroke()
        }
        NSColor(calibratedRed: 0.29, green: 0.56, blue: 0.46, alpha: 1).setFill()
        NSBezierPath(ovalIn: NSRect(x: 493, y: 493, width: 38, height: 38)).fill()
        NSGraphicsContext.restoreGraphicsState()
        try bitmap.representation(using: .png, properties: [:])!.write(to: folder.appendingPathComponent("icon-\(pixels).png"))
    }
    var images: [[String: String]] = []
    if platform == "iOS" {
        images = [["filename": "icon-1024.png", "idiom": "universal", "platform": "ios", "size": "1024x1024"]]
    } else {
        for points in [16, 32, 128, 256, 512] {
            for factor in [1, 2] { images.append(["filename": "icon-\(points*factor).png", "idiom": "mac", "scale": "\(factor)x", "size": "\(points)x\(points)"]) }
        }
    }
    let contents: [String: Any] = ["images": images, "info": ["author": "xcode", "version": 1]]
    try JSONSerialization.data(withJSONObject: contents, options: [.prettyPrinted, .sortedKeys]).write(to: folder.appendingPathComponent("Contents.json"))
    let assetInfo: [String: Any] = ["info": ["author": "xcode", "version": 1]]
    try JSONSerialization.data(withJSONObject: assetInfo).write(to: folder.deletingLastPathComponent().appendingPathComponent("Contents.json"))
}
