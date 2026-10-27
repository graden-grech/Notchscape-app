import Defaults
import SwiftUI

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
            symbol: AgentProviderStyle.symbol(for: "Codex"),
            tint: AgentProviderStyle.accent(for: "Codex")
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
        tint: Color,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack {
                Label(title, systemImage: symbol)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                Spacer()
                Button(showingHistory ? "Current" : "History") { showingHistory.toggle() }
                    .buttonStyle(.plain).font(.caption2)
                    .padding(.horizontal, 8).padding(.vertical, 3)
                    .liquidGlassCapsule()
            }
            content()
            Spacer(minLength: 0)
        }
        .padding(12)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .standardMaterialPanel(tint: tint, cornerRadius: 16)
    }
}

struct HomeWeatherTile: View {
    @ObservedObject private var weather = WeatherManager.shared
    @Default(.weatherEnabled) private var weatherEnabled

    var body: some View {
        if weatherEnabled {
            VStack(alignment: .leading, spacing: 7) {
                if let current = weather.weather {
                    HStack(alignment: .top, spacing: 6) {
                        Text(current.location == "Current location" ? "My Location" : current.location)
                            .font(.caption2.weight(.semibold))
                            .lineLimit(1)
                        Spacer(minLength: 0)
                        Image(systemName: current.symbol)
                            .font(.system(size: 22, weight: .medium))
                            .symbolRenderingMode(.multicolor)
                    }

                    Text("\(current.temperature, specifier: "%.0f")°")
                        .font(.system(size: 34, weight: .medium, design: .rounded))
                        .tracking(-1.5)

                    Text(current.condition)
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)

                    Spacer(minLength: 0)

                    HStack(spacing: 8) {
                        Text("H:\(current.high, specifier: "%.0f")°")
                        Text("L:\(current.low, specifier: "%.0f")°")
                    }
                    .font(.caption2.weight(.medium))
                    .foregroundStyle(.secondary)
                } else if weather.isLoading {
                    Spacer(minLength: 0)
                    ProgressView()
                        .controlSize(.small)
                        .frame(maxWidth: .infinity)
                    Spacer(minLength: 0)
                } else {
                    Label("Weather", systemImage: "cloud.sun.fill")
                        .font(.caption.weight(.semibold))
                    Spacer(minLength: 4)
                    Text(weather.errorMessage ?? "Weather unavailable")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(3)
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 3)
                    Button(weather.locationAuthorizationStatus == .notDetermined ? "Use My Location" : "Weather Settings…") {
                        if weather.locationAuthorizationStatus == .notDetermined && Defaults[.weatherUseCurrentLocation] { weather.useMyLocation() }
                        else { SettingsWindowController.shared.showWindow(section: "Weather") }
                    }.buttonStyle(.plain).font(.caption2.weight(.semibold))
                        .padding(.horizontal, 8).padding(.vertical, 5).liquidGlassCapsule()
                }
            }
            .padding(12)
            .frame(width: 144)
            .frame(maxHeight: .infinity, alignment: .topLeading)
            .foregroundStyle(.white)
            .background {
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .fill(LinearGradient(colors: skyColors, startPoint: .topLeading, endPoint: .bottomTrailing))
            }
            .overlay(alignment: .topTrailing) {
                if weather.weather != nil, let error = weather.errorMessage {
                    Image(systemName: "exclamationmark.circle.fill").font(.caption2)
                        .foregroundStyle(.white.opacity(0.8)).padding(7).help(error)
                }
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
        }
    }

    private var weatherTint: Color {
        guard let code = weather.weather?.weatherCode else { return .blue }
        switch code {
        case 0...2: return .blue
        case 45, 48: return .gray
        case 51...67, 80...82: return .indigo
        case 71...77, 85, 86: return .cyan
        case 95...99: return .purple
        default: return .blue
        }
    }

    private var skyColors: [Color] {
        guard let current = weather.weather else { return [Color(red: 0.18, green: 0.28, blue: 0.46), Color(red: 0.1, green: 0.15, blue: 0.28)] }
        if !current.isDay { return [Color(red: 0.12, green: 0.17, blue: 0.36), Color(red: 0.04, green: 0.07, blue: 0.18)] }
        if current.weatherCode >= 45 { return [Color(red: 0.33, green: 0.42, blue: 0.51), Color(red: 0.18, green: 0.25, blue: 0.36)] }
        return [Color(red: 0.24, green: 0.55, blue: 0.83), Color(red: 0.12, green: 0.32, blue: 0.61)]
    }
}
