//
//  Constants.swift
//  Notchscape
//
//  Created by Richard Kunkli on 2024. 10. 17..
//

import SwiftUI
import Defaults

extension HomeWidget: Defaults.Serializable {}
extension SeasonHemisphere: Defaults.Serializable {}
extension AppPerformanceMode: Defaults.Serializable {}
extension NotchQuickAction: Defaults.Serializable {}
extension AgentHistoryEntry: Defaults.Serializable {}
extension BatteryPresentationStyle: Defaults.Serializable {}
extension BatteryIndicatorDisplay: Defaults.Serializable {}
extension BatteryHistorySample: Defaults.Serializable {}
extension StarWarsThemeVariant: Defaults.Serializable {}
extension StarWarsCharacterArtwork: Defaults.Serializable {}
extension LightsaberColorMode: Defaults.Serializable {}

private let availableDirectories = FileManager
    .default
    .urls(for: .documentDirectory, in: .userDomainMask)
let documentsDirectory = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
let bundleIdentifier = Bundle.main.bundleIdentifier!
let appVersion = "\(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "") (\(Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? ""))"

let temporaryDirectory = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first!
let spacing: CGFloat = 16

struct CustomVisualizer: Codable, Hashable, Equatable, Defaults.Serializable {
    let UUID: UUID
    var name: String
    var url: URL
    var speed: CGFloat = 1.0
}

enum CalendarSelectionState: Codable, Defaults.Serializable {
    case all
    case selected(Set<String>)
}

enum HideNotchOption: String, Defaults.Serializable {
    case always
    case nowPlayingOnly
    case never
}

// Define notification names at file scope
extension Notification.Name {
    static let mediaControllerChanged = Notification.Name("mediaControllerChanged")
}

// Media controller types for selection in settings
enum MediaControllerType: String, CaseIterable, Identifiable, Defaults.Serializable {
    case nowPlaying = "Now Playing"
    case appleMusic = "Apple Music"
    case spotify = "Spotify"
    case youtubeMusic = "YouTube Music"
    
    var id: String { self.rawValue }
}

// Sneak peek styles for selection in settings
enum SneakPeekStyle: String, CaseIterable, Identifiable, Defaults.Serializable {
    case standard = "Default"
    case inline = "Inline"
    
    var id: String { self.rawValue }
}

// Action to perform when Option (⌥) is held while pressing media keys
enum OptionKeyAction: String, CaseIterable, Identifiable, Defaults.Serializable {
    case openSettings = "Open System Settings"
    case showHUD = "Show HUD"
    case none = "No Action"

    var id: String { self.rawValue }
}

extension Defaults.Keys {
    // Optional local tools. Private content is never stored in Defaults/sync.
    static let showToolsTab = Key<Bool>("showToolsTab", default: false)
    static let showWallpapersTab = Key<Bool>("showWallpapersTab", default: false)
    static let clipboardHistoryEnabled = Key<Bool>("clipboardHistoryEnabled", default: false)
    static let clipboardRetentionDays = Key<Int>("clipboardRetentionDays", default: 7)
    static let clipboardExcludedApps = Key<String>("clipboardExcludedApps", default: "")
    static let quickNotesEnabled = Key<Bool>("quickNotesEnabled", default: false)
    static let appleNotesSyncEnabled = Key<Bool>("appleNotesSyncEnabled", default: false)
    static let seasonalEaster = Key<Bool>("seasonalEaster", default: false)
    static let deviceControlsEnabled = Key<Bool>("deviceControlsEnabled", default: false)
    static let deviceConnectionAlerts = Key<Bool>("deviceConnectionAlerts", default: false)
    static let deviceLowBatteryAlerts = Key<Bool>("deviceLowBatteryAlerts", default: false)
    static let deviceLowBatteryThreshold = Key<Int>("deviceLowBatteryThreshold", default: 20)
    static let preferredAudioRouting = Key<Bool>("preferredAudioRouting", default: false)
    static let textCaptureEnabled = Key<Bool>("textCaptureEnabled", default: false)
    static let agentUsageEnabled = Key<Bool>("agentUsageEnabled", default: false)
    // MARK: General
    static let menubarIcon = Key<Bool>("menubarIcon", default: true)
    static let showDockIcon = Key<Bool>("showDockIcon", default: true)
    static let showOnAllDisplays = Key<Bool>("showOnAllDisplays", default: true)
    static let showOnExternalDisplays = Key<Bool>("showOnExternalDisplays", default: true)
    static let automaticallySwitchDisplay = Key<Bool>("automaticallySwitchDisplay", default: true)
    static let releaseName = Key<String>("releaseName", default: "Flying Rabbit 🐇🪽")
    
    // MARK: Behavior
    static let minimumHoverDuration = Key<TimeInterval>("minimumHoverDuration", default: 0.3)
    static let enableHaptics = Key<Bool>("enableHaptics", default: true)
    static let openNotchOnHover = Key<Bool>("openNotchOnHover", default: true)
    static let extendHoverArea = Key<Bool>("extendHoverArea", default: false)
    static let notchHeightMode = Key<WindowHeightMode>(
        "notchHeightMode",
        default: WindowHeightMode.matchRealNotchSize
    )
    static let nonNotchHeightMode = Key<WindowHeightMode>(
        "nonNotchHeightMode",
        default: WindowHeightMode.matchMenuBar
    )
    static let nonNotchHeight = Key<CGFloat>("nonNotchHeight", default: 32)
    static let nonNotchPresentation = Key<NonNotchPresentation>(
        "nonNotchPresentation",
        default: .dynamicIsland
    )
    static let notchHeight = Key<CGFloat>("notchHeight", default: 32)
    //static let openLastTabByDefault = Key<Bool>("openLastTabByDefault", default: false)
    static let showOnLockScreen = Key<Bool>("showOnLockScreen", default: false)
    static let hideFromScreenRecording = Key<Bool>("hideFromScreenRecording", default: false)
    
    // MARK: Appearance
    static let showEmojis = Key<Bool>("showEmojis", default: false)
    //static let alwaysShowTabs = Key<Bool>("alwaysShowTabs", default: true)
    static let showMirror = Key<Bool>("showMirror", default: false)
    static let mirrorShape = Key<MirrorShapeEnum>("mirrorShape", default: MirrorShapeEnum.rectangle)
    static let systemDashboardEnabled = Key<Bool>("systemDashboardEnabled", default: false)
    static let settingsIconInNotch = Key<Bool>("settingsIconInNotch", default: true)
    static let lightingEffect = Key<Bool>("lightingEffect", default: true)
    static let enableShadow = Key<Bool>("enableShadow", default: true)
    static let cornerRadiusScaling = Key<Bool>("cornerRadiusScaling", default: true)
    static let appIconVariant = Key<AppIconVariant>("appIconVariant", default: .standard)
    static let appIconFollowsTheme = Key<Bool>("appIconFollowsTheme", default: true)
    static let appTheme = Key<AppTheme>("appTheme", default: .system)
    static let whiteHousePreferredVariant = Key<WhiteHouseThemeVariant>("whiteHousePreferredVariant", default: .exterior)
    static let themeDetailsEnabled = Key<Bool>("themeDetailsEnabled", default: false)
    static let starWarsPreferredCharacter = Key<StarWarsThemeVariant>("starWarsPreferredCharacter", default: .luke)
    static let starWarsVaderArtwork = Key<StarWarsCharacterArtwork>("starWarsVaderArtwork", default: .lightsaber)
    static let lightsaberMusicBar = Key<Bool>("lightsaberMusicBar", default: true)
    static let lightsaberColorMode = Key<LightsaberColorMode>("lightsaberColorMode", default: .theme)
    static let lightsaberCustomColorData = Key<Data?>("lightsaberCustomColorData", default: nil)
    static let homeWidgetOrder = Key<[HomeWidget]>("homeWidgetOrder", default: [])
    static let hiddenHomeWidgets = Key<Set<HomeWidget>>("hiddenHomeWidgets", default: [])
    static let quickActions = Key<[NotchQuickAction]>("quickActions", default: [])
    static let automaticSeasonalThemes = Key<Bool>("automaticSeasonalThemes", default: false)
    static let seasonHemisphere = Key<SeasonHemisphere>("seasonHemisphere", default: .northern)
    static let seasonalHalloween = Key<Bool>("seasonalHalloween", default: false)
    static let seasonalChristmas = Key<Bool>("seasonalChristmas", default: false)
    static let performanceMode = Key<AppPerformanceMode>("performanceMode", default: .balanced)
    static let agentHistoryEnabled = Key<Bool>("agentHistoryEnabled", default: false)
    static let agentHistory = Key<[AgentHistoryEntry]>("agentHistory", default: [])

    static let showNotHumanFace = Key<Bool>("showNotHumanFace", default: false)
    static let tileShowLabels = Key<Bool>("tileShowLabels", default: false)
    static let showCalendar = Key<Bool>("showCalendar", default: false)
    static let hideCompletedReminders = Key<Bool>("hideCompletedReminders", default: true)
    static let sliderColor = Key<SliderColorEnum>(
        "sliderUseAlbumArtColor",
        default: SliderColorEnum.white
    )
    static let playerColorTinting = Key<Bool>("playerColorTinting", default: true)
    static let useMusicVisualizer = Key<Bool>("useMusicVisualizer", default: true)
    static let customVisualizers = Key<[CustomVisualizer]>("customVisualizers", default: [])
    static let selectedVisualizer = Key<CustomVisualizer?>("selectedVisualizer", default: nil)
    
    // MARK: Gestures
    static let enableGestures = Key<Bool>("enableGestures", default: true)
    static let closeGestureEnabled = Key<Bool>("closeGestureEnabled", default: true)
    static let gestureSensitivity = Key<CGFloat>("gestureSensitivity", default: 200.0)
    
    // MARK: Media playback
    static let coloredSpectrogram = Key<Bool>("coloredSpectrogram", default: true)
    static let enableSneakPeek = Key<Bool>("enableSneakPeek", default: false)
    static let sneakPeekStyles = Key<SneakPeekStyle>("sneakPeekStyles", default: .standard)
    static let waitInterval = Key<Double>("waitInterval", default: 3)
    static let showShuffleAndRepeat = Key<Bool>("showShuffleAndRepeat", default: false)
    static let enableLyrics = Key<Bool>("enableLyrics", default: false)
    static let musicControlSlots = Key<[MusicControlButton]>(
        "musicControlSlots",
        default: MusicControlButton.defaultLayout
    )
    static let musicControlSlotLimit = Key<Int>(
        "musicControlSlotLimit",
        default: MusicControlButton.defaultLayout.count
    )
    
    // MARK: Battery
    static let showPowerStatusNotifications = Key<Bool>("showPowerStatusNotifications", default: true)
    static let showBatteryIndicator = Key<Bool>("showBatteryIndicator", default: true)
    static let showBatteryPercentage = Key<Bool>("showBatteryPercentage", default: true)
    static let showPowerStatusIcons = Key<Bool>("showPowerStatusIcons", default: true)
    static let batteryPresentation = Key<BatteryPresentationStyle>("batteryPresentation", default: .original)
    static let batteryIndicatorDisplay = Key<BatteryIndicatorDisplay>("batteryIndicatorDisplay", default: .both)
    static let hideBatteryWhenAbsent = Key<Bool>("hideBatteryWhenAbsent", default: true)
    static let batteryAlert20 = Key<Bool>("batteryAlert20", default: false)
    static let batteryAlert10 = Key<Bool>("batteryAlert10", default: false)
    static let batteryAlertFull = Key<Bool>("batteryAlertFull", default: false)
    static let batteryHistoryEnabled = Key<Bool>("batteryHistoryEnabled", default: true)
    static let batteryHistory = Key<[BatteryHistorySample]>("batteryHistory", default: [])
    
    // MARK: Downloads
    static let enableDownloadListener = Key<Bool>("enableDownloadListener", default: true)
    static let enableSafariDownloads = Key<Bool>("enableSafariDownloads", default: true)
    static let selectedDownloadIndicatorStyle = Key<DownloadIndicatorStyle>("selectedDownloadIndicatorStyle", default: DownloadIndicatorStyle.progress)
    static let selectedDownloadIconStyle = Key<DownloadIconStyle>("selectedDownloadIconStyle", default: DownloadIconStyle.onlyAppIcon)
    
    // MARK: HUD
    static let hudReplacement = Key<Bool>("hudReplacement", default: true)
    static let inlineHUD = Key<Bool>("inlineHUD", default: false)
    static let enableGradient = Key<Bool>("enableGradient", default: false)
    static let systemEventIndicatorShadow = Key<Bool>("systemEventIndicatorShadow", default: false)
    static let systemEventIndicatorUseAccent = Key<Bool>("systemEventIndicatorUseAccent", default: false)
    static let showOpenNotchHUD = Key<Bool>("showOpenNotchHUD", default: true)
    static let showOpenNotchHUDPercentage = Key<Bool>("showOpenNotchHUDPercentage", default: true)
    static let showClosedNotchHUDPercentage = Key<Bool>("showClosedNotchHUDPercentage", default: false)
    // Option key modifier behaviour for media keys
    static let optionKeyAction = Key<OptionKeyAction>("optionKeyAction", default: OptionKeyAction.openSettings)
    
    // MARK: Shelf
    static let boringShelf = Key<Bool>("boringShelf", default: true)
    static let openShelfByDefault = Key<Bool>("openShelfByDefault", default: true)
    static let shelfTapToOpen = Key<Bool>("shelfTapToOpen", default: true)
    static let quickShareProvider = Key<String>("quickShareProvider", default: QuickShareProvider.defaultProvider.id)
    static let copyOnDrag = Key<Bool>("copyOnDrag", default: false)
    static let autoRemoveShelfItems = Key<Bool>("autoRemoveShelfItems", default: false)
    static let expandedDragDetection = Key<Bool>("expandedDragDetection", default: true)
    
    // MARK: Calendar
    static let calendarSelectionState = Key<CalendarSelectionState>("calendarSelectionState", default: .all)
    static let hideAllDayEvents = Key<Bool>("hideAllDayEvents", default: false)
    static let showFullEventTitles = Key<Bool>("showFullEventTitles", default: false)
    static let autoScrollToNextEvent = Key<Bool>("autoScrollToNextEvent", default: true)
    static let calendarAlertsEnabled = Key<Bool>("calendarAlertsEnabled", default: true)
    static let calendarAlertLeadMinutes = Key<Int>("calendarAlertLeadMinutes", default: 10)

    // MARK: Live dashboard
    static let liveActivitiesEnabled = Key<Bool>("liveActivitiesEnabled", default: true)
    static let musicActivityOverride = Key<Bool>("musicActivityOverride", default: false)
    static let activityProfile = Key<ActivityProfile>("activityProfile", default: .everything)
    static let privacyActivitiesEnabled = Key<Bool>("privacyActivitiesEnabled", default: true)
    static let weatherAlertsEnabled = Key<Bool>("weatherAlertsEnabled", default: true)
    static let timerActivitiesEnabled = Key<Bool>("timerActivitiesEnabled", default: true)
    static let agentStatusEnabled = Key<Bool>("agentStatusEnabled", default: true)
    static let liveActivityPriority = Key<LiveActivityPriority>("liveActivityPriority", default: .combined)
    static let sportsActivitiesEnabled = Key<Bool>("sportsActivitiesEnabled", default: false)
    static let sportsLeague = Key<SportsLeague>("sportsLeague", default: .nba)
    static let sportsFavoriteTeam = Key<String>("sportsFavoriteTeam", default: "")
    static let sportsEnabledLeagues = Key<Set<SportsLeague>>("sportsEnabledLeagues", default: [.nba])
    static let sportsFavoriteTeams = Key<Set<String>>("sportsFavoriteTeams", default: [])
    static let sportsScoreNotificationsEnabled = Key<Bool>("sportsScoreNotificationsEnabled", default: true)
    static let sportsShowUpcoming = Key<Bool>("sportsShowUpcoming", default: true)
    static let weatherEnabled = Key<Bool>("weatherEnabled", default: false)
    static let weatherUseCurrentLocation = Key<Bool>("weatherUseCurrentLocation", default: true)
    static let weatherOnLiveTab = Key<Bool>("weatherOnLiveTab", default: false)
    static let weatherTilePosition = Key<WeatherTilePosition>("weatherTilePosition", default: .afterMusic)
    static let weatherLocation = Key<String>("weatherLocation", default: "")
    static let weatherUseCelsius = Key<Bool>("weatherUseCelsius", default: false)
    
    // MARK: Fullscreen Media Detection
    static let hideNotchOption = Key<HideNotchOption>("hideNotchOption", default: .nowPlayingOnly)
    
    // MARK: Media Controller
    static let mediaController = Key<MediaControllerType>("mediaController", default: defaultMediaController)
    
    // MARK: Advanced Settings
    static let useCustomAccentColor = Key<Bool>("useCustomAccentColor", default: false)
    static let customAccentColorData = Key<Data?>("customAccentColorData", default: nil)
    // Show or hide the title bar
    static let hideTitleBar = Key<Bool>("hideTitleBar", default: true)
    
    // Helper to determine the default media controller based on NowPlaying deprecation status
    static var defaultMediaController: MediaControllerType {
        if MusicManager.shared.isNowPlayingDeprecated {
            return .appleMusic
        } else {
            return .nowPlaying
        }
    }

    static let didClearLegacyURLCacheV1 = Key<Bool>("didClearLegacyURLCache_v1", default: false)
}
