import Defaults
import SwiftUI

enum AppearancePage: String {
    case themes = "Themes & Colors"
    case home = "Home Layout"
    case icon = "App Icon"
    case effects = "Effects & Mirror"
    case media = "Player Appearance"
}

/// A calm entry point; each category opens the existing controls on a focused page.
struct AppearanceOverview: View {
    @Default(.appTheme) private var theme
    @Default(.appIconFollowsTheme) private var iconFollowsTheme
    @Default(.useCustomAccentColor) private var customAccent

    var body: some View {
        Form {
            Section("Personalize") {
                SettingsSubpageLink(destinationID: "Themes", subtitle: "\(theme.pickerTitle) · \(customAccent ? "Custom accent" : "Automatic accent")")
                SettingsSubpageLink(destinationID: "HomeLayout", subtitle: "Choose and arrange your tiles and quick actions")
                SettingsSubpageLink(destinationID: "AppIcon", subtitle: iconFollowsTheme ? "Matches your theme" : "Choose an independent icon")
                SettingsSubpageLink(destinationID: "Effects", subtitle: "Desktop snow, scene details, and mirror shapes")
            }

            Section("Weather") {
                SettingsSubpageLink(destinationID: "Weather", subtitle: "Location, forecast, and where the tile appears")
            }
        }
        .navigationTitle("Appearance")
    }
}
