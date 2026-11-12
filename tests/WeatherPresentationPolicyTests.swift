import Foundation

@main
@MainActor
struct WeatherPresentationPolicyTests {
    static var count = 0
    static func check(_ value: @autoclosure () -> Bool, _ message: String) { precondition(value(), message); count += 1 }
    static func main() {
        let examples: [(Int?, WeatherTilePresentation.Sky)] = [(0,.clear),(1,.partlyCloudy),(2,.partlyCloudy),(3,.overcast),(45,.fog),(48,.fog),(51,.rain),(57,.rain),(61,.rain),(67,.rain),(80,.rain),(82,.rain),(71,.snow),(77,.snow),(85,.snow),(86,.snow),(95,.storm),(99,.storm),(nil,.unknown),(-1,.unknown),(4,.unknown),(100,.unknown)]
        for (code, sky) in examples {
            for day in [false,true] {
                for mask in 0..<16 {
                    let low = mask&1 != 0, transparency = mask&2 != 0, contrast = mask&4 != 0, motion = mask&8 != 0
                    let p = WeatherTilePresentation(code: code, isDay: day, lowImpact: low, reduceTransparency: transparency, increasedContrast: contrast, reduceMotion: motion)
                    check(p.sky == sky, "Weather families preserve known WMO ranges and unknown fallbacks")
                    check(p.showsAtmosphere == !(low || transparency || contrast), "Decorative drawing disabled for accessibility and low impact")
                    check(p.nativeGlassAllowed == !(low || transparency || contrast), "Native lens request shares opaque/low-impact restrictions")
                    check(p.suppressMotion == (low || motion), "Reduce Motion and low impact disable implicit transitions")
                    if contrast || transparency { check(p.top == p.bottom, "Opaque accessibility fallback uses one quiet color") }
                    if sky == .clear { check(p.conditionSymbol == (day ? "sun.max.fill" : "moon.stars.fill"), "Clear nights never show a sun") }
                    if sky == .partlyCloudy { check(p.conditionSymbol == (day ? "cloud.sun.fill" : "cloud.moon.fill"), "Partly cloudy night uses moon symbol") }
                    for step in 0...10 {
                        let t = Double(step)/10
                        let c = WeatherTilePresentation.RGB(p.top.red+(p.bottom.red-p.top.red)*t, p.top.green+(p.bottom.green-p.top.green)*t, p.top.blue+(p.bottom.blue-p.top.blue)*t)
                        check(c.highlighted(by: p.highlightOpacity).contrastAgainstWhite >= (contrast ? 7 : 4.5), "White labels remain readable across sky and bounded light wash")
                    }
                }
            }
        }
        check(WeatherTilePresentation.tileWidth == 144 && WeatherTilePresentation.cornerRadius == 20, "Existing tile geometry retained")
        check(WeatherTilePresentation.temperature(-0.2) == "0°", "No negative zero")
        check(WeatherTilePresentation.temperature(21.6) == "22°", "Temperature rounds normally")
        check(WeatherTilePresentation.temperature(-12.6) == "-13°", "Cold temperatures preserve their sign")
        for value in [Double.nan, Double.infinity, -Double.infinity, 1e10] { check(WeatherTilePresentation.temperature(value) == "—", "Invalid numbers never render NaN/infinity or overflow") }
        check(WeatherTilePresentation.locationLabel("Current location") == "My Location", "Existing local-weather label retained")
        check(WeatherTilePresentation.locationLabel("  ") == "Weather", "Empty locations have a real fallback")
        check(WeatherTilePresentation.locationLabel(String(repeating: "x", count: 200)).count == 100, "Location labels remain bounded")
        print("PASS: \(count) synthetic weather presentation, contrast, accessibility and geometry checks")
    }
}
