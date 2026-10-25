import AppKit

// A quiet silver desk, with a mint connection path between the two icons.
// Coordinates are in Finder points; matching 1x and 2x reps produce a Retina TIFF.
let output = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
func color(_ r: CGFloat, _ g: CGFloat, _ b: CGFloat, _ a: CGFloat = 1) -> NSColor {
    NSColor(srgbRed: r, green: g, blue: b, alpha: a)
}
func text(_ value: String, _ x: CGFloat, _ y: CGFloat, _ size: CGFloat,
          _ weight: NSFont.Weight = .regular, _ ink: NSColor = .labelColor) {
    (value as NSString).draw(at: NSPoint(x: x, y: y), withAttributes: [
        .font: NSFont.systemFont(ofSize: size, weight: weight), .foregroundColor: ink
    ])
}
for scale in [1, 2] {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 720 * scale,
        pixelsHigh: 460 * scale, bitsPerSample: 8, samplesPerPixel: 4,
        hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
        bytesPerRow: 0, bitsPerPixel: 0)!
    rep.size = NSSize(width: 720, height: 460)
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    let context = NSGraphicsContext.current!.cgContext
    context.scaleBy(x: CGFloat(scale), y: CGFloat(scale))
    context.translateBy(x: 0, y: 460)
    context.scaleBy(x: 1, y: -1)
    // Flip AppKit drawing together with the canvas, so text stays upright.
    NSGraphicsContext.current = NSGraphicsContext(cgContext: context, flipped: true)
    NSGradient(starting: color(0.98, 0.99, 0.98), ending: color(0.89, 0.93, 0.92))!
        .draw(in: NSRect(x: 0, y: 0, width: 720, height: 460), angle: 80)
    color(1, 1, 1, 0.65).setFill()
    NSBezierPath(roundedRect: NSRect(x: 28, y: 28, width: 664, height: 404), xRadius: 26, yRadius: 26).fill()
    let ink = color(0.12, 0.21, 0.19)
    text("DUO / MAC", 54, 50, 11, .semibold, color(0.34, 0.46, 0.42))
    text("A little closer.", 52, 79, 36, .light, ink)
    text("Your iPhone. Your Mac. One smooth connection.", 54, 130, 15, .regular, color(0.38, 0.45, 0.43))
    for x: CGFloat in [190, 530] {
        color(0.90, 0.94, 0.92, 0.75).setFill()
        NSBezierPath(roundedRect: NSRect(x: x - 78, y: 178, width: 156, height: 142), xRadius: 28, yRadius: 28).fill()
    }
    let path = NSBezierPath()
    path.move(to: NSPoint(x: 307, y: 245)); path.line(to: NSPoint(x: 412, y: 245))
    path.move(to: NSPoint(x: 400, y: 233)); path.line(to: NSPoint(x: 412, y: 245)); path.line(to: NSPoint(x: 400, y: 257))
    path.lineWidth = 2; path.lineCapStyle = .round; path.lineJoinStyle = .round
    color(0.32, 0.52, 0.43).setStroke(); path.stroke()
    text("Drag to install", 306, 273, 12, .medium, color(0.34, 0.46, 0.42))
    text("01  Drag into Applications", 54, 367, 13, .medium, ink)
    text("02  Open Duo Receiver and allow Accessibility", 54, 390, 13, .regular, color(0.38, 0.45, 0.43))
    text("belweave", 585, 393, 12, .medium, color(0.34, 0.46, 0.42))
    NSGraphicsContext.restoreGraphicsState()
    let name = scale == 1 ? "background.png" : "background@2x.png"
    try rep.representation(using: .png, properties: [:])!.write(to: output.appendingPathComponent(name))
}
