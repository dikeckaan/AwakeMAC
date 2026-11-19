import AppKit
import SwiftUI

/// `LidAwake --snapshot <dir>` renders the popover in light and dark mode to PNGs
/// for the README. It never touches pmset or login items.
@MainActor
enum Snapshot {
    static func render(to dir: String) {
        let c = AwakeController.shared
        c.applyPreview(mode: .lid, remaining: 5400 - 17,
                       battery: BatteryInfo(hasBattery: true, level: 76, onBattery: true, charging: false))
        try? FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)

        var images: [NSImage] = []
        for (name, appearance) in [("light", NSAppearance.Name.aqua), ("dark", NSAppearance.Name.darkAqua)] {
            let root = MenuContentView(forceSettingsOpen: true)
                .environmentObject(c)
                .background(Color(nsColor: .windowBackgroundColor))
            let host = NSHostingView(rootView: root)
            host.appearance = NSAppearance(named: appearance)
            host.frame = NSRect(origin: .zero, size: host.fittingSize)

            let window = NSWindow(contentRect: NSRect(x: -4000, y: -4000, width: host.frame.width, height: host.frame.height),
                                  styleMask: [.borderless], backing: .buffered, defer: false)
            window.appearance = NSAppearance(named: appearance)
            window.contentView = host
            window.orderFrontRegardless()
            host.layoutSubtreeIfNeeded()
            RunLoop.current.run(until: Date().addingTimeInterval(0.6))

            guard let rep = host.bitmapImageRepForCachingDisplay(in: host.bounds) else { continue }
            host.cacheDisplay(in: host.bounds, to: rep)
            if let data = rep.representation(using: .png, properties: [:]) {
                try? data.write(to: URL(fileURLWithPath: dir).appendingPathComponent("popover-\(name).png"))
            }
            let img = NSImage(size: host.bounds.size)
            img.addRepresentation(rep)
            images.append(img)
            window.orderOut(nil)
        }

        guard images.count == 2 else { return }
        let hero = HStack(alignment: .top, spacing: 40) {
            ForEach(0..<2, id: \.self) { i in
                Image(nsImage: images[i])
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(.black.opacity(0.12)))
                    .shadow(color: .black.opacity(0.35), radius: 24, y: 12)
            }
        }
        .padding(56)
        .background(LinearGradient(colors: [Color(red: 0.36, green: 0.33, blue: 0.95), Color(red: 0.72, green: 0.30, blue: 0.90)],
                                   startPoint: .topLeading, endPoint: .bottomTrailing))
        let renderer = ImageRenderer(content: hero)
        renderer.scale = 2
        if let cg = renderer.cgImage {
            let rep = NSBitmapImageRep(cgImage: cg)
            if let data = rep.representation(using: .png, properties: [:]) {
                try? data.write(to: URL(fileURLWithPath: dir).appendingPathComponent("screenshot.png"))
            }
        }
    }
}
