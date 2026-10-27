import Foundation
import CoreFoundation

/// Release hold, not an authentication/authorization boundary. Missing or
/// malformed configuration must never enable the unfinished account feature.
enum AccountFeaturePolicy {
    static let enabled = isEnabled(Bundle.main.object(forInfoDictionaryKey: "NotchAccountsEnabled"))

    static func isEnabled(_ value: Any?) -> Bool {
        guard let number = value as? NSNumber,
              CFGetTypeID(number) == CFBooleanGetTypeID() else { return false }
        return number.boolValue
    }
}

/// This is deliberately not a dump of UserDefaults. Permissions, files, commands,
/// display IDs, credentials, locations and AI/calendar contents never enter sync.
enum AccountSettingValue: Codable, Equatable {
    case bool(Bool), string(String), strings([String])

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let value = try? container.decode(Bool.self) { self = .bool(value) }
        else if let value = try? container.decode(String.self) { self = .string(value) }
        else { self = .strings(try container.decode([String].self)) }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .bool(let value): try container.encode(value)
        case .string(let value): try container.encode(value)
        case .strings(let value): try container.encode(value)
        }
    }
}

struct AccountSettingsDocument: Codable, Equatable {
    var schemaVersion: Int = 1
    var values: [String: AccountSettingValue]

    init(schemaVersion: Int = 1, values: [String: AccountSettingValue]) {
        self.schemaVersion = schemaVersion
        self.values = values
    }

    // Validate nested API documents too, not only standalone import files.
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: Field.self)
        guard Set(container.allKeys.map(\.stringValue)) == ["schemaVersion", "values"] else {
            throw AccountSettingsError.invalidDocument
        }
        schemaVersion = try container.decode(Int.self, forKey: Field("schemaVersion"))
        values = try container.decode([String: AccountSettingValue].self, forKey: Field("values"))
        _ = try validated()
    }

    private struct Field: CodingKey {
        let stringValue: String
        var intValue: Int? { nil }
        init(_ value: String) { stringValue = value }
        init?(stringValue: String) { self.stringValue = stringValue }
        init?(intValue: Int) { return nil }
    }

    func validated() throws -> Self {
        guard schemaVersion == 1, values.count <= 40 else { throw AccountSettingsError.invalidDocument }
        for (key, value) in values {
            if AccountSettingsPolicy.booleans.contains(key), case .bool = value { continue }
            if let options = AccountSettingsPolicy.choices[key], case .string(let text) = value,
               options.contains(text) { continue }
            if AccountSettingsPolicy.lists.contains(key), case .strings(let items) = value,
               items.count <= 4, Set(items).count == items.count,
               items.allSatisfy(AccountSettingsPolicy.widgets.contains) { continue }
            throw AccountSettingsError.invalidDocument
        }
        return self
    }

    func encoded() throws -> Data {
        _ = try validated()
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let data = try encoder.encode(self)
        guard data.count <= 8_192 else { throw AccountSettingsError.invalidDocument }
        return data
    }

    static func decode(_ data: Data) throws -> Self {
        guard data.count <= 8_192,
              let object = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              Set(object.keys) == ["schemaVersion", "values"]
        else { throw AccountSettingsError.invalidDocument }
        return try JSONDecoder().decode(Self.self, from: data).validated()
    }
}

enum AccountSettingsPolicy {
    static let booleans: Set<String> = [
        "appIconFollowsTheme", "automaticSeasonalThemes", "seasonalHalloween", "seasonalChristmas",
        "weatherOnLiveTab", "tileShowLabels", "playerColorTinting", "useMusicVisualizer",
        "showShuffleAndRepeat", "coloredSpectrogram", "showBatteryIndicator", "showBatteryPercentage",
        "showPowerStatusIcons", "hideBatteryWhenAbsent", "hideCompletedReminders"
    ]
    static let choices: [String: Set<String>] = [
        "appTheme": ["system", "autumn", "halloween", "christmas", "winter", "easter",
                     "springBloom", "summerCoast", "nightSky", "botanical", "desertDusk", "graphite",
                     "starWars", "starWarsDarkSide", "starWarsLuke", "starWarsObiWan", "starWarsAhsoka",
                     "starWarsYoda", "starWarsMaceWindu", "starWarsRey", "starWarsVader", "starWarsMaul",
                     "whiteHouse", "whiteHouseOvalOffice", "whiteHouseEastRoom", "whiteHouseBlueRoom",
                     "whiteHouseRepublican", "whiteHouseRepublicanOvalOffice", "whiteHouseRepublicanEastRoom", "whiteHouseRepublicanBlueRoom",
                     "whiteHouseDemocrat", "whiteHouseDemocratOvalOffice", "whiteHouseDemocratEastRoom", "whiteHouseDemocratBlueRoom",
                     "whiteHouseChristmas", "whiteHouseChristmasOvalOffice", "whiteHouseChristmasEastRoom", "whiteHouseChristmasBlueRoom",
                     "whiteHouseRepublicanChristmas", "whiteHouseRepublicanChristmasOvalOffice", "whiteHouseRepublicanChristmasEastRoom", "whiteHouseRepublicanChristmasBlueRoom",
                     "whiteHouseDemocratChristmas", "whiteHouseDemocratChristmasOvalOffice", "whiteHouseDemocratChristmasEastRoom", "whiteHouseDemocratChristmasBlueRoom",
                     "cityNewYork", "cityChicago", "cityDetroit", "cityBoston", "cityPhiladelphia", "cityWashingtonDC",
                     "cityLosAngeles", "citySanFrancisco", "citySeattle", "cityLasVegas", "cityMiami", "cityNewOrleans"],
        "appIconVariant": ["standard", "autumn", "halloween", "christmas", "winter", "easter", "whiteHouse",
                           "whiteHouseRepublican", "whiteHouseDemocrat", "whiteHouseRepublicanChristmas", "whiteHouseDemocratChristmas"],
        "seasonHemisphere": ["northern", "southern"],
        "batteryPresentation": ["original", "enhanced"],
        "batteryIndicatorDisplay": ["iconOnly", "percentageOnly", "both"]
    ]
    static let lists: Set<String> = ["homeWidgetOrder", "hiddenHomeWidgets"]
    static let widgets: Set<String> = ["music", "calendar", "weather", "quickActions"]
}

enum AccountSettingsError: LocalizedError {
    case invalidDocument, notConfigured, signedOut, cloudNotConfigured, conflict, rejected, keychain, verifyEmail
    var errorDescription: String? {
        switch self {
        case .invalidDocument: "The saved settings are invalid or from an unsupported version. Nothing was applied."
        case .notConfigured: "Account sign-in has not been configured for this build."
        case .signedOut: "Please sign in again. Your local settings are unchanged."
        case .cloudNotConfigured: "Cloud settings are not available in this build yet. Local settings still work."
        case .conflict: "Settings changed on another Mac. Choose which copy to keep before syncing again."
        case .rejected: "The account service could not complete this request. Please try again later."
        case .keychain: "The session could not be saved securely in Keychain. Please try again."
        case .verifyEmail: "Verify your email, then refresh your account status before syncing. Your local settings are unchanged."
        }
    }
}
