//
//  generic.swift
//  Notchscape
//
//  Created by Harsh Vardhan  Goswami  on 04/08/24.
//

import Foundation
import Defaults
import AppKit

public enum Style {
    case notch
    case floating
}

public enum ContentType: Int, Codable, Hashable, Equatable {
    case normal
    case menu
    case settings
}

public enum NotchState {
    case closed
    case open
}

public enum NotchViews {
    case home
    case shelf
    case live
    case system
    case tools
    case wallpapers
}

enum SettingsEnum {
    case general
    case about
    case charge
    case download
    case mediaPlayback
    case hud
    case shelf
    case extensions
}

enum DownloadIndicatorStyle: String, Defaults.Serializable {
    case progress = "Progress"
    case percentage = "Percentage"
}

enum DownloadIconStyle: String, Defaults.Serializable {
    case onlyAppIcon = "Only app icon"
    case onlyIcon = "Only download icon"
    case iconAndAppIcon = "Icon and app icon"
}

enum MirrorShapeEnum: String, Defaults.Serializable {
    case rectangle = "Rectangular"
    case circle = "Circular"
    case roundedRectangle = "Rounded Rectangle"
    case squircle = "Squircle"
    case capsule = "Capsule"
}

enum WindowHeightMode: String, Defaults.Serializable {
    case matchMenuBar = "Match menubar height"
    case matchRealNotchSize = "Match real notch height"
    case custom = "Custom height"
}

enum NonNotchPresentation: String, CaseIterable, Defaults.Serializable, Identifiable {
    case dynamicIsland
    case notch

    var id: Self { self }

    var title: String {
        switch self {
        case .dynamicIsland: "Dynamic Island"
        case .notch: "Notch"
        }
    }
}

enum AppIconVariant: String, CaseIterable, Defaults.Serializable, Identifiable {
    case standard
    case autumn
    case halloween
    case christmas
    case winter
    case easter
    case whiteHouse
    case whiteHouseRepublican
    case whiteHouseDemocrat
    case whiteHouseRepublicanChristmas
    case whiteHouseDemocratChristmas

    var id: Self { self }

    var title: String {
        switch self {
        case .standard: "Standard"
        case .autumn: "Fall"
        case .halloween: "Halloween"
        case .christmas: "Christmas"
        case .winter: "Winter"
        case .easter: "Easter"
        case .whiteHouse: "White House"
        case .whiteHouseRepublican: "White House · Republican"
        case .whiteHouseDemocrat: "White House · Democrat"
        case .whiteHouseRepublicanChristmas: "White House · Republican Christmas"
        case .whiteHouseDemocratChristmas: "White House · Democrat Christmas"
        }
    }

    var isWhiteHouse: Bool {
        switch self {
        case .whiteHouse, .whiteHouseRepublican, .whiteHouseDemocrat,
             .whiteHouseRepublicanChristmas, .whiteHouseDemocratChristmas: true
        default: false
        }
    }

    var pickerTitle: String {
        switch self {
        case .whiteHouse: "Neutral"
        case .whiteHouseRepublican: "Republican"
        case .whiteHouseDemocrat: "Democrat"
        case .whiteHouseRepublicanChristmas: "Republican\nChristmas"
        case .whiteHouseDemocratChristmas: "Democrat\nChristmas"
        default: title
        }
    }

    var assetName: String {
        switch self {
        case .standard: "AppIconStandard"
        case .autumn: "AppIconAutumn"
        case .halloween: "AppIconHalloween"
        case .christmas: "AppIconChristmas"
        case .winter: "AppIconWinter"
        case .easter: "AppIconEaster"
        case .whiteHouse: "AppIconWhiteHouse"
        case .whiteHouseRepublican: "AppIconWhiteHouseRepublican"
        case .whiteHouseDemocrat: "AppIconWhiteHouseDemocrat"
        case .whiteHouseRepublicanChristmas: "AppIconWhiteHouseRepublicanChristmas"
        case .whiteHouseDemocratChristmas: "AppIconWhiteHouseDemocratChristmas"
        }
    }

    @MainActor
    func apply() {
        // Theme changes and startup must not touch a hidden Dock tile. The
        // saved icon choice is applied when Dock visibility is re-enabled.
        guard Defaults[.showDockIcon], NSApp.activationPolicy() == .regular else { return }
        guard let image = NSImage(named: assetName) else { return }
        if self == .autumn || self == .halloween {
            // Legacy seasonal artwork has a square backdrop. Apply a rounded
            // silhouette when drawing the Dock representation, preserving alpha.
            let icon = NSImage(size: NSSize(width: 1024, height: 1024))
            icon.lockFocus()
            NSBezierPath(roundedRect: NSRect(x: 80, y: 80, width: 864, height: 864), xRadius: 190, yRadius: 190).addClip()
            image.draw(in: NSRect(x: 0, y: 0, width: 1024, height: 1024))
            icon.unlockFocus()
            NSApp.applicationIconImage = icon
        } else {
            NSApp.applicationIconImage = image
        }
    }
}

enum AppTheme: String, CaseIterable, Defaults.Serializable, Identifiable {
    case system
    case autumn
    case halloween
    case christmas
    case winter
    case easter
    case springBloom, summerCoast, nightSky, botanical, desertDusk, graphite
    case starWars, starWarsDarkSide, starWarsLuke, starWarsObiWan
    case starWarsAhsoka, starWarsYoda, starWarsMaceWindu, starWarsRey, starWarsVader, starWarsMaul
    case whiteHouse, whiteHouseOvalOffice, whiteHouseEastRoom, whiteHouseBlueRoom
    case whiteHouseRepublican, whiteHouseRepublicanOvalOffice, whiteHouseRepublicanEastRoom, whiteHouseRepublicanBlueRoom
    case whiteHouseDemocrat, whiteHouseDemocratOvalOffice, whiteHouseDemocratEastRoom, whiteHouseDemocratBlueRoom
    case whiteHouseChristmas, whiteHouseChristmasOvalOffice, whiteHouseChristmasEastRoom, whiteHouseChristmasBlueRoom
    case whiteHouseRepublicanChristmas, whiteHouseRepublicanChristmasOvalOffice, whiteHouseRepublicanChristmasEastRoom, whiteHouseRepublicanChristmasBlueRoom
    case whiteHouseDemocratChristmas, whiteHouseDemocratChristmasOvalOffice, whiteHouseDemocratChristmasEastRoom, whiteHouseDemocratChristmasBlueRoom
    case cityNewYork, cityChicago, cityDetroit, cityBoston, cityPhiladelphia, cityWashingtonDC
    case cityLosAngeles, citySanFrancisco, citySeattle, cityLasVegas, cityMiami, cityNewOrleans

    var id: Self { self }
    var starWarsVariant: StarWarsThemeVariant? { StarWarsThemeVariant(rawValue: rawValue) }
    var isStarWars: Bool { starWarsVariant != nil }
    var whiteHouseVariant: WhiteHouseThemeVariant? { WhiteHouseThemeVariant(rawValue: rawValue) }
    var isWhiteHouse: Bool { whiteHouseVariant != nil }
    var cityscapeScene: CityscapeScene? { CityscapeScene(rawValue: rawValue) }
    var isCityscape: Bool { cityscapeScene != nil }
    var usesArchitecturalPhotoLayout: Bool { isWhiteHouse || isCityscape }
    var nativeSceneStyle: NativeAppearanceStyle? { NativeAppearanceStyle(rawValue: rawValue) }
    static var pickerThemes: [Self] {
        allCases.filter {
            (!$0.isStarWars || $0 == .starWars) && (!$0.isWhiteHouse || $0 == .whiteHouse)
                && (!$0.isCityscape || $0 == .cityNewYork)
        }
    }

    var pickerTitle: String { isWhiteHouse ? "White House" : isCityscape ? "Cityscapes" : isStarWars ? "Star Wars" : title }

    var title: String {
        if let variant = whiteHouseVariant { return "White House · \(variant.scene.title) · \(variant.style.title)\(variant.isChristmas ? " · Christmas" : "")" }
        if let scene = cityscapeScene { return "Cityscapes · \(scene.title)" }
        return switch self {
        case .system: "System"
        case .autumn: "Fall"
        case .halloween: "Halloween"
        case .christmas: "Christmas"
        case .winter: "Winter"
        case .easter: "Easter"
        case .springBloom: "Spring Bloom"
        case .summerCoast: "Summer Coast"
        case .nightSky: "Night Sky"
        case .botanical: "Botanical"
        case .desertDusk: "Desert Dusk"
        case .graphite: "Graphite"
        default: "Star Wars · \(starWarsVariant?.title ?? "Jedi")"
        }
    }

    var symbol: String {
        if let variant = whiteHouseVariant { return variant.scene.symbol }
        if isCityscape { return "building.2" }
        return switch self {
        case .system: "apple.logo"
        case .autumn: "leaf.fill"
        case .halloween: "moon.stars.fill"
        case .christmas: "tree.fill"
        case .winter: "snowflake"
        case .easter: "leaf.circle.fill"
        case .springBloom: "camera.macro"
        case .summerCoast: "water.waves"
        case .nightSky: "moon.stars.fill"
        case .botanical: "leaf.fill"
        case .desertDusk: "sun.horizon.fill"
        case .graphite: "circle.lefthalf.filled"
        default: "sparkles"
        }
    }

    var accentColor: NSColor? {
        switch self {
        case .system: nil
        case .autumn: NSColor(red: 0.82, green: 0.32, blue: 0.12, alpha: 1)
        case .halloween: NSColor(red: 0.62, green: 0.32, blue: 0.92, alpha: 1)
        case .christmas: NSColor(red: 0.14, green: 0.62, blue: 0.38, alpha: 1)
        case .winter: NSColor(red: 0.35, green: 0.64, blue: 0.84, alpha: 1)
        case .easter: NSColor(red: 0.42, green: 0.72, blue: 0.59, alpha: 1)
        case .springBloom, .summerCoast, .nightSky, .botanical, .desertDusk, .graphite:
            NSColor(name: NSColor.Name("Notchscape.\(rawValue)")) { [style = NativeAppearanceStyle(rawValue: rawValue) ?? .graphite] appearance in
                let dark = appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
                let (r, g, b) = AppearanceRecipe.rgb(dark ? style.darkAccent : style.lightAccent) ?? (128, 128, 128)
                return NSColor(srgbRed: Double(r)/255, green: Double(g)/255, blue: Double(b)/255, alpha: 1)
            }
        default: whiteHouseVariant?.accentColor ?? cityscapeScene?.accentColor ?? starWarsVariant?.accentColor
        }
    }

    var matchingIcon: AppIconVariant {
        if let variant = whiteHouseVariant,
           let icon = AppIconVariant(rawValue: variant.matchingIconID) { return icon }
        return switch self {
        case .system: .standard
        case .autumn: .autumn
        case .halloween: .halloween
        case .christmas: .christmas
        case .winter: .winter
        case .easter: .easter
        default: .standard
        }
    }

    var homeDecoration: String? {
        switch self {
        case .system: nil
        case .autumn: "🍁"
        case .halloween: "🎃"
        case .christmas: "🎄"
        case .winter: nil
        case .easter: nil
        default: nil
        }
    }

    var homeBackdrop: String? {
        switch self {
        case .autumn: "AutumnBackdrop"
        case .christmas: "ChristmasBackdrop"
        case .halloween: "HalloweenBackdrop"
        case .winter: "WinterBackdrop"
        case .easter: "EasterBackdrop"
        default: whiteHouseVariant?.backdropName ?? cityscapeScene?.backdropName ?? starWarsVariant?.backdropName
        }
    }

    var hasHomeScene: Bool { homeBackdrop != nil || nativeSceneStyle != nil }

    func homeBackdrop(characterArtwork: StarWarsCharacterArtwork, characterArtworkAvailable: Bool = true) -> String? {
        starWarsVariant?.backdropName(artwork: characterArtwork, characterArtworkAvailable: characterArtworkAvailable) ?? homeBackdrop
    }

    var subtitle: String {
        if isCityscape { return "Twelve cities in navy and warm light" }
        return switch self {
        case .system: "Classic Mac appearance"
        case .autumn: "Golden leaves and a warm cabin"
        case .halloween: "Pumpkin glow and candlelight"
        case .christmas: "Tree lights and a cozy fireplace"
        case .winter: "Snowy pines, without holiday decorations"
        case .easter: "Spring blossoms and pastel Easter eggs"
        case .springBloom: "Soft blossoms and fresh spring color"
        case .summerCoast: "Quiet waves and a sunlit horizon"
        case .nightSky: "A moonlit sky, without animation"
        case .botanical: "Deep greens and simple leaf silhouettes"
        case .desertDusk: "Warm dunes beneath a twilight sky"
        case .graphite: "Understated contours and neutral gray"
        default: isWhiteHouse ? "Four rooms, matching décor, and optional Christmas lights" : "Jedi, Dark Side, and character-inspired palettes"
        }
    }
}

extension StarWarsThemeVariant {
    var accentColor: NSColor { NSColor(srgbRed: rgb.red, green: rgb.green, blue: rgb.blue, alpha: 1) }
}

extension WhiteHouseThemeVariant: Defaults.Serializable {
    var accentColor: NSColor {
        NSColor(name: NSColor.Name("Notchscape.\(rawValue)")) { [style] appearance in
            let dark = appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
            let (r, g, b) = AppearanceRecipe.rgb(dark ? style.darkAccent : style.lightAccent) ?? (128, 128, 128)
            return NSColor(srgbRed: Double(r)/255, green: Double(g)/255, blue: Double(b)/255, alpha: 1)
        }
    }
}

extension CityscapeScene: Defaults.Serializable {
    var accentColor: NSColor {
        NSColor(name: NSColor.Name("Notchscape.\(rawValue)")) { [self] appearance in
            let dark = appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
            let (r, g, b) = AppearanceRecipe.rgb(dark ? darkAccent : lightAccent) ?? (128, 128, 128)
            return NSColor(srgbRed: Double(r)/255, green: Double(g)/255, blue: Double(b)/255, alpha: 1)
        }
    }
}

enum WeatherTilePosition: String, CaseIterable, Defaults.Serializable, Identifiable {
    case front
    case afterMusic
    case end

    var id: Self { self }

    var title: String {
        switch self {
        case .front: "Front"
        case .afterMusic: "After Music"
        case .end: "End"
        }
    }
}

enum SportsLeague: String, CaseIterable, Defaults.Serializable, Identifiable {
    case nba
    case nfl
    case mlb
    case nhl
    case mls
    case wnba
    case collegeFootball
    case collegeBasketball

    var id: Self { self }

    var title: String {
        switch self {
        case .nba: "NBA"
        case .nfl: "NFL"
        case .mlb: "MLB"
        case .nhl: "NHL"
        case .mls: "MLS"
        case .wnba: "WNBA"
        case .collegeFootball: "College Football"
        case .collegeBasketball: "College Basketball"
        }
    }

    var endpointPath: String {
        switch self {
        case .nba: "basketball/nba"
        case .nfl: "football/nfl"
        case .mlb: "baseball/mlb"
        case .nhl: "hockey/nhl"
        case .mls: "soccer/usa.1"
        case .wnba: "basketball/wnba"
        case .collegeFootball: "football/college-football"
        case .collegeBasketball: "basketball/mens-college-basketball"
        }
    }

    var symbol: String {
        switch self {
        case .nba, .wnba, .collegeBasketball: "basketball.fill"
        case .nfl, .collegeFootball: "football.fill"
        case .mlb: "baseball.fill"
        case .nhl: "hockey.puck.fill"
        case .mls: "soccerball"
        }
    }
}

enum LiveActivityPriority: String, CaseIterable, Defaults.Serializable, Identifiable {
    case combined
    case musicOnly
    case agentOnly

    var id: Self { self }

    var title: String {
        switch self {
        case .combined: "Music + AI"
        case .musicOnly: "Music only"
        case .agentOnly: "AI only"
        }
    }
}

enum ActivityProfile: String, CaseIterable, Defaults.Serializable, Identifiable {
    case everything
    case focus
    case minimal
    case entertainment

    var id: Self { self }

    var title: String {
        switch self {
        case .everything: "Everything"
        case .focus: "Focus"
        case .minimal: "Minimal"
        case .entertainment: "Entertainment"
        }
    }
}

enum SliderColorEnum: String, CaseIterable, Defaults.Serializable {
    case white = "White"
    case albumArt = "Match album art"
    case accent = "Accent color"
}
