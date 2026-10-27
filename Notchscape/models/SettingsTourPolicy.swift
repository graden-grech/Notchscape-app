import Foundation

/// Explanations and navigation only. The tour never reads or writes preferences
/// and never requests access; actual changes belong to their Settings page.
struct SettingsTourTopic: Equatable {
    let sectionID: String
    let summary: String
    let suggestion: String
}

enum SettingsTourChapter: String, CaseIterable, Identifiable {
    case makeItYours, yourDay, liveUpdates, workspace, yourMac, privacyAndHelp
    var id: Self { self }
    var title: String {
        switch self {
        case .makeItYours: "Make it yours"
        case .yourDay: "Your day, at a glance"
        case .liveUpdates: "Choose your live updates"
        case .workspace: "Your workspace"
        case .yourMac: "Keep an eye on your Mac"
        case .privacyAndHelp: "You're in control"
        }
    }
    var symbol: String {
        switch self {
        case .makeItYours: "paintpalette"
        case .yourDay: "sun.max"
        case .liveUpdates: "waveform.path.ecg"
        case .workspace: "rectangle.3.group"
        case .yourMac: "laptopcomputer"
        case .privacyAndHelp: "hand.raised"
        }
    }
    var subtitle: String {
        switch self {
        case .makeItYours: "Start with how Notchscape looks and where it appears."
        case .yourDay: "Pick the everyday information you want close by."
        case .liveUpdates: "Keep useful moments visible without adding distractions."
        case .workspace: "A few optional tools can save a trip to another app."
        case .yourMac: "Useful information, with lightweight background behavior."
        case .privacyAndHelp: "Access is optional. You can revisit every choice later."
        }
    }
    func topics(accountsEnabled: Bool = false) -> [SettingsTourTopic] {
        let all: [SettingsTourTopic] = switch self {
        case .makeItYours: [
            .init(sectionID: "General", summary: "Choose your displays, Notch or Dynamic Island, hover behavior and Dock visibility.", suggestion: "New users start with all displays enabled. You can hide external displays here."),
            .init(sectionID: "Appearance", summary: "Choose a theme, accent and icon, then arrange or hide Home tiles.", suggestion: "Match your icon and accent to the theme, or choose them yourself."),
            .init(sectionID: "Modes", summary: "Apply a group of temporary settings for work, study, gaming or travel.", suggestion: "Restore your personal settings when you're finished with a mode.")
        ]
        case .yourDay: [
            .init(sectionID: "Media", summary: "Choose your music source, player controls and music activity behavior.", suggestion: "Music can stay visible with its override even when other live activities are off."),
            .init(sectionID: "Calendar", summary: "Choose calendars and reminders to show beside your music.", suggestion: "Calendar and Reminders access are requested only when you choose to connect them."),
            .init(sectionID: "Weather", summary: "Add a forecast using a city or your current location, on Home or Live.", suggestion: "Weather starts off for new users. A manually chosen city doesn't need location access.")
        ]
        case .liveUpdates: [
            .init(sectionID: "Agents", summary: "Connect supported Codex or Claude activity to see working, waiting and finished states.", suggestion: "Use the connection instructions here; choosing a theme doesn't connect an agent."),
            .init(sectionID: "Sports", summary: "Choose favorite teams and leagues, then show scores when games are happening.", suggestion: "You choose which sports to follow."),
            .init(sectionID: "Activities", summary: "Choose which updates appear, set priorities, or turn live activities off.", suggestion: "Start with the sources you use most. Other sources can wait."),
            .init(sectionID: "HUD", summary: "Show volume and brightness changes inside Notchscape.", suggestion: "Replacing the system HUD needs Accessibility access. You can leave it off.")
        ]
        case .workspace: [
            .init(sectionID: "Tools", summary: "Explore quick notes, text recognition, clipboard, capture and other utilities.", suggestion: "Private features such as clipboard history and recording require an explicit choice."),
            .init(sectionID: "Wallpapers", summary: "Browse wallpapers, save favorites and optionally rotate your desktop.", suggestion: "Preview first; Apply changes your wallpaper. Automatic rotation is optional."),
            .init(sectionID: "Shelf", summary: "Keep files close by and choose how drag-and-drop and sharing behave.", suggestion: "Use the Shelf when you need it; your Home layout stays separate."),
            .init(sectionID: "Shortcuts", summary: "Choose keyboard shortcuts for the actions you use often.", suggestion: "Start with one or two shortcuts you will remember.")
        ]
        case .yourMac: [
            .init(sectionID: "System", summary: "Optionally show CPU, memory, storage and thermal information in the System tab.", suggestion: "Stats refresh while that tab is visible. Fan monitoring doesn't override Apple's cooling."),
            .init(sectionID: "Battery", summary: "Choose the original or enhanced battery display, percentage and optional alerts.", suggestion: "The original display remains available if you prefer the simpler look.")
        ]
        case .privacyAndHelp: [
            .init(sectionID: "Advanced", summary: "Find optional experimental controls and troubleshooting settings.", suggestion: "You can leave these unchanged to get started."),
            .init(sectionID: "About", summary: "Check your version and updates, or find help, source and legal information.", suggestion: "Replay this tour from General settings or the Help menu whenever you like."),
            .init(sectionID: "Account", summary: "Manage an optional account and supported appearance sync.", suggestion: "An account is never required to use Notchscape.")
        ]
        }
        return all.filter { accountsEnabled || $0.sectionID != "Account" }
    }
}

/// In-memory navigation. Finishing/skipping carries no preference payload.
struct SettingsTourProgress: Equatable {
    private(set) var index = 0
    private(set) var isFinished = false
    var chapter: SettingsTourChapter { SettingsTourChapter.allCases[index] }
    var isFirst: Bool { index == 0 }
    var isLast: Bool { index == SettingsTourChapter.allCases.count - 1 }
    mutating func next() {
        guard !isFinished else { return }
        if isLast { isFinished = true } else { index += 1 }
    }
    mutating func back() {
        guard !isFinished, !isFirst else { return }
        index -= 1
    }
    mutating func skip() { isFinished = true }
}
