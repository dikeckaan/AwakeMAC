// Renders the app icon (1024x1024 PNG). Usage: swift scripts/make-icon.swift out.png
import AppKit

let size: CGFloat = 1024
let out = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "AppIcon.png"
let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(size), pixelsHigh: Int(size), bitsPerSample: 8,
                           samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
                           bytesPerRow: 0, bitsPerPixel: 0)!
NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)

// macOS icon grid: 824pt squircle centred in 1024 canvas
let inset: CGFloat = 100
let rect = NSRect(x: inset, y: inset, width: size - inset * 2, height: size - inset * 2)
let shape = NSBezierPath(roundedRect: rect, xRadius: 185, yRadius: 185)

let shadow = NSShadow()
shadow.shadowColor = NSColor.black.withAlphaComponent(0.35)
shadow.shadowBlurRadius = 30
shadow.shadowOffset = NSSize(width: 0, height: -12)
NSGraphicsContext.current?.saveGraphicsState()
shadow.set()
NSColor.black.setFill()
shape.fill()
NSGraphicsContext.current?.restoreGraphicsState()

NSGradient(colors: [NSColor(red: 0.42, green: 0.38, blue: 1.00, alpha: 1),
                    NSColor(red: 0.72, green: 0.28, blue: 0.93, alpha: 1)])!.draw(in: shape, angle: -55)

// soft glow
NSGraphicsContext.current?.saveGraphicsState()
shape.addClip()
NSGradient(colors: [NSColor.white.withAlphaComponent(0.28), NSColor.white.withAlphaComponent(0)])!
    .draw(in: NSRect(x: rect.minX, y: rect.midY, width: rect.width, height: rect.height / 2), angle: -90)
NSGraphicsContext.current?.restoreGraphicsState()

func symbol(_ name: String, _ pt: CGFloat, _ color: NSColor) -> NSImage {
    let cfg = NSImage.SymbolConfiguration(pointSize: pt, weight: .semibold)
        .applying(.init(paletteColors: [color]))
    return NSImage(systemSymbolName: name, accessibilityDescription: nil)!.withSymbolConfiguration(cfg)!
}

let laptop = symbol("laptopcomputer", 420, .white)
let ls = laptop.size
laptop.draw(in: NSRect(x: (size - ls.width) / 2, y: 300, width: ls.width, height: ls.height))

let sun = symbol("sun.max.fill", 150, NSColor(red: 1.0, green: 0.66, blue: 0.16, alpha: 1))
let ss = sun.size
sun.draw(in: NSRect(x: (size - ss.width) / 2, y: 515 - ss.height / 2, width: ss.width, height: ss.height))

NSGraphicsContext.restoreGraphicsState()
try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: out))
print("wrote \(out)")
