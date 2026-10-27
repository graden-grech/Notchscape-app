import AppKit
import Combine
import Defaults
import UniformTypeIdentifiers

/// One owner for Dock visibility, including when Settings or permission alerts open.
@MainActor
final class AppPresentationManager {
    static let shared = AppPresentationManager()
    private var subscription: AnyCancellable?
    private var activationSubscription: AnyCancellable?

    private init() {}

    func start() {
        guard subscription == nil else { return }
        apply()
        subscription = Defaults.publisher(.showDockIcon)
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in self?.apply() }
        activationSubscription = NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in self?.refreshApplicationMenuAfterLayout() }
    }

    func apply() {
        defer { refreshApplicationMenuAfterLayout() }
        let policy: NSApplication.ActivationPolicy = Defaults[.showDockIcon] ? .regular : .accessory
        guard NSApp.activationPolicy() != policy else { return }
        let keyWindow = NSApp.keyWindow
        let wasActive = NSApp.isActive
        guard NSApp.setActivationPolicy(policy) else { return }
        // Only customize a visible Dock tile. Updating artwork after hiding
        // can leave/recreate a tile even though AppKit reports accessory mode.
        if policy == .regular { Defaults[.appIconVariant].apply() }
        if wasActive {
            NSApp.activate(ignoringOtherApps: true)
            keyWindow?.makeKeyAndOrderFront(nil)
        }
    }

    private func refreshApplicationMenuAfterLayout() {
        // SwiftUI may create/rebuild its menu after launch or activation-policy
        // changes. Update on the next turn, not with a timer or process rename.
        DispatchQueue.main.async { [weak self] in self?.refreshApplicationMenuTitle() }
    }

    private func refreshApplicationMenuTitle() {
        guard let applicationItem = NSApp.mainMenu?.items.first,
              let applicationMenu = applicationItem.submenu else { return }
        let name = Bundle.main.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String ?? "Notchscape"
        if applicationItem.title != name { applicationItem.title = name }
        if applicationMenu.title != name { applicationMenu.title = name }
        // Keep system localization and actions; replace only the previous brand.
        for item in applicationMenu.items {
            var title = item.title
            for previous in ["Boring Notch", "boring.notch", "boringNotch"] {
                title = title.replacingOccurrences(of: previous, with: name)
            }
            if item.title != title { item.title = title }
        }
    }
}

@MainActor
final class AppPerformanceManager: ObservableObject {
    static let shared = AppPerformanceManager()
    @Published private(set) var lowImpact = false
    @Published private(set) var reduceMotion = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
    @Published private(set) var reduceTransparency = NSWorkspace.shared.accessibilityDisplayShouldReduceTransparency
    var suppressAnimations: Bool { lowImpact || reduceMotion }
    var mediaInterval: TimeInterval { lowImpact ? 1 : 0.25 }
    var samplingInterval: TimeInterval { lowImpact ? 3 : 1.5 }
    var hookInterval: TimeInterval { lowImpact ? 1.8 : 0.65 }
    private var subscriptions = Set<AnyCancellable>()

    private init() {
        Defaults.publisher(.performanceMode).sink { [weak self] _ in self?.update() }.store(in: &subscriptions)
        WorkspaceModeManager.shared.$session.dropFirst().receive(on: RunLoop.main)
            .sink { [weak self] _ in self?.update() }.store(in: &subscriptions)
        BatteryStatusViewModel.shared.$isPluggedIn.combineLatest(BatteryStatusViewModel.shared.$maxCapacity)
            .receive(on: RunLoop.main).sink { [weak self] _ in self?.update() }.store(in: &subscriptions)
        NotificationCenter.default.publisher(for: .NSProcessInfoPowerStateDidChange)
            .receive(on: RunLoop.main).sink { [weak self] _ in self?.update() }.store(in: &subscriptions)
        NSWorkspace.shared.notificationCenter.publisher(for: NSWorkspace.accessibilityDisplayOptionsDidChangeNotification)
            .receive(on: RunLoop.main).sink { [weak self] _ in self?.update() }.store(in: &subscriptions)
        update()
    }

    private func update() {
        let battery = BatteryStatusViewModel.shared
        let newLowImpact = WorkspaceModePolicy.lowImpact(
            base: Defaults[.performanceMode].isLowImpact(onBattery: battery.maxCapacity > 0 && !battery.isPluggedIn,
                                                       systemLowPower: ProcessInfo.processInfo.isLowPowerModeEnabled),
            mode: WorkspaceModeManager.shared.active)
        if lowImpact != newLowImpact { lowImpact = newLowImpact }
        let newReduceMotion = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        if reduceMotion != newReduceMotion { reduceMotion = newReduceMotion }
        let newReduceTransparency = NSWorkspace.shared.accessibilityDisplayShouldReduceTransparency
        if reduceTransparency != newReduceTransparency { reduceTransparency = newReduceTransparency }
    }
}

@MainActor
final class SeasonalThemeManager {
    static let shared = SeasonalThemeManager()
    private var subscriptions = Set<AnyCancellable>()
    private var midnightTask: Task<Void, Never>?

    private init() {}

    func start() {
        guard subscriptions.isEmpty else { return }
        Defaults.publisher(.automaticSeasonalThemes).sink { [weak self] _ in self?.configure() }.store(in: &subscriptions)
        Defaults.publisher(.seasonHemisphere).sink { [weak self] _ in self?.refresh() }.store(in: &subscriptions)
        Defaults.publisher(.seasonalHalloween).sink { [weak self] _ in self?.refresh() }.store(in: &subscriptions)
        Defaults.publisher(.seasonalChristmas).sink { [weak self] _ in self?.refresh() }.store(in: &subscriptions)
        Defaults.publisher(.seasonalEaster).sink { [weak self] _ in self?.refresh() }.store(in: &subscriptions)
        NSWorkspace.shared.notificationCenter.publisher(for: NSWorkspace.didWakeNotification)
            .receive(on: RunLoop.main).sink { [weak self] _ in self?.configure() }.store(in: &subscriptions)
        NotificationCenter.default.publisher(for: .NSSystemClockDidChange)
            .receive(on: RunLoop.main).sink { [weak self] _ in self?.configure() }.store(in: &subscriptions)
        configure()
    }

    func refresh(date: Date = Date()) {
        guard Defaults[.automaticSeasonalThemes] else { return }
        let name = SeasonalThemeSchedule.themeName(date: date, hemisphere: Defaults[.seasonHemisphere],
            halloween: Defaults[.seasonalHalloween], christmas: Defaults[.seasonalChristmas], easter: Defaults[.seasonalEaster])
        guard let theme = AppTheme(rawValue: name) else { return }
        if Defaults[.appTheme] != theme { Defaults[.appTheme] = theme }
        if Defaults[.appIconFollowsTheme], Defaults[.appIconVariant] != theme.matchingIcon {
            Defaults[.appIconVariant] = theme.matchingIcon
            theme.matchingIcon.apply()
        }
    }

    private func configure() {
        midnightTask?.cancel()
        midnightTask = nil
        guard Defaults[.automaticSeasonalThemes] else { return }
        refresh()
        midnightTask = Task { [weak self] in
            while !Task.isCancelled {
                let now = Date()
                let nextDay = Calendar.current.date(byAdding: .day, value: 1, to: Calendar.current.startOfDay(for: now)) ?? now.addingTimeInterval(86400)
                try? await Task.sleep(for: .seconds(max(1, nextDay.timeIntervalSince(now))))
                guard !Task.isCancelled else { return }
                self?.refresh()
            }
        }
    }
}

@MainActor
final class QuickActionsManager: ObservableObject {
    static let shared = QuickActionsManager()
    @Published private(set) var shortcutNames: [String] = []
    @Published private(set) var isLoading = false
    @Published private(set) var runningIDs: Set<UUID> = []
    @Published var errorMessage: String?
    private var icons: [String: NSImage] = [:]
    private var activeProcesses: [UUID: Process] = [:]
    private init() {}

    func icon(for action: NotchQuickAction) -> NSImage? {
        guard action.kind == .application else { return nil }
        if let icon = icons[action.target] { return icon }
        let icon = NSWorkspace.shared.icon(forFile: action.target)
        if icons.count >= 12 { icons.removeAll() }
        icons[action.target] = icon
        return icon
    }

    func addApplication() {
        guard Defaults[.quickActions].count < 6 else { errorMessage = "Home supports up to six quick actions."; return }
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.applicationBundle]
        panel.directoryURL = URL(fileURLWithPath: "/Applications")
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.allowsMultipleSelection = false
        panel.title = "Choose an app for Quick Actions"
        panel.begin { [weak self] response in
            Task { @MainActor in
                guard response == .OK, let url = panel.url else { return }
                let name = (Bundle(url: url)?.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String)
                    ?? url.deletingPathExtension().lastPathComponent
                self?.add(NotchQuickAction(name: name, kind: .application, target: url.path))
            }
        }
    }

    func addShortcut(_ name: String) {
        guard !name.isEmpty, name.count <= 512 else { return }
        add(NotchQuickAction(name: name, kind: .shortcut, target: name))
    }

    private func add(_ action: NotchQuickAction) {
        var actions = Defaults[.quickActions]
        guard actions.count < 6 else { errorMessage = "Home supports up to six quick actions."; return }
        guard !actions.contains(where: { $0.kind == action.kind && $0.target == action.target }) else { return }
        actions.append(action)
        Defaults[.quickActions] = actions
    }

    func loadShortcuts() async {
        guard !isLoading else { return }
        isLoading = true
        defer { isLoading = false }
        let result = await Task.detached(priority: .utility) {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/shortcuts")
            process.arguments = ["list"]
            let output = Pipe()
            process.standardOutput = output
            process.standardError = FileHandle.nullDevice
            do {
                try process.run()
                let timeout = DispatchWorkItem { if process.isRunning { process.terminate() } }
                DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + 10, execute: timeout)
                defer { timeout.cancel() }
                // Drain concurrently with the process to avoid a full pipe deadlock.
                let data = output.fileHandleForReading.readDataToEndOfFile()
                process.waitUntilExit()
                guard process.terminationStatus == 0 else { return [String]() }
                return Array(Set(String(decoding: data, as: UTF8.self).split(separator: "\n").map(String.init))).sorted()
            } catch { return [String]() }
        }.value
        shortcutNames = result
    }

    func run(_ action: NotchQuickAction) {
        guard !runningIDs.contains(action.id) else { return }
        errorMessage = nil
        if action.kind == .application {
            let url = URL(fileURLWithPath: action.target)
            guard url.pathExtension.lowercased() == "app", FileManager.default.fileExists(atPath: url.path) else {
                errorMessage = "This app is no longer at its saved location. Remove it and add it again."
                return
            }
            NSWorkspace.shared.openApplication(at: url, configuration: .init()) { [weak self] _, error in
                Task { @MainActor in if error != nil { self?.errorMessage = "Couldn't open \(action.name)." } }
            }
        } else {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/shortcuts")
            // Separate argv values, never a shell command. -- protects names
            // beginning with a dash from being interpreted as an option.
            process.arguments = ["run", "--", action.target]
            process.standardOutput = FileHandle.nullDevice
            process.standardError = FileHandle.nullDevice
            process.terminationHandler = { [weak self] process in
                Task { @MainActor in
                    self?.runningIDs.remove(action.id)
                    self?.activeProcesses[action.id] = nil
                    if process.terminationStatus != 0 { self?.errorMessage = "\(action.name) didn't finish. Check its permissions in Shortcuts." }
                }
            }
            do {
                runningIDs.insert(action.id)
                activeProcesses[action.id] = process
                try process.run()
            } catch {
                runningIDs.remove(action.id)
                activeProcesses[action.id] = nil
                errorMessage = "Couldn't start Shortcuts."
            }
        }
    }
}
