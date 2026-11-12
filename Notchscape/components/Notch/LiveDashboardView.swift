import Defaults
import SwiftUI

/// Presentation only: hooks and diagnostics retain their original event text.
/// A tool identifier is not a useful status label in a compact activity card.
enum AgentActivityTextPresentation {
    static func summary(state: AgentActivityState, detail: String) -> String {
        switch state {
        case .completed: return "Task completed"
        case .needsInput: return "Waiting for you"
        case .interrupted: return "Task paused"
        case .usageLimited: return "Usage limit reached"
        case .working: break
        }

        let event = String(detail.prefix(256)).lowercased()
        if event == "thinking" { return "Thinking" }
        if event == "subagent started" { return "Working with a helper" }
        if event.hasPrefix("using ") {
            if event.contains("exec_command") || event.contains("shell") || event.contains("terminal") {
                return "Running a command"
            }
            if event.contains("search") || event.contains("browse") || event.contains("fetch") {
                return "Looking up information"
            }
            if event.contains("read_file") || event.contains("readfile") || event.contains("find_symbol") {
                return "Reviewing files"
            }
            if event.contains("apply_patch") || event.contains("replace_content") || event.contains("write_file") {
                return "Updating files"
            }
        }
        return "Working on your task"
    }
}

struct LiveDashboardView: View {
    @ObservedObject private var agents = AgentStatusManager.shared
    @Default(.weatherOnLiveTab) private var weatherOnLiveTab
    @Default(.agentHistoryEnabled) private var historyEnabled
    @State private var showingHistory = false

    var body: some View {
        HStack(spacing: 12) {
            agentCard

            if weatherOnLiveTab {
                HomeWeatherTile()
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.horizontal, 4)
        .padding(.bottom, 4)
        .task {
            agents.start()
        }
    }

    private var agentCard: some View {
        dashboardCard(
            title: "AI Agents",
            symbol: "sparkles"
        ) {
            if showingHistory {
                if agents.history.isEmpty {
                    Text(historyEnabled ? "No finished tasks yet." : "Enable local history in AI Agents settings.")
                        .font(.caption).foregroundStyle(.secondary)
                } else {
                    ScrollView { AgentHistoryRows(entries: Array(agents.history.prefix(20))) }
                }
            } else {
                AgentInsightsView()
            }
        }
    }

    private func dashboardCard<Content: View>(
        title: String,
        symbol: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label(title, systemImage: symbol)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary)
                Spacer()
                Button(showingHistory ? "Current" : "History") { showingHistory.toggle() }
                    .font(.caption).controlSize(.small).notchGlassButton()
            }
            content()
            Spacer(minLength: 0)
        }
        .padding(12)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .standardMaterialPanel(tint: .clear, cornerRadius: 14)
    }
}

struct HomeWeatherTile: View {
    @ObservedObject private var weather = WeatherManager.shared
    @ObservedObject private var performance = AppPerformanceManager.shared
    @Default(.weatherEnabled) private var weatherEnabled
    @Environment(\.colorSchemeContrast) private var contrast
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var presentation: WeatherTilePresentation {
        .init(code: weather.weather?.weatherCode, isDay: weather.weather?.isDay ?? true,
              lowImpact: performance.lowImpact,
              reduceTransparency: reduceTransparency || performance.reduceTransparency,
              increasedContrast: contrast == .increased,
              reduceMotion: reduceMotion || performance.reduceMotion)
    }

    var body: some View {
        if weatherEnabled {
            VStack(alignment: .leading, spacing: 6) {
                if let current = weather.weather {
                    WeatherTileReadingView(current: current, presentation: presentation, error: weather.errorMessage) {
                        SettingsWindowController.shared.showWindow(section: "Weather")
                    }
                } else if weather.isLoading {
                    Spacer(minLength: 0)
                    ProgressView()
                        .controlSize(.small)
                        .frame(maxWidth: .infinity)
                        .accessibilityLabel("Updating weather")
                    Spacer(minLength: 0)
                } else {
                    Label("Weather", systemImage: "cloud.sun.fill")
                        .font(.caption.weight(.semibold))
                    Spacer(minLength: 4)
                    Text(weather.errorMessage ?? "Weather unavailable")
                        .font(.caption2)
                        .lineLimit(3)
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 3)
                    Button(locationActionTitle) {
                        if weather.locationAuthorizationStatus == .notDetermined && Defaults[.weatherUseCurrentLocation] { weather.useMyLocation() }
                        else { SettingsWindowController.shared.showWindow(section: "Weather") }
                    }.font(.caption2.weight(.semibold)).controlSize(.small)
                        .notchGlassButton()
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .padding(12)
            .frame(width: WeatherTilePresentation.tileWidth)
            .frame(maxHeight: .infinity, alignment: .topLeading)
            .foregroundStyle(.white)
            .background { WeatherTileSky(presentation: presentation) }
            .clipShape(RoundedRectangle(cornerRadius: WeatherTilePresentation.cornerRadius, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: WeatherTilePresentation.cornerRadius, style: .continuous)
                    .strokeBorder(.white.opacity(presentation.increasedContrast ? 0.65 : 0.12), lineWidth: presentation.increasedContrast ? 1 : 0.5)
                    .allowsHitTesting(false)
            }
            .contextMenu {
                Button("Refresh Weather", systemImage: "arrow.clockwise") { weather.refresh(force: true) }
                Button("Weather Settings…", systemImage: "gearshape") { SettingsWindowController.shared.showWindow(section: "Weather") }
            }
            .task {
                while !Task.isCancelled {
                    weather.refresh()
                    do { try await Task.sleep(for: .seconds(900)) } catch { return }
                }
            }
            .transaction { if presentation.suppressMotion { $0.animation = nil; $0.disablesAnimations = true } }
        }
    }

    private var locationActionTitle: String {
        weather.locationAuthorizationStatus == .notDetermined && Defaults[.weatherUseCurrentLocation]
            ? "Use My Location" : "Weather Settings…"
    }
}

/// Separate from the service so render fixtures need no real weather/location access.
struct WeatherTileReadingView: View {
    let current: WeatherSnapshot
    let presentation: WeatherTilePresentation
    let error: String?
    var openSettings: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(alignment: .center, spacing: 5) {
                Text(WeatherTilePresentation.locationLabel(current.location))
                    .font(.caption2.weight(.semibold)).lineLimit(2)
                    .frame(maxWidth: .infinity, alignment: .leading)
                // One functional native-glass lens above a sky content plane.
                // The weather tile itself deliberately has no glass material.
                Button(action: openSettings) {
                    Image(systemName: presentation.conditionSymbol)
                        .font(.system(size: 17, weight: .regular))
                        .symbolRenderingMode(presentation.increasedContrast ? .monochrome : .multicolor)
                        .foregroundStyle(.white)
                }
                .controlSize(.small).notchGlassButton(circular: true, diameter: 28)
                .help(error ?? "Weather Settings")
                .accessibilityLabel("Weather Settings")
                .accessibilityValue(error ?? current.condition)
                .overlay(alignment: .bottomTrailing) {
                    if error != nil {
                        Image(systemName: "exclamationmark.circle.fill").font(.system(size: 8))
                            .foregroundStyle(.white, Color(red: 0.15, green: 0.22, blue: 0.32))
                            .accessibilityHidden(true).allowsHitTesting(false)
                    }
                }
            }
            Text(WeatherTilePresentation.temperature(current.temperature))
                .font(.system(size: 34, weight: .light)).tracking(-1.2)
                .lineLimit(1).minimumScaleFactor(0.8)
                .accessibilityLabel("Temperature \(WeatherTilePresentation.temperature(current.temperature))")
            Text(current.condition).font(.caption.weight(.medium)).lineLimit(1).minimumScaleFactor(0.85)
            Spacer(minLength: 0)
            HStack(spacing: 6) {
                Text("H:\(WeatherTilePresentation.temperature(current.high))")
                Text("L:\(WeatherTilePresentation.temperature(current.low))")
            }.font(.caption2.weight(.medium)).lineLimit(1).minimumScaleFactor(0.85)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("High \(WeatherTilePresentation.temperature(current.high)), low \(WeatherTilePresentation.temperature(current.low))")
        }
        .foregroundStyle(.white)
    }
}

struct WeatherTileSky: View {
    let presentation: WeatherTilePresentation
    private func color(_ rgb: WeatherTilePresentation.RGB) -> Color { Color(red: rgb.red, green: rgb.green, blue: rgb.blue) }

    var body: some View {
        LinearGradient(colors: [color(presentation.top), color(presentation.bottom)], startPoint: .top, endPoint: .bottom)
            .overlay {
                if presentation.showsAtmosphere {
                    // Two static, bounded light/haze shapes; no blur passes,
                    // particles, random values, timeline or geometry-state loop.
                    Canvas { context, size in
                        let bounds = CGRect(origin: .zero, size: size)
                        let glow = CGPoint(x: size.width * 0.92, y: size.height * 0.10)
                        context.fill(Path(bounds), with: .radialGradient(
                            Gradient(colors: [.white.opacity(presentation.highlightOpacity * 0.58), .clear]),
                            center: glow, startRadius: 0, endRadius: size.width * 0.82))
                        if presentation.sky != .clear && presentation.sky != .unknown {
                            context.fill(Path(bounds), with: .linearGradient(Gradient(colors: [.clear, .white.opacity(0.025), .clear]),
                                startPoint: CGPoint(x: 0, y: size.height * 0.38), endPoint: CGPoint(x: 0, y: size.height * 0.88)))
                        }
                    }
                }
            }
            .allowsHitTesting(false).accessibilityHidden(true)
    }
}
