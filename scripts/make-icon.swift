// Just Type It – created by Stefano Roman Gunness
// MIT License · https://github.com/stefanoromang/just-type-it

import AppKit

// Renders the app icon: a text cursor with a check mark on a green-to-teal rounded square.
let out = CommandLine.arguments[1]
try? FileManager.default.createDirectory(atPath: out, withIntermediateDirectories: true)

func render(_ px: Int) -> Data {
    let s = CGFloat(px)
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: px, pixelsHigh: px, bitsPerSample: 8,
                               samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                               colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    let inset = s * 0.09
    let rect = NSRect(x: inset, y: inset, width: s - inset * 2, height: s - inset * 2)
    let path = NSBezierPath(roundedRect: rect, xRadius: s * 0.2, yRadius: s * 0.2)
    NSGradient(colors: [NSColor(red: 0.09, green: 0.72, blue: 0.53, alpha: 1),
                        NSColor(red: 0.05, green: 0.47, blue: 0.62, alpha: 1)])!.draw(in: path, angle: -60)
    NSColor.white.setFill()
    NSColor.white.setStroke()
    // Text lines.
    let lw = rect.width * 0.07
    for (i, w) in [0.62, 0.48, 0.30].enumerated() {
        let y = rect.maxY - rect.height * (0.30 + 0.17 * CGFloat(i))
        NSBezierPath(roundedRect: NSRect(x: rect.minX + rect.width * 0.17, y: y, width: rect.width * w, height: lw), xRadius: lw / 2, yRadius: lw / 2).fill()
    }
    // Check mark.
    let check = NSBezierPath()
    check.lineWidth = rect.width * 0.085
    check.lineCapStyle = .round
    check.lineJoinStyle = .round
    check.move(to: NSPoint(x: rect.minX + rect.width * 0.52, y: rect.minY + rect.height * 0.30))
    check.line(to: NSPoint(x: rect.minX + rect.width * 0.62, y: rect.minY + rect.height * 0.20))
    check.line(to: NSPoint(x: rect.minX + rect.width * 0.83, y: rect.minY + rect.height * 0.42))
    check.stroke()
    NSGraphicsContext.restoreGraphicsState()
    return rep.representation(using: .png, properties: [:])!
}

for base in [16, 32, 128, 256, 512] {
    try! render(base).write(to: URL(fileURLWithPath: "\(out)/icon_\(base)x\(base).png"))
    try! render(base * 2).write(to: URL(fileURLWithPath: "\(out)/icon_\(base)x\(base)@2x.png"))
}
