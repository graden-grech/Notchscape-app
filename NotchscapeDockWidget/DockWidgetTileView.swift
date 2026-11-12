import AppKit

/// A native Dock icon-sized snapshot. NSDockTile requests the pixels; no hidden
/// window, SwiftUI graph, animation loop, web view or private Dock API is used.
@MainActor
final class DockWidgetTileView: NSView {
    var snapshot = DockWidgetSnapshot(widget: .clock, redacted: true, date: nil, battery: nil) {
        didSet { needsDisplay = true; updateAccessibility() }
    }
    override var isOpaque: Bool { false }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setAccessibilityElement(true)
        updateAccessibility()
    }
    required init?(coder: NSCoder) { nil }

    override func draw(_ dirtyRect: NSRect) {
        NSColor.clear.setFill(); bounds.fill(using: .copy)
        guard bounds.width > 0, bounds.height > 0 else { return }
        NSGraphicsContext.saveGraphicsState()
        let scale = min(bounds.width, bounds.height) / 128
        let transform = NSAffineTransform()
        transform.translateX(by: (bounds.width - 128 * scale) / 2, yBy: (bounds.height - 128 * scale) / 2)
        transform.scale(by: scale); transform.concat()
        let dark = effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
        let shape = NSBezierPath(roundedRect: NSRect(x: 7, y: 7, width: 114, height: 114), xRadius: 26, yRadius: 26)
        let background = dark ? NSColor(calibratedWhite: 0.16, alpha: 1) : NSColor(calibratedWhite: 0.98, alpha: 1)
        background.setFill(); shape.fill()
        NSColor.white.withAlphaComponent(dark ? 0.16 : 0.7).setStroke(); shape.lineWidth = 1; shape.stroke()
        let ink = dark ? NSColor.white : NSColor(calibratedWhite: 0.12, alpha: 1)
        if snapshot.redacted {
            symbol("square.stack.3d.up.fill", rect: NSRect(x: 46, y: 51, width: 36, height: 36), color: .secondaryLabelColor)
        } else {
            switch snapshot.widget {
            case .clock:
                if let date = snapshot.date {
                    let time = DateFormatter(); time.dateStyle = .none; time.timeStyle = .short
                    let day = DateFormatter(); day.setLocalizedDateFormatFromTemplate("EEE MMM d")
                    let clock = time.string(from: date)
                    let measured = (clock as NSString).size(withAttributes: [.font: NSFont.monospacedDigitSystemFont(ofSize: 26, weight: .medium)]).width
                    let fontSize = max(14, min(26, 26 * 104 / max(1, measured)))
                    text(clock, rect: NSRect(x: 12, y: 49, width: 104, height: 34), font: .monospacedDigitSystemFont(ofSize: fontSize, weight: .medium), color: ink)
                    text(day.string(from: date), rect: NSRect(x: 13, y: 28, width: 102, height: 19), font: .systemFont(ofSize: 11, weight: .medium), color: .secondaryLabelColor)
                    symbol("clock", rect: NSRect(x: 55, y: 92, width: 18, height: 18), color: .controlAccentColor)
                }
            case .calendar:
                if let date = snapshot.date {
                    let month = DateFormatter(); month.setLocalizedDateFormatFromTemplate("MMMM")
                    let weekday = DateFormatter(); weekday.setLocalizedDateFormatFromTemplate("EEEE")
                    text(month.string(from: date).uppercased(), rect: NSRect(x: 13, y: 91, width: 102, height: 16), font: .systemFont(ofSize: 12, weight: .bold), color: .systemRed)
                    text(String(Calendar.current.component(.day, from: date)), rect: NSRect(x: 12, y: 34, width: 104, height: 57), font: .systemFont(ofSize: 52, weight: .light), color: ink)
                    text(weekday.string(from: date), rect: NSRect(x: 13, y: 19, width: 102, height: 17), font: .systemFont(ofSize: 10, weight: .medium), color: .secondaryLabelColor)
                }
            case .battery:
                let reading = snapshot.battery
                let percent = reading.map { "\($0.percent)%" } ?? "—"
                let color: NSColor = reading.map { $0.percent <= 20 && !$0.onACPower ? .systemOrange : .systemGreen } ?? .secondaryLabelColor
                let shell = NSBezierPath(roundedRect: NSRect(x: 36, y: 84, width: 52, height: 22), xRadius: 6, yRadius: 6)
                color.setStroke(); shell.lineWidth = 2.5; shell.stroke()
                color.setFill(); NSBezierPath(roundedRect: NSRect(x: 90, y: 91, width: 4, height: 8), xRadius: 2, yRadius: 2).fill()
                if let reading, reading.percent > 0 {
                    NSBezierPath(roundedRect: NSRect(x: 40, y: 88, width: 44 * CGFloat(reading.percent) / 100, height: 14), xRadius: 3, yRadius: 3).fill()
                }
                text(percent, rect: NSRect(x: 12, y: 43, width: 104, height: 35), font: .monospacedDigitSystemFont(ofSize: 31, weight: .medium), color: ink)
                let state = reading.map { $0.charging ? "Charging" : $0.onACPower ? "Connected" : "On Battery" } ?? "Unavailable"
                text(state, rect: NSRect(x: 13, y: 24, width: 102, height: 17), font: .systemFont(ofSize: 10, weight: .medium), color: .secondaryLabelColor)
            }
        }
        NSGraphicsContext.restoreGraphicsState()
    }

    private func text(_ value: String, rect: NSRect, font: NSFont, color: NSColor) {
        let paragraph = NSMutableParagraphStyle(); paragraph.alignment = .center; paragraph.lineBreakMode = .byTruncatingTail
        (value as NSString).draw(in: rect, withAttributes: [.font: font, .foregroundColor: color, .paragraphStyle: paragraph])
    }
    private func symbol(_ name: String, rect: NSRect, color: NSColor) {
        let config = NSImage.SymbolConfiguration(paletteColors: [color])
        NSImage(systemSymbolName: name, accessibilityDescription: nil)?.withSymbolConfiguration(config)?.draw(in: rect)
    }
    private func updateAccessibility() {
        var label = snapshot.redacted ? "Notchscape Dock widget paused" : snapshot.widget.title
        if !snapshot.redacted, let date = snapshot.date { label += ", " + date.formatted(date: .complete, time: snapshot.widget == .clock ? .shortened : .omitted) }
        if !snapshot.redacted, snapshot.widget == .battery { label += snapshot.battery.map { ", \($0.percent) percent" } ?? ", unavailable" }
        setAccessibilityLabel(label)
    }
}
