// Catalog adapted from the user's MacScapes app. Artwork is downloaded on demand.
import Foundation

enum WallpaperCatalog {
    private static let thumbRoot = "https://media.512pixels.net/"
    private static let fullRoot = "https://media.512pixels.net/downloads/macos-wallpapers-6k/"

    private static func item(
        _ id: String,
        _ release: String,
        _ version: String,
        _ name: String,
        _ thumb: String,
        _ full: String
    ) -> Wallpaper {
        Wallpaper(
            id: id,
            platform: .macOS,
            isModern: {
                let cleaned = version
                    .replacingOccurrences(of: "macOS ", with: "")
                    .replacingOccurrences(of: "OS X ", with: "")
                    .replacingOccurrences(of: "Mac OS X ", with: "")
                return (Double(cleaned) ?? 0) >= 11
            }(),
            release: release,
            version: version,
            name: name,
            thumbnailURL: URL(string: thumbRoot + thumb)!,
            downloadURL: URL(string: fullRoot + full)!
        )
    }

    static let all: [Wallpaper] = [
        item("golden-gate-bridge", "Golden Gate", "macOS 27", "Golden Gate Bridge", "downloads/macos-wallpapers-thumbs/27-Golden-Gate-Bridge-thumb.jpg", "27-Golden-Gate-Bridge.jpg"),
        item("golden-gate-light", "Golden Gate", "macOS 27", "Golden Gate Light", "downloads/macos-wallpapers-thumbs/27-Golden-Gate-thumb.jpg", "27-Golden-Gate.png"),
        item("golden-gate-dark", "Golden Gate", "macOS 27", "Golden Gate Dark", "downloads/macos-wallpapers-thumbs/27-Golden-Gate-thumb-dark.png", "27-Golden-Gate-Dark.png"),
        item("tahoe-light", "Tahoe", "macOS 26", "Tahoe Light", "wp-content/uploads/2025/06/26-Tahoe-Light-6K-thumb.jpeg", "26-Tahoe-Light-6K.png"),
        item("tahoe-dark", "Tahoe", "macOS 26", "Tahoe Dark", "wp-content/uploads/2025/06/26-Tahoe-Dark-6K-thumb.jpeg", "26-Tahoe-Dark-6K.png"),
        item("tahoe-dawn", "Tahoe", "macOS 26", "Tahoe Beach — Dawn", "wp-content/uploads/2025/08/26-Tahoe-Beach-Dawn-thumb.jpeg", "26-Tahoe-Beach-Dawn.png"),
        item("tahoe-day", "Tahoe", "macOS 26", "Tahoe Beach — Day", "wp-content/uploads/2025/08/26-Tahoe-Beach-Day-thumb.jpeg", "26-Tahoe-Beach-Day.png"),
        item("tahoe-dusk", "Tahoe", "macOS 26", "Tahoe Beach — Dusk", "wp-content/uploads/2025/08/26-Tahoe-Beach-Dusk-thumb.jpeg", "26-Tahoe-Beach-Dusk.png"),
        item("tahoe-night", "Tahoe", "macOS 26", "Tahoe Beach — Night", "wp-content/uploads/2025/08/26-Tahoe-Beach-Night-thumb.jpeg", "26-Tahoe-Beach-Night.png"),
        item("sequoia-light", "Sequoia", "macOS 15", "Sequoia Light", "wp-content/uploads/2025/06/15-Sequoia-Light-thumbnail.jpg", "15-Sequoia-Light-6K.jpg"),
        item("sequoia-dark", "Sequoia", "macOS 15", "Sequoia Dark", "wp-content/uploads/2025/06/15-Sequoia-Dark-thumbnail.jpg", "15-Sequoia-Dark-6K.jpg"),
        item("sequoia-sunrise", "Sequoia", "macOS 15", "Sequoia Sunrise", "downloads/macos-wallpapers-6k/15-Sequoia-Sunrise.png", "15-Sequoia-Sunrise.png"),
        item("sonoma-light", "Sonoma", "macOS 14", "Sonoma Light", "wp-content/uploads/2025/06/14-Sonoma-Light-thumb.jpg", "14-Sonoma-Light.jpg"),
        item("sonoma-dark", "Sonoma", "macOS 14", "Sonoma Dark", "wp-content/uploads/2025/06/14-Sonoma-Dark-thumb.jpg", "14-Sonoma-Dark.jpg"),
        item("sonoma-horizon", "Sonoma", "macOS 14", "Sonoma Horizon", "wp-content/uploads/2025/06/14-Sonoma-Horizon-thumb.jpeg", "14-Sonoma-Horizon.png"),
        item("ventura-light", "Ventura", "macOS 13", "Ventura Light", "wp-content/uploads/2025/06/13-Ventura-Light-thumb.jpg", "13-Ventura-Light.jpg"),
        item("ventura-dark", "Ventura", "macOS 13", "Ventura Dark", "wp-content/uploads/2025/06/13-Ventura-Dark-thumb.jpg", "13-Ventura-Dark.jpg"),
        item("monterey-light", "Monterey", "macOS 12", "Monterey Light", "wp-content/uploads/2025/06/12-Light-thumbnail.jpg", "12-Monterey-Light.jpg"),
        item("monterey-dark", "Monterey", "macOS 12", "Monterey Dark", "wp-content/uploads/2025/06/12-Dark-thumbnail.jpg", "12-Monterey-Dark.jpg"),
        item("big-sur-color-day", "Big Sur", "macOS 11", "Big Sur Colorful Day", "wp-content/uploads/2025/06/11-0-Color-Day-thumbnails.jpg", "11-Big-Sur-Color-Day-6k.jpg"),
        item("big-sur-color-night", "Big Sur", "macOS 11", "Big Sur Colorful Night", "wp-content/uploads/2025/06/11-0-Color-Night-thumbnails.jpg", "11-Big-Sur-Color-Night-6k.jpg"),
        item("big-sur-day", "Big Sur", "macOS 11", "Big Sur Day", "wp-content/uploads/2025/06/11-0-Day-thumbnail.jpg", "11-Big-Sur-Day-6k.jpg"),
        item("big-sur-night", "Big Sur", "macOS 11", "Big Sur Night", "wp-content/uploads/2025/06/11-0-Night-thumbnail.jpg", "11-Big-Sur-Night-6k.jpg"),
        item("catalina-day", "Catalina", "macOS 10.15", "Catalina Day", "wp-content/uploads/2025/06/10-15-Day-thumb.jpg", "10-15-Day-6k.jpg"),
        item("catalina-night", "Catalina", "macOS 10.15", "Catalina Night", "wp-content/uploads/2025/06/10-15-Night-thumb.jpg", "10-15-Night-6k.jpg"),
        item("mojave-day", "Mojave", "macOS 10.14", "Mojave Day", "downloads/macos-wallpapers-thumbs/10-14-Day-Thumb.jpg", "10-14-Day-6k.jpg"),
        item("mojave-night", "Mojave", "macOS 10.14", "Mojave Night", "downloads/macos-wallpapers-thumbs/10-14-Night-Thumb.jpg", "10-14-Night-6k.jpg"),
        item("high-sierra", "High Sierra", "macOS 10.13", "High Sierra", "downloads/macos-wallpapers-thumbs/10-13--thumb.jpg", "10-13-6k.jpg"),
        item("sierra", "Sierra", "macOS 10.12", "Sierra", "downloads/macos-wallpapers-thumbs/10-12--thumb.jpg", "10-12-6k.jpg"),
        item("el-capitan", "El Capitan", "OS X 10.11", "El Capitan", "downloads/macos-wallpapers-thumbs/10-11--thumb.jpg", "10-11-6k.jpg"),
        item("yosemite", "Yosemite", "OS X 10.10", "Yosemite", "downloads/macos-wallpapers-thumbs/10-10--thumb.jpg", "10-10-6k.jpg"),
        item("mavericks", "Mavericks", "OS X 10.9", "Mavericks", "downloads/macos-wallpapers-thumbs/10-9--thumb.jpg", "10-9-6k.jpg"),
        item("mountain-lion", "Mountain Lion", "OS X 10.8", "Mountain Lion", "downloads/macos-wallpapers-thumbs/10-8--thumb.jpg", "10-8-6k.jpg"),
        item("lion", "Lion", "Mac OS X 10.7", "Lion", "downloads/macos-wallpapers-thumbs/10-7--thumb.png", "10-7-6k.jpg"),
        item("snow-leopard", "Snow Leopard", "Mac OS X 10.6", "Snow Leopard", "downloads/macos-wallpapers-thumbs/10-6--thumb.png", "10-6-6k.jpg"),
        item("snow-leopard-server", "Snow Leopard", "Mac OS X 10.6", "Snow Leopard Server", "downloads/macos-wallpapers-thumbs/10-6-Server-thumb.jpg", "10-6-Server-6k.jpg"),
        item("leopard", "Leopard", "Mac OS X 10.5", "Leopard", "downloads/macos-wallpapers-thumbs/10-5--thumb.png", "10-5-6k.jpg"),
        item("leopard-server", "Leopard", "Mac OS X 10.5", "Leopard Server", "downloads/macos-wallpapers-thumbs/10-5-Server-thumb.jpg", "10-5-Server-6k.jpg"),
        item("tiger", "Tiger", "Mac OS X 10.4", "Tiger", "downloads/macos-wallpapers-thumbs/10-4--thumb.png", "10-4-6k.jpg"),
        item("panther", "Panther", "Mac OS X 10.3", "Panther", "downloads/macos-wallpapers-thumbs/10-3--thumb.png", "10-3-6k.jpg"),
        item("jaguar", "Jaguar", "Mac OS X 10.2", "Jaguar", "downloads/macos-wallpapers-thumbs/10-2--thumb.png", "10-2-6k.jpg"),
        item("cheetah-puma", "Cheetah & Puma", "Mac OS X 10.0–10.1", "Aqua", "downloads/macos-wallpapers-thumbs/10-0_10.1--thumb.png", "10-0_10-1-6k.jpg")
    ]

    static func wallpapers(for platform: WallpaperPlatform) -> [Wallpaper] {
        switch platform {
        case .all: everyWallpaper
        case .seasons: SeasonalWallpaperCatalog.all
        case .space: SpaceWallpaperCatalog.all
        case .macOS: all
        case .windows: WindowsWallpaperCatalog.all
        }
    }

    static var everyWallpaper: [Wallpaper] { all + WindowsWallpaperCatalog.all + SeasonalInternetCatalog.all + SpaceWallpaperCatalog.all }
}

/// Real seasonal photographs hosted by Unsplash and downloaded on demand.
enum SeasonalInternetCatalog {
    private static func item(_ id: String, _ season: WallpaperSeason?, _ name: String, _ photoID: String,
                             photographer: String? = nil, pageID: String? = nil) -> Wallpaper {
        let root = "https://images.unsplash.com/photo-\(photoID)"
        return Wallpaper(
            id: "internet-\(id)",
            platform: .seasons,
            isModern: true,
            release: "Internet",
            version: season.map { "Unsplash · \($0.rawValue)" } ?? "Unsplash · Nature",
            name: name,
            thumbnailURL: URL(string: root + "?auto=format&fit=crop&w=476&h=232&q=78")!,
            downloadURL: URL(string: root + "?auto=format&fit=max&w=3840&q=92")!,
            attribution: photographer.flatMap { credit in
                pageID.map { .init(credit: "\(credit) · Unsplash", pageURL: URL(string: "https://unsplash.com/photos/\($0)")!,
                                  rights: "Original photography, made available under the Unsplash License.",
                                  licenseURL: URL(string: "https://unsplash.com/license")) }
            }
        )
    }

    static let all: [Wallpaper] = [
        // Verified photographer pages and image endpoints, October 2026.
        // The catalog stores links only; no third-party photos are bundled.
        item("spring-cherry-overlook", .spring, "Cherry Blossom Overlook", "1774093280188-5114e6a6a3e3", photographer: "JinHui CHEN", pageID: "61aBHL2sfhc"),
        item("fall-pumpkin-harvest", .fall, "Golden Hour Harvest", "1761284827163-66352655cac7", photographer: "Elijah Pilchard", pageID: "0ZQG2WeU8KM"),
        item("fall-forest-lantern", .fall, "Forest Jack-o’-Lantern", "1760199746599-12e43cbc573c", photographer: "Andrea Caramello", pageID: "hPnP1HnNcWA"),
        item("winter-christmas-snow", .winter, "Christmas in the Snow", "1767523881986-f8b55d3c5880", photographer: "Alexander Lunyov", pageID: "20u_wtTfnrI"),
        item("winter-arctic-sunrise", .winter, "Arctic Forest Sunrise", "1770287691979-6b8ec41f5331", photographer: "Harri P", pageID: "L8p9qMMiCWs"),
        item("spring-mountain-meadow", .spring, "Spring Mountain Meadow", "1469474968028-56623f02e42e"),
        item("spring-misty-forest", .spring, "Spring Misty Forest", "1470071459604-3b5ec3a7fe05"),
        item("spring-lake-valley", .spring, "Spring Lake Valley", "1470770841072-f978cf4d019e"),
        item("summer-coastal-mountains", .summer, "Summer Coastal Mountains", "1500534623283-312aade485b7"),
        item("summer-blue-lake", .summer, "Summer Blue Lake", "1501785888041-af3ef285b470"),
        item("summer-green-valley", .summer, "Summer Green Valley", "1464822759023-fed622ff2c3b"),
        item("fall-golden-forest", .fall, "Fall Golden Forest", "1447752875215-b2761acb3c5d"),
        item("fall-autumn-lane", .fall, "Fall Autumn Lane", "1473445361085-b9a07f55608b"),
        item("fall-redwood-light", .fall, "Fall Redwood Light", "1441974231531-c6227db76b6e"),
        // Keep legacy IDs (including favorites) but correct their visible names:
        // these are green landscapes/desert scenery, not snowy winter photos.
        item("winter-snowy-pines", nil, "Pine Forest Sunset", "1511497584788-876760111969"),
        item("winter-frosted-mountains", nil, "Green Rolling Hills", "1501854140801-50d01698950b"),
        item("winter-mountain-mist", nil, "Red Rock Desert Road", "1500530855697-b586d89ba3ee")
    ]

    static func season(for wallpaper: Wallpaper) -> WallpaperSeason? {
        all.first(where: { $0.id == wallpaper.id }).flatMap { wallpaper in
            WallpaperSeason.allCases.first { wallpaper.version.hasSuffix($0.rawValue) }
        }
    }
}

/// Selected still images from NASA's public Image and Video Library. Asset names
/// and credits are pinned from its collection.json/metadata.json, not guessed URLs.
enum SpaceWallpaperCatalog {
    private static func item(_ id: String, _ name: String, _ credit: String, png: Bool = false) -> Wallpaper {
        let root = "https://images-assets.nasa.gov/image/\(id)/\(id)"
        return Wallpaper(id: "space-" + id.lowercased().replacingOccurrences(of: "_", with: "-"),
            platform: .space, isModern: true, release: "Space", version: "NASA Image Library", name: name,
            thumbnailURL: URL(string: root + "~small.jpg")!,
            downloadURL: URL(string: root + (png ? "~orig.png" : "~orig.jpg"))!,
            attribution: .init(credit: credit, pageURL: URL(string: "https://images.nasa.gov/details/\(id)")!,
                rights: "Scientific imagery from NASA’s public library. Full credits and applicable rights are listed at the source. No NASA endorsement is implied.",
                licenseURL: URL(string: "https://www.nasa.gov/nasa-brand-center/images-and-media/")))
    }
    static let all: [Wallpaper] = [
        item("carina_nebula", "Cosmic Cliffs", "NASA, ESA, CSA, STScI", png: true),
        item("southern_ring_nebula", "Southern Ring · Two Views", "NASA, ESA, CSA, STScI", png: true),
        item("PIA04921", "Andromeda in Ultraviolet", "NASA/JPL/California Institute of Technology"),
        item("GSFC_20171208_Archive_e001386", "Blue Marble", "NASA/NOAA/GSFC/Suomi NPP/VIIRS/Norman Kuring")
    ]
}

extension WallpaperThemeMatch {
    func contains(_ wallpaper: Wallpaper) -> Bool {
        switch self {
        case .classicMac: wallpaper.platform == .macOS
        case .autumn: SeasonalWallpaperCatalog.contains(wallpaper, season: .fall)
        case .halloween:
            ["internet-fall-forest-lantern", "internet-fall-pumpkin-harvest", "mojave-night", "tahoe-night", "leopard-server"].contains(wallpaper.id)
        case .christmas:
            ["internet-winter-christmas-snow", "internet-winter-arctic-sunrise"].contains(wallpaper.id)
                || SeasonalWallpaperCatalog.contains(wallpaper, season: .winter)
        case .winter:
            // Keep the neutral Winter collection free of Christmas decorations.
            wallpaper.id != "internet-winter-christmas-snow" && SeasonalWallpaperCatalog.contains(wallpaper, season: .winter)
        case .spring: SeasonalWallpaperCatalog.contains(wallpaper, season: .spring)
        case .summer: SeasonalWallpaperCatalog.contains(wallpaper, season: .summer)
        case .botanical:
            ["internet-spring-misty-forest", "internet-fall-golden-forest", "internet-fall-autumn-lane", "internet-fall-redwood-light", "internet-winter-snowy-pines", "internet-summer-green-valley", "sequoia-sunrise"].contains(wallpaper.id)
        case .space: wallpaper.platform == .space
        case .jedi:
            wallpaper.platform == .space || ["sequoia-sunrise", "internet-spring-misty-forest", "internet-fall-redwood-light", "internet-summer-green-valley", "internet-winter-snowy-pines"].contains(wallpaper.id)
        case .darkSide:
            (wallpaper.platform == .space && wallpaper.id != "space-gsfc-20171208-archive-e001386")
                || ["mojave-night", "tahoe-night", "leopard", "leopard-server", "windows-windows-xp-desktop-red-moon-desert-jpg", "windows-windows-xp-desktop-vortec-space-jpg"].contains(wallpaper.id)
        case .desert:
            ["mojave-day", "mojave-night", "space-carina-nebula", "internet-winter-mountain-mist", "windows-windows-xp-desktop-red-moon-desert-jpg", "windows-windows-7-desktop-landscapes-img9-jpg"].contains(wallpaper.id)
        }
    }
}

enum SeasonalWallpaperCatalog {
    private static let memberships: [WallpaperSeason: Set<String>] = [
        .spring: [
            "windows-windows-xp-desktop-tulips-jpg",
            "windows-windows-7-desktop-landscapes-img10-jpg",
            "windows-windows-7-desktop-regional-japan-jp-wp3-jpg",
            "windows-windows-7-desktop-regional-netherlands-nl-wp5-jpg",
            "windows-windows-vista-desktop-img6-jpg",
            "windows-windows-8-1-desktop-flowers-img10-jpg",
            "windows-windows-10-desktop-flowers-img11-jpg"
        ],
        .summer: [
            "tahoe-day",
            "catalina-day",
            "sierra",
            "windows-windows-xp-desktop-bliss-bmp",
            "windows-windows-xp-desktop-azul-jpg",
            "windows-windows-7-desktop-landscapes-img12-jpg",
            "windows-windows-7-desktop-regional-canada-ca-wp2-jpg",
            "windows-windows-7-desktop-regional-canada-ca-wp6-jpg",
            "windows-windows-10-lock-screen-img101-png"
        ],
        .fall: [
            "high-sierra",
            "el-capitan",
            "windows-windows-xp-desktop-autumn-jpg",
            "windows-windows-7-desktop-nature-img6-jpg",
            "windows-windows-7-desktop-regional-germany-de-wp1-jpg",
            "windows-windows-7-desktop-regional-italy-it-wp2-jpg",
            "windows-windows-7-desktop-regional-south-africa-za-wp2-jpg",
            "windows-windows-7-desktop-regional-united-states-us-wp4-jpg",
            "windows-windows-vista-desktop-img22-jpg"
        ],
        .winter: [
            "windows-windows-7-desktop-landscapes-img8-jpg",
            "windows-windows-7-desktop-regional-canada-ca-wp1-jpg",
            "windows-windows-7-desktop-regional-germany-de-wp3-jpg",
            "windows-windows-7-desktop-regional-netherlands-nl-wp3-jpg",
            "windows-windows-7-desktop-regional-russia-ru-wp3-jpg",
            "windows-windows-7-desktop-regional-russia-ru-wp4-jpg",
            "windows-windows-7-desktop-regional-russia-ru-wp5-jpg"
        ]
    ]

    static let all: [Wallpaper] = WallpaperCatalog.everyWallpaper.filter { wallpaper in
        WallpaperSeason.allCases.contains { contains(wallpaper, season: $0) }
    }

    static func contains(_ wallpaper: Wallpaper, season: WallpaperSeason) -> Bool {
        memberships[season]?.contains(wallpaper.id) == true || SeasonalInternetCatalog.season(for: wallpaper) == season
    }

    static func seasons(for wallpaper: Wallpaper) -> [WallpaperSeason] {
        WallpaperSeason.allCases.filter { contains(wallpaper, season: $0) }
    }
}
