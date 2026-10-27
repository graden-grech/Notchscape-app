// Catalog adapted from the user's MacScapes app. Artwork is downloaded on demand.
import Foundation

enum WallpaperPlatform: String, CaseIterable, Identifiable, Sendable {
    case all = "All"
    case seasons = "Seasons"
    case space = "Space"
    case macOS = "macOS"
    case windows = "Windows"

    var id: String { rawValue }
}

enum WallpaperSeason: String, CaseIterable, Identifiable, Sendable {
    case spring = "Spring"
    case summer = "Summer"
    case fall = "Fall"
    case winter = "Winter"

    var id: String { rawValue }
}

enum WallpaperRotation: String, CaseIterable, Identifiable, Sendable {
    case off, thirtyMinutes, hourly, sixHours, daily
    var id: Self { self }
    var title: String {
        switch self {
        case .off: "Off"
        case .thirtyMinutes: "Every 30 minutes"
        case .hourly: "Every hour"
        case .sixHours: "Every 6 hours"
        case .daily: "Every day"
        }
    }
    var seconds: TimeInterval? {
        switch self {
        case .off: nil
        case .thirtyMinutes: 1800
        case .hourly: 3600
        case .sixHours: 21600
        case .daily: 86400
        }
    }
}

struct Wallpaper: Identifiable, Hashable, Sendable {
    let id: String
    let platform: WallpaperPlatform
    let isModern: Bool
    let release: String
    let version: String
    let name: String
    let thumbnailURL: URL
    let downloadURL: URL
    var attribution: WallpaperAttribution? = nil

    var displayRelease: String {
        version.isEmpty ? release : "\(release) · \(version)"
    }

    /// Some archive "thumbnails" are full-resolution multi-megabyte files.
    /// Request a bounded preview rather than decoding those originals in a grid.
    var previewURL: URL {
        guard thumbnailURL.host == "media.512pixels.net" else { return thumbnailURL }
        var proxy = URLComponents(string: "https://wsrv.nl/")!
        proxy.queryItems = [URLQueryItem(name: "url", value: thumbnailURL.absoluteString),
            .init(name: "w", value: "640"), .init(name: "h", value: "360"),
            .init(name: "fit", value: "cover"), .init(name: "output", value: "jpg"), .init(name: "q", value: "78")]
        return proxy.url!
    }

    /// Details keep the full composition, still using a bounded remote preview.
    var detailPreviewURL: URL {
        if platform == .space {
            return downloadURL.deletingLastPathComponent()
                .appendingPathComponent(downloadURL.lastPathComponent.components(separatedBy: "~")[0] + "~large.jpg")
        }
        if thumbnailURL.host == "images.unsplash.com" {
            var url = URLComponents(url: thumbnailURL, resolvingAgainstBaseURL: false)!
            url.queryItems = [.init(name: "auto", value: "format"), .init(name: "fit", value: "max"),
                              .init(name: "w", value: "1280"), .init(name: "q", value: "85")]
            return url.url!
        }
        var url = URLComponents(url: previewURL, resolvingAgainstBaseURL: false)!
        if url.host == "wsrv.nl" {
            url.queryItems = (url.queryItems ?? []).filter { !["w", "h", "fit"].contains($0.name) }
                + [.init(name: "w", value: "1280"), .init(name: "h", value: "800"), .init(name: "fit", value: "inside")]
        }
        return url.url!
    }

    var source: WallpaperAttribution {
        if let attribution { return attribution }
        switch platform {
        case .macOS:
            return .init(credit: "Apple · Archived by 512 Pixels",
                         pageURL: URL(string: "https://512pixels.net/projects/default-mac-wallpapers-in-5k/")!,
                         rights: "Apple artwork is provided by a public archive. Original rights remain with their owners.")
        case .windows:
            return .init(credit: "Microsoft · Windows UI Assets archive",
                         pageURL: URL(string: "https://github.com/bartekl1/windows-ui-assets/tree/main/Wallpapers")!,
                         rights: "Microsoft artwork is provided by a public archive. Original rights remain with their owners.")
        default:
            return .init(credit: "Unsplash photographers", pageURL: URL(string: "https://unsplash.com/")!,
                         rights: "Original photography, made available under the Unsplash License.",
                         licenseURL: URL(string: "https://unsplash.com/license"))
        }
    }
}

struct WallpaperAttribution: Hashable, Sendable {
    let credit: String
    let pageURL: URL
    let rights: String
    var licenseURL: URL? = nil
}

enum WallpaperBrowseSort: String, CaseIterable, Identifiable {
    case collection, nameAscending, nameDescending
    var id: Self { self }
    var title: String {
        switch self { case .collection: "Collection Order"; case .nameAscending: "Name, A–Z"; case .nameDescending: "Name, Z–A" }
    }
    func sorted(_ wallpapers: [Wallpaper]) -> [Wallpaper] {
        guard self != .collection else { return wallpapers }
        return wallpapers.sorted {
            let order = $0.name.localizedStandardCompare($1.name)
            if order == .orderedSame { return $0.id < $1.id }
            return self == .nameAscending ? order == .orderedAscending : order == .orderedDescending
        }
    }
}

/// A visual browsing suggestion, never a command to change the desktop.
/// Raw theme IDs keep this policy usable by lightweight catalog tests.
enum WallpaperThemeMatch: String, CaseIterable, Identifiable {
    case classicMac, autumn, halloween, christmas, winter, spring, summer, botanical, space, jedi, darkSide, desert
    var id: Self { self }
    static func matching(_ themeID: String) -> Self {
        switch themeID {
        case "autumn": .autumn
        case "halloween": .halloween
        case "christmas": .christmas
        case "winter": .winter
        case "easter", "springBloom": .spring
        case "summerCoast": .summer
        case "nightSky": .space
        case "botanical": .botanical
        case "desertDusk": .desert
        case "starWarsDarkSide", "starWarsVader", "starWarsMaul": .darkSide
        case "starWarsLuke", "starWarsObiWan", "starWarsRey": .desert
        case "starWars", "starWarsAhsoka", "starWarsYoda", "starWarsMaceWindu": .jedi
        default: .classicMac
        }
    }
}

enum ReleaseFilter: String, CaseIterable, Identifiable {
    case all = "All"
    case modern = "Modern"
    case classic = "Classic"
    case favorites = "Favorites"
    case downloaded = "Downloaded"
    case spring = "Spring"
    case summer = "Summer"
    case fall = "Fall"
    case winter = "Winter"
    case windowsXP = "XP"
    case windowsVista = "Vista"
    case windows7 = "7"
    case windows81 = "8.1"
    case windows10 = "10"
    case windows11 = "11"

    var id: String { rawValue }

    static func options(for platform: WallpaperPlatform) -> [ReleaseFilter] {
        switch platform {
        case .all:
            [.all, .modern, .classic, .favorites, .downloaded]
        case .seasons:
            [.all, .spring, .summer, .fall, .winter, .favorites, .downloaded]
        case .macOS:
            [.all, .modern, .classic, .favorites, .downloaded]
        case .windows:
            [.all, .windowsXP, .windowsVista, .windows7, .windows81, .windows10, .windows11]
        case .space:
            [.all, .favorites, .downloaded]
        }
    }

    var season: WallpaperSeason? {
        switch self {
        case .spring: .spring
        case .summer: .summer
        case .fall: .fall
        case .winter: .winter
        default: nil
        }
    }

    var windowsRelease: String? {
        switch self {
        case .windowsXP: "Windows XP"
        case .windowsVista: "Windows Vista"
        case .windows7: "Windows 7"
        case .windows81: "Windows 8.1"
        case .windows10: "Windows 10"
        case .windows11: "Windows 11"
        default: nil
        }
    }
}
