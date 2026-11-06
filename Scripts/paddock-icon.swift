import AppKit
let directory = URL(fileURLWithPath: CommandLine.arguments[1])
try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
for points in [16, 32, 128, 256, 512] {
    for scale in [1, 2] {
        let size = points * scale
        let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: size, pixelsHigh: size, bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)
        let context = NSGraphicsContext.current!.cgContext
        context.scaleBy(x: CGFloat(size) / 1024, y: CGFloat(size) / 1024)
        NSColor(calibratedRed: 0.07, green: 0.08, blue: 0.10, alpha: 1).setFill()
        NSBezierPath(roundedRect: NSRect(x: 72, y: 72, width: 880, height: 880), xRadius: 190, yRadius: 190).fill()
        NSColor(calibratedRed: 1, green: 0.36, blue: 0.16, alpha: 1).setStroke()
        let ring = NSBezierPath(ovalIn: NSRect(x: 248, y: 248, width: 528, height: 528))
        ring.lineWidth = 48; ring.stroke()
        let spokes = NSBezierPath(); spokes.lineWidth = 48; spokes.lineCapStyle = .round
        for end in [NSPoint(x: 270, y: 590), NSPoint(x: 754, y: 590), NSPoint(x: 512, y: 270)] {
            spokes.move(to: NSPoint(x: 512, y: 512)); spokes.line(to: end)
        }
        spokes.stroke()
        NSColor(calibratedRed: 1, green: 0.36, blue: 0.16, alpha: 1).setFill()
        NSBezierPath(ovalIn: NSRect(x: 446, y: 446, width: 132, height: 132)).fill()
        NSGraphicsContext.restoreGraphicsState()
        let name = "icon_\(points)x\(points)\(scale == 2 ? "@2x" : "").png"
        try bitmap.representation(using: .png, properties: [:])!.write(to: directory.appendingPathComponent(name))
    }
}
