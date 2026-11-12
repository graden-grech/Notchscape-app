import Foundation

/// Only explicitly known tracking parameters are removed. Signed URLs are kept
/// intact because even an unrelated query change can invalidate their signature.
enum CleanLinkPolicy {
    static func clean(_ input: String) -> String? {
        let text = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard text.utf8.count <= 16_384, !text.contains(where: { $0.isWhitespace }),
              var url = URLComponents(string: text),
              ["https", "http"].contains(url.scheme?.lowercased() ?? ""),
              let host = url.host, !host.isEmpty, url.user == nil, url.password == nil else { return nil }
        let items = url.queryItems ?? []
        let signed = items.contains {
            let key = $0.name.lowercased()
            return key.hasPrefix("x-amz-") || key.hasPrefix("x-goog-")
                || ["signature", "sig", "hmac", "token", "access_token"].contains(key)
        }
        guard !signed else { return text }
        let known: Set<String> = ["fbclid", "gclid", "dclid", "msclkid", "gbraid", "wbraid", "mc_cid", "mc_eid", "igshid"]
        let rawItems = (url.percentEncodedQuery ?? "").components(separatedBy: "&")
        let kept = rawItems.filter {
            let key = String($0.split(separator: "=", maxSplits: 1, omittingEmptySubsequences: false)[0]).removingPercentEncoding?.lowercased() ?? ""
            return !key.hasPrefix("utm_") && !known.contains(key)
        }
        // Preserve byte-for-byte escaping when nothing changes.
        guard kept.count != rawItems.count else { return text }
        url.percentEncodedQuery = kept.isEmpty ? nil : kept.joined(separator: "&")
        return url.string
    }
}

struct NotchSettingsDestination: Identifiable {
    let id: String
    let title: String
    let symbol: String
    let color: String
    let keywords: String
    func matches(_ query: String) -> Bool {
        let words = query.split(whereSeparator: \.isWhitespace)
        let haystack = "\(title) \(keywords)"
        return words.allSatisfy { haystack.localizedCaseInsensitiveContains($0) }
    }

    /// Keep established section IDs for shortcuts/tour/deep links while showing
    /// one parent row for related settings in the sidebar.
    static func parentID(for id: String) -> String {
        switch id {
        case "Weather", "Themes", "HomeLayout", "AppIcon", "Effects": "Appearance"
        case "MediaAppearance": "Media"
        case "Agents", "Sports": "Activities"
        case "Shortcuts", "Shelf": "Tools"
        case "Battery", "HUD": "System"
        default: id
        }
    }

    static var sidebar: [Self] { all.filter { parentID(for: $0.id) == $0.id } }

    /// A child keeps its established deep-link ID while its parent provides
    /// context in search results and stays selected in the normal sidebar.
    var parentTitle: String? {
        let parentID = Self.parentID(for: id)
        guard parentID != id else { return nil }
        return Self.all.first { $0.id == parentID }?.title
    }

    /// Search exposes the actual matching pages, including pages normally
    /// grouped beneath a parent. A title match takes precedence over a broader
    /// keyword match without changing the established order of equal results.
    static func destinations(matching query: String, accountsEnabled: Bool) -> [Self] {
        let normalizedQuery = query.split(whereSeparator: \.isWhitespace).joined(separator: " ")
        let available = all.filter { $0.id != "Account" || accountsEnabled }
        guard !normalizedQuery.isEmpty else {
            return available.filter { parentID(for: $0.id) == $0.id }
        }

        func rank(_ destination: Self) -> Int {
            if destination.title.localizedCaseInsensitiveCompare(normalizedQuery) == .orderedSame { return 0 }
            if destination.title.localizedStandardContains(normalizedQuery) { return 1 }
            return 2
        }

        return available.enumerated()
            .filter { _, destination in
                let searchableText = "\(destination.title) \(destination.keywords) \(destination.parentTitle ?? "")"
                return normalizedQuery.split(separator: " ").allSatisfy { searchableText.localizedCaseInsensitiveContains($0) }
            }
            .sorted { lhs, rhs in
                let leftRank = rank(lhs.element), rightRank = rank(rhs.element)
                return leftRank == rightRank ? lhs.offset < rhs.offset : leftRank < rightRank
            }
            .map(\.element)
    }

    func matchesIncludingChildren(_ query: String) -> Bool {
        matches(query) || Self.all.contains { Self.parentID(for: $0.id) == id && $0.matches(query) }
    }
    static let all: [Self] = [
        .init(id: "General", title: "General", symbol: "gearshape.fill", color: "gray", keywords: "display sizing external monitor notch island startup dock gestures performance"),
        .init(id: "Modes", title: "Modes", symbol: "square.stack.3d.up.fill", color: "indigo", keywords: "work study presentation gaming travel creative developer minimal presets overrides restore focus"),
        .init(id: "Account", title: "Account", symbol: "person.crop.circle.fill", color: "blue", keywords: "login sync password passkey"),
        .init(id: "Appearance", title: "Appearance", symbol: "paintpalette.fill", color: "indigo", keywords: "theme seasonal accent color icon home tiles layout glass white house republican democrat neutral oval office east room blue room snow snowfall winter desktop effects"),
        .init(id: "Themes", title: "Themes & Colors", symbol: "paintpalette.fill", color: "indigo", keywords: "theme seasonal accent color palette white house christmas halloween cities star wars recipes automatic sidebar"),
        .init(id: "HomeLayout", title: "Home Layout", symbol: "rectangle.3.group.fill", color: "blue", keywords: "home tiles arrange reorder quick actions tabs buttons layout transparency original refined backgrounds"),
        .init(id: "AppIcon", title: "App Icon", symbol: "app.fill", color: "purple", keywords: "icon dock logo seasonal branding follows theme"),
        .init(id: "Effects", title: "Effects & Mirror", symbol: "sparkles", color: "cyan", keywords: "snow snowfall desktop winter mirror camera shape detail"),
        .init(id: "MediaAppearance", title: "Player Appearance", symbol: "music.note", color: "pink", keywords: "music color slider visualizer spectrogram album tint lottie animation"),
        .init(id: "Store", title: "Add-ons", symbol: "square.stack.3d.up.fill", color: "blue", keywords: "store download install plugins extensions feature packs holiday civic government dock widgets face unlock advanced"),
        .init(id: "Dock", title: "Dock", symbol: "dock.rectangle", color: "indigo", keywords: "launcher apps folders widgets cards pinned reorder glass workspace clock battery calendar"),
        .init(id: "Media", title: "Media", symbol: "play.rectangle.fill", color: "pink", keywords: "music spotify playback album lightsaber override"),
        .init(id: "Calendar", title: "Calendar", symbol: "calendar", color: "red", keywords: "events appointments permissions"),
        .init(id: "Tools", title: "Tools & Shortcuts", symbol: "square.grid.2x2.fill", color: "indigo", keywords: "clipboard notes devices bluetooth audio text capture ocr links tracking color picker eyedropper utilities"),
        .init(id: "Wallpapers", title: "Wallpapers", symbol: "photo.on.rectangle.angled", color: "cyan", keywords: "macscapes background desktop rotation shuffle favorites macos windows seasons"),
        .init(id: "Agents", title: "AI Agents", symbol: "sparkles", color: "purple", keywords: "codex claude limits usage tokens hooks status"),
        .init(id: "Weather", title: "Weather", symbol: "cloud.sun.fill", color: "blue", keywords: "location forecast city temperature celsius fahrenheit"),
        .init(id: "Sports", title: "Sports", symbol: "sportscourt.fill", color: "green", keywords: "teams league scores games"),
        .init(id: "Activities", title: "Live Activities", symbol: "waveform.path.ecg", color: "pink", keywords: "notifications priority alerts music timer focus lock privacy"),
        .init(id: "System", title: "System & Power", symbol: "gauge.with.dots.needle.50percent", color: "gray", keywords: "cpu memory storage monitor stats thermal fans"),
        .init(id: "HUD", title: "HUDs", symbol: "dial.medium.fill", color: "cyan", keywords: "volume brightness accessibility permissions interceptor restart"),
        .init(id: "Battery", title: "Battery", symbol: "battery.100.bolt", color: "green", keywords: "power charging energy"),
        .init(id: "Shelf", title: "Shelf", symbol: "tray.fill", color: "blue", keywords: "files drop airdrop sharing"),
        .init(id: "Shortcuts", title: "Shortcuts", symbol: "keyboard.fill", color: "orange", keywords: "keyboard hotkeys commands"),
        .init(id: "Advanced", title: "Advanced", symbol: "gearshape.2.fill", color: "gray", keywords: "experimental debugging"),
        .init(id: "FaceUnlock", title: "Face Unlock", symbol: "person.crop.square", color: "green", keywords: "face id camera webcam local biometric glance lock password identities recognition"),
        .init(id: "About", title: "About", symbol: "info.circle.fill", color: "blue", keywords: "version update github help support license")
    ]
}

enum WallpaperPolicy {
    static let maximumDownloadBytes: Int64 = 100_000_000
    static let allowedHosts: Set<String> = ["media.512pixels.net", "raw.githubusercontent.com", "images.unsplash.com", "wsrv.nl", "images-assets.nasa.gov"]
    static func allowedURL(_ url: URL) -> Bool {
        url.scheme == "https" && url.user == nil && url.password == nil
            && allowedHosts.contains(url.host?.lowercased() ?? "")
    }
    static func safeID(_ id: String) -> Bool {
        !id.isEmpty && id.count < 180 && id.allSatisfy { $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "-") }
    }
    static func pool(platform: WallpaperPlatform, favorites: Set<String>, previous: String?) -> [Wallpaper] {
        let all = WallpaperCatalog.wallpapers(for: platform)
        let saved = all.filter { favorites.contains($0.id) }
        let pool = saved.isEmpty ? all : saved
        let alternatives = pool.filter { $0.id != previous }
        return alternatives.isEmpty ? pool : alternatives
    }
}
