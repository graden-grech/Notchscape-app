import Foundation

enum WorkspaceActivity: String, CaseIterable { case music, agent, calendar, download, weather, sports, privacy, timer }

enum WorkspaceMode: String, CaseIterable, Identifiable, Codable {
    case work, study, presentation, gaming, travel, creative, developer, minimal
    var id: Self { self }
    var title: String { rawValue.capitalized }
    var symbol: String {
        switch self {
        case .work: "briefcase"
        case .study: "book"
        case .presentation: "person.crop.rectangle"
        case .gaming: "gamecontroller"
        case .travel: "airplane"
        case .creative: "paintbrush.pointed"
        case .developer: "chevron.left.forwardslash.chevron.right"
        case .minimal: "circle.lefthalf.filled"
        }
    }
    var lowImpact: Bool { [.gaming, .travel, .minimal].contains(self) }
    var pauseWallpapers: Bool { [.presentation, .travel].contains(self) }
    var hidesPrivateContent: Bool { self == .presentation }
    var allowsHover: Bool { ![.presentation, .gaming, .minimal].contains(self) }
    var preferredActivity: String? {
        switch self { case .creative: "musicOnly"; case .developer: "agentOnly"; default: nil }
    }
    var homePriority: [String] {
        switch self {
        case .work, .study: ["calendar", "quickActions", "music", "weather"]
        case .creative: ["music", "quickActions", "calendar", "weather"]
        default: []
        }
    }
    func allows(_ activity: WorkspaceActivity) -> Bool {
        switch self {
        case .work: [.agent, .calendar, .privacy, .timer].contains(activity)
        case .study: [.music, .calendar, .privacy, .timer].contains(activity)
        case .presentation, .gaming, .minimal: false
        case .travel: activity != .sports && activity != .download
        case .creative: [.music, .privacy, .timer].contains(activity)
        case .developer: [.agent, .calendar, .privacy, .timer, .download].contains(activity)
        }
    }
    var changes: [String] {
        var result: [String] = []
        switch self {
        case .work: result = ["Quiet music, sports, weather and download activities", "Calendar and quick-action tiles first"]
        case .study: result = ["Quiet AI, sports, weather and download activities", "Calendar and quick-action tiles first; music keeps your own settings"]
        case .presentation: result = ["Hide private content in the expanded notch", "Close Tools and pause clipboard recording", "Quiet live activities; click to open", "Pause automatic wallpaper changes"]
        case .gaming: result = ["Quiet live activities", "Click to open instead of hover"]
        case .travel: result = ["Quiet sports and download activities", "Pause automatic wallpaper changes"]
        case .creative: result = ["Music-first activity priority and Home layout", "Quiet AI, calendar, sports, weather and downloads"]
        case .developer: result = ["AI-first activity priority", "Quiet music, sports and weather activities"]
        case .minimal: result = ["Quiet live activities", "Click to open instead of hover"]
        }
        if lowImpact { result.append("Low-impact glass, animation and refresh rates") }
        result.append("No permissions or saved preferences are changed")
        return result
    }
}

enum WorkspaceModeDuration: String, CaseIterable, Identifiable {
    case untilQuit, thirtyMinutes, oneHour
    var id: Self { self }
    var title: String {
        switch self { case .untilQuit: "Until app quits"; case .thirtyMinutes: "30 minutes"; case .oneHour: "1 hour" }
    }
    var seconds: TimeInterval? {
        switch self { case .untilQuit: nil; case .thirtyMinutes: 1800; case .oneHour: 3600 }
    }
}

struct WorkspaceModeSession: Equatable {
    let id: UUID
    let mode: WorkspaceMode
    let startedAt: Date
    let expiresAt: Date?
    init(mode: WorkspaceMode, duration: WorkspaceModeDuration, now: Date = Date()) {
        id = UUID(); self.mode = mode; startedAt = now
        // Privacy must never end automatically in the middle of a screen share.
        expiresAt = mode.hidesPrivateContent ? nil : duration.seconds.map { now.addingTimeInterval($0) }
    }
    func isExpired(at now: Date) -> Bool { expiresAt.map { $0 <= now } ?? false }
}

enum WorkspaceModePolicy {
    static func allowed(base: Bool, mode: WorkspaceMode?, activity: WorkspaceActivity) -> Bool {
        base && (mode?.allows(activity) ?? true)
    }
    static func hover(base: Bool, mode: WorkspaceMode?) -> Bool { base && (mode?.allowsHover ?? true) }
    static func lowImpact(base: Bool, mode: WorkspaceMode?) -> Bool { base || mode?.lowImpact == true }
    static func homeOrder(_ ids: [String], mode: WorkspaceMode?) -> [String] {
        guard let priority = mode?.homePriority, !priority.isEmpty else { return ids }
        return priority.filter(ids.contains) + ids.filter { !priority.contains($0) }
    }
}
