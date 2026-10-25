// Renders Support/AppIcon.icns. Run: swift scripts/make-icon.swift
import AppKit

func render(_ size: CGFloat) -> Data {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(size), pixelsHigh: Int(size), bitsPerSample: 8,
                               samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    let s = size / 1024
    let bg = NSBezierPath(roundedRect: NSRect(x: 100 * s, y: 100 * s, width: 824 * s, height: 824 * s), xRadius: 185 * s, yRadius: 185 * s)
    NSGradient(starting: NSColor(calibratedRed: 0.16, green: 0.17, blue: 0.22, alpha: 1),
               ending: NSColor(calibratedRed: 0.05, green: 0.05, blue: 0.08, alpha: 1))!.draw(in: bg, angle: -90)
    let bar = NSBezierPath(roundedRect: NSRect(x: 170 * s, y: 430 * s, width: 684 * s, height: 164 * s), xRadius: 40 * s, yRadius: 40 * s)
    NSColor.black.setFill(); bar.fill()
    let colors: [NSColor] = [.systemOrange, .systemTeal, .systemPink, .systemGray]
    for (i, c) in colors.enumerated() {
        let r = NSBezierPath(roundedRect: NSRect(x: (200 + CGFloat(i) * 160) * s, y: 460 * s, width: 140 * s, height: 104 * s), xRadius: 22 * s, yRadius: 22 * s)
        c.setFill(); r.fill()
    }
    NSGraphicsContext.restoreGraphicsState()
    return rep.representation(using: .png, properties: [:])!
}

let fm = FileManager.default
let iconset = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("AppIcon.iconset")
try? fm.removeItem(at: iconset)
try! fm.createDirectory(at: iconset, withIntermediateDirectories: true)
for base in [16, 32, 128, 256, 512] {
    try! render(CGFloat(base)).write(to: iconset.appendingPathComponent("icon_\(base)x\(base).png"))
    try! render(CGFloat(base * 2)).write(to: iconset.appendingPathComponent("icon_\(base)x\(base)@2x.png"))
}
let p = Process()
p.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
p.arguments = ["-c", "icns", iconset.path, "-o", "Support/AppIcon.icns"]
try! p.run(); p.waitUntilExit()
print(p.terminationStatus == 0 ? "Wrote Support/AppIcon.icns" : "iconutil failed")
