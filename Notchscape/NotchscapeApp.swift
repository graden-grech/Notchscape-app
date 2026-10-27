//
//  NotchscapeApp.swift
//  NotchscapeApp
//
//  Created by Harsh Vardhan  Goswami  on 02/08/24.
//

import AVFoundation
import Combine
import Defaults
import KeyboardShortcuts
import Sparkle
import SwiftUI

@main
struct NotchscapeApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @Default(.menubarIcon) var showMenuBarIcon
    @Environment(\.openWindow) var openWindow

    let updaterController: SPUStandardUpdaterController

    init() {
        Self.migrateSandboxPreferencesIfNeeded()
        Self.applyInitialPresentationDefaults()

        updaterController = SPUStandardUpdaterController(
            startingUpdater: true, updaterDelegate: nil, userDriverDelegate: nil)

        // Keep the local agent bridge available even before the Live tab is opened.
        _ = AgentStatusManager.shared

        // Start the HUD interceptor at process launch. This cannot rely only on
        // the settings/coordinator view lifecycle because the notch app may run
        // without either view being constructed yet.
        Task { @MainActor in
            if Defaults[.hudReplacement] {
                await MediaKeyInterceptor.shared.start(promptIfNeeded: false)
            }
        }

        // Initialize the settings window controller with the updater controller
        SettingsWindowController.shared.setUpdaterController(updaterController)
    }

    private static func applyInitialPresentationDefaults() {
        guard let bundleID = Bundle.main.bundleIdentifier else { return }
        let defaults = UserDefaults.standard
        guard !defaults.bool(forKey: InitialPresentationDefaults.migrationKey) else { return }
        let persistent = defaults.persistentDomain(forName: bundleID) ?? [:]
        let missing = InitialPresentationDefaults.missingValues(in: persistent)
        // Write through Defaults to update any cache constructed by AppDelegate.
        if let weather = missing["weatherEnabled"] { Defaults[.weatherEnabled] = weather }
        if let displays = missing["showOnAllDisplays"] { Defaults[.showOnAllDisplays] = displays }
        defaults.set(true, forKey: InitialPresentationDefaults.migrationKey)
    }

    private static func migrateSandboxPreferencesIfNeeded() {
        guard let bundleID = Bundle.main.bundleIdentifier else { return }

        let legacyURL = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Containers")
            .appendingPathComponent(bundleID)
            .appendingPathComponent("Data/Library/Preferences")
            .appendingPathComponent("\(bundleID).plist")

        let defaults = UserDefaults.standard
        let existing = defaults.persistentDomain(forName: bundleID) ?? [:]

        // AppDelegate constructs objects with @Default properties before this
        // App initializer runs, so refresh the typed cache from the real
        // unsandboxed domain even when there is no legacy container left.
        if let currentHUDEnabled = existing["hudReplacement"] as? Bool {
            Defaults[.hudReplacement] = currentHUDEnabled
        }

        guard
            let data = try? Data(contentsOf: legacyURL),
            let legacy = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any]
        else { return }

        var migrated = false

        let hudMigrationKey = "didMigrateUnsandboxedHUDPreference"
        if existing["hudReplacement"] == nil,
           !defaults.bool(forKey: hudMigrationKey),
                  let legacyHUDEnabled = legacy["hudReplacement"] as? Bool {
            // The Defaults package may already have cached the key's default
            // value while AppDelegate and its coordinator are initialized.
            // Write through Defaults so that cache and disk agree immediately.
            Defaults[.hudReplacement] = legacyHUDEnabled
            defaults.set(true, forKey: hudMigrationKey)
            migrated = true
        }

        for (key, value) in legacy where existing[key] == nil {
            defaults.set(value, forKey: key)
            migrated = true
        }

        if migrated {
            defaults.synchronize()
            NSLog("Notchscape: migrated preferences from the previous sandboxed build")
        }
    }

    var body: some Scene {
        MenuBarExtra("Notchscape", systemImage: "sparkle", isInserted: $showMenuBarIcon) {
            Button("Settings") {
                DispatchQueue.main.async {
                    SettingsWindowController.shared.showWindow()
                }
            }
            CheckForUpdatesView(updater: updaterController.updater)
            Button("Commands…") { CommandPaletteController.shared.show() }
            Button("Workspace Tools…") { WorkspaceToolsWindowController.shared.show() }
            Button("Capture Studio…") { CaptureStudioController.shared.show() }
            Button("Windows & Workspaces…") { WindowToolsController.shared.show() }
            RecordingMenuControl()
            Button("Open Tools…") { NotchToolsWindowController.shared.show() }
            WorkspaceModeMenu()
            Divider()
            Button("Restart Notchscape") {
                ApplicationRelauncher.restart()
            }
            Button("Quit", role: .destructive) {
                NSApplication.shared.terminate(self)
            }
            .keyboardShortcut(KeyEquivalent("Q"), modifiers: .command)
        }
        .commands {
            CommandGroup(replacing: .appSettings) {
                Button("Settings…") { SettingsWindowController.shared.showWindow() }
                    .keyboardShortcut(",", modifiers: .command)
            }
            CommandGroup(after: .help) {
                Button("Settings Tour…") { SettingsTourWindowController.shared.show() }
            }
            // App-local menu commands, not a global hotkey that steals Finder's
            // Network shortcut or another app's keystrokes. Available before a
            // lazily-created menu-bar-extra popover has ever opened.
            CommandMenu("Tools") {
                Button("Commands…") { CommandPaletteController.shared.show() }
                    .keyboardShortcut("k", modifiers: [.command, .shift])
                Button("Workspace Tools…") { WorkspaceToolsWindowController.shared.show() }
                Button("Capture Studio…") { CaptureStudioController.shared.show() }
                Button("Windows & Workspaces…") { WindowToolsController.shared.show() }
                RecordingMenuControl()
            }
        }
    }
}

class AppDelegate: NSObject, NSApplicationDelegate {
    var statusItem: NSStatusItem?
    var windows: [String: NSWindow] = [:] // UUID -> NSWindow
    var viewModels: [String: NotchscapeViewModel] = [:] // UUID -> NotchscapeViewModel
    var window: NSWindow?
    let vm: NotchscapeViewModel = .init()
    @ObservedObject var coordinator = NotchscapeCoordinator.shared
    var quickShareService = QuickShareService.shared
    var whatsNewWindow: NSWindow?
    var timer: Timer?
    var closeNotchTask: Task<Void, Never>?
    private var previousScreens: [NSScreen]?
    private var onboardingWindowController: NSWindowController?
    private var screenLockedObserver: Any?
    private var screenUnlockedObserver: Any?
    private var isScreenLocked: Bool = true // Fail closed until launch reads the session.
    private var windowScreenDidChangeObserver: Any?
    private var dragDetectors: [String: DragDetector] = [:] // UUID -> DragDetector
    private var externalDisplayObservation: AnyCancellable?
    private var lockScreenObservation: AnyCancellable?
    private var unlockTransitionTask: Task<Void, Never>?
    private var lockPreviewTask: Task<Void, Never>?
    private var isPreviewingLockedHome = false

    private var notchWindowModels: [(NSWindow, NotchscapeViewModel)] {
        var pairs = windows.compactMap { id, window -> (NSWindow, NotchscapeViewModel)? in
            guard let model = viewModels[id] else { return nil }
            return (window, model)
        }
        if let window { pairs.append((window, vm)) }
        return pairs
    }

    private var eligibleNotchScreens: [NSScreen] {
        NSScreen.screens.filter { Defaults[.showOnExternalDisplays] || $0.isBuiltInDisplay }
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        // Opening the app from Applications must still provide a way back when
        // every connected display is excluded and the Dock/menu icon is hidden.
        SettingsWindowController.shared.showWindow()
        return true
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        return false
    }

    func application(_ application: NSApplication, open urls: [URL]) {
        for url in urls.prefix(8) where url.scheme == "notchscape" { WorkspaceActions.handle(url) }
    }

    private var toolsTerminationInProgress = false
    private var toolsTerminationApproved = false

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        guard !toolsTerminationApproved, LocalToolsManager.shared.needsSave || MediaToolsManager.shared.isBusy else { return .terminateNow }
        guard !toolsTerminationInProgress else { return .terminateCancel }
        toolsTerminationInProgress = true
        // Keep AppKit's normal event loop running while Swift concurrency flushes
        // encrypted storage. A terminateLater modal loop can starve that task.
        Task { @MainActor in
            MediaToolsManager.shared.privacyStop()
            for _ in 0..<50 where MediaToolsManager.shared.finalizing || MediaToolsManager.shared.converting {
                try? await Task.sleep(for: .milliseconds(100))
            }
            await LocalToolsManager.shared.flush()
            var shouldQuit = true
            if LocalToolsManager.shared.needsSave {
                let alert = NSAlert()
                alert.messageText = "Your latest Tools changes couldn’t be saved"
                alert.informativeText = "Keep the app open to retry, or quit without saving the latest changes. Previously saved notes and clipboard items are preserved."
                alert.addButton(withTitle: "Keep Open")
                alert.addButton(withTitle: "Quit Without Saving")
                shouldQuit = alert.runModal() == .alertSecondButtonReturn
            }
            toolsTerminationInProgress = false
            if shouldQuit {
                toolsTerminationApproved = true
                sender.terminate(nil)
            }
        }
        return .terminateCancel
    }

    func applicationWillTerminate(_ notification: Notification) {
        WorkspaceClockManager.shared.stopKeepAwake()
        unlockTransitionTask?.cancel()
        lockPreviewTask?.cancel()
        NotificationCenter.default.removeObserver(self)
        if let observer = screenLockedObserver {
            DistributedNotificationCenter.default().removeObserver(observer)
            screenLockedObserver = nil
        }
        if let observer = screenUnlockedObserver {
            DistributedNotificationCenter.default().removeObserver(observer)
            screenUnlockedObserver = nil
        }
        MusicManager.shared.destroy()
        cleanupDragDetectors()
        cleanupWindows()
        XPCHelperClient.shared.stopMonitoringAccessibilityAuthorization()
    }

    @MainActor
    func onScreenLocked(_ notification: Notification) {
        isScreenLocked = true
        LocalToolsManager.shared.setLocked(true)
        DownloadWatcher.shared.setLocked(true)
        AppleNotesSyncManager.shared.setLocked(true)
        NotchWallpaperManager.shared.setLocked(true)
        NotchToolsWindowController.shared.close()
        WorkspaceToolsWindowController.shared.close()
        CommandPaletteController.shared.close()
        PinnedScratchpadController.shared.close()
        CaptureStudioController.shared.close()
        WindowToolsController.shared.close()
        MediaToolsManager.shared.privacyStop()
        WorkspaceClockManager.shared.stopKeepAwake()
        DeviceControlsManager.shared.stop()
        AudioRoutingManager.shared.stop()
        AgentInsightsManager.shared.clear()
        unlockTransitionTask?.cancel()
        lockPreviewTask?.cancel()
        isPreviewingLockedHome = false
        closeNotchTask?.cancel()
        cleanupDragDetectors()
        // Stop only this app's Mirror camera. No system camera permission changes.
        WebcamManager.shared.stopSession()
        for (_, model) in notchWindowModels { model.isCameraExpanded = false }
        if !Defaults[.showOnLockScreen] {
            cleanupWindows()
            cleanupWindows(shouldInvert: true)
        } else {
            // Hide first, replace the entire private tree, then join the lock
            // space. Never move the normal Home/Shelf window above loginwindow.
            for (window, model) in notchWindowModels {
                window.orderOut(nil)
                installNotchContent(in: window, model: model)
            }
            adjustWindowPosition(changeAlpha: true)
            enableSkyLightOnAllWindows()
        }
    }

    @MainActor
    func onScreenUnlocked(_ notification: Notification) {
        // Ignore a stale/forged unlock notification while the session is locked.
        guard let session = CGSessionCopyCurrentDictionary() as? [String: Any],
              session["CGSSessionScreenIsLocked"] as? Bool != true else { return }
        isScreenLocked = false
        LocalToolsManager.shared.setLocked(false)
        DownloadWatcher.shared.setLocked(false)
        AppleNotesSyncManager.shared.setLocked(false)
        NotchWallpaperManager.shared.setLocked(false)
        DeviceControlsManager.shared.configureNotifications()
        AudioRoutingManager.shared.configure()
        disableSkyLightOnAllWindows()
    }
    
    @MainActor
    private func enableSkyLightOnAllWindows() {
        guard isScreenLocked, Defaults[.showOnLockScreen] else { return }
        for (window, _) in notchWindowModels {
            if let skyWindow = window as? NotchscapeWindow {
                skyWindow.enableSkyLight()
            }
            window.orderFrontRegardless()
        }
    }
    
    @MainActor
    private func disableSkyLightOnAllWindows() {
        // Keep the privacy view through the unlock transition. Cancel a stale
        // restore on a rapid re-lock, before private content can be reattached.
        unlockTransitionTask?.cancel()
        unlockTransitionTask = Task { @MainActor [weak self] in
            do { try await Task.sleep(for: .milliseconds(150)) } catch { return }
            guard let self, !self.isScreenLocked, !Task.isCancelled else { return }
            for (window, model) in self.notchWindowModels {
                window.orderOut(nil)
                (window as? NotchscapeWindow)?.disableSkyLight()
                self.installNotchContent(in: window, model: model)
                // Delegation removed the original Spaces membership. Re-add
                // explicitly so the normal notch returns after unlocking.
                NotchSpaceManager.shared.notchSpace.windows.remove(window)
                NotchSpaceManager.shared.notchSpace.windows.insert(window)
                window.orderFrontRegardless()
            }
            self.adjustWindowPosition(changeAlpha: true)
            self.setupDragDetectors()
        }
    }

    @MainActor
    private func installNotchContent(in window: NSWindow, model: NotchscapeViewModel) {
        switch NotchLockScreenPresentation.resolve(isLocked: isScreenLocked,
            enabled: Defaults[.showOnLockScreen], preview: isPreviewingLockedHome) {
        case .normal:
            window.contentView = NSHostingView(rootView: ContentView().environmentObject(model))
        case .hidden:
            window.contentView = NSHostingView(rootView: Color.clear)
        case .lockedHome:
            let screen = model.screenUUID.flatMap { NSScreen.screen(withUUID: $0) }
            let physical = (screen?.safeAreaInsets.top ?? 0) > 0
            let island = !physical && Defaults[.nonNotchPresentation] == .dynamicIsland
            var size = getClosedNotchSize(screenUUID: model.screenUUID)
            if island, let screen {
                size.height = max(18, min(size.height, screen.frame.maxY - screen.visibleFrame.maxY - 6))
            }
            window.contentView = NSHostingView(rootView: LockedNotchHomeView(
                closedSize: size, hasPhysicalNotch: physical, usesIsland: island,
                endPreview: isPreviewingLockedHome ? { [weak self] in self?.endLockedHomePreview() } : nil))
        }
        window.contentView?.layoutSubtreeIfNeeded()
        window.displayIfNeeded()
    }

    @MainActor
    @objc func previewLockedHome() {
        guard !isScreenLocked else { return }
        lockPreviewTask?.cancel()
        isPreviewingLockedHome = true
        cleanupDragDetectors()
        SettingsWindowController.shared.close()
        for (window, model) in notchWindowModels { installNotchContent(in: window, model: model) }
        lockPreviewTask = Task { @MainActor [weak self] in
            do { try await Task.sleep(for: .seconds(30)) } catch { return }
            self?.endLockedHomePreview()
        }
    }

    @MainActor
    private func endLockedHomePreview() {
        lockPreviewTask?.cancel()
        isPreviewingLockedHome = false
        guard !isScreenLocked else { return } // Ending a preview never unlocks content.
        for (window, model) in notchWindowModels { installNotchContent(in: window, model: model) }
        setupDragDetectors()
        SettingsWindowController.shared.showWindow()
    }

    private func cleanupWindows(shouldInvert: Bool = false) {
        let shouldCleanupMulti = shouldInvert ? !Defaults[.showOnAllDisplays] : Defaults[.showOnAllDisplays]
        
        if shouldCleanupMulti {
            windows.values.forEach { window in
                window.close()
                NotchSpaceManager.shared.notchSpace.windows.remove(window)
            }
            windows.removeAll()
            viewModels.removeAll()
        } else if let window = window {
            window.close()
            NotchSpaceManager.shared.notchSpace.windows.remove(window)
            if let obs = windowScreenDidChangeObserver {
                NotificationCenter.default.removeObserver(obs)
                windowScreenDidChangeObserver = nil
            }
            self.window = nil
        }
    }

    private func cleanupDragDetectors() {
        dragDetectors.values.forEach { detector in
            detector.stopMonitoring()
        }
        dragDetectors.removeAll()
    }

    private func setupDragDetectors() {
        cleanupDragDetectors()

        guard !isScreenLocked, !isPreviewingLockedHome, Defaults[.expandedDragDetection] else { return }

        if Defaults[.showOnAllDisplays] {
            for screen in eligibleNotchScreens {
                setupDragDetectorForScreen(screen)
            }
        } else {
            let preferredScreen: NSScreen? = window?.screen
                ?? NSScreen.screen(withUUID: coordinator.selectedScreenUUID)
                ?? NSScreen.main

            if let screen = preferredScreen {
                setupDragDetectorForScreen(screen)
            }
        }
    }

    private func setupDragDetectorForScreen(_ screen: NSScreen) {
        guard Defaults[.showOnExternalDisplays] || screen.isBuiltInDisplay else { return }
        guard let uuid = screen.displayUUID else { return }
        
        let screenFrame = screen.frame
        let notchHeight = openNotchSize.height
        let notchWidth = openNotchSize.width
        
        // Create notch region at the top-center of the screen where an open notch would occupy
        let notchRegion = CGRect(
            x: screenFrame.midX - notchWidth / 2,
            y: screenFrame.maxY - notchHeight,
            width: notchWidth,
            height: notchHeight
        )
        
        let detector = DragDetector(notchRegion: notchRegion)
        
        detector.onDragEntersNotchRegion = { [weak self] in
            Task { @MainActor in
                self?.handleDragEntersNotchRegion(onScreen: screen)
            }
        }
        
        dragDetectors[uuid] = detector
        detector.startMonitoring()
    }

    private func handleDragEntersNotchRegion(onScreen screen: NSScreen) {
        guard !isScreenLocked, !isPreviewingLockedHome else { return }
        guard let uuid = screen.displayUUID else { return }
        
        if Defaults[.showOnAllDisplays], let viewModel = viewModels[uuid] {
            viewModel.open()
            coordinator.currentView = .shelf
        } else if !Defaults[.showOnAllDisplays], let windowScreen = window?.screen, screen == windowScreen {
            vm.open()
            coordinator.currentView = .shelf
        }
    }

    private func createNotchscapePanel(for screen: NSScreen, with viewModel: NotchscapeViewModel) -> NSWindow {
        let rect = NSRect(x: 0, y: 0, width: windowSize.width, height: windowSize.height)
        let styleMask: NSWindow.StyleMask = [.borderless, .nonactivatingPanel, .utilityWindow, .hudWindow]
        
        let window = NotchscapeWindow(contentRect: rect, styleMask: styleMask, backing: .buffered, defer: false)
        
        installNotchContent(in: window, model: viewModel)
        NotchSpaceManager.shared.notchSpace.windows.insert(window)
        if isScreenLocked && Defaults[.showOnLockScreen] { window.enableSkyLight() }
        window.orderFrontRegardless()

        // Observe when the window's screen changes so we can update drag detectors
        windowScreenDidChangeObserver = NotificationCenter.default.addObserver(
            forName: NSWindow.didChangeScreenNotification,
            object: window,
            queue: .main) { [weak self] _ in
                Task { @MainActor in
                    self?.setupDragDetectors()
                }
        }
        return window
    }

    @MainActor
    private func positionWindow(_ window: NSWindow, on screen: NSScreen, changeAlpha: Bool = false) {
        if changeAlpha {
            window.alphaValue = 0
        }

        let screenFrame = screen.frame
        window.setFrameOrigin(
            NSPoint(
                x: screenFrame.origin.x + (screenFrame.width / 2) - window.frame.width / 2,
                y: screenFrame.origin.y + screenFrame.height - window.frame.height
            ))
        window.alphaValue = 1
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.servicesProvider = NotchscapeFinderServices.shared

        // The existing optional SkyLight integration also needs a safe initial
        // state if the app is restarted while the Mac is already locked.
        if let session = CGSessionCopyCurrentDictionary() as? [String: Any] {
            isScreenLocked = session["CGSSessionScreenIsLocked"] as? Bool == true
        }

        AppPresentationManager.shared.start()
        _ = AppPerformanceManager.shared
        SeasonalThemeManager.shared.start()
        KeyboardShortcuts.onKeyDown(for: .clipboardHistoryPanel) {
            guard Defaults[.clipboardHistoryEnabled] else { return }
            NotchToolsWindowController.shared.show(.clipboard)
        }
        KeyboardShortcuts.onKeyDown(for: .captureNotchText) {
            guard Defaults[.textCaptureEnabled] else { return }
            NotchToolsWindowController.shared.show(.capture)
            LocalToolsManager.shared.captureScreenText()
        }
        LocalToolsManager.shared.start()
        LocalToolsManager.shared.setLocked(isScreenLocked)
        AppleNotesSyncManager.shared.start()
        AppleNotesSyncManager.shared.setLocked(isScreenLocked)
        DeviceControlsManager.shared.start()
        _ = AudioRoutingManager.shared
        NotchWallpaperManager.shared.start(locked: isScreenLocked)

        externalDisplayObservation = Defaults.publisher(.showOnExternalDisplays)
            .dropFirst()
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                self?.adjustWindowPosition(changeAlpha: true)
                self?.setupDragDetectors()
            }

        lockScreenObservation = Defaults.publisher(.showOnLockScreen)
            .dropFirst()
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                guard let self, self.isScreenLocked else { return }
                self.adjustWindowPosition(changeAlpha: true)
                self.enableSkyLightOnAllWindows()
            }

        if let variant = Defaults[.appTheme].whiteHouseVariant {
            Defaults[.whiteHousePreferredVariant] = variant
        }
        if Defaults[.appIconFollowsTheme] {
            Defaults[.appIconVariant] = Defaults[.appTheme].matchingIcon
        }
        Defaults[.appIconVariant].apply()

        // Start the HUD after AppKit has finished launching. Starting it only
        // from `App.init()` can race the application run loop, which leaves a
        // successfully-created event tap without a reliable run-loop owner (or
        // prevents the startup task from running at all on some launches).
        Task { @MainActor in
            let hudEnabled = Defaults[.hudReplacement]
            let accessibilityGranted = await XPCHelperClient.shared.isAccessibilityAuthorized()
            NSLog(
                "Notchscape HUD: launch check enabled=%@ accessibility=%@",
                hudEnabled ? "yes" : "no",
                accessibilityGranted ? "granted" : "denied"
            )

            if hudEnabled {
                XPCHelperClient.shared.startMonitoringAccessibilityAuthorization()
                let started = await MediaKeyInterceptor.shared.start(
                    promptIfNeeded: !accessibilityGranted
                )
                if !started { MediaKeyInterceptor.shared.recoverIfNeeded() }
            }
        }

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(accessibilityAuthorizationDidChange(_:)),
            name: .accessibilityAuthorizationChanged,
            object: nil
        )

        NotificationCenter.default.addObserver(self,
            selector: #selector(recoverHUDIfNeeded(_:)),
            name: NSApplication.didBecomeActiveNotification, object: NSApp)
        NotificationCenter.default.addObserver(self,
            selector: #selector(previewLockedHome),
            name: .previewLockedHomeRequested, object: nil)
        NSWorkspace.shared.notificationCenter.addObserver(self,
            selector: #selector(recoverHUDIfNeeded(_:)),
            name: NSWorkspace.didWakeNotification, object: nil)

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(screenConfigurationDidChange),
            name: NSApplication.didChangeScreenParametersNotification,
            object: nil
        )

        NotificationCenter.default.addObserver(
            forName: Notification.Name.selectedScreenChanged, object: nil, queue: nil
        ) { [weak self] _ in
            Task { @MainActor in
                self?.adjustWindowPosition(changeAlpha: true)
                self?.setupDragDetectors()
            }
        }

        NotificationCenter.default.addObserver(
            forName: Notification.Name.notchHeightChanged, object: nil, queue: nil
        ) { [weak self] _ in
            Task { @MainActor in
                self?.adjustWindowPosition()
                self?.setupDragDetectors()
            }
        }

        NotificationCenter.default.addObserver(
            forName: Notification.Name.automaticallySwitchDisplayChanged, object: nil, queue: nil
        ) { [weak self] _ in
            Task { @MainActor in
                self?.adjustWindowPosition(changeAlpha: true)
                self?.setupDragDetectors()
            }
        }

        NotificationCenter.default.addObserver(
            forName: Notification.Name.showOnAllDisplaysChanged, object: nil, queue: nil
        ) { [weak self] _ in
            Task { @MainActor in
                guard let self = self else { return }
                self.cleanupWindows(shouldInvert: true)
                self.adjustWindowPosition(changeAlpha: true)
                self.setupDragDetectors()
            }
        }

        NotificationCenter.default.addObserver(
            forName: Notification.Name.expandedDragDetectionChanged, object: nil, queue: nil
        ) { [weak self] _ in
            Task { @MainActor in
                self?.setupDragDetectors()
            }
        }

        // Use closure-based observers for DistributedNotificationCenter and keep tokens for removal
        screenLockedObserver = DistributedNotificationCenter.default().addObserver(
            forName: NSNotification.Name(rawValue: "com.apple.screenIsLocked"),
            object: nil, queue: .main) { [weak self] notification in
                Task { @MainActor in
                    self?.onScreenLocked(notification)
                }
        }

        screenUnlockedObserver = DistributedNotificationCenter.default().addObserver(
            forName: NSNotification.Name(rawValue: "com.apple.screenIsUnlocked"),
            object: nil, queue: .main) { [weak self] notification in
                Task { @MainActor in
                    self?.onScreenUnlocked(notification)
                }
        }

        KeyboardShortcuts.onKeyDown(for: .toggleSneakPeek) { [weak self] in
            guard let self = self else { return }
            if Defaults[.sneakPeekStyles] == .inline {
                let newStatus = !self.coordinator.expandingView.show
                self.coordinator.toggleExpandingView(status: newStatus, type: .music)
            } else {
                self.coordinator.toggleSneakPeek(
                    status: !self.coordinator.sneakPeek.show,
                    type: .music,
                    duration: 3.0
                )
            }
        }

        KeyboardShortcuts.onKeyDown(for: .toggleNotchOpen) { [weak self] in
            Task { [weak self] in
                guard let self = self else { return }

                let mouseLocation = NSEvent.mouseLocation

                var viewModel: NotchscapeViewModel? = self.window == nil ? nil : self.vm

                if Defaults[.showOnAllDisplays] {
                    for screen in self.eligibleNotchScreens {
                        if screen.frame.contains(mouseLocation) {
                            if let uuid = screen.displayUUID, let screenViewModel = self.viewModels[uuid] {
                                viewModel = screenViewModel
                                break
                            }
                        }
                    }
                }
                guard let viewModel else { return }

                self.closeNotchTask?.cancel()
                self.closeNotchTask = nil

                switch viewModel.notchState {
                case .closed:
                    await MainActor.run {
                        viewModel.open()
                    }

                    let task = Task { [weak viewModel] in
                        do {
                            try await Task.sleep(for: .seconds(3))
                            await MainActor.run {
                                viewModel?.close()
                            }
                        } catch { }
                    }
                    self.closeNotchTask = task
                case .open:
                    await MainActor.run {
                        viewModel.close()
                    }
                }
            }
        }

        adjustWindowPosition(changeAlpha: true)

        setupDragDetectors()

        if coordinator.firstLaunch {
            DispatchQueue.main.async {
                self.showOnboardingWindow()
            }
            playWelcomeSound()
        }

        // A skipped setup stays skipped. MusicManager provides a fallback for
        // unsupported sources without changing the saved choice; selecting a
        // different source is an explicit action in Media settings.

        previousScreens = NSScreen.screens
    }

    @objc private func recoverHUDIfNeeded(_ notification: Notification) {
        Task { @MainActor in MediaKeyInterceptor.shared.recoverIfNeeded() }
    }

    @objc private func accessibilityAuthorizationDidChange(_ notification: Notification) {
        guard let granted = notification.userInfo?["granted"] as? Bool else { return }

        Task { @MainActor in
            if granted && Defaults[.hudReplacement] {
                _ = await MediaKeyInterceptor.shared.start(promptIfNeeded: false)
            } else if !granted {
                MediaKeyInterceptor.shared.stop()
            }
        }
    }

    func playWelcomeSound() {
        NSSound(named: "Glass")?.play()
    }

    func deviceHasNotch() -> Bool {
        if #available(macOS 12.0, *) {
            for screen in NSScreen.screens {
                if screen.safeAreaInsets.top > 0 {
                    return true
                }
            }
        }
        return false
    }

    @objc func screenConfigurationDidChange() {
        let currentScreens = NSScreen.screens

        let screensChanged =
            currentScreens.count != previousScreens?.count
            || Set(currentScreens.compactMap { $0.displayUUID })
                != Set(previousScreens?.compactMap { $0.displayUUID } ?? [])
            || Set(currentScreens.map { $0.frame }) != Set(previousScreens?.map { $0.frame } ?? [])

        previousScreens = currentScreens

        if screensChanged {
            DispatchQueue.main.async { [weak self] in
                self?.cleanupWindows()
                self?.adjustWindowPosition()
                self?.setupDragDetectors()
            }
        }
    }

    @objc func adjustWindowPosition(changeAlpha: Bool = false) {
        guard !isScreenLocked || Defaults[.showOnLockScreen] else {
            cleanupWindows()
            cleanupWindows(shouldInvert: true)
            cleanupDragDetectors()
            return
        }
        let availableScreens = eligibleNotchScreens
        if Defaults[.showOnAllDisplays] {
            let currentScreenUUIDs = Set(availableScreens.compactMap { $0.displayUUID })

            // Remove windows for screens that no longer exist
            for uuid in Array(windows.keys) where !currentScreenUUIDs.contains(uuid) {
                if let window = windows[uuid] {
                    window.close()
                    NotchSpaceManager.shared.notchSpace.windows.remove(window)
                    windows.removeValue(forKey: uuid)
                    viewModels.removeValue(forKey: uuid)
                }
            }

            // Create or update windows for all screens
            for screen in availableScreens {
                guard let uuid = screen.displayUUID else { continue }
                
                if windows[uuid] == nil {
                    let viewModel = NotchscapeViewModel(screenUUID: uuid)
                    let window = createNotchscapePanel(for: screen, with: viewModel)

                    windows[uuid] = window
                    viewModels[uuid] = viewModel
                }

                if let window = windows[uuid], let viewModel = viewModels[uuid] {
                    positionWindow(window, on: screen, changeAlpha: changeAlpha)

                    if viewModel.notchState == .closed {
                        viewModel.close()
                    }
                }
            }
        } else {
            let destinations = NSScreen.screens.compactMap { screen -> NotchDisplayDestination? in
                guard let id = screen.displayUUID else { return nil }
                return NotchDisplayDestination(id: id, isBuiltIn: screen.isBuiltInDisplay)
            }
            guard let selectedID = NotchDisplayPolicy.selectedID(
                in: destinations, preferred: coordinator.preferredScreenUUID,
                main: NSScreen.main?.displayUUID, automaticallySwitch: Defaults[.automaticallySwitchDisplay],
                showExternal: Defaults[.showOnExternalDisplays]),
                let selectedScreen = availableScreens.first(where: { $0.displayUUID == selectedID }) else {
                cleanupWindows()
                cleanupDragDetectors()
                return
            }

            coordinator.selectedScreenUUID = selectedID

            vm.screenUUID = selectedScreen.displayUUID
            vm.notchSize = getClosedNotchSize(screenUUID: selectedScreen.displayUUID)

            if window == nil {
                window = createNotchscapePanel(for: selectedScreen, with: vm)
            }

            if let window = window {
                positionWindow(window, on: selectedScreen, changeAlpha: changeAlpha)

                if vm.notchState == .closed {
                    vm.close()
                }
            }
        }
    }

    @objc func togglePopover(_ sender: Any?) {
        if window?.isVisible == true {
            window?.orderOut(nil)
        } else {
            window?.orderFrontRegardless()
        }
    }

    @objc func showMenu() {
        statusItem?.menu?.popUp(positioning: nil, at: NSEvent.mouseLocation, in: nil)
    }

    @objc func quitAction() {
        NSApplication.shared.terminate(self)
    }

    private func showOnboardingWindow(step: OnboardingStep = .welcome) {
        if onboardingWindowController == nil {
            let window = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 400, height: 600),
                styleMask: [.titled, .fullSizeContentView],
                backing: .buffered,
                defer: false
            )
            window.center()
            window.title = "Onboarding"
            window.titlebarAppearsTransparent = true
            window.titleVisibility = .hidden
            window.contentView = NSHostingView(
                rootView: OnboardingView(
                    step: step,
                    onFinish: {
                        window.orderOut(nil)
//                        NSApp.setActivationPolicy(.accessory)
                        window.close()
                        NSApp.deactivate()
                    },
                    onOpenSettings: {
                        window.close()
                        SettingsWindowController.shared.showWindow()
                    }
                ))
            window.isRestorable = false
            window.identifier = NSUserInterfaceItemIdentifier("OnboardingWindow")

            onboardingWindowController = NSWindowController(window: window)
        }

//        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
        onboardingWindowController?.window?.makeKeyAndOrderFront(nil)
        onboardingWindowController?.window?.orderFrontRegardless()
    }
}

extension Notification.Name {
    static let previewLockedHomeRequested = Notification.Name("PreviewLockedHomeRequested")
    static let selectedScreenChanged = Notification.Name("SelectedScreenChanged")
    static let notchHeightChanged = Notification.Name("NotchHeightChanged")
    static let showOnAllDisplaysChanged = Notification.Name("showOnAllDisplaysChanged")
    static let automaticallySwitchDisplayChanged = Notification.Name("automaticallySwitchDisplayChanged")
    static let expandedDragDetectionChanged = Notification.Name("expandedDragDetectionChanged")
}

extension CGRect: @retroactive Hashable {
    public func hash(into hasher: inout Hasher) {
        hasher.combine(origin.x)
        hasher.combine(origin.y)
        hasher.combine(size.width)
        hasher.combine(size.height)
    }

    public static func == (lhs: CGRect, rhs: CGRect) -> Bool {
        return lhs.origin == rhs.origin && lhs.size == rhs.size
    }
}
