//
//  SettingsView.swift
//  Notchscape
//
//  Created by Richard Kunkli on 07/08/2024.
//

import AppKit
import AVFoundation
import Defaults
import EventKit
import KeyboardShortcuts
import LaunchAtLogin
import Sparkle
import SwiftUI
import SwiftUIIntrospect

struct SettingsView: View {
    @State private var selectedTab = "General"
    @State private var search = ""
    private var destinations: [NotchSettingsDestination] {
        NotchSettingsDestination.all.filter { ($0.id != "Account" || AccountFeaturePolicy.enabled) && $0.matches(search) }
    }
    private func sidebarColor(_ name: String) -> Color {
        switch name {
        case "blue": .blue
        case "indigo": .indigo
        case "pink": .pink
        case "red": .red
        case "cyan": .cyan
        case "purple": .purple
        case "green": .green
        case "orange": .orange
        default: .gray
        }
    }
    @Default(.appTheme) private var appTheme
    @Default(.useCustomAccentColor) private var useCustomAccentColor
    @Default(.customAccentColorData) private var customAccentColorData
    @ObservedObject private var performance = AppPerformanceManager.shared

    private var currentAccent: Color {
        Color(nsColor: NSColor.resolvedAccent(theme: appTheme, customEnabled: useCustomAccentColor, customData: customAccentColorData))
    }

    let updaterController: SPUStandardUpdaterController

    init(updaterController: SPUStandardUpdaterController? = nil) {
        self.updaterController = updaterController ?? SPUStandardUpdaterController(
            startingUpdater: false, updaterDelegate: nil, userDriverDelegate: nil)
    }

    var body: some View {
        NavigationSplitView {
            List(selection: $selectedTab) {
                ForEach(destinations) { destination in
                    NavigationLink(value: destination.id) {
                        SettingsSidebarItem(destination.title, symbol: destination.symbol, color: sidebarColor(destination.color))
                    }
                }
            }
            .overlay {
                if destinations.isEmpty {
                    Text("No matching settings").font(.callout).foregroundStyle(.secondary).padding()
                }
            }
            .listStyle(SidebarListStyle())
            .tint(currentAccent)
            .toolbar(removing: .sidebarToggle)
            .navigationSplitViewColumnWidth(min: 210, ideal: 220, max: 250)
        } detail: {
            Group {
                switch selectedTab {
                case "General":
                    GeneralSettings()
                case "Modes":
                    WorkspaceModesSettings()
                case "Account":
                    if AccountFeaturePolicy.enabled {
                        AccountSettingsView()
                    } else {
                        GeneralSettings()
                    }
                case "Appearance":
                    Appearance()
                case "Media":
                    Media()
                case "Calendar":
                    CalendarSettings()
                case "Tools":
                    ProductivitySettings()
                case "Wallpapers":
                    WallpaperSettings()
                case "Agents":
                    AgentSettings()
                case "Weather":
                    WeatherSettings()
                case "Sports":
                    SportsSettings()
                case "Activities":
                    ActivitySettings()
                case "System":
                    SystemSettings()
                case "HUD":
                    HUD()
                case "Battery":
                    Charge()
                case "Shelf":
                    Shelf()
                case "Shortcuts":
                    Shortcuts()
                case "Extensions":
                    GeneralSettings()
                case "Advanced":
                    Advanced()
                case "About":
                    About(updaterController: updaterController)
                default:
                    GeneralSettings()
                }
            }
            .navigationTitle(NotchSettingsDestination.all.first(where: { $0.id == selectedTab })?.title ?? "Settings")
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .scrollContentBackground(.hidden)
            .background(Color.clear)
        }
        .navigationSplitViewStyle(.balanced)
        .searchable(text: $search, prompt: "Search Settings")
        .toolbar(removing: .sidebarToggle)
        .formStyle(.grouped)
        .toggleStyle(CompactSwitchToggleStyle())
        .controlSize(.regular)
        .frame(minWidth: 760, idealWidth: 840, maxWidth: .infinity, minHeight: 560, maxHeight: .infinity)
        .background(LiquidGlassSettingsBackground())
        .tint(currentAccent)
        .onReceive(NotificationCenter.default.publisher(for: .notchSettingsSectionRequested)) { notification in
            if let section = notification.object as? String,
               NotchSettingsDestination.all.contains(where: { $0.id == section && ($0.id != "Account" || AccountFeaturePolicy.enabled) }) {
                search = ""; selectedTab = section
            }
        }
        .transaction { if performance.suppressAnimations { $0.animation = nil; $0.disablesAnimations = true } }
    }
}

private struct SettingsSidebarItem: View {
    let title: String
    let symbol: String
    let color: Color
    init(_ title: String, symbol: String, color: Color) { self.title = title; self.symbol = symbol; self.color = color }
    var body: some View {
        HStack(spacing: 9) {
            Image(systemName: symbol).font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.white).frame(width: 22, height: 22)
                .background(color.gradient, in: RoundedRectangle(cornerRadius: 6, style: .continuous))
            Text(title).font(.body).foregroundStyle(.primary)
        }.padding(.vertical, 1)
    }
}

struct SystemSettings: View {
    @ObservedObject private var performance = AppPerformanceManager.shared
    @Default(.systemDashboardEnabled) private var systemDashboardEnabled

    var body: some View {
        Form {
            Section {
                Toggle("Show System tab in the notch", isOn: $systemDashboardEnabled)
                LabeledContent("Sampling", value: "Only while the tab is visible")
                LabeledContent("Refresh rate", value: performance.lowImpact ? "Every 3 seconds" : "Every 1.5 seconds")
            } header: {
                Text("System Dashboard")
            } footer: {
                Text("Shows CPU, memory, storage, and thermal pressure with shortcuts for Activity Monitor, System Settings, display sleep, and Lock Screen.")
            }

            Section("Fan Control") {
                Label("Monitoring only", systemImage: "fan")
                Text("macOS does not provide a safe public fan-control API. This version reports thermal pressure without overriding Apple's cooling controller.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Privacy and efficiency") {
                Label("No performance data leaves your Mac", systemImage: "lock.shield.fill")
                Text("The sampler stops as soon as you leave the System tab, keeping background CPU use close to zero.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .navigationTitle("System")
        .accentColor(.effectiveAccent)
    }
}

struct GeneralSettings: View {
    @State private var screens: [(uuid: String, name: String)] = NSScreen.screens.compactMap { screen in
        guard let uuid = screen.displayUUID else { return nil }
        return (uuid, screen.localizedName)
    }
    @EnvironmentObject var vm: NotchscapeViewModel
    @ObservedObject var coordinator = NotchscapeCoordinator.shared

    @Default(.mirrorShape) var mirrorShape
    @Default(.showEmojis) var showEmojis
    @Default(.gestureSensitivity) var gestureSensitivity
    @Default(.minimumHoverDuration) var minimumHoverDuration
    @Default(.nonNotchHeight) var nonNotchHeight
    @Default(.nonNotchHeightMode) var nonNotchHeightMode
    @Default(.nonNotchPresentation) var nonNotchPresentation
    @Default(.notchHeight) var notchHeight
    @Default(.notchHeightMode) var notchHeightMode
    @Default(.showOnAllDisplays) var showOnAllDisplays
    @Default(.showOnExternalDisplays) var showOnExternalDisplays
    @Default(.automaticallySwitchDisplay) var automaticallySwitchDisplay
    @Default(.enableGestures) var enableGestures
    @Default(.openNotchOnHover) var openNotchOnHover
    

    var body: some View {
        Form {
            Section("Get Started") {
                Button("Take the Settings Tour…", systemImage: "map") {
                    SettingsTourWindowController.shared.show()
                }
                Text("Six short chapters explain the settings. Skip at any time; taking the tour doesn't change your choices.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            PerformanceSettingsSection()
            Section {
                Toggle(isOn: Binding(
                    get: { Defaults[.menubarIcon] },
                    set: { Defaults[.menubarIcon] = $0 }
                )) {
                    Text("Show menu bar icon")
                }
                .tint(.effectiveAccent)
                Defaults.Toggle(key: .showDockIcon) {
                    Text("Show Dock icon")
                }
                Text("Hides the running app from the Dock and Command-Tab. Settings remain available from the notch or menu bar. A pinned or recent Dock shortcut may remain; right-click it and choose Options → Remove from Dock once.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                LaunchAtLogin.Toggle("Launch at login")
                Group {
                Defaults.Toggle(key: .showOnAllDisplays) {
                    Text("Show on all displays")
                }
                .onChange(of: showOnAllDisplays) {
                    NotificationCenter.default.post(
                        name: Notification.Name.showOnAllDisplaysChanged, object: nil)
                }
                Picker("Preferred display", selection: $coordinator.preferredScreenUUID) {
                    ForEach(screens, id: \.uuid) { screen in
                        Text(screen.name).tag(screen.uuid as String?)
                    }
                }
                .onChange(of: NSScreen.screens) {
                    screens = NSScreen.screens.compactMap { screen in
                        guard let uuid = screen.displayUUID else { return nil }
                        return (uuid, screen.localizedName)
                    }
                }
                .disabled(showOnAllDisplays)
                
                Defaults.Toggle(key: .automaticallySwitchDisplay) {
                    Text("Automatically switch displays")
                }
                    .onChange(of: automaticallySwitchDisplay) {
                        NotificationCenter.default.post(
                            name: Notification.Name.automaticallySwitchDisplayChanged, object: nil)
                    }
                    .disabled(showOnAllDisplays)
                }
                .disabled(!showOnExternalDisplays)
                .opacity(showOnExternalDisplays ? 1 : 0.42)
            } header: {
                Text("System features")
            }

            Section {
                Toggle("Show on external displays", isOn: $showOnExternalDisplays)
                    .accessibilityHint("Hides the notch and Dynamic Island on external monitors without changing your saved layout.")
                if !showOnExternalDisplays {
                    Label("External displays are off", systemImage: "display.slash")
                        .font(.callout.weight(.semibold))
                        .foregroundStyle(.secondary)
                    Text("External-display controls are disabled below. Your choices are kept for when you turn them back on. Open the app from Applications to return to Settings if no notch is visible.")
                        .font(.caption).foregroundStyle(.secondary)
                }

                Picker(
                    selection: $notchHeightMode,
                    label:
                        Text("Notch height on notch displays")
                ) {
                    Text("Match real notch height")
                        .tag(WindowHeightMode.matchRealNotchSize)
                    Text("Match menu bar height")
                        .tag(WindowHeightMode.matchMenuBar)
                    Text("Custom height")
                        .tag(WindowHeightMode.custom)
                }
                .onChange(of: notchHeightMode) {
                    switch notchHeightMode {
                    case .matchRealNotchSize:
                        notchHeight = 38
                    case .matchMenuBar:
                        notchHeight = 44
                    case .custom:
                        notchHeight = 38
                    }
                    NotificationCenter.default.post(
                        name: Notification.Name.notchHeightChanged, object: nil)
                }
                if notchHeightMode == .custom {
                    Slider(value: $notchHeight, in: 15...45, step: 1) {
                        Text("Custom notch size - \(notchHeight, specifier: "%.0f")")
                    }
                    .onChange(of: notchHeight) {
                        NotificationCenter.default.post(
                            name: Notification.Name.notchHeightChanged, object: nil)
                    }
                }
                Group {
                Picker("Style on displays without a notch", selection: $nonNotchPresentation) {
                    ForEach(NonNotchPresentation.allCases) { presentation in
                        Text(presentation.title).tag(presentation)
                    }
                }
                .pickerStyle(.segmented)
                .onChange(of: nonNotchPresentation) {
                    NotificationCenter.default.post(
                        name: Notification.Name.notchHeightChanged, object: nil)
                }
                Picker("Notch height on non-notch displays", selection: $nonNotchHeightMode) {
                    Text("Match menubar height")
                        .tag(WindowHeightMode.matchMenuBar)
                    Text("Match real notch height")
                        .tag(WindowHeightMode.matchRealNotchSize)
                    Text("Custom height")
                        .tag(WindowHeightMode.custom)
                }
                .onChange(of: nonNotchHeightMode) {
                    switch nonNotchHeightMode {
                    case .matchMenuBar:
                        nonNotchHeight = 24
                    case .matchRealNotchSize:
                        nonNotchHeight = 32
                    case .custom:
                        nonNotchHeight = 32
                    }
                    NotificationCenter.default.post(
                        name: Notification.Name.notchHeightChanged, object: nil)
                }
                if nonNotchHeightMode == .custom {
                    Slider(value: $nonNotchHeight, in: 0...40, step: 1) {
                        Text("Custom notch size - \(nonNotchHeight, specifier: "%.0f")")
                    }
                    .onChange(of: nonNotchHeight) {
                        NotificationCenter.default.post(
                            name: Notification.Name.notchHeightChanged, object: nil)
                    }
                }
                }
                .disabled(!showOnExternalDisplays)
                .opacity(showOnExternalDisplays ? 1 : 0.42)
            } header: {
                Text("Display style and sizing")
            } footer: {
                Text("Turning external displays off keeps the built-in display available, if connected. Dynamic Island stays inside the menu bar; Notch attaches to the top edge. This display choice stays on this Mac and is not synced to your account.")
            }

            NotchBehaviour()

            gestureControls()
        }
        .accentColor(.effectiveAccent)
        .navigationTitle("General")
        .onChange(of: openNotchOnHover) {
            if !openNotchOnHover {
                enableGestures = true
            }
        }
    }

    @ViewBuilder
    func gestureControls() -> some View {
        Section {
            Defaults.Toggle(key: .enableGestures) {
                Text("Enable gestures")
            }
                .disabled(!openNotchOnHover)
            if enableGestures {
                Toggle("Change media with horizontal gestures", isOn: .constant(false))
                    .disabled(true)
                Defaults.Toggle(key: .closeGestureEnabled) {
                    Text("Close gesture")
                }
                Slider(value: $gestureSensitivity, in: 100...300, step: 100) {
                    HStack {
                        Text("Gesture sensitivity")
                        Spacer()
                        Text(
                            Defaults[.gestureSensitivity] == 100
                                ? "High" : Defaults[.gestureSensitivity] == 200 ? "Medium" : "Low"
                        )
                        .foregroundStyle(.secondary)
                    }
                }
            }
        } header: {
            HStack {
                Text("Gesture control")
                customBadge(text: "Beta")
            }
        } footer: {
            Text(
                "Two-finger swipe up on notch to close, two-finger swipe down on notch to open when **Open notch on hover** option is disabled"
            )
            .multilineTextAlignment(.trailing)
            .foregroundStyle(.secondary)
            .font(.caption)
        }
    }

    @ViewBuilder
    func NotchBehaviour() -> some View {
        Section {
            Defaults.Toggle(key: .openNotchOnHover) {
                Text("Open notch on hover")
            }
            Defaults.Toggle(key: .enableHaptics) {
                    Text("Enable haptic feedback")
            }
            Toggle("Remember last tab", isOn: $coordinator.openLastTabByDefault)
            if openNotchOnHover {
                Slider(value: $minimumHoverDuration, in: 0...1, step: 0.1) {
                    HStack {
                        Text("Hover delay")
                        Spacer()
                        Text("\(minimumHoverDuration, specifier: "%.1f")s")
                            .foregroundStyle(.secondary)
                    }
                }
                .onChange(of: minimumHoverDuration) {
                    NotificationCenter.default.post(
                        name: Notification.Name.notchHeightChanged, object: nil)
                }
            }
        } header: {
            Text("Notch behavior")
        }
    }
}

struct Charge: View {
    @Default(.batteryPresentation) private var presentation
    @Default(.batteryIndicatorDisplay) private var display
    @Default(.batteryHistoryEnabled) private var historyEnabled
    @Default(.showPowerStatusNotifications) private var notifications
    @ObservedObject private var battery = BatteryStatusViewModel.shared
    @State private var confirmClearHistory = false
    var body: some View {
        Form {
            Section {
                Picker("Battery style", selection: $presentation) {
                    ForEach(BatteryPresentationStyle.allCases) { style in Text(style.title).tag(style) }
                }.pickerStyle(.segmented)
                Text("Original keeps the familiar indicator and popover. Enhanced adds a cleaner popover, local history and optional battery alerts. Your Original display preferences are saved separately.")
                    .font(.caption).foregroundStyle(.secondary)
            } header: { Text("Appearance") }
            Section {
                Defaults.Toggle(key: .showBatteryIndicator) {
                    Text("Show battery indicator")
                }
                Defaults.Toggle(key: .showPowerStatusNotifications) {
                    Text("Show power status notifications")
                }
                Defaults.Toggle(key: .hideBatteryWhenAbsent) { Text("Hide on Macs without a battery") }
            } header: {
                Text("General")
            }
            Section {
                if presentation == .enhanced {
                    Picker("Home indicator", selection: $display) {
                        ForEach(BatteryIndicatorDisplay.allCases) { option in Text(option.title).tag(option) }
                    }
                } else {
                    Defaults.Toggle(key: .showBatteryPercentage) {
                        Text("Show battery percentage")
                    }
                }
                Defaults.Toggle(key: .showPowerStatusIcons) {
                    Text("Show power status icons")
                }
            } header: {
                Text("Battery Information")
            }
            if presentation == .enhanced {
                Section {
                    Defaults.Toggle(key: .batteryAlert20) { Text("Alert at 20%") }
                    Defaults.Toggle(key: .batteryAlert10) { Text("Alert at 10%") }
                    Defaults.Toggle(key: .batteryAlertFull) { Text("Alert when fully charged") }
                    Text("Alerts appear briefly in the notch for about 3 seconds. Low-battery alerts only appear while using battery power, once when crossing a threshold—not at every update or app launch.")
                        .font(.caption).foregroundStyle(.secondary)
                } header: { Text("Optional alerts") }
                    .disabled(!notifications)
                Section {
                    Defaults.Toggle(key: .batteryHistoryEnabled) { Text("Show battery history") }
                    Text("Keeps up to 24 hours of readings on this Mac. No background polling, cloud uploads, or made-up readings while the app is closed. Turning this off stops recording; Clear History removes existing readings.")
                        .font(.caption).foregroundStyle(.secondary)
                    Button("Clear History…", role: .destructive) { confirmClearHistory = true }
                        .disabled(battery.history.isEmpty)
                        .confirmationDialog("Clear battery history?", isPresented: $confirmClearHistory) {
                            Button("Clear History", role: .destructive) { battery.clearHistory() }
                        }
                } header: { Text("History") }
            }
        }
        .onAppear {
            Task { @MainActor in
                await XPCHelperClient.shared.isAccessibilityAuthorized()
            }
        }
        .accentColor(.effectiveAccent)
        .navigationTitle("Battery")
    }
}

//struct Downloads: View {
//    @Default(.selectedDownloadIndicatorStyle) var selectedDownloadIndicatorStyle
//    @Default(.selectedDownloadIconStyle) var selectedDownloadIconStyle
//    var body: some View {
//        Form {
//            warningBadge("We don't support downloads yet", "It will be supported later on.")
//            Section {
//                Defaults.Toggle(key: .enableDownloadListener) {
//                    Text("Show download progress")
//                }
//                    .disabled(true)
//                Defaults.Toggle(key: .enableSafariDownloads) {
//                    Text("Enable Safari Downloads")
//                }
//                    .disabled(!Defaults[.enableDownloadListener])
//                Picker("Download indicator style", selection: $selectedDownloadIndicatorStyle) {
//                    Text("Progress bar")
//                        .tag(DownloadIndicatorStyle.progress)
//                    Text("Percentage")
//                        .tag(DownloadIndicatorStyle.percentage)
//                }
//                Picker("Download icon style", selection: $selectedDownloadIconStyle) {
//                    Text("Only app icon")
//                        .tag(DownloadIconStyle.onlyAppIcon)
//                    Text("Only download icon")
//                        .tag(DownloadIconStyle.onlyIcon)
//                    Text("Both")
//                        .tag(DownloadIconStyle.iconAndAppIcon)
//                }
//
//            } header: {
//                HStack {
//                    Text("Download indicators")
//                    comingSoonTag()
//                }
//            }
//            Section {
//                List {
//                    ForEach([].indices, id: \.self) { index in
//                        Text("\(index)")
//                    }
//                }
//                .frame(minHeight: 96)
//                .overlay {
//                    if true {
//                        Text("No excluded apps")
//                            .foregroundStyle(Color(.secondaryLabelColor))
//                    }
//                }
//                .actionBar(padding: 0) {
//                    Group {
//                        Button {
//                        } label: {
//                            Image(systemName: "plus")
//                                .frame(width: 25, height: 16, alignment: .center)
//                                .contentShape(Rectangle())
//                                .foregroundStyle(.secondary)
//                        }
//
//                        Divider()
//                        Button {
//                        } label: {
//                            Image(systemName: "minus")
//                                .frame(width: 20, height: 16, alignment: .center)
//                                .contentShape(Rectangle())
//                                .foregroundStyle(.secondary)
//                        }
//                    }
//                }
//            } header: {
//                HStack(spacing: 4) {
//                    Text("Exclude apps")
//                    comingSoonTag()
//                }
//            }
//        }
//        .navigationTitle("Downloads")
//    }
//}

struct HUD: View {
    @EnvironmentObject var vm: NotchscapeViewModel
    @Default(.inlineHUD) var inlineHUD
    @Default(.enableGradient) var enableGradient
    @Default(.optionKeyAction) var optionKeyAction
    @Default(.hudReplacement) var hudReplacement
    @ObservedObject var coordinator = NotchscapeCoordinator.shared
    @State private var accessibilityAuthorized = false
    @State private var hudInterceptorActive = false
    
    var body: some View {
        Form {
            Section {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Replace system HUD")
                            .font(.headline)
                        Text("Replaces the standard macOS volume, display brightness, and keyboard brightness HUDs with a custom design.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer(minLength: 40)
                    Defaults.Toggle("", key: .hudReplacement)
                    .labelsHidden()
                    .toggleStyle(.switch)
                    .controlSize(.small)
                    .disabled(!accessibilityAuthorized)
                }
                
                if !accessibilityAuthorized {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Accessibility access is required to replace the system HUD.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)

                        HStack(spacing: 12) {
                            Button("Request Accessibility") {
                                Task {
                                    accessibilityAuthorized = await XPCHelperClient.shared
                                        .ensureAccessibilityAuthorization(promptIfNeeded: true)

                                    if accessibilityAuthorized {
                                        Defaults[.hudReplacement] = true
                                        hudInterceptorActive = await MediaKeyInterceptor.shared.start()
                                    } else if
                                       let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
                                        NSWorkspace.shared.open(url)
                                    }
                                }
                            }
                            .buttonStyle(.borderedProminent)

                            Button("Open System Settings") {
                                if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
                                    NSWorkspace.shared.open(url)
                                }
                            }
                        }

                        Text("After you enable Notchscape, the HUD replacement will turn on automatically.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.top, 6)
                }

                if accessibilityAuthorized {
                    Label(
                        hudInterceptorActive ? "HUD interceptor is active" :
                            (hudReplacement ? "HUD is enabled but its interceptor is not running" : "Turn on Replace system HUD to start the interceptor"),
                        systemImage: hudInterceptorActive ? "checkmark.circle.fill" : "info.circle"
                    )
                    .foregroundStyle(hudInterceptorActive ? .green : .secondary)

                    if hudReplacement {
                        Button("Restart HUD") {
                            Task {
                                MediaKeyInterceptor.shared.stop()
                                hudInterceptorActive = await MediaKeyInterceptor.shared.start(promptIfNeeded: false)
                                if !hudInterceptorActive { MediaKeyInterceptor.shared.recoverIfNeeded() }
                            }
                        }
                    }
                }
            }
            
            Section {
                Picker("Option key behaviour", selection: $optionKeyAction) {
                    ForEach(OptionKeyAction.allCases) { opt in
                        Text(opt.rawValue).tag(opt)
                    }
                }
                
                Picker("Progress bar style", selection: $enableGradient) {
                    Text("Hierarchical")
                        .tag(false)
                    Text("Gradient")
                        .tag(true)
                }
                Defaults.Toggle(key: .systemEventIndicatorShadow) {
                    Text("Enable glowing effect")
                }
                Defaults.Toggle(key: .systemEventIndicatorUseAccent) {
                    Text("Tint progress bar with accent color")
                }
            } header: {
                Text("General")
            }
            .disabled(!hudReplacement)
            
            Section {
                Defaults.Toggle(key: .showOpenNotchHUD) {
                    Text("Show HUD in open notch")
                }
                Defaults.Toggle(key: .showOpenNotchHUDPercentage) {
                    Text("Show percentage")
                }
                .disabled(!Defaults[.showOpenNotchHUD])
            } header: {
                HStack {
                    Text("Open Notch")
                    customBadge(text: "Beta")
                }
            }
            .disabled(!hudReplacement)
            
            Section {
                Picker("HUD style", selection: $inlineHUD) {
                    Text("Default")
                        .tag(false)
                    Text("Inline")
                        .tag(true)
                }
                .onChange(of: Defaults[.inlineHUD]) {
                    if Defaults[.inlineHUD] {
                        withAnimation {
                            Defaults[.systemEventIndicatorShadow] = false
                            Defaults[.enableGradient] = false
                        }
                    }
                }
                
                Defaults.Toggle(key: .showClosedNotchHUDPercentage) {
                    Text("Show percentage")
                }
            } header: {
                Text("Closed Notch")
            }
            .disabled(!Defaults[.hudReplacement])
        }
        .accentColor(.effectiveAccent)
        .navigationTitle("HUDs")
        .task {
            accessibilityAuthorized = await XPCHelperClient.shared.isAccessibilityAuthorized()
            if accessibilityAuthorized && hudReplacement {
                hudInterceptorActive = await MediaKeyInterceptor.shared.start(promptIfNeeded: false)
            } else {
                hudInterceptorActive = MediaKeyInterceptor.shared.isActive
            }
        }
        .onAppear {
            XPCHelperClient.shared.startMonitoringAccessibilityAuthorization()
        }
        .onDisappear {
            if !hudReplacement { XPCHelperClient.shared.stopMonitoringAccessibilityAuthorization() }
        }
        .onReceive(NotificationCenter.default.publisher(for: .accessibilityAuthorizationChanged)) { notification in
            if let granted = notification.userInfo?["granted"] as? Bool {
                accessibilityAuthorized = granted
                if granted {
                    Defaults[.hudReplacement] = true
                    Task {
                        hudInterceptorActive = await MediaKeyInterceptor.shared.start()
                    }
                } else {
                    hudInterceptorActive = false
                }
            }
        }
        .onChange(of: hudReplacement) { enabled in
            if enabled {
                Task {
                    hudInterceptorActive = await MediaKeyInterceptor.shared.start()
                }
            } else {
                MediaKeyInterceptor.shared.stop()
                hudInterceptorActive = false
            }
        }
    }
}

struct Media: View {
    @Default(.waitInterval) var waitInterval
    @Default(.mediaController) var mediaController
    @ObservedObject var coordinator = NotchscapeCoordinator.shared
    @Default(.hideNotchOption) var hideNotchOption
    @Default(.enableSneakPeek) private var enableSneakPeek
    @Default(.sneakPeekStyles) var sneakPeekStyles
    @Default(.musicActivityOverride) private var musicActivityOverride

    @Default(.enableLyrics) var enableLyrics

    var body: some View {
        Form {
            Section {
                Picker("Music Source", selection: $mediaController) {
                    ForEach(availableMediaControllers) { controller in
                        Text(controller.rawValue).tag(controller)
                    }
                }
                .onChange(of: mediaController) { _, _ in
                    NotificationCenter.default.post(
                        name: Notification.Name.mediaControllerChanged,
                        object: nil
                    )
                }
            } header: {
                Text("Media Source")
            } footer: {
                if MusicManager.shared.isNowPlayingDeprecated {
                    HStack {
                        Text("YouTube Music requires this third-party app to be installed: ")
                            .foregroundStyle(.secondary)
                            .font(.caption)
                        Link(
                            "https://github.com/pear-devs/pear-desktop",
                            destination: URL(string: "https://github.com/pear-devs/pear-desktop")!
                        )
                        .font(.caption)
                        .foregroundColor(.blue)  // Ensures it's visibly a link
                    }
                } else {
                    Text(
                        "'Now Playing' was the only option on previous versions and works with all media apps."
                    )
                    .foregroundStyle(.secondary)
                    .font(.caption)
                }
            }
            
            Section {
                Toggle(
                    "Show music in the notch",
                    isOn: $coordinator.musicLiveActivityEnabled.animation()
                )
                Toggle("Keep music visible", isOn: $musicActivityOverride)
                    .disabled(!coordinator.musicLiveActivityEnabled)
                    .help("Keep music in the closed notch even when Live Activities are off or the activity profile hides music.")
            } header: {
                Text("Music in the notch")
            } footer: {
                Text("Keep music visible overrides the Live Activities switch and activity profiles. Music still hides when stopped, and its own switch above always takes priority. The Home music tile is managed separately in Appearance → Home layout.")
            }

            Section("Playback behavior") {
                Toggle("Show sneak peek on playback changes", isOn: $enableSneakPeek)
                Picker("Sneak Peek Style", selection: $sneakPeekStyles) {
                    ForEach(SneakPeekStyle.allCases) { style in
                        Text(style.rawValue).tag(style)
                    }
                }
                HStack {
                    Stepper(value: $waitInterval, in: 0...10, step: 1) {
                        HStack {
                            Text("Media inactivity timeout")
                            Spacer()
                            Text("\(Defaults[.waitInterval], specifier: "%.0f") seconds")
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                Picker(
                    selection: $hideNotchOption,
                    label:
                        HStack {
                            Text("Full screen behavior")
                            customBadge(text: "Beta")
                        }
                ) {
                    Text("Hide for all apps").tag(HideNotchOption.always)
                    Text("Hide for media app only").tag(
                        HideNotchOption.nowPlayingOnly)
                    Text("Never hide").tag(HideNotchOption.never)
                }
            }
            
            Section {
                MusicSlotConfigurationView()
                Defaults.Toggle(key: .enableLyrics) {
                    HStack {
                        Text("Show lyrics below artist name")
                        customBadge(text: "Beta")
                    }
                }
            } header: {
                Text("Media controls")
            }  footer: {
                Text("Customize which controls appear in the music player. Volume expands when active.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .accentColor(.effectiveAccent)
        .navigationTitle("Media")
    }

    // Only show controller options that are available on this macOS version
    private var availableMediaControllers: [MediaControllerType] {
        if MusicManager.shared.isNowPlayingDeprecated {
            return MediaControllerType.allCases.filter { $0 != .nowPlaying }
        } else {
            return MediaControllerType.allCases
        }
    }
}

struct CalendarSettings: View {
    @ObservedObject private var calendarManager = CalendarManager.shared
    @State private var requestingCalendar = false
    @State private var requestingReminders = false
    @Default(.showCalendar) var showCalendar: Bool
    @Default(.hideCompletedReminders) var hideCompletedReminders
    @Default(.hideAllDayEvents) var hideAllDayEvents
    @Default(.autoScrollToNextEvent) var autoScrollToNextEvent
    @Default(.calendarAlertsEnabled) private var calendarAlertsEnabled
    @Default(.calendarAlertLeadMinutes) private var calendarAlertLeadMinutes

    var body: some View {
        Form {
            Defaults.Toggle(key: .showCalendar) {
                Text("Show calendar")
            }
            Defaults.Toggle(key: .hideCompletedReminders) {
                Text("Hide completed reminders")
            }
            Defaults.Toggle(key: .hideAllDayEvents) {
                Text("Hide all-day events")
            }
            Defaults.Toggle(key: .autoScrollToNextEvent) {
                Text("Auto-scroll to next event")
            }
            Defaults.Toggle(key: .showFullEventTitles) {
                Text("Always show full event titles")
            }
            Section(header: Text("Upcoming Event Alerts")) {
                Toggle("Show events on the closed notch", isOn: $calendarAlertsEnabled)
                    .onChange(of: calendarAlertsEnabled) {
                        Task { await calendarManager.refreshUpcomingAlert() }
                    }
                Picker("Show before event", selection: $calendarAlertLeadMinutes) {
                    Text("5 minutes").tag(5)
                    Text("10 minutes").tag(10)
                    Text("15 minutes").tag(15)
                    Text("30 minutes").tag(30)
                }
                .disabled(!calendarAlertsEnabled)
                .onChange(of: calendarAlertLeadMinutes) {
                    Task { await calendarManager.refreshUpcomingAlert() }
                }
                Text("Click an alert to join its meeting link, or open the event in Calendar.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Section(header: Text("Calendars")) {
                if calendarManager.calendarAuthorizationStatus == .notDetermined {
                    Text("Connect Calendar to show your events. You can keep using Notchscape without connecting it.")
                        .font(.callout).foregroundStyle(.secondary)
                    HStack {
                        Button("Connect Calendar…") {
                            guard !requestingCalendar && !requestingReminders else { return }
                            requestingCalendar = true
                            Task {
                                await calendarManager.checkCalendarAuthorization(requestIfNeeded: true)
                                requestingCalendar = false
                            }
                        }.disabled(requestingCalendar || requestingReminders)
                        if requestingCalendar { ProgressView().controlSize(.small).accessibilityLabel("Waiting for Calendar access") }
                    }
                } else if calendarManager.calendarAuthorizationStatus != .fullAccess {
                    Text("Calendar access is denied. Please enable it in System Settings.")
                        .foregroundColor(.red)
                        .multilineTextAlignment(.center)
                        .padding()
                    Button("Open Calendar Settings") {
                        if let settingsURL = URL(
                            string:
                                "x-apple.systempreferences:com.apple.preference.security?Privacy_Calendars"
                        ) {
                            NSWorkspace.shared.open(settingsURL)
                        }
                    }
                } else {
                    List {
                        ForEach(calendarManager.eventCalendars, id: \.id) { calendar in
                            Toggle(
                                isOn: Binding(
                                    get: { calendarManager.getCalendarSelected(calendar) },
                                    set: { isSelected in
                                        Task {
                                            await calendarManager.setCalendarSelected(
                                                calendar, isSelected: isSelected)
                                        }
                                    }
                                )
                            ) {
                                Text(calendar.title)
                            }
                            .accentColor(lighterColor(from: calendar.color))
                            .disabled(!showCalendar)
                        }
                    }
                }
            }
            Section(header: Text("Reminders")) {
                if calendarManager.reminderAuthorizationStatus == .notDetermined {
                    Text("Connect Reminders to show reminders alongside your events. This is optional.")
                        .font(.callout).foregroundStyle(.secondary)
                    HStack {
                        Button("Connect Reminders…") {
                            guard !requestingCalendar && !requestingReminders else { return }
                            requestingReminders = true
                            Task {
                                await calendarManager.checkReminderAuthorization(requestIfNeeded: true)
                                requestingReminders = false
                            }
                        }.disabled(requestingCalendar || requestingReminders)
                        if requestingReminders { ProgressView().controlSize(.small).accessibilityLabel("Waiting for Reminders access") }
                    }
                } else if calendarManager.reminderAuthorizationStatus != .fullAccess {
                    Text("Reminder access is denied. Please enable it in System Settings.")
                        .foregroundColor(.red)
                        .multilineTextAlignment(.center)
                        .padding()
                    Button("Open Reminder Settings") {
                        if let settingsURL = URL(
                            string:
                                "x-apple.systempreferences:com.apple.preference.security?Privacy_Reminders"
                        ) {
                            NSWorkspace.shared.open(settingsURL)
                        }
                    }
                } else {
                    List {
                        ForEach(calendarManager.reminderLists, id: \.id) { calendar in
                            Toggle(
                                isOn: Binding(
                                    get: { calendarManager.getCalendarSelected(calendar) },
                                    set: { isSelected in
                                        Task {
                                            await calendarManager.setCalendarSelected(
                                                calendar, isSelected: isSelected)
                                        }
                                    }
                                )
                            ) {
                                Text(calendar.title)
                            }
                            .accentColor(lighterColor(from: calendar.color))
                            .disabled(!showCalendar)
                        }
                    }
                }
            }
        }
        .accentColor(.effectiveAccent)
        .navigationTitle("Calendar")
        .onAppear {
            Task {
                await calendarManager.checkCalendarAuthorization()
                await calendarManager.checkReminderAuthorization()
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            // A person may have just changed access in System Settings. Read
            // the current status on return without asking for access again.
            Task {
                await calendarManager.checkCalendarAuthorization()
                await calendarManager.checkReminderAuthorization()
            }
        }
    }
}

struct ActivitySettings: View {
    @Default(.liveActivitiesEnabled) private var liveActivitiesEnabled
    @Default(.activityProfile) private var activityProfile
    @Default(.privacyActivitiesEnabled) private var privacyActivitiesEnabled
    @Default(.weatherAlertsEnabled) private var weatherAlertsEnabled
    @Default(.timerActivitiesEnabled) private var timerActivitiesEnabled
    @Default(.sportsActivitiesEnabled) private var sportsActivitiesEnabled
    @Default(.enableDownloadListener) private var enableDownloadListener
    @ObservedObject private var timer = NotchTimerManager.shared
    @ObservedObject private var privacy = PrivacyActivityMonitor.shared
    @ObservedObject private var downloads = DownloadWatcher.shared

    var body: some View {
        Form {
            Section {
                Toggle("Show Live Activities", isOn: $liveActivitiesEnabled)
            } footer: {
                Text("Turn this off to hide AI, sports, calendar, timer, privacy, download, and weather activities from the closed notch. Music can stay visible using its override in Media. HUDs and the expanded notch still work normally.")
                Button("Music settings…") { SettingsWindowController.shared.showWindow(section: "Media") }
                    .buttonStyle(.link)
            }

            Section("Activity Profile") {
                Picker("Show", selection: $activityProfile) {
                    ForEach(ActivityProfile.allCases) { profile in
                        Text(profile.title).tag(profile)
                    }
                }
                Text("Focus hides music and downloads. Entertainment keeps music and downloads. Minimal keeps only AI and privacy indicators. Music’s override in Media takes priority over these profiles.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .disabled(!liveActivitiesEnabled)

            Section("Sources") {
                Toggle("Microphone and camera indicators", isOn: $privacyActivitiesEnabled)
                Toggle("Weather warnings", isOn: $weatherAlertsEnabled)
                Toggle("Timers", isOn: $timerActivitiesEnabled)
                Toggle("Sports scores", isOn: $sportsActivitiesEnabled)
                Toggle("Downloads folder progress", isOn: $enableDownloadListener)
                ForEach(downloads.folders) { folder in
                    HStack { Label(folder.name, systemImage: "folder"); Spacer(); Button("Remove") { downloads.removeFolder(folder.id) } }
                }
                Button("Add Watched Folder…") { downloads.chooseFolder() }.disabled(!enableDownloadListener || downloads.folders.count >= 8)
                Text("Downloads plus up to eight chosen folders. Top-level entries only; filesystem events while idle and bounded scans while downloading. Paused when locked or presenting.").font(.caption).foregroundStyle(.secondary)
                if let error = downloads.folderError { Text(error).font(.caption).foregroundStyle(.orange) }
                if privacy.microphoneInUse || privacy.cameraInUse {
                    Label(
                        privacy.cameraInUse && privacy.microphoneInUse
                            ? "Camera and microphone currently active"
                            : privacy.cameraInUse ? "Camera currently active" : "Microphone currently active",
                        systemImage: privacy.cameraInUse ? "video.fill" : "mic.fill"
                    )
                    .foregroundStyle(privacy.cameraInUse ? .green : .orange)
                }
                if let download = downloads.downloadFiles.first {
                    LabeledContent("Active download", value: download.name)
                }
            }
            .disabled(!liveActivitiesEnabled)

            Section("Quick Timers") {
                Button("Stopwatch and Focus Cycles…") { WorkspaceToolsWindowController.shared.show() }
                HStack {
                    Button("5 min") { timer.start(minutes: 5) }
                    Button("10 min") { timer.start(minutes: 10) }
                    Button("25 min Focus") { timer.start(minutes: 25, label: "Focus timer") }
                    Spacer()
                    if timer.endDate != nil {
                        Button("Cancel", role: .destructive) { timer.cancel() }
                    }
                }
                if timer.endDate != nil {
                    LabeledContent("Remaining", value: String(format: "%d:%02d", timer.remainingSeconds / 60, timer.remainingSeconds % 60))
                }
            }
            .disabled(!liveActivitiesEnabled)

            Section("Controls") {
                Text("Click sports activities for game details, AI badges for agent details, timers to cancel, downloads to reveal them, and calendar alerts to join meetings.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .disabled(!liveActivitiesEnabled)
        }
        .navigationTitle("Live Activities")
        .accentColor(.effectiveAccent)
    }
}

struct AgentSettings: View {
    @ObservedObject private var manager = AgentStatusManager.shared
    @Default(.liveActivityPriority) private var liveActivityPriority

    var body: some View {
        Form {
            AgentHistorySettings()
            Section {
                Defaults.Toggle(key: .agentUsageEnabled) { Text("Show available local AI usage") }
            } header: { Text("Usage dashboard") } footer: {
                Text("Reads usage events from recent local Codex session files only while Live is open, and accepts explicit usage fields from agent hooks. Prompts, credentials and OAuth tokens are not retained or uploaded. Claude usage requires hook-provided data. Reset times and percentages appear only when supplied; these readings never mark a task as complete or interrupted. Open Terminal returns to the Terminal app, not an exact Claude session.")
            }
            Section {
                Defaults.Toggle(key: .agentStatusEnabled) {
                    Text("Show AI agent status")
                }
                Picker("When music and AI are active", selection: $liveActivityPriority) {
                    ForEach(LiveActivityPriority.allCases) { priority in
                        Text(priority.title).tag(priority)
                    }
                }
                LabeledContent("Local bridge") {
                    Label(
                        manager.isListening ? "Listening on 127.0.0.1:\(String(AgentStatusManager.port))" : "Not connected",
                        systemImage: manager.isListening ? "checkmark.circle.fill" : "exclamationmark.circle"
                    )
                    .foregroundStyle(manager.isListening ? .green : .orange)
                }
            } header: {
                Text("AI Agents")
            } footer: {
                Text("In Music + AI mode, swipe the closed notch to switch between the combined, music-only, and AI-only views. Activity stays on this Mac.")
            }

            Section {
                Button("Copy Codex hook configuration") {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(Self.hookConfiguration, forType: .string)
                }
                Button("Copy Claude Code hook command") {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(Self.claudeHookCommand, forType: .string)
                }
                Text("Codex uses ~/.codex/hooks.json. Claude Code uses the command in ~/.claude/settings.json.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
            } header: {
                Text("Setup")
            }
        }
        .navigationTitle("AI Agents")
        .accentColor(.effectiveAccent)
        .onAppear { manager.start() }
    }

    private static let hookConfiguration = """
    {
      "description": "Send local Codex activity to Notchscape.",
      "hooks": {
        "SessionStart": [{"hooks": [{"type": "command", "command": "/usr/bin/curl -sS --max-time 1 -H 'Content-Type: application/json' --data-binary @- http://127.0.0.1:43765/codex >/dev/null", "timeout": 2}]}],
        "UserPromptSubmit": [{"hooks": [{"type": "command", "command": "/usr/bin/curl -sS --max-time 1 -H 'Content-Type: application/json' --data-binary @- http://127.0.0.1:43765/codex >/dev/null", "timeout": 2}]}],
        "PreToolUse": [{"hooks": [{"type": "command", "command": "/usr/bin/curl -sS --max-time 1 -H 'Content-Type: application/json' --data-binary @- http://127.0.0.1:43765/codex >/dev/null", "timeout": 2}]}],
        "PostToolUse": [{"hooks": [{"type": "command", "command": "/usr/bin/curl -sS --max-time 1 -H 'Content-Type: application/json' --data-binary @- http://127.0.0.1:43765/codex >/dev/null", "timeout": 2}]}],
        "PermissionRequest": [{"hooks": [{"type": "command", "command": "/usr/bin/curl -sS --max-time 1 -H 'Content-Type: application/json' --data-binary @- http://127.0.0.1:43765/codex >/dev/null", "timeout": 2}]}],
        "Stop": [{"hooks": [{"type": "command", "command": "/usr/bin/curl -sS --max-time 1 -H 'Content-Type: application/json' --data-binary @- http://127.0.0.1:43765/codex >/dev/null", "timeout": 2}]}],
        "Interrupt": [{"hooks": [{"type": "command", "command": "/usr/bin/curl -sS --max-time 1 -H 'Content-Type: application/json' --data-binary @- http://127.0.0.1:43765/codex >/dev/null", "timeout": 2}]}],
        "SessionEnd": [{"hooks": [{"type": "command", "command": "/usr/bin/curl -sS --max-time 1 -H 'Content-Type: application/json' --data-binary @- http://127.0.0.1:43765/codex >/dev/null", "timeout": 2}]}]
      }
    }
    """

    private static let claudeHookCommand = """
    /usr/bin/jq -c '. + {"provider":"Claude Code"}' | /usr/bin/curl -sS --connect-timeout 0.2 --max-time 1 -H 'Content-Type: application/json' --data-binary @- http://127.0.0.1:43765/claude >/dev/null # boringnotch-agents-claude-hook
    """
}

struct SportsSettings: View {
    @ObservedObject private var sports = SportsActivityManager.shared
    @Default(.sportsActivitiesEnabled) private var sportsActivitiesEnabled
    @Default(.sportsEnabledLeagues) private var enabledLeagues
    @Default(.sportsFavoriteTeams) private var favoriteTeams
    @Default(.sportsScoreNotificationsEnabled) private var scoreNotificationsEnabled
    @Default(.sportsShowUpcoming) private var showUpcoming
    @State private var browsingLeague: SportsLeague = .nba
    @State private var teamSearch = ""

    private var filteredTeams: [SportsDirectoryTeam] {
        guard !teamSearch.isEmpty else { return sports.availableTeams }
        return sports.availableTeams.filter {
            $0.name.localizedCaseInsensitiveContains(teamSearch)
                || $0.abbreviation.localizedCaseInsensitiveContains(teamSearch)
        }
    }

    var body: some View {
        Form {
            Section {
                Toggle("Show sports Live Activities", isOn: $sportsActivitiesEnabled)
                Toggle("Score update pop-downs", isOn: $scoreNotificationsEnabled)
                Toggle("Show upcoming games", isOn: $showUpcoming)
            } header: {
                Label("Live scores", systemImage: "sportscourt.fill")
            } footer: {
                Text("Your favorite games appear beside the notch. Score changes briefly drop down underneath it, similar to Apple Sports.")
            }

            Section("Leagues") {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(SportsLeague.allCases) { league in
                            let selected = enabledLeagues.contains(league)
                            Button {
                                if selected {
                                    enabledLeagues.remove(league)
                                } else {
                                    enabledLeagues.insert(league)
                                }
                                sports.configurationChanged()
                            } label: {
                                Label(league.title, systemImage: selected ? "checkmark.circle.fill" : league.symbol)
                                    .font(.callout.weight(.semibold))
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 8)
                                    .foregroundStyle(selected ? .white : .primary)
                                    .background(
                                        selected ? Color.accentColor : Color.secondary.opacity(0.12),
                                        in: Capsule()
                                    )
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.vertical, 2)
                }

                Text("Choose every league you want followed. At least one league is recommended.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .disabled(!sportsActivitiesEnabled)

            Section {
                Picker("Browse", selection: $browsingLeague) {
                    ForEach(SportsLeague.allCases) { league in
                        Text(league.title).tag(league)
                    }
                }

                TextField("Search teams", text: $teamSearch)
                    .textFieldStyle(.roundedBorder)

                if sports.isLoadingTeams {
                    HStack {
                        Spacer()
                        ProgressView().controlSize(.small)
                        Text("Loading teams…").foregroundStyle(.secondary)
                        Spacer()
                    }
                    .frame(height: 90)
                } else if let message = sports.teamsErrorMessage {
                    ContentUnavailableView(
                        "Couldn’t Load Teams",
                        systemImage: "wifi.exclamationmark",
                        description: Text(message)
                    )
                    .frame(height: 130)
                } else {
                    ScrollView {
                        LazyVGrid(columns: [GridItem(.adaptive(minimum: 210), spacing: 8)], spacing: 8) {
                            ForEach(filteredTeams) { team in
                                favoriteTeamButton(team)
                            }
                        }
                        .padding(.vertical, 2)
                    }
                    .frame(minHeight: 170, maxHeight: 310)
                }
            } header: {
                HStack {
                    Text("Favorite teams")
                    Spacer()
                    if !favoriteTeams.isEmpty {
                        Text("\(favoriteTeams.count) selected")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            } footer: {
                Text("Tap the star beside any team. When a favorite is playing, its game takes priority over other scores.")
            }
            .disabled(!sportsActivitiesEnabled)

            Section("Current activity") {
                if let game = sports.currentGame {
                    LabeledContent("Matchup", value: "\(game.away.abbreviation) at \(game.home.abbreviation)")
                    LabeledContent("Score", value: game.scoreSummary)
                    LabeledContent("Status", value: game.statusText)
                } else if sports.isLoading {
                    HStack {
                        ProgressView().controlSize(.small)
                        Text("Checking live scores…")
                    }
                } else {
                    Text(sports.errorMessage ?? "No matching game is available right now.")
                        .foregroundStyle(.secondary)
                }

                Button("Refresh Scores") {
                    Task { await sports.refresh() }
                }
                .disabled(!sportsActivitiesEnabled || sports.isLoading)

                Button("Preview Score Pop-down") {
                    sports.showScorePreview()
                }
                .disabled(!sportsActivitiesEnabled || !scoreNotificationsEnabled)
            }
            .disabled(!sportsActivitiesEnabled)

            Section("Data source") {
                Label("No account or API key required", systemImage: "lock.shield.fill")
                Text("Scores come from ESPN's public scoreboard feed. This custom feature is not affiliated with or endorsed by Apple or ESPN.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .navigationTitle("Sports")
        .accentColor(.effectiveAccent)
        .onAppear {
            if let first = enabledLeagues.first { browsingLeague = first }
            sports.start()
            Task { await sports.loadTeams(for: browsingLeague) }
        }
        .onChange(of: sportsActivitiesEnabled) { _, _ in sports.configurationChanged() }
        .onChange(of: showUpcoming) { _, _ in sports.configurationChanged() }
        .onChange(of: browsingLeague) { _, league in
            teamSearch = ""
            Task { await sports.loadTeams(for: league) }
        }
    }

    @ViewBuilder
    private func favoriteTeamButton(_ team: SportsDirectoryTeam) -> some View {
        let selected = favoriteTeams.contains(team.favoriteKey)
        Button {
            if selected {
                favoriteTeams.remove(team.favoriteKey)
            } else {
                favoriteTeams.insert(team.favoriteKey)
                enabledLeagues.insert(team.league)
            }
            sports.configurationChanged()
        } label: {
            HStack(spacing: 10) {
                AsyncImage(url: team.logoURL) { phase in
                    if case .success(let image) = phase {
                        image
                            .resizable()
                            .interpolation(.high)
                            .antialiased(true)
                            .scaledToFit()
                    } else {
                        Image(systemName: team.league.symbol)
                            .foregroundStyle(.secondary)
                    }
                }
                .frame(width: 30, height: 30)

                VStack(alignment: .leading, spacing: 1) {
                    Text(team.name)
                        .font(.callout.weight(.medium))
                        .lineLimit(1)
                    Text(team.abbreviation)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }

                Spacer(minLength: 4)

                Image(systemName: selected ? "star.fill" : "star")
                    .foregroundStyle(selected ? Color.yellow : Color.secondary)
                    .symbolEffect(.bounce, value: selected)
            }
            .padding(.horizontal, 10)
            .frame(height: 48)
            .background(
                selected ? Color.accentColor.opacity(0.13) : Color.secondary.opacity(0.07),
                in: RoundedRectangle(cornerRadius: 12, style: .continuous)
            )
            .overlay {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(selected ? Color.accentColor.opacity(0.38) : Color.white.opacity(0.06))
            }
        }
        .buttonStyle(.plain)
    }
}

struct WeatherSettings: View {
    @ObservedObject private var manager = WeatherManager.shared
    @Default(.weatherUseCurrentLocation) private var useCurrentLocation
    @Default(.weatherLocation) private var location
    @Default(.weatherUseCelsius) private var useCelsius
    @Default(.weatherOnLiveTab) private var weatherOnLiveTab

    var body: some View {
        Form {
            Section {
                Defaults.Toggle(key: .weatherEnabled) {
                    Text("Show weather")
                }
                Toggle("Use current location", isOn: $useCurrentLocation)
                    .onChange(of: useCurrentLocation) { manager.refresh() }

                Toggle("Show on Live tab", isOn: $weatherOnLiveTab)

                if !weatherOnLiveTab {
                    Text("Reorder or hide the Weather tile in Appearance → Home layout.")
                        .font(.caption).foregroundStyle(.secondary)
                }

                if !useCurrentLocation {
                    TextField("City or postal code", text: $location)
                        .onSubmit { manager.refresh() }
                }

                Picker("Temperature unit", selection: $useCelsius) {
                    Text("Fahrenheit").tag(false)
                    Text("Celsius").tag(true)
                }
                .onChange(of: useCelsius) { manager.refresh() }

                Button("Refresh Weather") {
                    manager.refresh(force: true)
                }
                .disabled((!useCurrentLocation && location.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty) || manager.isLoading)

                if useCurrentLocation {
                    if manager.locationAuthorizationStatus == .notDetermined {
                        Button("Use My Location…") { manager.useMyLocation() }
                    }
                    LabeledContent("Permission", value: manager.locationPermissionDescription)

                    if manager.locationAuthorizationStatus == .denied {
                        Button("Open Location Settings") {
                            if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_LocationServices") {
                                NSWorkspace.shared.open(url)
                            }
                        }
                    }
                }
            } header: {
                Text("Location")
            } footer: {
                Text(useCurrentLocation
                     ? "Your approximate coordinates are sent to Open-Meteo to retrieve local weather. No weather API key is needed."
                     : "The city name is sent to Open-Meteo to retrieve the forecast. No weather API key is needed.")
            }

            if let weather = manager.weather {
                Section("Preview") {
                    let valueString = String(format: "%.0f° • %@", weather.temperature, weather.condition)
                    LabeledContent(weather.location, value: valueString)
                }
            }
            if let error = manager.errorMessage {
                Section {
                    Label(error, systemImage: "exclamationmark.triangle")
                        .foregroundStyle(.orange)
                }
            }
            Section {
                Link("Weather data by Open-Meteo", destination: URL(string: "https://open-meteo.com/")!)
                    .font(.caption)
            }
        }
        .navigationTitle("Weather")
        .accentColor(.effectiveAccent)
        .onAppear { manager.refresh() }
    }
}

func lighterColor(from nsColor: NSColor, amount: CGFloat = 0.14) -> Color {
    let srgb = nsColor.usingColorSpace(.sRGB) ?? nsColor
    var (r, g, b, a): (CGFloat, CGFloat, CGFloat, CGFloat) = (0,0,0,0)
    srgb.getRed(&r, green: &g, blue: &b, alpha: &a)

    func lighten(_ c: CGFloat) -> CGFloat {
        let increased = c + (1.0 - c) * amount
        return min(max(increased, 0), 1)
    }

    let nr = lighten(r)
    let ng = lighten(g)
    let nb = lighten(b)

    return Color(red: Double(nr), green: Double(ng), blue: Double(nb), opacity: Double(a))
}

struct About: View {
    @State private var showBuildNumber: Bool = false
    let updaterController: SPUStandardUpdaterController
    @Environment(\.openWindow) var openWindow
    var body: some View {
        VStack {
            Form {
                Section {
                    HStack(spacing: 14) {
                        Image(nsImage: NSApplication.shared.applicationIconImage)
                            .resizable()
                            .scaledToFit()
                            .frame(width: 56, height: 56)
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Notchscape").font(.title2.weight(.semibold))
                            Text("Your Mac, together.").foregroundStyle(.secondary)
                        }
                    }
                    .padding(.vertical, 4)
                }
                Section {
                    HStack {
                        Text("Version")
                        Spacer()
                        if showBuildNumber {
                            Text("(\(Bundle.main.buildVersionNumber ?? ""))")
                                .foregroundStyle(.secondary)
                        }
                        Text(Bundle.main.releaseVersionNumber ?? "Unknown")
                            .foregroundStyle(.secondary)
                    }
                    .onTapGesture {
                        withAnimation {
                            showBuildNumber.toggle()
                        }
                    }
                } header: {
                    Text("Version info")
                }

                UpdaterSettingsView(updater: updaterController.updater)

                HStack(spacing: 30) {
                    Spacer(minLength: 0)
                    Button {
                        if let url = URL(string: "https://github.com/graden-grech/Notchscape-app") {
                            NSWorkspace.shared.open(url)
                        }
                    } label: {
                        VStack(spacing: 5) {
                            Image("Github")
                                .resizable()
                                .aspectRatio(contentMode: .fit)
                                .frame(width: 18)
                            Text("GitHub")
                        }
                        .contentShape(Rectangle())
                    }
                    Spacer(minLength: 0)
                }
                .buttonStyle(PlainButtonStyle())

                Section("Legal") {
                    Link("Open-Source Notices", destination: URL(string: "https://github.com/graden-grech/Notchscape-app/blob/main/docs/ATTRIBUTION.md")!)
                    Link("GNU General Public License", destination: URL(string: "https://github.com/graden-grech/Notchscape-app/blob/main/LICENSE")!)
                }
            }
            VStack(spacing: 0) {
                Divider()
                Text("Published by Notchscape")
                    .foregroundStyle(.secondary)
                    .padding(.top, 5)
                    .padding(.bottom, 7)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 10)
            }
            .frame(maxWidth: .infinity, alignment: .center)
        }
        .toolbar {
            //            Button("Welcome window") {
            //                openWindow(id: "onboarding")
            //            }
            //            .controlSize(.extraLarge)
            CheckForUpdatesView(updater: updaterController.updater)
        }
        .navigationTitle("About")
    }
}

struct Shelf: View {
    
    @Default(.shelfTapToOpen) var shelfTapToOpen: Bool
    @Default(.quickShareProvider) var quickShareProvider
    @Default(.expandedDragDetection) var expandedDragDetection: Bool
    @StateObject private var quickShareService = QuickShareService.shared

    private var selectedProvider: QuickShareProvider? {
        quickShareService.availableProviders.first(where: { $0.id == quickShareProvider })
    }
    
    init() {
        Task { await QuickShareService.shared.discoverAvailableProviders() }
    }
    
    var body: some View {
        Form {
            Section {
                Defaults.Toggle(key: .boringShelf) {
                    Text("Enable shelf")
                }
                Defaults.Toggle(key: .openShelfByDefault) {
                    Text("Open shelf by default if items are present")
                }
                Defaults.Toggle(key: .expandedDragDetection) {
                    Text("Expanded drag detection area")
                }
                .onChange(of: expandedDragDetection) {
                    NotificationCenter.default.post(
                        name: Notification.Name.expandedDragDetectionChanged,
                        object: nil
                    )
                }
                Defaults.Toggle(key: .copyOnDrag) {
                    Text("Copy items on drag")
                }
                Defaults.Toggle(key: .autoRemoveShelfItems) {
                    Text("Remove from shelf after dragging")
                }

            } header: {
                HStack {
                    Text("General")
                }
            }
            
            Section {
                Picker("Quick Share Service", selection: $quickShareProvider) {
                    ForEach(quickShareService.availableProviders, id: \.id) { provider in
                        HStack {
                            Group {
                                if let imgData = provider.imageData, let nsImg = NSImage(data: imgData) {
                                    Image(nsImage: nsImg)
                                        .resizable()
                                        .aspectRatio(contentMode: .fit)
                                } else {
                                    Image(systemName: "square.and.arrow.up")
                                }
                            }
                            .frame(width: 16, height: 16)
                            .foregroundColor(.accentColor)
                            Text(provider.id)
                        }
                        .tag(provider.id)
                    }
                }
                .pickerStyle(.menu)
                
                if let selectedProvider = selectedProvider {
                    HStack {
                        Group {
                            if let imgData = selectedProvider.imageData, let nsImg = NSImage(data: imgData) {
                                Image(nsImage: nsImg)
                                    .resizable()
                                    .aspectRatio(contentMode: .fit)
                            } else {
                                Image(systemName: "square.and.arrow.up")
                            }
                        }
                        .frame(width: 16, height: 16)
                        .foregroundColor(.accentColor)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Currently selected: \(selectedProvider.id)")
                                .font(.caption)
                                .foregroundColor(.secondary)
                            Text("Files dropped on the shelf will be shared via this service")
                                .font(.caption2)
                                .foregroundColor(.secondary)
                        }
                    }
                    .padding(.vertical, 4)
                }
                // Providers are always enabled; user can pick default service above.
                
            } header: {
                HStack {
                    Text("Quick Share")
                }
            } footer: {
                Text("Choose which service to use when sharing files from the shelf. Click the shelf button to select files, or drag files onto it to share immediately.")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .accentColor(.effectiveAccent)
        .navigationTitle("Shelf")
    }
}

//struct Extensions: View {
//    @State private var effectTrigger: Bool = false
//    var body: some View {
//        Form {
//            Section {
//                List {
//                    ForEach(extensionManager.installedExtensions.indices, id: \.self) { index in
//                        let item = extensionManager.installedExtensions[index]
//                        HStack {
//                            AppIcon(for: item.bundleIdentifier)
//                                .resizable()
//                                .frame(width: 24, height: 24)
//                            Text(item.name)
//                            ListItemPopover {
//                                Text("Description")
//                            }
//                            Spacer(minLength: 0)
//                            HStack(spacing: 6) {
//                                Circle()
//                                    .frame(width: 6, height: 6)
//                                    .foregroundColor(
//                                        isExtensionRunning(item.bundleIdentifier)
//                                            ? .green : item.status == .disabled ? .gray : .red
//                                    )
//                                    .conditionalModifier(isExtensionRunning(item.bundleIdentifier))
//                                { view in
//                                    view
//                                        .shadow(color: .green, radius: 3)
//                                }
//                                Text(
//                                    isExtensionRunning(item.bundleIdentifier)
//                                        ? "Running"
//                                        : item.status == .disabled ? "Disabled" : "Stopped"
//                                )
//                                .contentTransition(.numericText())
//                                .foregroundStyle(.secondary)
//                                .font(.footnote)
//                            }
//                            .frame(width: 60, alignment: .leading)
//
//                            Menu(
//                                content: {
//                                    Button("Restart") {
//                                        let ws = NSWorkspace.shared
//
//                                        if let ext = ws.runningApplications.first(where: {
//                                            $0.bundleIdentifier == item.bundleIdentifier
//                                        }) {
//                                            ext.terminate()
//                                        }
//
//                                        if let appURL = ws.urlForApplication(
//                                            withBundleIdentifier: item.bundleIdentifier)
//                                        {
//                                            ws.openApplication(
//                                                at: appURL, configuration: .init(),
//                                                completionHandler: nil)
//                                        }
//                                    }
//                                    .keyboardShortcut("R", modifiers: .command)
//                                    Button("Disable") {
//                                        if let ext = NSWorkspace.shared.runningApplications.first(
//                                            where: { $0.bundleIdentifier == item.bundleIdentifier })
//                                        {
//                                            ext.terminate()
//                                        }
//                                        extensionManager.installedExtensions[index].status =
//                                            .disabled
//                                    }
//                                    .keyboardShortcut("D", modifiers: .command)
//                                    Divider()
//                                    Button("Uninstall", role: .destructive) {
//                                        //
//                                    }
//                                },
//                                label: {
//                                    Image(systemName: "ellipsis.circle")
//                                        .foregroundStyle(.secondary)
//                                }
//                            )
//                            .controlSize(.regular)
//                        }
//                        .buttonStyle(PlainButtonStyle())
//                        .padding(.vertical, 5)
//                    }
//                }
//                .frame(minHeight: 120)
//                .actionBar {
//                    Button {
//                    } label: {
//                        HStack(spacing: 3) {
//                            Image(systemName: "plus")
//                            Text("Add manually")
//                        }
//                        .foregroundStyle(.secondary)
//                    }
//                    .disabled(true)
//                    Spacer()
//                    Button {
//                        withAnimation(.linear(duration: 1)) {
//                            effectTrigger.toggle()
//                        } completion: {
//                            effectTrigger.toggle()
//                        }
//                        extensionManager.checkIfExtensionsAreInstalled()
//                    } label: {
//                        HStack(spacing: 3) {
//                            Image(systemName: "arrow.triangle.2.circlepath")
//                                .rotationEffect(effectTrigger ? .degrees(360) : .zero)
//                        }
//                        .foregroundStyle(.secondary)
//                    }
//                }
//                .controlSize(.small)
//                .buttonStyle(PlainButtonStyle())
//                .overlay {
//                    if extensionManager.installedExtensions.isEmpty {
//                        Text("No extension installed")
//                            .foregroundStyle(Color(.secondaryLabelColor))
//                            .padding(.bottom, 22)
//                    }
//                }
//            } header: {
//                HStack(spacing: 0) {
//                    Text("Installed extensions")
//                    if !extensionManager.installedExtensions.isEmpty {
//                        Text(" – \(extensionManager.installedExtensions.count)")
//                            .foregroundStyle(.secondary)
//                    }
//                }
//            }
//        }
//        .accentColor(.effectiveAccent)
//        .navigationTitle("Extensions")
//        // TipsView()
//        // .padding(.horizontal, 19)
//    }
//}

private struct ThemePreviewCard: View {
    let theme: AppTheme
    let selected: Bool
    @Default(.useCustomAccentColor) private var useCustomAccentColor
    @Default(.customAccentColorData) private var customAccentColorData
    @Default(.starWarsVaderArtwork) private var starWarsVaderArtwork

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            ZStack {
                GeometryReader { geometry in
                    if theme.hasHomeScene {
                        HomeThemeScene(theme: theme, vaderArtwork: starWarsVaderArtwork,
                                       imageAlignment: theme.isStarWars ? .topTrailing : .center,
                                       preserveEntirePhoto: true)
                    } else {
                        LinearGradient(colors: [theme == .autumn ? Color.brown.opacity(0.75) : .black, .black], startPoint: .topLeading, endPoint: .bottomTrailing)
                    }
                }
                .overlay(.black.opacity(0.3))
                HStack(spacing: 10) {
                    Image(theme.matchingIcon.assetName).resizable().scaledToFit()
                        .frame(width: 30, height: 30)
                    VStack(alignment: .leading, spacing: 5) {
                        Capsule().fill(.white.opacity(0.85)).frame(width: 46, height: 3)
                        Capsule().fill(.white.opacity(0.35)).frame(width: 31, height: 3)
                        HStack(spacing: 8) {
                            Image(systemName: "backward.fill")
                            Image(systemName: "play.fill")
                            Image(systemName: "forward.fill")
                        }.font(.system(size: 8))
                    }
                    Image(systemName: "calendar").font(.system(size: 22, weight: .light))
                    Spacer(minLength: 0)
                }
                .foregroundStyle(.white)
                .padding(12)
            }
            .aspectRatio(theme.isWhiteHouse ? 16.0 / 9.0 : 3.0, contentMode: .fit)
            .clipShape(RoundedRectangle(cornerRadius: 11, style: .continuous))

            HStack {
                Text(theme.isWhiteHouse ? "White House" : theme.isStarWars ? "Star Wars" : theme.title).font(.callout.weight(.semibold))
                Spacer()
                Image(systemName: selected ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(selected ? Color.effectiveAccent : .secondary.opacity(0.45))
            }
            Text(theme.subtitle).font(.caption).foregroundStyle(.secondary)
                .lineLimit(2).frame(height: 28, alignment: .topLeading)
        }
        .padding(10)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(.white.opacity(selected ? 0.085 : 0.035), in: RoundedRectangle(cornerRadius: 16))
        .overlay {
            RoundedRectangle(cornerRadius: 16).strokeBorder(selected ? Color.effectiveAccent : .white.opacity(0.1), lineWidth: selected ? 2 : 1)
        }
    }
}

private struct SeasonalIconPicker: View {
    @Default(.appIconFollowsTheme) private var followsTheme
    @Default(.appIconVariant) private var selectedIcon
    @Default(.appTheme) private var theme
    @Default(.useCustomAccentColor) private var useCustomAccentColor
    @Default(.customAccentColorData) private var customAccentColorData

    var body: some View {
        Toggle("Match icon to theme", isOn: $followsTheme)
            .onChange(of: followsTheme) { _, enabled in
                if enabled {
                    selectedIcon = theme.matchingIcon
                    selectedIcon.apply()
                }
            }
        iconGrid(AppIconVariant.allCases.filter { !$0.isWhiteHouse })
        VStack(alignment: .leading, spacing: 8) {
            Text("White House").font(.subheadline.weight(.medium))
                .accessibilityAddTraits(.isHeader)
            iconGrid(AppIconVariant.allCases.filter(\.isWhiteHouse))
        }
        Text("Choose any icon yourself, or let the theme choose it. White House matching follows its color style and Christmas setting. Manual choices turn off matching.")
            .font(.caption).foregroundStyle(.secondary)
    }

    private func iconGrid(_ icons: [AppIconVariant]) -> some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 84), spacing: 8)], spacing: 8) {
            ForEach(icons) { icon in
                Button {
                    followsTheme = false
                    selectedIcon = icon
                    icon.apply()
                } label: {
                    VStack(spacing: 6) {
                        Image(icon.assetName).resizable().scaledToFit()
                            .frame(width: 64, height: 64)
                        Text(icon.pickerTitle).font(.caption)
                            .multilineTextAlignment(.center)
                            .lineLimit(2, reservesSpace: true)
                        Image(systemName: selectedIcon == icon ? "checkmark.circle.fill" : "circle")
                            .foregroundStyle(selectedIcon == icon ? Color.effectiveAccent : .secondary.opacity(0.4))
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
                    .background(.white.opacity(selectedIcon == icon ? 0.08 : 0), in: RoundedRectangle(cornerRadius: 12))
                }
                .buttonStyle(.plain)
                .accessibilityLabel(icon.title + " app icon")
                .accessibilityAddTraits(selectedIcon == icon ? [.isSelected] : [])
            }
        }
    }
}

private struct ThemeAccentPicker: View {
    @Default(.useCustomAccentColor) private var useCustomAccentColor
    @Default(.customAccentColorData) private var customAccentColorData
    @Default(.appTheme) private var theme

    private var savedColor: NSColor? {
        guard let data = customAccentColorData else { return nil }
        return try? NSKeyedUnarchiver.unarchivedObject(ofClass: NSColor.self, from: data)
    }

    private var followsTheme: Binding<Bool> {
        Binding(get: { !useCustomAccentColor }, set: { automatic in
            if automatic {
                useCustomAccentColor = false
            } else if savedColor == nil {
                saveColor(Color(nsColor: .effectiveAccent))
            } else {
                useCustomAccentColor = true
            }
        })
    }

    private var customColor: Binding<Color> {
        Binding(get: { Color(nsColor: savedColor ?? .effectiveAccent) }, set: saveColor)
    }

    var body: some View {
        Toggle("Match theme", isOn: followsTheme)
        LabeledContent("Current accent") {
            HStack(spacing: 8) {
                Circle().fill(Color.effectiveAccent).frame(width: 16, height: 16)
                Text(useCustomAccentColor ? "Custom" : theme == .system ? "macOS system" : theme.title)
                    .foregroundStyle(.secondary)
            }
        }
        HStack(spacing: 12) {
            ForEach(PresetAccentColor.allCases) { preset in
                AccentCircleButton(isSelected: isSelected(preset.color), color: preset.color) {
                    saveColor(preset.color)
                }
                .help(preset.rawValue + " accent")
                .accessibilityLabel(preset.rawValue + " accent")
                .accessibilityAddTraits(isSelected(preset.color) ? [.isSelected] : [])
            }
        }
        .padding(.vertical, 4)
        ColorPicker("Choose your own color", selection: customColor, supportsOpacity: false)
        Text("Themes choose the accent automatically. Picking a color turns off matching and keeps your choice when you switch themes. Turn matching back on to restore automatic colors.")
            .font(.caption)
            .foregroundStyle(.secondary)
    }

    private func saveColor(_ color: Color) {
        let nsColor = (NSColor(color).usingColorSpace(.sRGB) ?? NSColor(color)).withAlphaComponent(1)
        guard let data = try? NSKeyedArchiver.archivedData(withRootObject: nsColor, requiringSecureCoding: true) else { return }
        customAccentColorData = data
        useCustomAccentColor = true
    }

    private func isSelected(_ color: Color) -> Bool {
        guard useCustomAccentColor,
              let saved = savedColor?.usingColorSpace(.sRGB),
              let candidate = NSColor(color).usingColorSpace(.sRGB) else { return false }
        return abs(saved.redComponent - candidate.redComponent) < 0.01
            && abs(saved.greenComponent - candidate.greenComponent) < 0.01
            && abs(saved.blueComponent - candidate.blueComponent) < 0.01
    }
}

struct Appearance: View {
    @ObservedObject var coordinator = NotchscapeCoordinator.shared
    @ObservedObject private var performance = AppPerformanceManager.shared
    @Default(.mirrorShape) var mirrorShape
    @Default(.sliderColor) var sliderColor
    @Default(.useMusicVisualizer) var useMusicVisualizer
    @Default(.customVisualizers) var customVisualizers
    @Default(.selectedVisualizer) var selectedVisualizer
    @Default(.appTheme) var appTheme
    @Default(.whiteHousePreferredVariant) private var whiteHousePreferredVariant
    @Default(.appIconVariant) var appIconVariant
    @Default(.appIconFollowsTheme) private var appIconFollowsTheme
    @Default(.useCustomAccentColor) private var useCustomAccentColor
    @Default(.customAccentColorData) private var customAccentColorData

    @State private var selectedListVisualizer: CustomVisualizer? = nil
    @State private var isPresented: Bool = false
    @State private var name: String = ""
    @State private var url: String = ""
    @State private var speed: CGFloat = 1.0
    @State private var starWarsSettingsPresented = false
    @State private var whiteHouseSettingsPresented = false

    private func previewTheme(for theme: AppTheme) -> AppTheme {
        if theme.isStarWars && appTheme.isStarWars { return appTheme }
        if theme.isWhiteHouse {
            return appTheme.isWhiteHouse ? appTheme : AppTheme(rawValue: whiteHousePreferredVariant.rawValue) ?? .whiteHouse
        }
        return theme
    }

    private func isSelected(_ theme: AppTheme) -> Bool {
        appTheme == theme || (theme.isStarWars && appTheme.isStarWars) || (theme.isWhiteHouse && appTheme.isWhiteHouse)
    }

    var body: some View {
        Form {
            Section {
                Toggle("Always show tabs", isOn: $coordinator.alwaysShowTabs)
                Defaults.Toggle(key: .settingsIconInNotch) {
                    Text("Show settings icon in notch")
                }

            } header: {
                Text("General")
            }

            Section {
                LazyVGrid(columns: [GridItem(.flexible(), alignment: .top), GridItem(.flexible(), alignment: .top)], spacing: 14) {
                    ForEach(AppTheme.pickerThemes) { theme in
                        Button {
                            let selectedTheme = previewTheme(for: theme)
                            if let current = appTheme.whiteHouseVariant { whiteHousePreferredVariant = current }
                            withAnimation(performance.suppressAnimations ? nil : .smooth(duration: 0.22)) {
                                Defaults[.automaticSeasonalThemes] = false
                                appTheme = selectedTheme
                                if appIconFollowsTheme {
                                    appIconVariant = selectedTheme.matchingIcon
                                }
                            }
                            if appIconFollowsTheme { selectedTheme.matchingIcon.apply() }
                            if theme.isStarWars { starWarsSettingsPresented = true }
                            if theme.isWhiteHouse { whiteHouseSettingsPresented = true }
                        } label: {
                            ThemePreviewCard(theme: previewTheme(for: theme), selected: isSelected(theme))
                        }
                        .buttonStyle(.plain)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                        .accessibilityLabel(theme.isWhiteHouse ? "White House theme" : theme.isStarWars ? "Star Wars themes" : theme.title)
                        .accessibilityHint(theme.isWhiteHouse ? "Choose neutral, Republican or Democrat décor, four rooms or views, and optional Christmas decorations." : theme.isStarWars ? "Choose Jedi, Dark Side, or a character, and customize your lightsaber music bar." : "Apply this theme")
                        .accessibilityAddTraits(isSelected(theme) ? [.isSelected] : [])
                    }
                }
            } header: {
                Text("Menu theme")
            } footer: {
                Text("Preview Home’s scenes and six quiet, scalable palette themes. White House opens its own room and accent choices. Star Wars opens Jedi, Dark Side, and Characters. Winter has no holiday decorations.")
            }
            .sheet(isPresented: $starWarsSettingsPresented) { StarWarsThemeSettingsView() }
            .sheet(isPresented: $whiteHouseSettingsPresented) { WhiteHouseThemeSettingsView() }

            Section {
                Defaults.Toggle("Quiet scene detail", key: .themeDetailsEnabled)
                Text("Adds a small, static motif to the six palette themes. Off by default; no animation, particles, audio, or background work. Low-impact mode hides the extra detail.")
                    .font(.caption).foregroundStyle(.secondary)
            } header: { Text("Scene Detail") }

            AppearanceRecipesView()

            Section("App icon") {
                SeasonalIconPicker()
            }

            Section("Seasonal switching") {
                SeasonalThemeSettings()
            }

            Section("Accent color") {
                ThemeAccentPicker()
            }

            Section("Home layout") {
                HomeLayoutSettings()
            }

            Section("Quick Actions") {
                QuickActionsSettings()
            }

            Section {
                Defaults.Toggle(key: .coloredSpectrogram) {
                    Text("Colored spectrogram")
                }
                Defaults
                    .Toggle("Player tinting", key: .playerColorTinting)
                Defaults.Toggle(key: .lightingEffect) {
                    Text("Enable blur effect behind album art")
                }
                Picker("Slider color", selection: $sliderColor) {
                    ForEach(SliderColorEnum.allCases, id: \.self) { option in
                        Text(option.rawValue)
                    }
                }
            } header: {
                Text("Media")
            }

            Section {
                Toggle(
                    "Use music visualizer spectrogram",
                    isOn: $useMusicVisualizer.animation()
                )
                .disabled(true)
                if !useMusicVisualizer {
                    if customVisualizers.count > 0 {
                        Picker(
                            "Selected animation",
                            selection: $selectedVisualizer
                        ) {
                            ForEach(
                                customVisualizers,
                                id: \.self
                            ) { visualizer in
                                Text(visualizer.name)
                                    .tag(visualizer)
                            }
                        }
                    } else {
                        HStack {
                            Text("Selected animation")
                            Spacer()
                            Text("No custom animation available")
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            } header: {
                HStack {
                    Text("Custom music live activity animation")
                    customBadge(text: "Coming soon")
                }
            }

            Section {
                List {
                    ForEach(customVisualizers, id: \.self) { visualizer in
                        HStack {
                            LottieView(
                                url: visualizer.url, speed: visualizer.speed,
                                loopMode: .loop
                            )
                            .frame(width: 30, height: 30, alignment: .center)
                            Text(visualizer.name)
                            Spacer(minLength: 0)
                            if selectedVisualizer == visualizer {
                                Text("selected")
                                    .font(.caption)
                                    .fontWeight(.medium)
                                    .foregroundStyle(.secondary)
                                    .padding(.trailing, 8)
                            }
                        }
                        .buttonStyle(PlainButtonStyle())
                        .padding(.vertical, 2)
                        .background(
                            selectedListVisualizer != nil
                                ? selectedListVisualizer == visualizer
                                    ? Color.effectiveAccent : Color.clear : Color.clear,
                            in: RoundedRectangle(cornerRadius: 5)
                        )
                        .contentShape(Rectangle())
                        .onTapGesture {
                            if selectedListVisualizer == visualizer {
                                selectedListVisualizer = nil
                                return
                            }
                            selectedListVisualizer = visualizer
                        }
                    }
                }
                .safeAreaPadding(
                    EdgeInsets(top: 5, leading: 0, bottom: 5, trailing: 0)
                )
                .frame(minHeight: 120)
                .actionBar {
                    HStack(spacing: 5) {
                        Button {
                            name = ""
                            url = ""
                            speed = 1.0
                            isPresented.toggle()
                        } label: {
                            Image(systemName: "plus")
                                .foregroundStyle(.secondary)
                                .contentShape(Rectangle())
                        }
                        Divider()
                        Button {
                            if selectedListVisualizer != nil {
                                let visualizer = selectedListVisualizer!
                                selectedListVisualizer = nil
                                customVisualizers.remove(
                                    at: customVisualizers.firstIndex(of: visualizer)!)
                                if visualizer == selectedVisualizer && customVisualizers.count > 0 {
                                    selectedVisualizer = customVisualizers[0]
                                }
                            }
                        } label: {
                            Image(systemName: "minus")
                                .foregroundStyle(.secondary)
                                .contentShape(Rectangle())
                        }
                    }
                }
                .controlSize(.small)
                .buttonStyle(PlainButtonStyle())
                .overlay {
                    if customVisualizers.isEmpty {
                        Text("No custom visualizer")
                            .foregroundStyle(Color(.secondaryLabelColor))
                            .padding(.bottom, 22)
                    }
                }
                .sheet(isPresented: $isPresented) {
                    VStack(alignment: .leading) {
                        Text("Add new visualizer")
                            .font(.largeTitle.bold())
                            .padding(.vertical)
                        TextField("Name", text: $name)
                        TextField("Lottie JSON URL", text: $url)
                        HStack {
                            Text("Speed")
                            Spacer(minLength: 80)
                            Text("\(speed, specifier: "%.1f")s")
                                .multilineTextAlignment(.trailing)
                                .foregroundStyle(.secondary)
                            Slider(value: $speed, in: 0...2, step: 0.1)
                        }
                        .padding(.vertical)
                        HStack {
                            Button {
                                isPresented.toggle()
                            } label: {
                                Text("Cancel")
                                    .frame(maxWidth: .infinity, alignment: .center)
                            }

                            Button {
                                let visualizer: CustomVisualizer = .init(
                                    UUID: UUID(),
                                    name: name,
                                    url: URL(string: url)!,
                                    speed: speed
                                )

                                if !customVisualizers.contains(visualizer) {
                                    customVisualizers.append(visualizer)
                                }

                                isPresented.toggle()
                            } label: {
                                Text("Add")
                                    .frame(maxWidth: .infinity, alignment: .center)
                            }
                            .buttonStyle(BorderedProminentButtonStyle())
                        }
                    }
                    .textFieldStyle(RoundedBorderTextFieldStyle())
                    .controlSize(.extraLarge)
                    .padding()
                }
            } header: {
                HStack(spacing: 0) {
                    Text("Custom vizualizers (Lottie)")
                    if !Defaults[.customVisualizers].isEmpty {
                        Text(" – \(Defaults[.customVisualizers].count)")
                            .foregroundStyle(.secondary)
                    }
                }
            }

            Section {
                Defaults.Toggle(key: .showMirror) {
                    Text("Enable mirror")
                }
                    .disabled(!checkVideoInput())
                Picker("Mirror shape", selection: $mirrorShape) {
                    ForEach(
                        [MirrorShapeEnum.circle, .rectangle, .roundedRectangle, .squircle, .capsule],
                        id: \.rawValue
                    ) { shape in
                        Text(shape.rawValue).tag(shape)
                    }
                }
                Defaults.Toggle(key: .showNotHumanFace) {
                    Text("Show cool face animation while inactive")
                }
            } header: {
                HStack {
                    Text("Additional features")
                }
            }
        }
        .accentColor(.effectiveAccent)
        .navigationTitle("Appearance")
    }

    func checkVideoInput() -> Bool {
        if AVCaptureDevice.default(for: .video) != nil {
            return true
        }

        return false
    }
}

struct Advanced: View {
    var body: some View {
        Form {
            Section("Window Appearance") {
                Defaults.Toggle(key: .enableShadow) { Text("Enable window shadow") }
                Defaults.Toggle(key: .cornerRadiusScaling) { Text("Corner radius scaling") }
            }
            Section("Window Behavior") {
                Defaults.Toggle(key: .extendHoverArea) { Text("Extend hover area") }
                Defaults.Toggle(key: .hideFromScreenRecording) { Text("Hide from screen recording") }
            }
            Section {
                Defaults.Toggle(key: .showOnLockScreen) { Text("Show locked Home dropdown") }
                Button("Preview Locked Home…") {
                    NotificationCenter.default.post(name: .previewLockedHomeRequested, object: nil)
                }
            } header: {
                Text("Lock Screen · Experimental")
            } footer: {
                Text("Shows a lock instead of your Home widgets while your Mac is locked. Hover or click to expand the lock view; unlock your Mac normally to return to Home. Calendar, files, AI activity and account details are not shown. Uses the existing experimental lock-screen window integration; interaction depends on macOS. Preview does not lock your Mac and ends after 30 seconds.")
            }
            Text("App icons, themes, accent colors and Home layout are in Appearance. Performance options are in General.")
                .font(.caption).foregroundStyle(.secondary)
        }
        .accentColor(.effectiveAccent)
        .navigationTitle("Advanced")
    }
}

// MARK: - Accent Circle Button Component
struct AccentCircleButton: View {
    let isSelected: Bool
    let color: Color
    var isSystemDefault: Bool = false
    var isMulticolor: Bool = false
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            ZStack {
                // Color circle
                Circle()
                    .fill(color)
                    .frame(width: 32, height: 32)
                
                // Subtle border
                Circle()
                    .strokeBorder(Color.primary.opacity(0.15), lineWidth: 1)
                    .frame(width: 32, height: 32)
                
                // Apple-style highlight ring around the middle when selected
                if isSelected {
                    Circle()
                        .strokeBorder(
                            Color.white.opacity(0.5),
                            lineWidth: 2
                        )
                        .frame(width: 28, height: 28)
                }
            }
        }
        .buttonStyle(.plain)
        .help(isSystemDefault ? "Use your macOS system accent color" : "")
    }
}

struct Shortcuts: View {
    var body: some View {
        Form {
            Section {
                KeyboardShortcuts.Recorder("Toggle Sneak Peek:", name: .toggleSneakPeek)
            } header: {
                Text("Media")
            } footer: {
                Text(
                    "Sneak Peek shows the media title and artist under the notch for a few seconds."
                )
                .multilineTextAlignment(.trailing)
                .foregroundStyle(.secondary)
                .font(.caption)
            }
            Section {
                KeyboardShortcuts.Recorder("Toggle Notch Open:", name: .toggleNotchOpen)
            }
        }
        .accentColor(.effectiveAccent)
        .navigationTitle("Shortcuts")
    }
}

func proFeatureBadge() -> some View {
    Text("Upgrade to Pro")
        .foregroundStyle(Color(red: 0.545, green: 0.196, blue: 0.98))
        .font(.footnote.bold())
        .padding(.vertical, 3)
        .padding(.horizontal, 6)
        .background(
            RoundedRectangle(cornerRadius: 4).stroke(
                Color(red: 0.545, green: 0.196, blue: 0.98), lineWidth: 1))
}

func comingSoonTag() -> some View {
    Text("Coming soon")
        .foregroundStyle(.secondary)
        .font(.footnote.bold())
        .padding(.vertical, 3)
        .padding(.horizontal, 6)
        .background(Color(nsColor: .secondarySystemFill))
        .clipShape(.capsule)
}

func customBadge(text: String) -> some View {
    Text(text)
        .foregroundStyle(.secondary)
        .font(.footnote.bold())
        .padding(.vertical, 3)
        .padding(.horizontal, 6)
        .background(Color(nsColor: .secondarySystemFill))
        .clipShape(.capsule)
}

func warningBadge(_ text: String, _ description: String) -> some View {
    Section {
        HStack(spacing: 12) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 22))
                .foregroundStyle(.yellow)
            VStack(alignment: .leading) {
                Text(text)
                    .font(.headline)
                Text(description)
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
    }
}

#Preview {
    HUD()
}
