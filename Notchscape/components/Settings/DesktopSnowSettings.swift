import Defaults
import SwiftUI

/// Desktop decoration is independent of menu themes and starts only by choice.
struct DesktopSnowSettings: View {
    @ObservedObject private var snow = DesktopSnowManager.shared
    @Default(.desktopSnowEnabled) private var enabled
    @Default(.desktopSnowIntensity) private var intensity
    @Default(.desktopSnowSpeed) private var speed
    @Default(.desktopSnowWind) private var wind
    @Default(.desktopSnowAccumulation) private var accumulation
    @Default(.desktopSnowWindowEdges) private var windowEdges
    @Default(.desktopSnowAllDisplays) private var allDisplays
    @Default(.desktopSnowHomeWidgets) private var homeWidgets

    var body: some View {
        Section {
            Toggle(isOn: $enabled) {
                Label("Let it snow", systemImage: "snowflake")
            }
            Text("Soft snowfall across your desktop, gathering in little rounded piles along the bottom edge and Dock. Your menu theme stays independent.")
                .font(.callout).foregroundStyle(.secondary)

            if enabled {
                Text(snow.statusText).font(.caption).foregroundStyle(.secondary)
                LabeledContent("Snowfall") {
                    Slider(value: $intensity, in: 0.15...1)
                        .frame(width: 170).accessibilityLabel("Snowfall amount")
                    Text(intensity < 0.4 ? "Light" : intensity < 0.75 ? "Steady" : "Heavy")
                        .font(.callout).foregroundStyle(.secondary).frame(width: 52, alignment: .trailing)
                }
                Toggle("Let snow settle", isOn: $accumulation)
                Toggle("Snow on Home widgets", isOn: $homeWidgets)
                Toggle("Settle on windows and the macOS Dock", isOn: $windowEdges)
                    .disabled(!accumulation).opacity(accumulation ? 1 : 0.45)
                Text("Window snow uses window positions, never pictures or the words inside them. It falls away as windows move or close.")
                    .font(.caption).foregroundStyle(.secondary)

                DisclosureGroup("Snowfall options") {
                    LabeledContent("Fall speed") {
                        Slider(value: $speed, in: 0.5...1.8)
                            .frame(width: 180).accessibilityLabel("Snowfall speed")
                    }
                    LabeledContent("Breeze") {
                        Slider(value: $wind, in: -1...1)
                            .frame(width: 180).accessibilityLabel("Snowfall breeze")
                    }
                    Toggle("Show on all enabled displays", isOn: $allDisplays)
                }
                HStack {
                    Button("Clear settled snow", systemImage: "wind") {
                        DesktopSnowManager.shared.clearSnow()
                    }.notchGlassButton()
                    Spacer()
                    Button("Stop snow", systemImage: "snowflake.slash") { enabled = false }
                        .notchGlassButton()
                }
            }
        } header: {
            Text("Desktop snow")
        } footer: {
            Text("Clicks pass through the snow. It pauses while your Mac is locked or asleep, in Presentation mode, and when Reduce Motion is enabled. Low-impact mode limits the animation.")
        }
    }
}
