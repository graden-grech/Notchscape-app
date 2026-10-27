import Foundation

@main
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
        print("PASS: \(checks) wallpaper, utilities and settings search checks")
    }
}
