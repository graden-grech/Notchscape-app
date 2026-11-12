import Foundation

@main
@MainActor
struct NotchUtilitiesPolicyTests {
    static var checks = 0
    static func check(_ value: @autoclosure () -> Bool, _ message: String) {
        precondition(value(), message); checks += 1
    }
    static func main() {
        check(CleanLinkPolicy.clean("https://example.com/article?utm_source=email&id=42&fbclid=abc#section") == "https://example.com/article?id=42#section", "Tracking only, preserve functional query and fragment")
        check(CleanLinkPolicy.clean(" https://example.com/?gclid=x \n") == "https://example.com/", "Trim input, remove empty tracking query")
        check(CleanLinkPolicy.clean("https://example.com/?q=a%20b&ref=friend") == "https://example.com/?q=a%20b&ref=friend", "Unchanged links preserve exact escapes and functional ref")
        check(CleanLinkPolicy.clean("https://example.com/?q=a%2Fb+%3D&UTM_source=x#t") == "https://example.com/?q=a%2Fb+%3D#t", "Cleaning preserves exact escapes of remaining query")
        check(CleanLinkPolicy.clean("https://example.com/?utm_source=x&signature=abc") == "https://example.com/?utm_source=x&signature=abc", "Never alter signed URLs")
        check(CleanLinkPolicy.clean("https://example.com/?X-Amz-Signature=a&utm_campaign=b") == "https://example.com/?X-Amz-Signature=a&utm_campaign=b", "Case insensitive signature protection")
        for input in ["javascript:alert(1)", "file:///etc/passwd", "mailto:test@example.com", "https://user:password@example.com/", "not a link", "https://", "https://example.com/a b"] {
            check(CleanLinkPolicy.clean(input) == nil, "Reject unsafe or invalid link")
        }
        check(CleanLinkPolicy.clean("https://example.com/" + String(repeating: "x", count: 16_384)) == nil, "Bound link size")
        let all = WallpaperCatalog.everyWallpaper
        check(all.count == 328, "Import 42 macOS, 265 Windows, 17 nature and 4 NASA sources")
        check(Set(all.map(\.id)).count == all.count, "Unique stable catalog IDs")
        for wallpaper in all {
            check(WallpaperPolicy.safeID(wallpaper.id), "Cache paths stay within the wallpaper directory")
            check(WallpaperPolicy.allowedURL(wallpaper.thumbnailURL), "Allowlisted preview")
            check(WallpaperPolicy.allowedURL(wallpaper.previewURL), "Allowlisted bounded preview")
            check(WallpaperPolicy.allowedURL(wallpaper.downloadURL), "Allowlisted full image")
        }
        for id in ["../secret", "a/b", "", "..", "a.jpg", "é", String(repeating: "a", count: 180)] {
            check(!WallpaperPolicy.safeID(id), "Reject unsafe path ID")
        }
        for url in ["http://media.512pixels.net/a.jpg", "https://example.com/a.jpg", "https://media.512pixels.net.evil.com/a.jpg", "https://u:p@media.512pixels.net/a.jpg", "file:///a.jpg"] {
            check(!WallpaperPolicy.allowedURL(URL(string: url)!), "Reject noncatalog or unencrypted URLs")
        }
        check(WallpaperRotation.off.seconds == nil, "No background rotation by default")
        check(WallpaperRotation.allCases.compactMap(\.seconds).min() == 1800, "Rotation cannot busy-loop")
        let one = WallpaperCatalog.all[0], two = WallpaperCatalog.all[1]
        check(WallpaperPolicy.pool(platform: .macOS, favorites: [one.id, two.id], previous: one.id).map(\.id) == [two.id], "Favorites preferred without immediate repeats")
        check(WallpaperPolicy.pool(platform: .macOS, favorites: [one.id], previous: one.id).map(\.id) == [one.id], "One favorite does not empty shuffle pool")
        check(!WallpaperPolicy.pool(platform: .macOS, favorites: ["not-in-catalog"], previous: nil).isEmpty, "Missing favorite falls back safely")
        check(SeasonalWallpaperCatalog.all.count == 46, "Seasonal collection preserves curation with verified additions")
        check(SpaceWallpaperCatalog.all.count == 4, "Official NASA Space collection")
        for theme in ["system", "autumn", "halloween", "christmas", "winter", "easter", "springBloom", "summerCoast", "nightSky", "botanical", "desertDusk", "graphite", "starWars", "starWarsDarkSide", "starWarsLuke", "starWarsObiWan", "starWarsAhsoka", "starWarsYoda", "starWarsMaceWindu", "starWarsRey", "starWarsVader", "starWarsMaul", "whiteHouse", "whiteHouseOvalOffice", "whiteHouseEastRoom", "whiteHouseBlueRoom", "whiteHouseRepublican", "whiteHouseRepublicanOvalOffice", "whiteHouseRepublicanEastRoom", "whiteHouseRepublicanBlueRoom", "whiteHouseDemocrat", "whiteHouseDemocratOvalOffice", "whiteHouseDemocratEastRoom", "whiteHouseDemocratBlueRoom"] {
            check(all.contains { WallpaperThemeMatch.matching(theme).contains($0) }, "Theme matching always has suggestions")
        }
        check(!all.contains { WallpaperThemeMatch.matching("winter").contains($0) && $0.name.localizedCaseInsensitiveContains("Christmas") }, "Neutral Winter does not suggest Christmas")
        for sort in WallpaperBrowseSort.allCases {
            check(Set(sort.sorted(all).map(\.id)) == Set(all.map(\.id)), "Sorting preserves catalog entries")
        }
        check(NotchSettingsDestination.all.first { $0.id == "HUD" }!.matches("volume permissions"), "Search matches settings keywords")
        check(NotchSettingsDestination.all.first { $0.id == "Wallpapers" }!.matches("macscapes"), "Find integrated library by old app name")
        check(NotchSettingsDestination.all.first { $0.id == "Tools" }!.matches("color picker"), "Find color picker under Tools")
        check(NotchSettingsDestination.all.first { $0.id == "Appearance" }!.matches("white house oval office"), "Find the White House room controls in Appearance")
        check(!NotchSettingsDestination.all.first { $0.id == "Tools" }!.matches("color volcano"), "All search words must match")
        check(NotchSettingsDestination.all.allSatisfy { $0.matches("  \n ") }, "Empty query restores sidebar")
        check(Set(NotchSettingsDestination.all.map(\.id)).count == NotchSettingsDestination.all.count, "Unique navigation IDs")
        for id in ["Themes", "HomeLayout", "AppIcon", "Effects", "MediaAppearance", "Weather", "Agents", "Sports", "Shortcuts", "Shelf", "Battery", "HUD"] {
            let parent = NotchSettingsDestination.parentID(for: id)
            check(parent != id && NotchSettingsDestination.sidebar.contains { $0.id == parent }, "Existing leaf routes retain a visible parent")
            check(NotchSettingsDestination.all.contains { $0.id == id }, "Existing section links remain addressable")
        }
        check(NotchSettingsDestination.sidebar.filter { $0.id != "Account" }.count == 14, "Related sections, Dock Workspace and the Add-ons store have native destinations")
        check(NotchSettingsDestination.sidebar.first { $0.id == "Dock" }!.matches("launcher widgets"), "Dock Workspace has its own searchable settings")
        check(NotchSettingsDestination.sidebar.first { $0.id == "Store" }!.matches("download plugins"), "Add-ons store is searchable")
        check(NotchSettingsDestination.sidebar.first { $0.id == "Appearance" }!.matchesIncludingChildren("fahrenheit"), "Weather search finds Appearance")
        check(NotchSettingsDestination.sidebar.first { $0.id == "Activities" }!.matchesIncludingChildren("codex"), "Agent search finds Live Activities")
        check(NotchSettingsDestination.sidebar.first { $0.id == "FaceUnlock" }!.matches("face id"), "Face Unlock has its own searchable destination")

        func results(_ query: String, accountsEnabled: Bool = false) -> [NotchSettingsDestination] {
            NotchSettingsDestination.destinations(matching: query, accountsEnabled: accountsEnabled)
        }
        let normalSidebarIDs = NotchSettingsDestination.sidebar.filter { $0.id != "Account" }.map(\.id)
        check(results("").map(\.id) == normalSidebarIDs, "Empty search preserves the grouped sidebar and its order")
        check(results(" \n\t ").map(\.id) == normalSidebarIDs, "Whitespace-only search restores the grouped sidebar")
        check(results("HUD").map(\.id) == ["HUD"], "Searching a child title exposes its actual destination, not the parent")
        check(results("volume permissions").map(\.id) == ["HUD"], "Multiple keywords navigate directly to HUD settings")
        check(results("fahrenheit").map(\.id) == ["Weather"], "Weather keyword no longer forces a detour through Appearance")
        check(results("codex").map(\.id) == ["Agents"], "Agent keyword exposes the actual AI Agents destination")
        check(results("system brightness").map(\.id) == ["HUD"], "A search can combine parent context and child keywords")
        check(results("appearance fahrenheit").map(\.id) == ["Weather"], "Parent context can qualify a child search")
        check(results("BATTERY").first?.id == "Battery", "A case-insensitive exact title outranks another page's keyword")
        check(results(" battery ").map(\.id) == results("BATTERY").map(\.id), "Search ignores outer whitespace and casing")
        check(results("face \n unlock").first?.id == "FaceUnlock", "Title ranking normalizes repeated whitespace")
        check(results("volcano xyz").isEmpty, "Unknown searches have an explicit empty result")
        check(results("volume volcano").isEmpty, "A matching keyword cannot hide another unmatched query word")
        check(!results("password passkey").contains { $0.id == "Account" }, "Disabled accounts stay absent from keyword results")
        check(results("account").isEmpty, "Disabled Account cannot be opened by searching its title")
        check(results("account", accountsEnabled: true).first?.id == "Account", "Enabled accounts are directly searchable")
        check(results("password passkey", accountsEnabled: true).map(\.id) == ["Account"], "Enabled account keywords use the established route")
        check(results("", accountsEnabled: true).map(\.id) == NotchSettingsDestination.sidebar.map(\.id), "Account enablement preserves normal sidebar order")
        check(results("Themes & Colors").first?.id == "Themes", "Theme controls have a direct focused search destination")
        check(results("Home Layout").first?.id == "HomeLayout", "Home controls are directly addressable")
        check(results("App Icon").first?.id == "AppIcon", "Icon controls are directly addressable")
        check(results("Player Appearance").first?.id == "MediaAppearance", "Player styling remains grouped under Media")
        let parentTitles = ["Themes": "Appearance", "HomeLayout": "Appearance", "AppIcon": "Appearance", "Effects": "Appearance", "MediaAppearance": "Media", "Weather": "Appearance", "Agents": "Live Activities", "Sports": "Live Activities",
                            "Shortcuts": "Tools & Shortcuts", "Shelf": "Tools & Shortcuts", "Battery": "System & Power", "HUD": "System & Power"]
        for destination in NotchSettingsDestination.all {
            check(destination.parentTitle == parentTitles[destination.id], "Only child results carry their existing parent breadcrumb")
        }
        for query in ["HUD", "volume", "weather", "codex", "live activities", "system", "battery", "dock", "appearance", "face unlock", "\u{1F383}"] {
            let first = results(query), second = results(query)
            check(first.map(\.id) == second.map(\.id), "Repeated search has stable ranking")
            check(Set(first.map(\.id)).count == first.count, "A destination appears only once in search results")
            check(first.allSatisfy { result in NotchSettingsDestination.all.contains { $0.id == result.id } && result.id != "Account" }, "Search exposes only known enabled routes")
        }
        print("PASS: \(checks) wallpaper, utilities and settings search checks")
    }
}
