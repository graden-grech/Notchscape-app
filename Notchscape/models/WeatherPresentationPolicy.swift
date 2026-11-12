import Foundation

/// Pure rendering decisions only. No weather requests, location, timers or saved preferences.
struct WeatherTilePresentation: Equatable {
    enum Sky: CaseIterable { case clear, partlyCloudy, overcast, fog, rain, snow, storm, unknown }
    struct RGB: Equatable {
        let red: Double
        let green: Double
        let blue: Double
        init(_ red: Double, _ green: Double, _ blue: Double) { self.red = red; self.green = green; self.blue = blue }
        func highlighted(by opacity: Double) -> Self {
            .init(red + (1-red)*opacity, green + (1-green)*opacity, blue + (1-blue)*opacity)
        }
        var contrastAgainstWhite: Double {
            func linear(_ value: Double) -> Double { value <= 0.04045 ? value/12.92 : pow((value+0.055)/1.055, 2.4) }
            return 1.05 / (0.2126*linear(red) + 0.7152*linear(green) + 0.0722*linear(blue) + 0.05)
        }
    }
    static let tileWidth: Double = 144
    static let cornerRadius: Double = 20
    static let maximumHighlightOpacity: Double = 0.06

    let sky: Sky
    let isDay: Bool
    let simplified: Bool
    let increasedContrast: Bool
    let suppressMotion: Bool
    let top: RGB
    let bottom: RGB

    init(code: Int?, isDay: Bool, lowImpact: Bool, reduceTransparency: Bool,
         increasedContrast: Bool, reduceMotion: Bool) {
        switch code ?? -1 {
        case 0: sky = .clear
        case 1, 2: sky = .partlyCloudy
        case 3: sky = .overcast
        case 45, 48: sky = .fog
        case 51...57, 61...67, 80...82: sky = .rain
        case 71...77, 85, 86: sky = .snow
        case 95...99: sky = .storm
        default: sky = .unknown
        }
        self.isDay = isDay
        self.increasedContrast = increasedContrast
        simplified = lowImpact || reduceTransparency || increasedContrast
        suppressMotion = lowImpact || reduceMotion
        let palette: (RGB, RGB)
        if !isDay {
            palette = sky == .storm ? (.init(0.16, 0.15, 0.26), .init(0.06, 0.07, 0.14))
                                   : (.init(0.10, 0.15, 0.30), .init(0.035, 0.065, 0.145))
        } else {
            switch sky {
            case .clear: palette = (.init(0.12, 0.36, 0.65), .init(0.09, 0.22, 0.45))
            case .partlyCloudy: palette = (.init(0.17, 0.36, 0.57), .init(0.12, 0.25, 0.43))
            case .overcast: palette = (.init(0.27, 0.36, 0.45), .init(0.15, 0.23, 0.33))
            case .fog: palette = (.init(0.29, 0.35, 0.40), .init(0.17, 0.23, 0.29))
            case .rain: palette = (.init(0.20, 0.31, 0.43), .init(0.11, 0.18, 0.29))
            case .snow: palette = (.init(0.23, 0.37, 0.48), .init(0.13, 0.25, 0.36))
            case .storm: palette = (.init(0.23, 0.25, 0.38), .init(0.11, 0.14, 0.26))
            case .unknown: palette = (.init(0.18, 0.28, 0.42), .init(0.10, 0.16, 0.27))
            }
        }
        // Opaque, quiet backgrounds when contrast/transparency demands it.
        top = reduceTransparency || increasedContrast ? palette.1 : palette.0
        bottom = palette.1
    }

    var conditionSymbol: String {
        switch sky {
        case .clear: isDay ? "sun.max.fill" : "moon.stars.fill"
        case .partlyCloudy: isDay ? "cloud.sun.fill" : "cloud.moon.fill"
        case .overcast, .unknown: "cloud.fill"
        case .fog: "cloud.fog.fill"
        case .rain: "cloud.rain.fill"
        case .snow: "cloud.snow.fill"
        case .storm: "cloud.bolt.rain.fill"
        }
    }
    var showsAtmosphere: Bool { !simplified }
    var nativeGlassAllowed: Bool { !simplified }
    var highlightOpacity: Double { showsAtmosphere ? Self.maximumHighlightOpacity : 0 }

    static func temperature(_ value: Double) -> String {
        guard value.isFinite, (-300...300).contains(value) else { return "—" }
        let rounded = value.rounded()
        return (rounded == 0 ? "0" : rounded.formatted(.number.precision(.fractionLength(0)))) + "°"
    }

    static func locationLabel(_ value: String) -> String {
        let label = value.trimmingCharacters(in: .whitespacesAndNewlines)
        if label == "Current location" { return "My Location" }
        return label.isEmpty ? "Weather" : String(label.prefix(100))
    }
}
