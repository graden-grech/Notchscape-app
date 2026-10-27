import Foundation

/// A bounded, declarative appearance document. No code, URLs, color archives,
/// permissions, accounts, hardware settings or seasonal scheduling are imported.
struct AppearanceRecipe: Codable, Identifiable, Equatable {
    static let maximumBytes = 16_384
    static let maximumSaved = 20
    static let maximumStorageBytes = 400_000
    static let widgets: Set<String> = ["calendar", "music", "weather", "quickActions"]
    var version = 1
    var id = UUID()
    var name: String
    var theme: String
    var accentHex: String?
    var icon: String
    var followsThemeIcon: Bool
    var homeOrder: [String]
    var hiddenWidgets: [String]
    var showsThemeDetails = false

    enum CodingKeys: String, CodingKey, CaseIterable {
        case version, id, name, theme, accentHex, icon, followsThemeIcon, homeOrder, hiddenWidgets, showsThemeDetails
    }
    init(version: Int = 1, id: UUID = UUID(), name: String, theme: String, accentHex: String?, icon: String,
         followsThemeIcon: Bool, homeOrder: [String], hiddenWidgets: [String], showsThemeDetails: Bool = false) {
        self.version = version; self.id = id; self.name = name; self.theme = theme; self.accentHex = accentHex
        self.icon = icon; self.followsThemeIcon = followsThemeIcon; self.homeOrder = homeOrder
        self.hiddenWidgets = hiddenWidgets; self.showsThemeDetails = showsThemeDetails
    }
    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        version = try values.decode(Int.self, forKey: .version); id = try values.decode(UUID.self, forKey: .id)
        name = try values.decode(String.self, forKey: .name); theme = try values.decode(String.self, forKey: .theme)
        accentHex = try values.decodeIfPresent(String.self, forKey: .accentHex); icon = try values.decode(String.self, forKey: .icon)
        followsThemeIcon = try values.decode(Bool.self, forKey: .followsThemeIcon)
        homeOrder = try values.decode([String].self, forKey: .homeOrder)
        hiddenWidgets = try values.decode([String].self, forKey: .hiddenWidgets)
        showsThemeDetails = try values.decodeIfPresent(Bool.self, forKey: .showsThemeDetails) ?? false
    }
    static func validName(_ name: String) -> Bool {
        !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && name.count <= 80 && name.utf8.count <= 320
            && !name.unicodeScalars.contains { CharacterSet.controlCharacters.contains($0) || CharacterSet.illegalCharacters.contains($0) }
    }
    static func rgb(_ hex: String) -> (Int, Int, Int)? {
        let value = hex.hasPrefix("#") ? String(hex.dropFirst()) : hex
        guard value.utf8.count == 6, value.unicodeScalars.allSatisfy({ $0.isASCII && CharacterSet(charactersIn: "0123456789abcdefABCDEF").contains($0) }),
              let n = UInt32(value, radix: 16) else { return nil }
        return (Int(n >> 16), Int((n >> 8) & 255), Int(n & 255))
    }
    func valid(themes: Set<String>, icons: Set<String>) -> Bool {
        version == 1 && Self.validName(name) && theme.utf8.count <= 64 && icon.utf8.count <= 64
            && themes.contains(theme) && icons.contains(icon)
            && (accentHex.map { Self.rgb($0) != nil } ?? true)
            && homeOrder.count <= 4 && Set(homeOrder).count == homeOrder.count && Set(homeOrder).isSubset(of: Self.widgets)
            && hiddenWidgets.count <= 4 && Set(hiddenWidgets).count == hiddenWidgets.count && Set(hiddenWidgets).isSubset(of: Self.widgets)
    }
    enum Invalid: Error { case recipe }
    static func decode(_ data: Data, themes: Set<String>, icons: Set<String>) throws -> Self {
        let allowed = Set(CodingKeys.allCases.map(\.rawValue))
        guard data.count <= maximumBytes, let object = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              Set(object.keys).isSubset(of: allowed) else { throw Invalid.recipe }
        let value = try JSONDecoder().decode(Self.self, from: data)
        guard value.valid(themes: themes, icons: icons) else { throw Invalid.recipe }
        return value
    }
    static func decodeSaved(_ data: Data, themes: Set<String>, icons: Set<String>) -> [Self] {
        guard data.count <= maximumStorageBytes,
              let objects = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]], objects.count <= maximumSaved else { return [] }
        var ids = Set<UUID>()
        return objects.compactMap { object in
            guard let item = try? JSONSerialization.data(withJSONObject: object),
                  let value = try? decode(item, themes: themes, icons: icons), ids.insert(value.id).inserted else { return nil }
            return value
        }
    }
}

/// In-memory only: scheduling and exact archived accent bytes are restored by
/// Undo, but are never part of a shared appearance document.
struct AppearanceRecipeUndo {
    let recipe: AppearanceRecipe
    let automaticSeasonal: Bool
    let customAccentEnabled: Bool
    let customAccentData: Data?
}

/// Static vector palettes, not downloaded or generated artwork. Text and system
/// controls retain their semantic styling over this decorative content layer.
enum NativeAppearanceStyle: String, CaseIterable, Identifiable, Sendable {
    case springBloom, summerCoast, nightSky, botanical, desertDusk, graphite
    var id: Self { self }
    var title: String {
        switch self {
        case .springBloom: "Spring Bloom"; case .summerCoast: "Summer Coast"; case .nightSky: "Night Sky"
        case .botanical: "Botanical"; case .desertDusk: "Desert Dusk"; case .graphite: "Graphite"
        }
    }
    var subtitle: String {
        switch self {
        case .springBloom: "Soft blossoms and fresh spring color"
        case .summerCoast: "Quiet waves and a sunlit horizon"
        case .nightSky: "A moonlit sky, without animation"
        case .botanical: "Deep greens and simple leaf silhouettes"
        case .desertDusk: "Warm dunes beneath a twilight sky"
        case .graphite: "Understated contours and neutral gray"
        }
    }
    var symbol: String {
        switch self {
        case .springBloom: "camera.macro"; case .summerCoast: "water.waves"; case .nightSky: "moon.stars.fill"
        case .botanical: "leaf.fill"; case .desertDusk: "sun.horizon.fill"; case .graphite: "circle.lefthalf.filled"
        }
    }
    var lightAccent: String {
        switch self {
        case .springBloom: "#A13670"; case .summerCoast: "#007B91"; case .nightSky: "#5753B7"
        case .botanical: "#297343"; case .desertDusk: "#A7462B"; case .graphite: "#5C616B"
        }
    }
    var darkAccent: String {
        switch self {
        case .springBloom: "#E397C1"; case .summerCoast: "#5CCAD9"; case .nightSky: "#A5A0F2"
        case .botanical: "#82BE8C"; case .desertDusk: "#EBAB82"; case .graphite: "#B8BDC8"
        }
    }
    var sky: [String] {
        switch self {
        case .springBloom: ["#152C2A", "#3D5361", "#8F5975"]
        case .summerCoast: ["#102D42", "#246279", "#72A8A8"]
        case .nightSky: ["#080E24", "#20264D", "#464773"]
        case .botanical: ["#0D201B", "#244B39", "#47604B"]
        case .desertDusk: ["#1D233E", "#795266", "#BC806C"]
        case .graphite: ["#101217", "#30343D", "#555B66"]
        }
    }
}
