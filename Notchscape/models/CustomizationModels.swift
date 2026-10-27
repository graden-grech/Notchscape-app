import Foundation

/// Music has an explicit opt-in exception to the activity master switch/profile.
/// Its own off switch always wins; this never overrides lock/full-screen rules.
enum MusicPresentationPolicy {
    static func isAllowed(musicEnabled: Bool, overrideEnabled: Bool,
                          liveActivitiesEnabled: Bool, profileAllowsMusic: Bool) -> Bool {
        musicEnabled && (overrideEnabled || (liveActivitiesEnabled && profileAllowsMusic))
    }
}

/// Decorative color choices only. No affiliation is inferred from a user's
/// account, location, or other settings, and Neutral is always the default.
enum WhiteHouseStyle: String, Codable, CaseIterable, Identifiable {
    case neutral, republican, democrat
    var id: Self { self }
    var title: String {
        switch self { case .neutral: "Neutral"; case .republican: "Republican"; case .democrat: "Democrat" }
    }
    var subtitle: String {
        switch self { case .neutral: "Limestone, navy, and gold"; case .republican: "Red décor and warm light"; case .democrat: "Blue décor and cool accents" }
    }
    var lightAccent: String {
        switch self { case .neutral: "#645221"; case .republican: "#B32632"; case .democrat: "#1F62AD" }
    }
    var darkAccent: String {
        switch self { case .neutral: "#DFC891"; case .republican: "#F18B85"; case .democrat: "#79B9FF" }
    }
}

enum WhiteHouseScene: String, Codable, CaseIterable, Identifiable {
    case exterior, ovalOffice, eastRoom, blueRoom
    var id: Self { self }
    var title: String {
        switch self { case .exterior: "Exterior"; case .ovalOffice: "Oval Office"; case .eastRoom: "East Room"; case .blueRoom: "Blue Room" }
    }
    var symbol: String {
        switch self { case .exterior: "building.columns"; case .ovalOffice: "deskclock"; case .eastRoom: "sparkles"; case .blueRoom: "chair.lounge" }
    }
    var backdropName: String {
        switch self {
        case .exterior: "WhiteHouseExteriorBackdrop"
        case .ovalOffice: "WhiteHouseOvalOfficeBackdrop"
        case .eastRoom: "WhiteHouseEastRoomBackdrop"
        case .blueRoom: "WhiteHouseBlueRoomBackdrop"
        }
    }

    /// Every choice resolves to bundled, separately art-directed photography.
    /// Do not tint the whole photograph or fetch an image during theme changes.
    func backdropName(style: WhiteHouseStyle, christmas: Bool) -> String {
        let stem: String = switch self {
        case .exterior: "WhiteHouseExterior"
        case .ovalOffice: "WhiteHouseOvalOffice"
        case .eastRoom: "WhiteHouseEastRoom"
        case .blueRoom: "WhiteHouseBlueRoom"
        }
        let palette: String = switch style {
        case .neutral: ""
        case .republican: "Republican"
        case .democrat: "Democrat"
        }
        return stem + palette + (christmas ? "Christmas" : "") + "Backdrop"
    }
}

/// Each independent style × scene combination is one atomic theme value. That
/// keeps existing accent, Home, icon, recipe and transition observers in sync,
/// without a global red/blue setting that can bleed into unrelated themes.
enum WhiteHouseThemeVariant: String, Codable, CaseIterable, Identifiable {
    case exterior = "whiteHouse"
    case ovalOffice = "whiteHouseOvalOffice"
    case eastRoom = "whiteHouseEastRoom"
    case blueRoom = "whiteHouseBlueRoom"
    case republicanExterior = "whiteHouseRepublican"
    case republicanOvalOffice = "whiteHouseRepublicanOvalOffice"
    case republicanEastRoom = "whiteHouseRepublicanEastRoom"
    case republicanBlueRoom = "whiteHouseRepublicanBlueRoom"
    case democratExterior = "whiteHouseDemocrat"
    case democratOvalOffice = "whiteHouseDemocratOvalOffice"
    case democratEastRoom = "whiteHouseDemocratEastRoom"
    case democratBlueRoom = "whiteHouseDemocratBlueRoom"
    case christmasExterior = "whiteHouseChristmas"
    case christmasOvalOffice = "whiteHouseChristmasOvalOffice"
    case christmasEastRoom = "whiteHouseChristmasEastRoom"
    case christmasBlueRoom = "whiteHouseChristmasBlueRoom"
    case republicanChristmasExterior = "whiteHouseRepublicanChristmas"
    case republicanChristmasOvalOffice = "whiteHouseRepublicanChristmasOvalOffice"
    case republicanChristmasEastRoom = "whiteHouseRepublicanChristmasEastRoom"
    case republicanChristmasBlueRoom = "whiteHouseRepublicanChristmasBlueRoom"
    case democratChristmasExterior = "whiteHouseDemocratChristmas"
    case democratChristmasOvalOffice = "whiteHouseDemocratChristmasOvalOffice"
    case democratChristmasEastRoom = "whiteHouseDemocratChristmasEastRoom"
    case democratChristmasBlueRoom = "whiteHouseDemocratChristmasBlueRoom"
    var id: Self { self }
    var style: WhiteHouseStyle {
        switch self {
        case .exterior, .ovalOffice, .eastRoom, .blueRoom,
             .christmasExterior, .christmasOvalOffice, .christmasEastRoom, .christmasBlueRoom: .neutral
        case .republicanExterior, .republicanOvalOffice, .republicanEastRoom, .republicanBlueRoom,
             .republicanChristmasExterior, .republicanChristmasOvalOffice, .republicanChristmasEastRoom, .republicanChristmasBlueRoom: .republican
        case .democratExterior, .democratOvalOffice, .democratEastRoom, .democratBlueRoom,
             .democratChristmasExterior, .democratChristmasOvalOffice, .democratChristmasEastRoom, .democratChristmasBlueRoom: .democrat
        }
    }
    var scene: WhiteHouseScene {
        switch self {
        case .exterior, .republicanExterior, .democratExterior,
             .christmasExterior, .republicanChristmasExterior, .democratChristmasExterior: .exterior
        case .ovalOffice, .republicanOvalOffice, .democratOvalOffice,
             .christmasOvalOffice, .republicanChristmasOvalOffice, .democratChristmasOvalOffice: .ovalOffice
        case .eastRoom, .republicanEastRoom, .democratEastRoom,
             .christmasEastRoom, .republicanChristmasEastRoom, .democratChristmasEastRoom: .eastRoom
        case .blueRoom, .republicanBlueRoom, .democratBlueRoom,
             .christmasBlueRoom, .republicanChristmasBlueRoom, .democratChristmasBlueRoom: .blueRoom
        }
    }
    var isChristmas: Bool { rawValue.contains("Christmas") }
    var backdropName: String { scene.backdropName(style: style, christmas: isChristmas) }
    /// Room changes retain the same icon family; only palette and Christmas
    /// affect the matching icon. Neutral keeps the existing limestone artwork.
    var matchingIconID: String {
        switch (style, isChristmas) {
        case (.neutral, _): "whiteHouse"
        case (.republican, false): "whiteHouseRepublican"
        case (.democrat, false): "whiteHouseDemocrat"
        case (.republican, true): "whiteHouseRepublicanChristmas"
        case (.democrat, true): "whiteHouseDemocratChristmas"
        }
    }
    init(style: WhiteHouseStyle, scene: WhiteHouseScene, christmas: Bool = false) {
        // The finite cross-product above guarantees exactly one match. Keep a
        // stable default if a future schema is accidentally left incomplete.
        self = Self.allCases.first { $0.style == style && $0.scene == scene && $0.isChristmas == christmas } ?? .exterior
    }
    func selecting(style: WhiteHouseStyle) -> Self { .init(style: style, scene: scene, christmas: isChristmas) }
    func selecting(scene: WhiteHouseScene) -> Self { .init(style: style, scene: scene, christmas: isChristmas) }
    func selecting(christmas: Bool) -> Self { .init(style: style, scene: scene, christmas: christmas) }
}

/// One bundled architectural photo per city. These are atomic theme values,
/// grouped under Cityscapes in Appearance, so selection and restoration use the
/// same Home, accent, icon, and transition observers as every existing theme.
enum CityscapeScene: String, Codable, CaseIterable, Identifiable {
    case newYork = "cityNewYork"
    case chicago = "cityChicago"
    case detroit = "cityDetroit"
    case boston = "cityBoston"
    case philadelphia = "cityPhiladelphia"
    case washingtonDC = "cityWashingtonDC"
    case losAngeles = "cityLosAngeles"
    case sanFrancisco = "citySanFrancisco"
    case seattle = "citySeattle"
    case lasVegas = "cityLasVegas"
    case miami = "cityMiami"
    case newOrleans = "cityNewOrleans"

    var id: Self { self }
    var title: String {
        switch self {
        case .newYork: "New York"
        case .chicago: "Chicago"
        case .detroit: "Detroit"
        case .boston: "Boston"
        case .philadelphia: "Philadelphia"
        case .washingtonDC: "Washington D.C."
        case .losAngeles: "Los Angeles"
        case .sanFrancisco: "San Francisco"
        case .seattle: "Seattle"
        case .lasVegas: "Las Vegas"
        case .miami: "Miami"
        case .newOrleans: "New Orleans"
        }
    }
    var backdropName: String {
        switch self {
        case .newYork: "CityNewYorkBackdrop"
        case .chicago: "CityChicagoBackdrop"
        case .detroit: "CityDetroitBackdrop"
        case .boston: "CityBostonBackdrop"
        case .philadelphia: "CityPhiladelphiaBackdrop"
        case .washingtonDC: "CityWashingtonDCBackdrop"
        case .losAngeles: "CityLosAngelesBackdrop"
        case .sanFrancisco: "CitySanFranciscoBackdrop"
        case .seattle: "CitySeattleBackdrop"
        case .lasVegas: "CityLasVegasBackdrop"
        case .miami: "CityMiamiBackdrop"
        case .newOrleans: "CityNewOrleansBackdrop"
        }
    }
    /// Warm architecture colors retain readable contrast on both control planes.
    /// A manual accent still takes precedence through the shared color resolver.
    var lightAccent: String {
        switch self {
        case .newYork, .washingtonDC: "#645221"
        case .chicago, .philadelphia: "#5C5532"
        case .detroit, .boston: "#664D2F"
        case .losAngeles, .lasVegas: "#6A4C2B"
        case .sanFrancisco, .newOrleans: "#68503A"
        case .seattle, .miami: "#5E5737"
        }
    }
    var darkAccent: String {
        switch self {
        case .newYork, .washingtonDC: "#DFC891"
        case .chicago, .philadelphia: "#D9CC9B"
        case .detroit, .boston: "#E2BF95"
        case .losAngeles, .lasVegas: "#E7C28C"
        case .sanFrancisco, .newOrleans: "#DFC2A0"
        case .seattle, .miami: "#D8CEAA"
        }
    }
}

enum StarWarsThemeCategory: String, CaseIterable, Identifiable {
    case jedi, darkSide, characters
    var id: Self { self }
    var title: String {
        switch self { case .jedi: "Jedi"; case .darkSide: "Dark Side"; case .characters: "Characters" }
    }
}

enum StarWarsCharacterArtwork: String, Codable, CaseIterable, Identifiable {
    case lightsaber, character
    var id: Self { self }
    var title: String { self == .lightsaber ? "Lightsaber" : "Character" }
}

/// Each variant is a real theme value so existing accent, Home, and animation
/// observers update together. The picker groups them under one Star Wars card.
enum StarWarsThemeVariant: String, Codable, CaseIterable, Identifiable {
    case jedi = "starWars"
    case darkSide = "starWarsDarkSide"
    case luke = "starWarsLuke"
    case obiWan = "starWarsObiWan"
    case ahsoka = "starWarsAhsoka"
    case yoda = "starWarsYoda"
    case maceWindu = "starWarsMaceWindu"
    case rey = "starWarsRey"
    case vader = "starWarsVader"
    case maul = "starWarsMaul"
    var id: Self { self }
    var category: StarWarsThemeCategory {
        switch self { case .jedi: .jedi; case .darkSide: .darkSide; default: .characters }
    }
    static var characters: [Self] { allCases.filter { $0.category == .characters } }
    var title: String {
        switch self {
        case .jedi: "Jedi"
        case .darkSide: "Dark Side"
        case .luke: "Luke Skywalker"
        case .obiWan: "Obi-Wan Kenobi"
        case .ahsoka: "Ahsoka Tano"
        case .yoda: "Yoda"
        case .maceWindu: "Mace Windu"
        case .rey: "Rey"
        case .vader: "Darth Vader"
        case .maul: "Darth Maul"
        }
    }
    var colorName: String {
        switch self {
        case .jedi, .obiWan: "Azure"
        case .darkSide, .vader, .maul: "Crimson"
        case .luke, .yoda: "Emerald"
        case .ahsoka: "Pearl"
        case .maceWindu: "Amethyst"
        case .rey: "Golden"
        }
    }
    var rgb: (red: Double, green: Double, blue: Double) {
        switch self {
        case .jedi, .obiWan: (0.20, 0.65, 1)
        case .darkSide, .vader, .maul: (1, 0.20, 0.25)
        case .luke, .yoda: (0.28, 0.92, 0.46)
        case .ahsoka: (0.86, 0.95, 1)
        case .maceWindu: (0.75, 0.38, 1)
        case .rey: (1, 0.78, 0.22)
        }
    }
    var backdropName: String {
        switch self {
        case .darkSide, .vader, .maul: "StarWarsDarkSideBackdrop"
        case .luke, .obiWan, .rey: "StarWarsDesertBackdrop"
        default: "StarWarsJediBackdrop"
        }
    }
    var supportsCharacterArtwork: Bool { self == .vader }
    func backdropName(artwork: StarWarsCharacterArtwork, characterArtworkAvailable: Bool = true) -> String {
        if supportsCharacterArtwork && artwork == .character && characterArtworkAvailable { return "StarWarsVaderSceneBackdrop" }
        return backdropName
    }
}

enum LightsaberColorMode: String, Codable, CaseIterable, Identifiable {
    case theme, albumArtwork, custom
    var id: Self { self }
    var title: String {
        switch self { case .theme: "Theme / character"; case .albumArtwork: "Album cover"; case .custom: "Custom color" }
    }
}

/// Shared by drawing, scrubbing, and keyboard/VoiceOver adjustment.
enum LightsaberTrackPolicy {
    static func progress(value: Double, duration: Double) -> Double {
        guard value.isFinite, duration.isFinite, duration > 0 else { return 0 }
        return min(1, max(0, value / duration))
    }
    static func time(at x: Double, width: Double, duration: Double) -> Double? {
        guard x.isFinite, width.isFinite, width > 0, duration.isFinite, duration > 0 else { return nil }
        return min(1, max(0, x / width)) * duration
    }
}

/// Locked windows must never reuse the normal Home/Shelf/Live view hierarchy.
enum NotchLockScreenPresentation: Equatable {
    case normal, hidden, lockedHome

    static func resolve(isLocked: Bool, enabled: Bool, preview: Bool = false) -> Self {
        if isLocked { return enabled ? .lockedHome : .hidden }
        return preview ? .lockedHome : .normal
    }
}

struct NotchDisplayDestination: Equatable {
    let id: String
    let isBuiltIn: Bool
}

/// Hardware visibility is local to each Mac; it is never restored from an account.
enum NotchDisplayPolicy {
    static func eligible(_ displays: [NotchDisplayDestination], showExternal: Bool) -> [NotchDisplayDestination] {
        displays.filter { showExternal || $0.isBuiltIn }
    }

    static func selectedID(in displays: [NotchDisplayDestination], preferred: String?, main: String?,
                           automaticallySwitch: Bool, showExternal: Bool) -> String? {
        let available = eligible(displays, showExternal: showExternal)
        if let preferred, available.contains(where: { $0.id == preferred }) { return preferred }
        // An external preference is retained for later, but cannot defeat the
        // explicit external-display off switch, even with automatic switching off.
        if !showExternal { return available.first(where: \.isBuiltIn)?.id }
        if automaticallySwitch, let main, available.contains(where: { $0.id == main }) { return main }
        return nil
    }
}

enum HomeWidget: String, Codable, CaseIterable, Identifiable {
    case music, calendar, weather, quickActions
    var id: Self { self }
    var title: String {
        switch self {
        case .music: "Music"
        case .calendar: "Calendar"
        case .weather: "Weather"
        case .quickActions: "Quick Actions"
        }
    }
    var symbol: String {
        switch self {
        case .music: "music.note"
        case .calendar: "calendar"
        case .weather: "cloud.sun"
        case .quickActions: "bolt.fill"
        }
    }
}

enum HomeLayoutPolicy {
    static func normalized(_ order: [HomeWidget], legacyWeatherPosition: String) -> [HomeWidget] {
        let legacy: [HomeWidget]
        switch legacyWeatherPosition {
        case "front": legacy = [.weather, .music, .calendar, .quickActions]
        case "afterMusic": legacy = [.music, .weather, .calendar, .quickActions]
        default: legacy = HomeWidget.allCases
        }
        var result: [HomeWidget] = []
        for widget in (order.isEmpty ? legacy : order) + HomeWidget.allCases where !result.contains(widget) {
            result.append(widget)
        }
        return result
    }

    static func moved(_ widget: HomeWidget, by delta: Int, in order: [HomeWidget]) -> [HomeWidget] {
        guard let index = order.firstIndex(of: widget), order.indices.contains(index + delta) else { return order }
        var result = order
        result.swapAt(index, index + delta)
        return result
    }
    static func reordered(_ widget: HomeWidget, over target: HomeWidget, in order: [HomeWidget]) -> [HomeWidget] {
        guard widget != target, let source = order.firstIndex(of: widget), let destination = order.firstIndex(of: target) else { return order }
        var result = order
        result.remove(at: source)
        result.insert(widget, at: destination)
        return result
    }
}

enum NotchTabLayoutPolicy {
    static func index(at x: Double, width: Double, count: Int) -> Int? {
        guard count > 0, width > 0, x.isFinite, width.isFinite else { return nil }
        return max(0, min(count - 1, Int(max(0, min(width, x)) / width * Double(count))))
    }
}

enum SeasonHemisphere: String, Codable, CaseIterable, Identifiable {
    case northern, southern
    var id: Self { self }
    var title: String { self == .northern ? "Northern Hemisphere" : "Southern Hemisphere" }
}

enum SeasonalThemeSchedule {
    /// Western/Gregorian Easter; holiday switching remains explicitly opt-in.
    static func easterComponents(year: Int) -> DateComponents? {
        guard (1583...9999).contains(year) else { return nil }
        let a = year % 19, b = year / 100, c = year % 100
        let d = b / 4, e = b % 4, f = (b + 8) / 25
        let g = (b - f + 1) / 3
        let h = (19 * a + b - d - g + 15) % 30
        let i = c / 4, k = c % 4
        let l = (32 + 2 * e + 2 * i - h - k) % 7
        let m = (a + 11 * h + 22 * l) / 451
        return DateComponents(year: year, month: (h + l - 7 * m + 114) / 31, day: (h + l - 7 * m + 114) % 31 + 1)
    }
    static func themeName(date: Date, hemisphere: SeasonHemisphere, halloween: Bool, christmas: Bool,
                          easter: Bool, calendar: Calendar = .current) -> String {
        var calendar = calendar
        if calendar.identifier != .gregorian { calendar = Calendar(identifier: .gregorian) }
        let components = calendar.dateComponents([.year, .month, .day], from: date)
        if easter, let year = components.year, let day = easterComponents(year: year), let holiday = calendar.date(from: day) {
            let distance = calendar.dateComponents([.day], from: holiday, to: calendar.startOfDay(for: date)).day ?? Int.max
            if (-7...1).contains(distance) { return "easter" }
        }
        return themeName(month: components.month ?? 1, day: components.day ?? 1, hemisphere: hemisphere, halloween: halloween, christmas: christmas)
    }
    /// Explicit, testable schedule. Holiday themes are optional in either hemisphere.
    static func themeName(month: Int, day: Int, hemisphere: SeasonHemisphere, halloween: Bool, christmas: Bool) -> String {
        if halloween && month == 10 && day >= 15 { return "halloween" }
        if christmas && month == 12 && day <= 26 { return "christmas" }
        let seasonalMonth = hemisphere == .northern ? month : ((month + 5) % 12) + 1
        switch seasonalMonth {
        case 9...11: return "autumn"
        case 12, 1, 2: return "winter"
        default: return "system"
        }
    }
}

enum AppPerformanceMode: String, Codable, CaseIterable, Identifiable {
    case balanced, lowImpact, automatic
    var id: Self { self }
    var title: String {
        switch self {
        case .balanced: "Balanced"
        case .lowImpact: "Low impact"
        case .automatic: "Automatic on battery"
        }
    }
    func isLowImpact(onBattery: Bool, systemLowPower: Bool) -> Bool {
        self == .lowImpact || (self == .automatic && (onBattery || systemLowPower))
    }
}

enum QuickActionKind: String, Codable { case application, shortcut }

struct NotchQuickAction: Codable, Identifiable, Equatable {
    var id = UUID()
    var name: String
    var kind: QuickActionKind
    var target: String
    var symbol: String { kind == .application ? "app.fill" : "bolt.fill" }
}

struct AgentHistoryEntry: Codable, Identifiable, Equatable {
    var id: UUID
    var provider: String
    var title: String
    var state: AgentActivityState
    var startedAt: Date
    var endedAt: Date
}

enum BatteryPresentationStyle: String, Codable, CaseIterable, Identifiable {
    case original, enhanced
    var id: Self { self }
    var title: String { self == .original ? "Original" : "Enhanced" }
}

enum BatteryIndicatorDisplay: String, Codable, CaseIterable, Identifiable {
    case iconOnly, percentageOnly, both
    var id: Self { self }
    var title: String {
        switch self {
        case .iconOnly: "Icon only"
        case .percentageOnly: "Percentage only"
        case .both: "Icon and percentage"
        }
    }
}

struct BatteryReading: Equatable {
    var level: Double
    var pluggedIn: Bool
    var charging: Bool
    var fullyCharged: Bool
    var status: String {
        if charging { return "Charging" }
        if pluggedIn { return fullyCharged ? "Fully charged" : "Connected to power · Not charging" }
        return "On battery"
    }
}

enum BatteryAlertKind: String {
    case low20, low10, full
    var title: String {
        switch self {
        case .low20: "Battery at 20% or lower"
        case .low10: "Battery at 10% or lower"
        case .full: "Battery fully charged"
        }
    }
}

enum BatteryPolicy {
    static func symbol(level: Double, charging: Bool) -> String {
        if charging { return "battery.100percent.bolt" }
        switch level {
        case ..<12.5: return "battery.0percent"
        case ..<37.5: return "battery.25percent"
        case ..<62.5: return "battery.50percent"
        case ..<87.5: return "battery.75percent"
        default: return "battery.100percent"
        }
    }
    static func shouldShow(enabled: Bool, hasBattery: Bool, hideWhenAbsent: Bool) -> Bool {
        enabled && (hasBattery || !hideWhenAbsent)
    }
    static func percentage(current: Double, maximum: Double) -> Double? {
        guard current.isFinite, maximum.isFinite, current >= 0, maximum > 0 else { return nil }
        return min(100, max(0, current / maximum * 100))
    }
    static func alert(from old: BatteryReading?, to new: BatteryReading,
                      low20: Bool, low10: Bool, full: Bool) -> BatteryAlertKind? {
        guard let old else { return nil }
        if full && new.pluggedIn && new.fullyCharged && !old.fullyCharged { return .full }
        guard !new.pluggedIn, !new.charging else { return nil }
        if low10 && old.level > 10 && new.level <= 10 { return .low10 }
        if low20 && old.level > 20 && new.level <= 20 { return .low20 }
        return nil
    }
}

struct BatteryHistorySample: Codable, Equatable, Identifiable {
    var date: Date
    var level: Double
    var pluggedIn: Bool
    var id: Date { date }
}

enum BatteryHistoryPolicy {
    static func retained(_ samples: [BatteryHistorySample], now: Date) -> [BatteryHistorySample] {
        Array(samples.filter { $0.date <= now && now.timeIntervalSince($0.date) <= 86400
            && $0.level.isFinite && (0...100).contains($0.level) }.sorted { $0.date < $1.date }.suffix(512))
    }
    static func adding(_ sample: BatteryHistorySample, to samples: [BatteryHistorySample]) -> [BatteryHistorySample] {
        var result = retained(samples, now: sample.date)
        if let last = result.last, last.level == sample.level, last.pluggedIn == sample.pluggedIn,
           sample.date.timeIntervalSince(last.date) < 300 { return result }
        result.append(sample)
        return Array(result.suffix(512))
    }
}
