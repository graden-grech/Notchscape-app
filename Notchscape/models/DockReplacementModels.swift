import Foundation

/// The replacement surface has independent widget instances. It does not
/// reuse the single selected-kind Dock tile or overwrite its saved preferences.
enum DockReplacementWidgetKind: String, Codable, CaseIterable, Sendable {
    case nowPlaying, upNext, battery, timer, clock, calculator, weather, system

    var title: String {
        switch self {
        case .nowPlaying: "Now Playing"
        case .upNext: "Up Next"
        case .battery: "Battery"
        case .timer: "Timer"
        case .clock: "Clock"
        case .calculator: "Calculator"
        case .weather: "Weather"
        case .system: "System"
        }
    }
    var symbol: String {
        switch self {
        case .nowPlaying: "music.note"
        case .upNext: "calendar"
        case .battery: "battery.100percent"
        case .timer: "timer"
        case .clock: "clock"
        case .calculator: "plus.forwardslash.minus"
        case .weather: "cloud.sun.fill"
        case .system: "chart.bar.xaxis"
        }
    }
}

struct DockReplacementWidgetInstance: Codable, Equatable, Identifiable, Sendable {
    let id: UUID
    var kind: DockReplacementWidgetKind
    var timeZoneIdentifier: String?
    var timerDuration: TimeInterval

    init(id: UUID = UUID(), kind: DockReplacementWidgetKind,
         timeZoneIdentifier: String? = nil, timerDuration: TimeInterval = 300) {
        self.id = id
        self.kind = kind
        self.timeZoneIdentifier = timeZoneIdentifier
        self.timerDuration = timerDuration
    }

    var isValid: Bool {
        timerDuration.isFinite && (1...86_400).contains(timerDuration) &&
        (timeZoneIdentifier.map { $0.utf8.count <= 128 && TimeZone(identifier: $0) != nil } ?? true)
    }
}

struct DockReplacementLayout: Codable, Equatable, Sendable {
    var schemaVersion = 1
    var widgets: [DockReplacementWidgetInstance]

    static var starter: Self {
        // New widget types remain opt-in; keep the original starter layout.
        .init(widgets: [.nowPlaying, .upNext, .battery, .timer, .clock, .calculator].map { .init(kind: $0) })
    }

    var isValid: Bool {
        schemaVersion == 1 && widgets.count <= 48 && widgets.allSatisfy(\.isValid) &&
        Set(widgets.map(\.id)).count == widgets.count
    }

    /// Unknown or damaged data stays unavailable; callers must preserve it
    /// rather than replacing the user's layout with a starter preset.
    static func decode(_ data: Data) -> Self? {
        guard data.count <= 65_536,
              let value = try? JSONDecoder().decode(Self.self, from: data), value.isValid else { return nil }
        return value
    }
}
