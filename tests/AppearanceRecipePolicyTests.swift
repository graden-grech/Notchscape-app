import Foundation

@main
struct AppearanceRecipePolicyTests {
    static var checks = 0
    static let whiteHouseThemes = ["whiteHouse", "whiteHouseOvalOffice", "whiteHouseEastRoom", "whiteHouseBlueRoom",
        "whiteHouseRepublican", "whiteHouseRepublicanOvalOffice", "whiteHouseRepublicanEastRoom", "whiteHouseRepublicanBlueRoom",
        "whiteHouseDemocrat", "whiteHouseDemocratOvalOffice", "whiteHouseDemocratEastRoom", "whiteHouseDemocratBlueRoom",
        "whiteHouseChristmas", "whiteHouseChristmasOvalOffice", "whiteHouseChristmasEastRoom", "whiteHouseChristmasBlueRoom",
        "whiteHouseRepublicanChristmas", "whiteHouseRepublicanChristmasOvalOffice", "whiteHouseRepublicanChristmasEastRoom", "whiteHouseRepublicanChristmasBlueRoom",
        "whiteHouseDemocratChristmas", "whiteHouseDemocratChristmasOvalOffice", "whiteHouseDemocratChristmasEastRoom", "whiteHouseDemocratChristmasBlueRoom"]
    static let cityscapeThemes = ["cityNewYork", "cityChicago", "cityDetroit", "cityBoston", "cityPhiladelphia", "cityWashingtonDC",
        "cityLosAngeles", "citySanFrancisco", "citySeattle", "cityLasVegas", "cityMiami", "cityNewOrleans"]
    static let themes = Set(["system", "autumn", "halloween", "christmas", "winter", "easter", "starWars", "starWarsVader"] + NativeAppearanceStyle.allCases.map(\.rawValue) + whiteHouseThemes + cityscapeThemes)
    static let icons: Set<String> = ["standard", "autumn", "halloween", "christmas", "winter", "easter", "whiteHouse",
        "whiteHouseRepublican", "whiteHouseDemocrat", "whiteHouseRepublicanChristmas", "whiteHouseDemocratChristmas"]
    static func check(_ result: @autoclosure () -> Bool, _ reason: String) {
        precondition(result(), reason); checks += 1
    }
    static func luminance(_ hex: String) -> Double {
        let (r, g, b) = AppearanceRecipe.rgb(hex)!
        let linear = [r, g, b].map { value -> Double in
            let c = Double(value) / 255
            return c <= 0.04045 ? c / 12.92 : pow((c + 0.055) / 1.055, 2.4)
        }
        return linear[0] * 0.2126 + linear[1] * 0.7152 + linear[2] * 0.0722
    }
    static func main() throws {
        let recipe = AppearanceRecipe(name: "My Appearance", theme: "system", accentHex: "#12ABEF", icon: "standard",
            followsThemeIcon: true, homeOrder: ["calendar", "music", "weather", "quickActions"], hiddenWidgets: ["weather"])
        let data = try JSONEncoder().encode(recipe)
        let decoded = try AppearanceRecipe.decode(data, themes: themes, icons: icons)
        check(decoded == recipe, "Appearance document roundtrip")
        for icon in icons.filter({ $0.hasPrefix("whiteHouse") }) {
            var value = recipe
            value.theme = "whiteHouseDemocratChristmasOvalOffice"
            value.icon = icon; value.followsThemeIcon = false
            let restored = try AppearanceRecipe.decode(JSONEncoder().encode(value), themes: themes, icons: icons)
            check(restored == value, "Every White House icon can be manually saved independently of the theme")
            check(restored.accentHex == recipe.accentHex, "New icons preserve a saved custom accent")
        }
        for theme in whiteHouseThemes {
            for followsTheme in [false, true] {
                var value = recipe
                value.theme = theme; value.icon = followsTheme ? "whiteHouse" : "winter"; value.followsThemeIcon = followsTheme
                let restored = try AppearanceRecipe.decode(JSONEncoder().encode(value), themes: themes, icons: icons)
                check(restored == value, "White House room, accent style, custom accent and manual/theme icon roundtrip together")
                check(restored.homeOrder == recipe.homeOrder && restored.hiddenWidgets == recipe.hiddenWidgets, "Theme choices preserve full calendar/music/Home layout")
            }
        }
        for theme in cityscapeThemes {
            for followsTheme in [false, true] {
                var value = recipe
                value.theme = theme; value.icon = followsTheme ? "standard" : "winter"; value.followsThemeIcon = followsTheme
                let restored = try AppearanceRecipe.decode(JSONEncoder().encode(value), themes: themes, icons: icons)
                check(restored == value, "Every city restores with its custom accent and manual or matching icon preference")
                check(restored.homeOrder == recipe.homeOrder && restored.hiddenWidgets == recipe.hiddenWidgets,
                      "City changes preserve the saved Home layout")
            }
        }
        var object = try JSONSerialization.jsonObject(with: data) as! [String: Any]
        let original = object
        func rejects(_ value: Any, _ reason: String) throws {
            let data = try JSONSerialization.data(withJSONObject: value, options: [.fragmentsAllowed])
            do { _ = try AppearanceRecipe.decode(data, themes: themes, icons: icons); preconditionFailure(reason) }
            catch { checks += 1 }
        }
        for key in ["automaticSeasonalThemes", "showDockIcon", "notes", "clipboard", "permissions", "role", "url", "command", "__proto__"] {
            var bad = original; bad[key] = "admin; DROP TABLE users"
            try rejects(bad, "Unknown and security-sensitive fields rejected")
        }
        for version in [-1, 0, 2, 1000] { var bad = original; bad["version"] = version; try rejects(bad, "Unsupported schema") }
        for name in ["", "  \n ", String(repeating: "a", count: 81), "name\0", "name\nnext", "name\tmore"] {
            var bad = original; bad["name"] = name; try rejects(bad, "Bounded single-line names")
        }
        for name in ["admin", "DROP TABLE users;", "My 🌿 Appearance", String(repeating: "a", count: 80)] {
            check(AppearanceRecipe.validName(name), "Names are inert display data, not executable commands")
        }
        for hex in ["", "#123", "1234567", "#GG0011", "#12ABEF\0", "＃12ABEF", "#１２３４５６"] {
            var bad = original; bad["accentHex"] = hex; try rejects(bad, "Strict ASCII RGB values")
        }
        for hex in ["#000000", "ffffff", "#12ABef"] {
            check(AppearanceRecipe.rgb(hex) != nil, "Safe hex color accepted")
        }
        for key in ["theme", "icon"] {
            var bad = original; bad[key] = "file:///private/secret"; try rejects(bad, "Known themes/icons only")
        }
        for key in ["homeOrder", "hiddenWidgets"] {
            for values in [["music", "music"], ["admin"], Array(repeating: "calendar", count: 5)] {
                var bad = original; bad[key] = values; try rejects(bad, "Bounded unique known widgets")
            }
        }
        for key in ["followsThemeIcon", "showsThemeDetails"] {
            var bad = original; bad[key] = "true"; try rejects(bad, "Booleans cannot be string-injected")
        }
        try rejects([original], "Root must be one object")
        try rejects(NSNull(), "Root cannot be null")
        object.removeValue(forKey: "showsThemeDetails")
        let old = try AppearanceRecipe.decode(JSONSerialization.data(withJSONObject: object), themes: themes, icons: icons)
        check(!old.showsThemeDetails, "Legacy recipes keep optional detail off")
        for key in ["version", "id", "name", "theme", "icon", "followsThemeIcon", "homeOrder", "hiddenWidgets"] {
            var bad = original; bad.removeValue(forKey: key); try rejects(bad, "Required field cannot disappear")
        }
        do { _ = try AppearanceRecipe.decode(Data(repeating: 32, count: AppearanceRecipe.maximumBytes + 1), themes: themes, icons: icons); preconditionFailure("Oversize import") }
        catch { checks += 1 }
        let saved = try JSONEncoder().encode([recipe, recipe])
        check(AppearanceRecipe.decodeSaved(saved, themes: themes, icons: icons).count == 1, "Duplicate local IDs deduplicated")
        let tooMany = try JSONEncoder().encode(Array(repeating: recipe, count: 21))
        check(AppearanceRecipe.decodeSaved(tooMany, themes: themes, icons: icons).isEmpty, "At most20 saved records")
        check(AppearanceRecipe.decodeSaved(Data(repeating: 32, count: AppearanceRecipe.maximumStorageBytes + 1), themes: themes, icons: icons).isEmpty, "Bound local file")
        for flag in [false, true] {
            let bytes = Data([0, 1, 254, 255])
            let undo = AppearanceRecipeUndo(recipe: recipe, automaticSeasonal: flag, customAccentEnabled: flag, customAccentData: bytes)
            check(undo.automaticSeasonal == flag && undo.customAccentEnabled == flag && undo.customAccentData == bytes, "Undo retains scheduling flag and exact private accent bytes")
        }
        check(!Set(original.keys).contains("automaticSeasonal"), "Undo metadata is never exported")
        check(NativeAppearanceStyle.allCases.count == 6, "Six coherent native palette themes")
        check(Set(NativeAppearanceStyle.allCases.map(\.rawValue)) == ["springBloom", "summerCoast", "nightSky", "botanical", "desertDusk", "graphite"], "Stable theme IDs")
        for style in NativeAppearanceStyle.allCases {
            var value = recipe; value.theme = style.rawValue
            check(value.valid(themes: themes, icons: icons), "New theme recipes accepted")
            check(!style.title.isEmpty && !style.subtitle.isEmpty && !style.symbol.isEmpty, "Accessible theme metadata")
            check(style.sky.count == 3, "Stable static vector palette")
            for hex in style.sky + [style.lightAccent, style.darkAccent] {
                check(AppearanceRecipe.rgb(hex) != nil, "Native theme uses bounded sRGB color")
            }
            check(1.05 / (luminance(style.lightAccent) + 0.05) >= 4.5, "Light accent is readable on white")
            check((luminance(style.darkAccent) + 0.05) / (luminance("#111111") + 0.05) >= 4.5, "Dark accent is readable on the notch content background")
        }
        print("PASS: \(checks) bounded appearance recipe, undo snapshot, and native theme policy checks")
    }
}
