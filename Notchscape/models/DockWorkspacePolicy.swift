import Foundation
import CoreGraphics

/// Eligibility for ordinary app-owned desktop surfaces, not authorization for
/// credential operations. The caller must additionally retain its lock-event,
/// sleep, user-switch and Presentation fences. Apple's public session fields
/// are required; the supplemental lock flag is absent on an unlocked desktop
/// on some macOS versions. A present but malformed flag fails closed.
enum LocalDesktopSessionPolicy {
    static func permitsDisplay(session: [String: Any]?, currentUID: UInt32, effectiveUID: UInt32) -> Bool {
        guard currentUID == effectiveUID, let session,
              let uid = session[kCGSessionUserIDKey as String] as? NSNumber,
              CFGetTypeID(uid) == CFNumberGetTypeID(),
              uid.doubleValue.isFinite, uid.doubleValue >= 0, uid.doubleValue <= Double(UInt32.max),
              uid.doubleValue.rounded(.towardZero) == uid.doubleValue,
              UInt32(uid.doubleValue) == currentUID,
              boolean(session[kCGSessionOnConsoleKey as String]) == true,
              boolean(session[kCGSessionLoginDoneKey as String]) == true else { return false }
        if let lock = session["CGSSessionScreenIsLocked"] { return boolean(lock) == false }
        return true
    }

    private static func boolean(_ value: Any?) -> Bool? {
        guard let value = value as? NSNumber, CFGetTypeID(value) == CFBooleanGetTypeID() else { return nil }
        return value.boolValue
    }
}

/// Portable saved layout only. A bookmark is resolved only for an explicit
/// action in the unlocked local session, never by this policy.
struct DockWorkspacePin: Codable, Equatable, Identifiable, Sendable {
    enum Kind: String, Codable, Sendable { case application, folder }
    let id: UUID
    var title: String
    let kind: Kind
    var bookmark: Data

    var isValid: Bool {
        !title.isEmpty && title == DockWorkspacePolicy.title(title) &&
        !bookmark.isEmpty && bookmark.count <= DockWorkspacePolicy.maximumBookmarkBytes
    }
}

enum DockWorkspaceWidget: String, Codable, CaseIterable, Identifiable, Sendable {
    case clock, calendar, battery, system, music
    var id: Self { self }
    var title: String {
        switch self {
        case .clock: "Clock"
        case .calendar: "This Week"
        case .battery: "Battery"
        case .system: "System"
        case .music: "Now Playing"
        }
    }
    var symbol: String {
        switch self {
        case .clock: "clock"
        case .calendar: "calendar"
        case .battery: "battery.100percent"
        case .system: "gauge.with.dots.needle.50percent"
        case .music: "music.note"
        }
    }
}

struct DockWorkspaceLayout: Codable, Equatable, Sendable {
    var schemaVersion = 1
    var pins: [DockWorkspacePin] = []
    var widgets: [DockWorkspaceWidget] = [.clock, .battery, .system]
    var isValid: Bool {
        schemaVersion == 1 && pins.count <= DockWorkspacePolicy.maximumPins &&
        pins.allSatisfy(\.isValid) && Set(pins.map(\.id)).count == pins.count &&
        widgets.count <= DockWorkspaceWidget.allCases.count && Set(widgets).count == widgets.count
    }
}

struct DockWorkspacePrivacy: Equatable, Sendable {
    var enabled: Bool
    var unlocked: Bool
    var awake: Bool
    var activeSession: Bool
    var presenting: Bool
    var permitsDisplay: Bool { enabled && unlocked && awake && activeSession && !presenting }
}

enum DockWorkspacePolicy {
    static let maximumPins = 24
    static let maximumBookmarkBytes = 65_536
    static let maximumLayoutBytes = 2_200_000

    /// A tiny bounded collection uses eager rows with a deterministic proposal.
    /// Do not infer its column count from a lazy grid's changing visible rect.
    static func columnCount(contentWidth: Double, minimumItemWidth: Double, maximumColumns: Int) -> Int {
        guard contentWidth.isFinite, minimumItemWidth.isFinite, contentWidth > 0,
              minimumItemWidth > 0, (1...24).contains(maximumColumns) else { return 1 }
        let count = ((contentWidth + 12) / (minimumItemWidth + 12)).rounded(.down)
        return Int(max(1, min(Double(maximumColumns), count)))
    }

    static func rowRanges(itemCount: Int, columns: Int) -> [Range<Int>] {
        guard (0...maximumPins).contains(itemCount), (1...maximumPins).contains(columns) else { return [] }
        return stride(from: 0, to: itemCount, by: columns).map { $0..<min(itemCount, $0 + columns) }
    }

    static func title(_ value: String) -> String {
        let safe = value.unicodeScalars.prefix(1024).map {
            CharacterSet.controlCharacters.contains($0) ? " " : String($0)
        }.joined().trimmingCharacters(in: .whitespacesAndNewlines)
        return String(safe.prefix(80))
    }

    static func decode(_ data: Data?) -> DockWorkspaceLayout? {
        guard let data, data.count <= maximumLayoutBytes,
              let layout = try? JSONDecoder().decode(DockWorkspaceLayout.self, from: data),
              layout.isValid else { return nil }
        return layout
    }

    /// One position at a time makes the keyboard/context-menu path identical to
    /// local drag reorder. Unknown IDs and boundary moves are no-ops.
    static func moving<T: Equatable>(_ value: T, by direction: Int, in values: [T]) -> [T] {
        guard direction == -1 || direction == 1, let source = values.firstIndex(of: value),
              values.indices.contains(source + direction) else { return values }
        var result = values
        result.swapAt(source, source + direction)
        return result
    }

    static func placing<T: Equatable>(_ value: T, at target: T, in values: [T]) -> [T] {
        guard value != target, values.contains(value), let index = values.firstIndex(of: target) else { return values }
        var result = values.filter { $0 != value }
        result.insert(value, at: min(index, result.count))
        return result
    }

    /// AppKit visible frame already excludes the hardware notch, menu bar and
    /// the normal Dock. Never resize or relocate Apple's Dock to make room.
    static func panelFrame(in visibleFrame: CGRect) -> CGRect? {
        guard !visibleFrame.isNull, !visibleFrame.isInfinite,
              [visibleFrame.minX, visibleFrame.minY, visibleFrame.width, visibleFrame.height,
               visibleFrame.maxX, visibleFrame.maxY].allSatisfy(\.isFinite),
              visibleFrame.width >= 480, visibleFrame.height >= 280 else { return nil }
        let inset = 12.0
        let width = min(620, visibleFrame.width - inset * 2)
        let height = min(500, visibleFrame.height - inset * 2)
        return CGRect(x: visibleFrame.midX - width / 2, y: visibleFrame.minY + inset,
                      width: width, height: height)
    }
}
