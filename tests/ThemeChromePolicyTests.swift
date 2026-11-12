import Foundation

#if THEME_CHROME_POLICY_TEST
enum AgentActivityState: String, Codable { case working, needsInput, completed, interrupted, usageLimited }
#endif

@main struct ThemeChromePolicyTests {
    static func main() {
        var checks = 0
        func check(_ condition: @autoclosure () -> Bool, _ message: String) {
            precondition(condition(), message); checks += 1
        }
        let themes = ["system", "autumn", "halloween", "christmas", "winter", "easter",
                      "springBloom", "summerCoast", "nightSky", "botanical", "desertDusk", "graphite"]
            + WhiteHouseThemeVariant.allCases.map(\.rawValue)
            + CityscapeScene.allCases.map(\.rawValue)
            + StarWarsThemeVariant.allCases.map(\.rawValue)
        for id in themes {
            check(!ThemeChromePolicy.sidebarUsesThemeAccent(themeID: id, alwaysMulticolor: true),
                  "The explicit multicolor override wins for every theme family")
            check(ThemeChromePolicy.sidebarUsesThemeAccent(themeID: id, alwaysMulticolor: false) == (id != "system"),
                  "System retains section colors; other themes may use their effective accent")
        }
        for variant in WhiteHouseThemeVariant.allCases {
            check(ThemeChromePolicy.showsChristmasTrim(themeID: variant.rawValue) == variant.isChristmas,
                  "Every room and palette consistently honors its existing Christmas choice")
        }
        check(ThemeChromePolicy.showsChristmasTrim(themeID: "christmas"), "The standalone Christmas theme shares Settings décor")
        for id in themes where id != "christmas" && WhiteHouseThemeVariant(rawValue: id) == nil {
            check(!ThemeChromePolicy.showsChristmasTrim(themeID: id), "Other themes never acquire Christmas décor")
        }
        for id in ["unknownChristmas", "whiteHouseChristmasUnknown", "Christmas", "winterChristmas"] {
            check(!ThemeChromePolicy.showsChristmasTrim(themeID: id), "Unknown values do not trigger décor by substring")
        }

        func luminance(_ channel: Double) -> Double {
            channel <= 0.04045 ? channel / 12.92 : pow((channel + 0.055) / 1.055, 2.4)
        }
        let home = ThemeChromePolicy.sceneScrim(isHome: true, reduceTransparency: false)
        let content = ThemeChromePolicy.sceneScrim(isHome: false, reduceTransparency: false)
        let reducedHome = ThemeChromePolicy.sceneScrim(isHome: true, reduceTransparency: true)
        let reducedContent = ThemeChromePolicy.sceneScrim(isHome: false, reduceTransparency: true)
        check(home.trailing < home.leading, "Home's photo showcase lane remains visible")
        check(content.trailing > home.trailing, "Full-width tabs protect the former photo showcase lane")
        for opacity in [content.leading, content.middle, content.trailing] {
            // Worst-case white photography; secondary text at 60% white must
            // still reach a 4.5:1 contrast ratio after compositing.
            let background = 1 - opacity
            let secondary = 0.6 + 0.4 * background
            let contrast = (luminance(secondary) + 0.05) / (luminance(background) + 0.05)
            check(contrast >= 4.5, "Every point of non-Home scenes supports readable secondary text")
        }
        check(reducedHome == reducedContent, "Reduce Transparency has consistent readability across tabs")
        for (ordinary, reduced) in [(home.leading, reducedHome.leading), (home.middle, reducedHome.middle),
                                    (home.trailing, reducedHome.trailing), (content.leading, reducedContent.leading),
                                    (content.middle, reducedContent.middle), (content.trailing, reducedContent.trailing)] {
            check(reduced >= ordinary && (0...1).contains(reduced), "Accessibility never weakens the content backing")
        }
        print("PASS \(checks) theme chrome behavior checks")
    }
}
