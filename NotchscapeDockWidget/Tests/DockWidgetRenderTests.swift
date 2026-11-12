import AppKit
import Darwin

/// Dedicated inert fixture executable: excludes the host's main/controller,
/// creates no visible window, changes no Dock item, and reads no live source.
@main struct DockWidgetRenderTests {
    @MainActor static func main() throws {
        guard CommandLine.arguments.count == 2 else { exit(64) }
        let output = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
        try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
        _ = NSApplication.shared; NSApp.setActivationPolicy(.prohibited)
        let date = Date(timeIntervalSince1970: 1_793_640_010)
        var privacy = DockWidgetPrivacy(); privacy.sessionEligible = true; privacy.locked = false; privacy.presenting = false
        let battery = DockWidgetBattery.reading(current: 75, maximum: 100, charging: true, onACPower: true)
        let view = DockWidgetTileView(frame: NSRect(x: 0, y: 0, width: 256, height: 256))
        var checks = 0
        for (name, appearance) in [("light", NSAppearance.Name.aqua), ("dark", .darkAqua)] {
            view.appearance = NSAppearance(named: appearance)
            for kind in DockWidgetKind.allCases {
                view.snapshot = .make(widget: kind, privacy: privacy, now: date, battery: battery)
                try render(view, to: output.appendingPathComponent("\(kind.rawValue)-\(name).png")); checks += 1
            }
            var blocked = privacy; blocked.presenting = true
            view.snapshot = .make(widget: .clock, privacy: blocked, now: date, battery: battery)
            precondition(view.snapshot.date == nil && view.snapshot.battery == nil)
            try render(view, to: output.appendingPathComponent("paused-\(name).png")); checks += 1
        }
        for index in 0..<300 {
            view.snapshot = .make(widget: DockWidgetKind.allCases[index % 3], privacy: privacy,
                now: date.addingTimeInterval(Double(index) * 60), battery: battery)
            guard let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { fatalError("No native bitmap") }
            view.cacheDisplay(in: view.bounds, to: rep)
            precondition(rep.pixelsWide == 256 && rep.pixelsHigh == 256)
            checks += 1
        }
        print("PASS \(checks) native Dock tile render checks;8PNGfixtures,300snapshotdraws,inertdata,no host/Dock/owner launch or private access")
    }

    @MainActor static func render(_ view: NSView, to destination: URL) throws {
        guard let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { fatalError("No native bitmap") }
        view.cacheDisplay(in: view.bounds, to: rep)
        guard let data = rep.representation(using: .png, properties: [:]) else { fatalError("No PNG") }
        precondition(rep.colorAt(x: 0, y: 0)!.alphaComponent == 0, "rounded tile leaves transparent corners")
        precondition(rep.colorAt(x: 128, y: 128)!.alphaComponent > 0.99, "center is opaque and readable")
        try data.write(to: destination, options: .atomic)
    }
}
