//
//  ContentView.swift
//  NotchscapeApp
//
//  Created by Harsh Vardhan Goswami  on 02/08/24
//  Modified by Richard Kunkli on 24/08/2024.
//

import AVFoundation
import Combine
import Defaults
import KeyboardShortcuts
import SwiftUI
import SwiftUIIntrospect

@MainActor
struct ContentView: View {
    private enum ClosedActivityPage: Int, CaseIterable {
        case combined
        case music
        case agent
    }

    @EnvironmentObject var vm: NotchscapeViewModel
    @ObservedObject var webcamManager = WebcamManager.shared

    @ObservedObject var coordinator = NotchscapeCoordinator.shared
    @ObservedObject var musicManager = MusicManager.shared
    @ObservedObject var batteryModel = BatteryStatusViewModel.shared
    @ObservedObject var brightnessManager = BrightnessManager.shared
    @ObservedObject var volumeManager = VolumeManager.shared
    @ObservedObject private var agentStatusManager = AgentStatusManager.shared
    @ObservedObject private var calendarManager = CalendarManager.shared
    @ObservedObject private var weatherManager = WeatherManager.shared
    @ObservedObject private var sportsManager = SportsActivityManager.shared
    @ObservedObject private var downloadWatcher = DownloadWatcher.shared
    @ObservedObject private var notchTimer = NotchTimerManager.shared
    @ObservedObject private var privacyMonitor = PrivacyActivityMonitor.shared
    @ObservedObject private var modes = WorkspaceModeManager.shared
    @State private var hoverTask: Task<Void, Never>?
    @State private var isHovering: Bool = false
    @State private var anyDropDebounceTask: Task<Void, Never>?
    @State private var closedActivityPage: ClosedActivityPage = .combined
    @State private var agentDetailExpanded = false

    @State private var gestureProgress: CGFloat = .zero

    @State private var haptics: Bool = false

    @Namespace var albumArtNamespace

    @Default(.useMusicVisualizer) var useMusicVisualizer

    @Default(.showNotHumanFace) var showNotHumanFace

    @Default(.weatherEnabled) private var weatherEnabled
    @Default(.weatherOnLiveTab) private var weatherOnLiveTab
    @Default(.liveActivitiesEnabled) private var liveActivitiesEnabled
    @Default(.musicActivityOverride) private var musicActivityOverride
    @Default(.agentStatusEnabled) private var agentStatusEnabled
    @Default(.liveActivityPriority) private var savedLiveActivityPriority
    private var liveActivityPriority: LiveActivityPriority {
        modes.active?.preferredActivity.flatMap(LiveActivityPriority.init(rawValue:)) ?? savedLiveActivityPriority
    }
    private func modeAllows(_ activity: WorkspaceActivity) -> Bool { modes.active?.allows(activity) ?? true }
    @Default(.activityProfile) private var activityProfile
    @Default(.privacyActivitiesEnabled) private var privacyActivitiesEnabled
    @Default(.weatherAlertsEnabled) private var weatherAlertsEnabled
    @Default(.timerActivitiesEnabled) private var timerActivitiesEnabled
    @Default(.sportsActivitiesEnabled) private var sportsActivitiesEnabled
    @Default(.nonNotchPresentation) private var nonNotchPresentation
    @Default(.appTheme) private var appTheme
    @Default(.starWarsVaderArtwork) private var starWarsVaderArtwork
    @Default(.useCustomAccentColor) private var useCustomAccentColor
    @Default(.customAccentColorData) private var customAccentColorData
    @Default(.hiddenHomeWidgets) private var hiddenHomeWidgets
    @Default(.quickActions) private var quickActions
    @ObservedObject private var performance = AppPerformanceManager.shared

    // Shared interactive spring for movement/resizing to avoid conflicting animations
    private let animationSpring = Animation.interactiveSpring(response: 0.38, dampingFraction: 0.8, blendDuration: 0)

    private let extendedHoverPadding: CGFloat = 30
    private let zeroHeightHoverPadding: CGFloat = 10
    private let closedActivityDetailWidth: CGFloat = 154
    private let closedActivitySpacing: CGFloat = 8

    private var agentActivityTransition: AnyTransition {
        .asymmetric(
            insertion: .scale(scale: 0.82, anchor: .top).combined(with: .opacity),
            removal: .move(edge: .top)
                .combined(with: .scale(scale: 0.55, anchor: .top))
                .combined(with: .opacity)
        )
    }

    private var topCornerRadius: CGFloat {
       ((vm.notchState == .open) && Defaults[.cornerRadiusScaling])
                ? cornerRadiusInsets.opened.top
                : cornerRadiusInsets.closed.top
    }

    private var currentNotchShape: NotchShape {
        NotchShape(
            topCornerRadius: topCornerRadius,
            bottomCornerRadius: ((vm.notchState == .open) && Defaults[.cornerRadiusScaling])
                ? cornerRadiusInsets.opened.bottom
                : cornerRadiusInsets.closed.bottom
        )
    }

    private var sportsUsesPhysicalNotchLayout: Bool {
        let screen = vm.screenUUID.flatMap { NSScreen.screen(withUUID: $0) }
        return (screen?.safeAreaInsets.top ?? 0) > 0
    }

    private var usesFloatingIslandLayout: Bool {
        !sportsUsesPhysicalNotchLayout
            && vm.notchState == .closed
            && !vm.hideOnClosed
    }

    private var usesNotchlessIslandPresentation: Bool {
        !sportsUsesPhysicalNotchLayout && nonNotchPresentation == .dynamicIsland
    }

    private var sportsUsesInlineLayout: Bool {
        sportsUsesPhysicalNotchLayout || nonNotchPresentation == .notch
    }

    private var floatingIslandTopInset: CGFloat { 3 }

    private var floatingIslandHeight: CGFloat {
        let screen = vm.screenUUID.flatMap { NSScreen.screen(withUUID: $0) }
        let menuBarHeight = screen.map { $0.frame.maxY - $0.visibleFrame.maxY }
            ?? vm.closedNotchSize.height
        return max(18, min(vm.closedNotchSize.height, menuBarHeight - 6))
    }

    private var sportsDropOffset: CGFloat {
        if sportsUsesPhysicalNotchLayout {
            // Clear the camera housing while visually joining its lower edge.
            return max(0, vm.effectiveClosedNotchHeight - 2)
        }

        // Keep the floating island fully inside the macOS menu bar.
        return floatingIslandTopInset
    }

    private var sportsActivityHeight: CGFloat {
        sportsUsesPhysicalNotchLayout ? 42 : floatingIslandHeight
    }

    private var sportsActivityCornerRadius: CGFloat {
        sportsUsesPhysicalNotchLayout ? 15 : floatingIslandHeight / 2
    }

    private var sportsActivityLogoSize: CGFloat {
        sportsUsesPhysicalNotchLayout ? 25 : 18
    }

    private var sportsActivityScoreSize: CGFloat {
        sportsUsesPhysicalNotchLayout ? 15 : 12
    }

    private var sportsUsesFloatingIsland: Bool {
        usesNotchlessIslandPresentation
            && vm.notchState == .closed
            && !vm.hideOnClosed
            && (activeSportsGame != nil || activeSportsBanner != nil)
    }

    private var activeAgentActivity: AgentActivity? {
        guard modeAllows(.agent), liveActivitiesEnabled, agentStatusEnabled, activityProfile != .entertainment else { return nil }
        return agentStatusManager.activities.first
    }

    private var upcomingCalendarActivity: EventModel? {
        guard modeAllows(.calendar), liveActivitiesEnabled,
              activityProfile == .everything || activityProfile == .focus else { return nil }
        return calendarManager.upcomingAlertEvent ?? calendarManager.upcomingReminderEvent
    }

    private var activeDownload: DownloadFile? {
        guard modeAllows(.download), liveActivitiesEnabled,
              activityProfile == .everything || activityProfile == .entertainment else { return nil }
        return downloadWatcher.downloadFiles.first
    }

    private var activeWeatherAlert: WeatherSnapshot? {
        guard modeAllows(.weather), liveActivitiesEnabled,
              activityProfile == .everything,
              weatherAlertsEnabled,
              let weather = weatherManager.weather,
              weather.isAlertWorthy else { return nil }
        return weather
    }

    private var activeSportsGame: SportsGame? {
        guard modeAllows(.sports), liveActivitiesEnabled,
              sportsActivitiesEnabled,
              activityProfile == .everything || activityProfile == .entertainment else { return nil }
        return sportsManager.currentGame
    }

    private var activeSportsBanner: SportsScoreBanner? {
        guard modeAllows(.sports), liveActivitiesEnabled, sportsActivitiesEnabled,
              activityProfile == .everything || activityProfile == .entertainment else { return nil }
        return sportsManager.scoreBanner
    }

    private var privacyActivityIsVisible: Bool {
        modeAllows(.privacy) && liveActivitiesEnabled
            && privacyActivitiesEnabled
            && activityProfile != .entertainment
            && privacyMonitor.shouldShowActivity
            && (privacyMonitor.microphoneInUse || privacyMonitor.cameraInUse)
    }

    private var timerActivityIsVisible: Bool {
        modeAllows(.timer) && liveActivitiesEnabled
            && timerActivitiesEnabled
            && (activityProfile == .everything || activityProfile == .focus)
            && (notchTimer.endDate != nil || notchTimer.justFinished)
    }

    private var hasMusicActivity: Bool {
        MusicPresentationPolicy.isAllowed(
            musicEnabled: coordinator.musicLiveActivityEnabled,
            overrideEnabled: musicActivityOverride,
            liveActivitiesEnabled: liveActivitiesEnabled,
            profileAllowsMusic: activityProfile == .everything || activityProfile == .entertainment
        )
            && modeAllows(.music)
            && (!coordinator.expandingView.show || coordinator.expandingView.type == .music)
            && (musicManager.isPlaying || !musicManager.isPlayerIdle)
            && !vm.hideOnClosed
    }

    private var computedChinWidth: CGFloat {
        var chinWidth: CGFloat = vm.closedNotchSize.width

        if (upcomingCalendarActivity != nil || timerActivityIsVisible
            || activeDownload != nil || activeWeatherAlert != nil)
            && vm.notchState == .closed && !vm.hideOnClosed {
            // Keep equal-width lanes on both sides so the hardware-notch gap
            // remains centered even when the detail pill is only on the right.
            chinWidth += 2 * (closedActivityDetailWidth + closedActivitySpacing)
        } else if privacyActivityIsVisible && vm.notchState == .closed && !vm.hideOnClosed {
            chinWidth += (2 * max(0, vm.effectiveClosedNotchHeight - 12) + 20)
        } else if activeAgentActivity != nil && vm.notchState == .closed && !vm.hideOnClosed {
            chinWidth += agentDetailExpanded
                ? 2 * (closedActivityDetailWidth + closedActivitySpacing)
                : (2 * max(0, vm.effectiveClosedNotchHeight - 12) + 20)
        } else if coordinator.expandingView.type == .battery && coordinator.expandingView.show
            && vm.notchState == .closed && Defaults[.showPowerStatusNotifications]
        {
            chinWidth = 640
        } else if vm.notchState == .closed && hasMusicActivity
        {
            chinWidth += (2 * max(0, vm.effectiveClosedNotchHeight - 12) + 20)
        } else if !coordinator.expandingView.show && vm.notchState == .closed
            && (!musicManager.isPlaying && musicManager.isPlayerIdle) && Defaults[.showNotHumanFace]
            && !vm.hideOnClosed
        {
            chinWidth += (2 * max(0, vm.effectiveClosedNotchHeight - 12) + 20)
        }

        return chinWidth
    }

    var body: some View {
        // Calculate scale based on gesture progress only
        let gestureScale: CGFloat = {
            guard gestureProgress != 0 else { return 1.0 }
            let scaleFactor = 1.0 + gestureProgress * 0.01
            return max(0.6, scaleFactor)
        }()
        
        ZStack(alignment: .top) {
            VStack(spacing: 0) {
                let mainLayout = NotchLayout()
                    .frame(alignment: .top)
                    .padding(
                        .horizontal,
                        vm.notchState == .open
                        ? Defaults[.cornerRadiusScaling]
                        ? (cornerRadiusInsets.opened.top) : (cornerRadiusInsets.opened.bottom)
                        : cornerRadiusInsets.closed.bottom
                    )
                    .padding([.horizontal, .bottom], vm.notchState == .open ? 12 : 0)
                    .background {
                        ZStack(alignment: .top) {
                            sportsUsesFloatingIsland ? Color.clear : Color.black
                            if appTheme.hasHomeScene {
                                // Keep the photo at its expanded dimensions while
                                // the outer mask contracts. Replacing/remapping the
                                // background on close caused a flash and image jump.
                                HomeThemeScene(theme: appTheme, vaderArtwork: starWarsVaderArtwork,
                                               imageAlignment: .top)
                                    .frame(width: getOpenNotchSize().width, height: getOpenNotchSize().height, alignment: .top)
                                    .clipped()
                                    .overlay {
                                        LinearGradient(stops: [
                                            .init(color: .black.opacity(0.76), location: 0),
                                            .init(color: .black.opacity(0.54), location: 0.78),
                                            .init(color: .black.opacity(0.03), location: 0.86)
                                        ], startPoint: .leading, endPoint: .trailing)
                                    }
                                    .opacity(vm.notchState == .open && coordinator.currentView == .home ? 1 : 0)
                                    .animation(.easeOut(duration: 0.24), value: vm.notchState)
                                    .animation(.easeOut(duration: 0.2), value: coordinator.currentView)
                            }
                        }
                        .allowsHitTesting(false)
                    }
                    .overlay(alignment: .top) {
                        Rectangle()
                            .fill(sportsUsesPhysicalNotchLayout ? Color.black : Color.clear)
                            .frame(height: 1)
                            .padding(.horizontal, topCornerRadius)
                    }
                    .padding(
                        .bottom,
                        vm.effectiveClosedNotchHeight == 0 ? 10 : 0
                    )
                
                mainLayout
                    .frame(
                        width: vm.notchState == .open ? vm.notchSize.width : nil,
                        height: vm.notchState == .open ? vm.notchSize.height : nil,
                        alignment: sportsUsesPhysicalNotchLayout ? .center : .top
                    )
                    // Apply the mask after the final frame. Flexible Home/Live
                    // content can otherwise grow beyond the earlier mask and
                    // expose a rectangular outer edge.
                    .conditionalModifier(usesNotchlessIslandPresentation) { view in
                        view
                            .frame(
                                height: vm.notchState == .closed ? floatingIslandHeight : nil,
                                alignment: .top
                            )
                            .clipShape(
                                RoundedRectangle(
                                    cornerRadius: vm.notchState == .closed
                                        ? floatingIslandHeight / 2
                                        : cornerRadiusInsets.opened.bottom,
                                    style: .continuous
                                )
                            )
                            .offset(y: floatingIslandTopInset)
                    }
                    .conditionalModifier(!usesNotchlessIslandPresentation) { view in
                        view.clipShape(currentNotchShape)
                    }
                    .shadow(
                        color: ((vm.notchState == .open || isHovering) && Defaults[.enableShadow])
                            ? .black.opacity(0.7) : .clear,
                        radius: Defaults[.cornerRadiusScaling] ? 6 : 4
                    )
                    .conditionalModifier(true) { view in
                        let openAnimation = Animation.spring(response: 0.42, dampingFraction: 0.8, blendDuration: 0)
                        let closeAnimation = Animation.spring(response: 0.45, dampingFraction: 1.0, blendDuration: 0)
                        
                        return view
                            .animation(vm.notchState == .open ? openAnimation : closeAnimation, value: vm.notchState)
                            .animation(.smooth, value: gestureProgress)
                    }
                    .contentShape(Rectangle())
                    .accessibilityElement(children: .contain)
                    .accessibilityLabel("Notch menu")
                    .accessibilityAction(named: "Open menu") {
                        doOpen()
                    }
                    .onHover { hovering in
                        handleHover(hovering)
                    }
                    .onTapGesture {
                        doOpen()
                    }
                    .conditionalModifier(Defaults[.enableGestures]) { view in
                        view
                            .panGesture(direction: .down) { translation, phase in
                                handleDownGesture(translation: translation, phase: phase)
                            }
                    }
                    .conditionalModifier(Defaults[.closeGestureEnabled] && Defaults[.enableGestures]) { view in
                        view
                            .panGesture(direction: .up) { translation, phase in
                                handleUpGesture(translation: translation, phase: phase)
                            }
                    }
                    .onReceive(NotificationCenter.default.publisher(for: .sharingDidFinish)) { _ in
                        if vm.notchState == .open && !isHovering && !vm.isBatteryPopoverActive {
                            hoverTask?.cancel()
                            hoverTask = Task {
                                try? await Task.sleep(for: .milliseconds(100))
                                guard !Task.isCancelled else { return }
                                await MainActor.run {
                                    if self.vm.notchState == .open && !self.isHovering && !self.vm.isBatteryPopoverActive && !SharingStateManager.shared.preventNotchClose {
                                        self.vm.close()
                                    }
                                }
                            }
                        }
                    }
                    .onChange(of: vm.notchState) { _, newState in
                        if newState == .closed && isHovering {
                            withAnimation {
                                isHovering = false
                            }
                        }
                    }
                    .onChange(of: vm.isBatteryPopoverActive) {
                        if !vm.isBatteryPopoverActive && !isHovering && vm.notchState == .open && !SharingStateManager.shared.preventNotchClose {
                            hoverTask?.cancel()
                            hoverTask = Task {
                                try? await Task.sleep(for: .milliseconds(100))
                                guard !Task.isCancelled else { return }
                                await MainActor.run {
                                    if !self.vm.isBatteryPopoverActive && !self.isHovering && self.vm.notchState == .open && !SharingStateManager.shared.preventNotchClose {
                                        self.vm.close()
                                    }
                                }
                            }
                        }
                    }
                    .sensoryFeedback(.alignment, trigger: haptics)
                    .contextMenu {
                        WorkspaceModeMenu()
                        Divider()
                        if coordinator.currentView == .home {
                            Button(vm.isEditingHomeLayout ? "Done Editing Home" : "Edit Home…", systemImage: "square.grid.2x2") {
                                Defaults[.homeWidgetOrder] = HomeLayoutPolicy.normalized(Defaults[.homeWidgetOrder],
                                    legacyWeatherPosition: Defaults[.weatherTilePosition].rawValue)
                                withAnimation(.smooth(duration: 0.2)) { vm.isEditingHomeLayout.toggle() }
                            }.disabled(modes.active?.homePriority.isEmpty == false || modes.active?.hidesPrivateContent == true)
                            Button("Home Layout Settings…", systemImage: "slider.horizontal.3") {
                                SettingsWindowController.shared.showWindow(section: "Appearance")
                            }
                            Divider()
                        }
                        Button("Settings") {
                            DispatchQueue.main.async {
                                SettingsWindowController.shared.showWindow()
                            }
                        }
                        .keyboardShortcut(KeyEquivalent(","), modifiers: .command)
                        //                    Button("Edit") { // Doesnt work....
                        //                        let dn = DynamicNotch(content: EditPanelView())
                        //                        dn.toggle()
                        //                    }
                        //                    .keyboardShortcut("E", modifiers: .command)
                    }
                if vm.chinHeight > 0 {
                    Rectangle()
                        .fill(Color.black.opacity(0.01))
                        .frame(width: computedChinWidth, height: vm.chinHeight)
                }
            }
        }
        .padding(.bottom, 8)
        .frame(maxWidth: windowSize.width, maxHeight: windowSize.height, alignment: .top)
        .compositingGroup()
        .scaleEffect(
            x: gestureScale,
            y: gestureScale,
            anchor: .top
        )
        .animation(.smooth, value: gestureProgress)
        .animation(.snappy(duration: 0.48, extraBounce: 0.04), value: activeAgentActivity?.state)
        .animation(.snappy(duration: 0.5, extraBounce: 0.08), value: activeSportsBanner)
        .background(dragDetector)
        .preferredColorScheme(.dark)
        .tint(Color(nsColor: NSColor.resolvedAccent(theme: appTheme, customEnabled: useCustomAccentColor, customData: customAccentColorData)))
        .transaction { if performance.suppressAnimations { $0.animation = nil; $0.disablesAnimations = true } }
        .environmentObject(vm)
        .task {
            if sportsActivitiesEnabled { sportsManager.start() }
        }
        .onChange(of: sportsActivitiesEnabled) { _, _ in
            sportsManager.configurationChanged()
        }
        .onChange(of: weatherOnLiveTab) { _, _ in
            withAnimation(animationSpring) {
                vm.refreshOpenNotchSize()
            }
        }
        .onChange(of: appTheme) { _, _ in
            withAnimation(animationSpring) {
                vm.refreshOpenNotchSize()
            }
        }
        .onChange(of: hiddenHomeWidgets) { _, _ in vm.refreshOpenNotchSize() }
        .onChange(of: modes.session) { _, session in
            hoverTask?.cancel(); hoverTask = nil
            vm.isEditingHomeLayout = false; vm.draggedHomeWidget = nil
            if session?.mode.hidesPrivateContent == true {
                vm.isCameraExpanded = false
            }
        }
        .onChange(of: quickActions) { _, _ in vm.refreshOpenNotchSize() }
        .onChange(of: weatherEnabled) { _, _ in
            withAnimation(animationSpring) {
                vm.refreshOpenNotchSize()
            }
        }
        .onChange(of: vm.anyDropZoneTargeting) { _, isTargeted in
            anyDropDebounceTask?.cancel()

            if isTargeted {
                if vm.notchState == .closed {
                    coordinator.currentView = .shelf
                    doOpen()
                }
                return
            }

            anyDropDebounceTask = Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(500))
                guard !Task.isCancelled else { return }

                if vm.dropEvent {
                    vm.dropEvent = false
                    return
                }

                vm.dropEvent = false
                if !SharingStateManager.shared.preventNotchClose {
                    vm.close()
                }
            }
        }
        .onDisappear {
            // The lock-screen window replaces, rather than overlays, this tree.
            // Cancel pending hover/drop work when private Home content detaches.
            hoverTask?.cancel()
            anyDropDebounceTask?.cancel()
        }
    }

    @ViewBuilder
    func NotchLayout() -> some View {
        VStack(alignment: .leading) {
            VStack(alignment: .leading) {
                if coordinator.helloAnimationRunning {
                    Spacer()
                    HelloAnimation(onFinish: {
                        vm.closeHello()
                    }).frame(
                        width: getClosedNotchSize().width,
                        height: 80
                    )
                    .padding(.top, 40)
                    Spacer()
                } else {
                    if coordinator.expandingView.type == .battery && coordinator.expandingView.show
                        && vm.notchState == .closed && Defaults[.showPowerStatusNotifications]
                    {
                        HStack(spacing: 0) {
                            HStack {
                                Text(batteryModel.statusText)
                                    .font(.subheadline)
                                    .foregroundStyle(.white)
                            }

                            Rectangle()
                                .fill(.black)
                                .frame(width: vm.closedNotchSize.width + 10)

                            HStack {
                                NotchscapeBatteryView(
                                    batteryWidth: 30,
                                    isCharging: batteryModel.isCharging,
                                    isInLowPowerMode: batteryModel.isInLowPowerMode,
                                    isPluggedIn: batteryModel.isPluggedIn,
                                    levelBattery: batteryModel.levelBattery,
                                    isForNotification: true
                                )
                            }
                            .frame(width: 76, alignment: .trailing)
                        }
                        .frame(height: vm.effectiveClosedNotchHeight, alignment: .center)
                      } else if coordinator.sneakPeek.show && Defaults[.inlineHUD] && (coordinator.sneakPeek.type != .music) && (coordinator.sneakPeek.type != .battery) && vm.notchState == .closed {
                          InlineHUD(type: $coordinator.sneakPeek.type, value: $coordinator.sneakPeek.value, icon: $coordinator.sneakPeek.icon, hoverAnimation: $isHovering, gestureProgress: $gestureProgress)
                              .transition(.opacity)
                      } else if let event = upcomingCalendarActivity,
                                vm.notchState == .closed,
                                !vm.hideOnClosed {
                          CalendarLiveActivity(event: event)
                              .transition(.scale(scale: 0.9).combined(with: .opacity))
                      } else if timerActivityIsVisible,
                                vm.notchState == .closed,
                                !vm.hideOnClosed {
                          TimerLiveActivity()
                              .transition(.scale(scale: 0.9).combined(with: .opacity))
                      } else if privacyActivityIsVisible,
                                vm.notchState == .closed,
                                !vm.hideOnClosed {
                          PrivacyLiveActivity()
                              .transition(.scale(scale: 0.9).combined(with: .opacity))
                      } else if let game = activeSportsGame,
                                vm.notchState == .closed,
                                !vm.hideOnClosed {
                          if sportsUsesInlineLayout {
                              SportsInlineNotchActivity(game: game)
                                  .transition(.scale(scale: 0.9).combined(with: .opacity))
                          } else {
                              Color.clear
                                  .frame(width: vm.closedNotchSize.width - 20, height: vm.effectiveClosedNotchHeight)
                          }
                      } else if let activity = activeAgentActivity,
                                vm.notchState == .closed,
                                !vm.hideOnClosed,
                                hasMusicActivity {
                          ConcurrentLiveActivity(activity: activity)
                              .transition(agentActivityTransition)
                      } else if let activity = activeAgentActivity,
                                vm.notchState == .closed,
                                !vm.hideOnClosed {
                          AgentLiveActivity(activity: activity)
                              .transition(agentActivityTransition)
                      } else if let download = activeDownload,
                                vm.notchState == .closed,
                                !vm.hideOnClosed {
                          DownloadLiveActivity(download: download, completedName: nil)
                              .transition(.scale(scale: 0.9).combined(with: .opacity))
                      } else if let completedName = downloadWatcher.recentlyCompletedName,
                                modeAllows(.download),
                                liveActivitiesEnabled,
                                activityProfile != .focus,
                                activityProfile != .minimal,
                                vm.notchState == .closed,
                                !vm.hideOnClosed {
                          DownloadLiveActivity(download: nil, completedName: completedName)
                              .transition(.scale(scale: 0.9).combined(with: .opacity))
                      } else if let weather = activeWeatherAlert,
                                vm.notchState == .closed,
                                !vm.hideOnClosed {
                          WeatherAlertLiveActivity(weather: weather)
                              .transition(.scale(scale: 0.9).combined(with: .opacity))
                      } else if vm.notchState == .closed && hasMusicActivity {
                          MusicLiveActivity()
                              .frame(alignment: .center)
                      } else if !coordinator.expandingView.show && vm.notchState == .closed && (!musicManager.isPlaying && musicManager.isPlayerIdle) && Defaults[.showNotHumanFace] && !vm.hideOnClosed  {
                          NotchscapeFaceAnimation()
                       } else if vm.notchState == .open {
                           NotchscapeHeader()
                               // Glass extends beyond its label's bounds. All
                               // expanded controls need the same safe top inset,
                               // including beside a physical notch. Closed island
                               // and hardware-notch geometry remain untouched.
                               .frame(height: CGFloat(NotchHeaderLayoutPolicy.rowHeight(
                                   closedHeight: Double(vm.effectiveClosedNotchHeight),
                                   hasPhysicalNotch: sportsUsesPhysicalNotchLayout)))
                               .padding(.top, NotchHeaderMetrics.topInset)
                               .opacity(gestureProgress != 0 ? 1.0 - min(abs(gestureProgress) * 0.1, 0.3) : 1.0)
                       } else {
                           Rectangle().fill(.clear).frame(width: vm.closedNotchSize.width - 20, height: vm.effectiveClosedNotchHeight)
                       }

                      if coordinator.sneakPeek.show {
                          if (coordinator.sneakPeek.type != .music) && (coordinator.sneakPeek.type != .battery) && !Defaults[.inlineHUD] && vm.notchState == .closed {
                              SystemEventIndicatorModifier(
                                  eventType: $coordinator.sneakPeek.type,
                                  value: $coordinator.sneakPeek.value,
                                  icon: $coordinator.sneakPeek.icon,
                                  sendEventBack: { newVal in
                                      switch coordinator.sneakPeek.type {
                                      case .volume:
                                          VolumeManager.shared.setAbsolute(Float32(newVal))
                                      case .brightness:
                                          BrightnessManager.shared.setAbsolute(value: Float32(newVal))
                                      default:
                                          break
                                      }
                                  }
                              )
                              .padding(.bottom, 10)
                              .padding(.leading, 4)
                              .padding(.trailing, 8)
                          }
                          // Old sneak peek music
                          else if coordinator.sneakPeek.type == .music && modeAllows(.music) {
                              if vm.notchState == .closed && !vm.hideOnClosed && Defaults[.sneakPeekStyles] == .standard {
                                  HStack(alignment: .center) {
                                      Image(systemName: "music.note")
                                      GeometryReader { geo in
                                          MarqueeText(.constant(musicManager.songTitle + " - " + musicManager.artistName),  textColor: Defaults[.playerColorTinting] ? Color(nsColor: musicManager.avgColor).ensureMinimumBrightness(factor: 0.6) : .gray, minDuration: 1, frameWidth: geo.size.width)
                                      }
                                  }
                                  .foregroundStyle(.gray)
                                  .padding(.bottom, 10)
                              }
                          }
                      }
                  }
              }
              .conditionalModifier((coordinator.sneakPeek.show && (coordinator.sneakPeek.type == .music) && vm.notchState == .closed && !vm.hideOnClosed && Defaults[.sneakPeekStyles] == .standard) || (coordinator.sneakPeek.show && (coordinator.sneakPeek.type != .music) && (vm.notchState == .closed))) { view in
                  view
                      .fixedSize()
              }
              .zIndex(2)
            if vm.notchState == .closed,
               !vm.hideOnClosed,
               usesNotchlessIslandPresentation,
               activeSportsBanner == nil,
               let game = activeSportsGame {
                SportsLiveActivity(game: game)
                    .padding(.top, sportsDropOffset)
                    .transition(.move(edge: .top).combined(with: .opacity))
                    .zIndex(3)
            }
            if vm.notchState == .closed,
               !vm.hideOnClosed,
               usesNotchlessIslandPresentation,
               let banner = activeSportsBanner {
                SportsScorePopdown(banner: banner)
                    .padding(.horizontal, 10)
                    .padding(.bottom, 10)
                    .padding(.top, sportsDropOffset)
                    .transition(
                        .asymmetric(
                            insertion: .move(edge: .top)
                                .combined(with: .scale(scale: 0.82, anchor: .top))
                                .combined(with: .opacity),
                            removal: .move(edge: .top)
                                .combined(with: .scale(scale: 0.94, anchor: .top))
                                .combined(with: .opacity)
                        )
                    )
                    .zIndex(3)
            }
            if vm.notchState == .open {
                VStack {
                    if modes.active?.hidesPrivateContent == true {
                        PresentationModePlaceholder()
                    } else {
                    switch coordinator.currentView {
                    case .home:
                        NotchHomeView(albumArtNamespace: albumArtNamespace)
                    case .live:
                        LiveDashboardView()
                    case .shelf:
                        ShelfView()
                    case .system:
                        SystemDashboardView()
                    case .tools:
                        ProductivityHubView()
                    case .wallpapers:
                        WallpaperBrowserView()
                    }
                    }
                }
                .transition(
                    .move(edge: .top)
                        .combined(with: .opacity)
                        .animation(.smooth(duration: 0.28))
                )
                .zIndex(1)
                .allowsHitTesting(vm.notchState == .open)
                .opacity(gestureProgress != 0 ? 1.0 - min(abs(gestureProgress) * 0.1, 0.3) : 1.0)
            }
        }
        .onDrop(of: [.fileURL, .url, .utf8PlainText, .plainText, .data], delegate: GeneralDropTargetDelegate(isTargeted: $vm.generalDropTargeting))
    }

    @ViewBuilder
    func ConcurrentLiveActivity(activity: AgentActivity) -> some View {
        switch liveActivityPriority {
        case .combined:
            DualActivitySwitcher(activity: activity)
        case .musicOnly:
            MusicLiveActivity()
        case .agentOnly:
            AgentLiveActivity(activity: activity)
        }
    }

    @ViewBuilder
    func DualActivitySwitcher(activity: AgentActivity) -> some View {
        Group {
            switch closedActivityPage {
            case .combined:
                CombinedLiveActivity(activity: activity)
            case .music:
                MusicLiveActivity()
            case .agent:
                AgentLiveActivity(activity: activity)
            }
        }
        .id(closedActivityPage)
        .transition(.asymmetric(
            insertion: .move(edge: .trailing).combined(with: .opacity),
            removal: .move(edge: .leading).combined(with: .opacity)
        ))
        .contentShape(Rectangle())
        .simultaneousGesture(
            DragGesture(minimumDistance: 18)
                .onEnded { value in
                    guard abs(value.translation.width) > abs(value.translation.height),
                          abs(value.translation.width) > 24 else { return }

                    let pages = ClosedActivityPage.allCases
                    guard let currentIndex = pages.firstIndex(of: closedActivityPage) else { return }
                    let delta = value.translation.width < 0 ? 1 : -1
                    let nextIndex = (currentIndex + delta + pages.count) % pages.count
                    withAnimation(.snappy(duration: 0.28)) {
                        closedActivityPage = pages[nextIndex]
                    }
                }
        )
        .accessibilityHint("Swipe left or right to switch between combined, music, and agent activity")
    }

    @ViewBuilder
    func CombinedLiveActivity(activity: AgentActivity) -> some View {
        let side = max(0, vm.effectiveClosedNotchHeight - 12)

        HStack(spacing: 8) {
            Image(nsImage: musicManager.albumArt)
                .resizable()
                .scaledToFill()
                .clipShape(RoundedRectangle(
                    cornerRadius: MusicPlayerImageSizes.cornerRadiusInset.closed,
                    style: .continuous
                ))
                .frame(width: side, height: side)
                .shadow(color: Color(nsColor: musicManager.avgColor).opacity(0.35), radius: 5)
                .accessibilityLabel("Music: \(musicManager.songTitle) by \(musicManager.artistName)")
                .frame(
                    width: agentDetailExpanded ? closedActivityDetailWidth : side,
                    alignment: .trailing
                )

            Rectangle()
                .fill(.black)
                .frame(width: vm.closedNotchSize.width - cornerRadiusInsets.closed.top)

            AgentActivityBadge(activity: activity, providerSymbol: true)
                .frame(
                    width: agentDetailExpanded ? closedActivityDetailWidth : nil,
                    alignment: .leading
                )
        }
        .frame(height: vm.effectiveClosedNotchHeight, alignment: .center)
    }

    @ViewBuilder
    func AgentActivityBadge(activity: AgentActivity, providerSymbol: Bool) -> some View {
        let isClaude = activity.provider.localizedCaseInsensitiveContains("claude")
        let accent: Color = switch activity.state {
        case .completed: .green
        case .usageLimited: .red
        default: AgentProviderStyle.accent(for: activity.provider)
        }
        let side = max(0, vm.effectiveClosedNotchHeight - 12)
        let symbolOverride = activity.state == .working && !providerSymbol
            ? "waveform.path"
            : nil

        Button {
            withAnimation(.snappy(duration: 0.3)) {
                agentDetailExpanded.toggle()
            }
        } label: {
            HStack(spacing: 7) {
                AgentProviderMark(
                    provider: activity.provider,
                    state: activity.state,
                    size: side,
                    symbolOverride: symbolOverride
                )

                if agentDetailExpanded {
                    VStack(alignment: .leading, spacing: 0) {
                        Text(activity.title)
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(.white)
                            .lineLimit(1)
                        Text(activity.detail)
                            .font(.caption2)
                            .foregroundStyle(accent)
                            .lineLimit(1)
                    }
                    .frame(width: 112, alignment: .leading)
                    .transition(.move(edge: .trailing).combined(with: .opacity))
                }
            }
            .padding(.trailing, agentDetailExpanded ? 7 : 0)
            .background(.black.opacity(0.74), in: Capsule())
            .liquidGlassCapsule(tint: accent)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(activity.title), \(activity.provider), \(activity.state.label), \(activity.detail)")
        .accessibilityHint("Click to show or hide agent details")
        .contextMenu {
            Button("Open \(activity.provider)") {
                let bundleID = isClaude ? "com.anthropic.claudefordesktop" : "com.openai.codex"
                if let appURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) {
                    NSWorkspace.shared.open(appURL)
                }
            }
            Divider()
            ForEach(LiveActivityPriority.allCases) { priority in
                Button(priority.title) { Defaults[.liveActivityPriority] = priority }
            }
        }
    }

    @ViewBuilder
    func CalendarLiveActivity(event: EventModel) -> some View {
        let side = max(0, vm.effectiveClosedNotchHeight - 12)
        let destination = event.meetingURL ?? event.calendarAppURL()

        HStack(spacing: 8) {
            ZStack {
                RoundedRectangle(cornerRadius: max(6, side * 0.28), style: .continuous)
                    .fill(LinearGradient(
                        colors: [Color(red: 0.18, green: 0.62, blue: 1.0), .blue],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ))
                Image(systemName: event.type.isReminder ? "checklist" : "calendar")
                    .font(.system(size: max(10, side * 0.45), weight: .semibold))
                    .foregroundStyle(.white)
            }
            .frame(width: side, height: side)
            .shadow(color: .blue.opacity(0.4), radius: 6)
            .frame(width: closedActivityDetailWidth, alignment: .trailing)

            Rectangle()
                .fill(.black)
                .frame(width: vm.closedNotchSize.width - cornerRadiusInsets.closed.top)

            Button {
                if let destination { NSWorkspace.shared.open(destination) }
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: event.type.isReminder ? "bell.fill" : event.meetingURL == nil ? "arrow.up.forward.app.fill" : "video.fill")
                        .foregroundStyle(.blue)
                    VStack(alignment: .leading, spacing: 0) {
                        Text(event.title)
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(.white)
                            .lineLimit(1)
                        Text(event.start, style: .relative)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(.horizontal, 9)
                .frame(width: 154, height: side, alignment: .leading)
                .background(.black.opacity(0.72), in: Capsule())
                .liquidGlassCapsule(tint: .blue)
            }
            .buttonStyle(.plain)
            .disabled(destination == nil)
        }
        .frame(height: vm.effectiveClosedNotchHeight, alignment: .center)
        .accessibilityLabel("Upcoming event \(event.title)")
    }

    @ViewBuilder
    func TimerLiveActivity() -> some View {
        let side = max(0, vm.effectiveClosedNotchHeight - 12)
        let finished = notchTimer.justFinished
        HStack(spacing: 8) {
            ZStack {
                RoundedRectangle(cornerRadius: max(6, side * 0.28), style: .continuous)
                    .fill(finished ? Color.green.gradient : Color.orange.gradient)
                Image(systemName: finished ? "checkmark" : "timer")
                    .font(.system(size: max(10, side * 0.44), weight: .bold))
                    .foregroundStyle(.white)
                    .symbolEffect(.bounce, value: finished)
            }
            .frame(width: side, height: side)
            .frame(width: closedActivityDetailWidth, alignment: .trailing)
            Rectangle().fill(.black).frame(width: vm.closedNotchSize.width - cornerRadiusInsets.closed.top)
            Button { notchTimer.cancel() } label: {
                VStack(alignment: .leading, spacing: 0) {
                    Text(finished ? "Timer finished" : notchTimer.label)
                        .font(.caption2.weight(.semibold)).lineLimit(1)
                    Text(finished ? "Done" : timerText(notchTimer.remainingSeconds))
                        .font(.caption.monospacedDigit()).foregroundStyle(finished ? .green : .orange)
                }
                .padding(.horizontal, 10)
                .frame(width: 154, height: side, alignment: .leading)
                .background(.black.opacity(0.72), in: Capsule())
                .liquidGlassCapsule(tint: finished ? .green : .orange)
            }
            .buttonStyle(.plain)
            .help("Click to cancel")
        }
        .frame(height: vm.effectiveClosedNotchHeight)
    }

    private func timerText(_ seconds: Int) -> String {
        String(format: "%d:%02d", seconds / 60, seconds % 60)
    }

    @ViewBuilder
    func PrivacyLiveActivity() -> some View {
        let side = max(0, vm.effectiveClosedNotchHeight - 12)
        let camera = privacyMonitor.cameraInUse
        let both = camera && privacyMonitor.microphoneInUse
        let color: Color = camera ? .green : .orange
        HStack(spacing: 8) {
            ZStack {
                Circle().fill(color)
                Image(systemName: both ? "video.badge.waveform.fill" : camera ? "video.fill" : "mic.fill")
                    .font(.system(size: max(9, side * 0.4), weight: .bold)).foregroundStyle(.black)
            }
            .frame(width: side, height: side)
            .shadow(color: color.opacity(0.45), radius: 6)
            Rectangle().fill(.black).frame(width: vm.closedNotchSize.width - cornerRadiusInsets.closed.top)
            Circle()
                .fill(color)
                .frame(width: 7, height: 7)
                .shadow(color: color.opacity(0.5), radius: 3)
                .frame(width: side, height: side)
        }
        .frame(height: vm.effectiveClosedNotchHeight)
        .accessibilityLabel(both ? "Camera and microphone active" : camera ? "Camera active" : "Microphone active")
    }

    @ViewBuilder
    func DownloadLiveActivity(download: DownloadFile?, completedName: String?) -> some View {
        let side = max(0, vm.effectiveClosedNotchHeight - 12)
        let finished = completedName != nil
        HStack(spacing: 8) {
            ZStack {
                RoundedRectangle(cornerRadius: max(6, side * 0.28), style: .continuous)
                    .fill(finished ? Color.green.gradient : Color.blue.gradient)
                Image(systemName: finished ? "checkmark" : "arrow.down")
                    .font(.system(size: max(10, side * 0.44), weight: .bold)).foregroundStyle(.white)
                    .symbolEffect(.bounce, value: finished)
            }
            .frame(width: side, height: side)
            .frame(width: closedActivityDetailWidth, alignment: .trailing)
            Rectangle().fill(.black).frame(width: vm.closedNotchSize.width - cornerRadiusInsets.closed.top)
            Button {
                if let download { downloadWatcher.reveal(download) }
            } label: {
                HStack(spacing: 7) {
                    if !finished { ProgressView().controlSize(.mini) }
                    VStack(alignment: .leading, spacing: 0) {
                        Text(finished ? "Download finished" : "Downloading")
                            .font(.caption2.weight(.semibold))
                        Text(completedName ?? download?.name ?? "File")
                            .font(.caption2).foregroundStyle(.secondary).lineLimit(1)
                    }
                }
                .padding(.horizontal, 9)
                .frame(width: 154, height: side, alignment: .leading)
                .background(.black.opacity(0.72), in: Capsule())
                .liquidGlassCapsule(tint: finished ? .green : .blue)
            }
            .buttonStyle(.plain)
        }
        .frame(height: vm.effectiveClosedNotchHeight)
    }

    @ViewBuilder
    func SportsLiveActivity(game: SportsGame) -> some View {
        Button {
            if let url = game.gameURL { NSWorkspace.shared.open(url) }
        } label: {
            HStack(spacing: 5) {
                SportsTeamLane(team: game.away, game: game, leading: false)

                VStack(spacing: 2) {
                    if game.isLive {
                        Circle().fill(.red).frame(width: 5, height: 5)
                    }
                    Text(game.statusText)
                        .font(.system(size: sportsUsesPhysicalNotchLayout ? 8 : 7, weight: .semibold, design: .rounded))
                        .foregroundStyle(game.isLive ? .white : .secondary)
                        .lineLimit(1)
                }
                .frame(maxWidth: 42)

                SportsTeamLane(team: game.home, game: game, leading: true)
            }
            .padding(.horizontal, 7)
            .frame(width: 190, height: sportsActivityHeight)
            .background(.black, in: RoundedRectangle(cornerRadius: sportsActivityCornerRadius, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: sportsActivityCornerRadius, style: .continuous)
                    .strokeBorder(.white.opacity(0.1), lineWidth: 0.75)
            }
            .shadow(color: .black.opacity(0.28), radius: 10, y: 5)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(game.league.title), \(game.away.name) \(game.away.score), \(game.home.name) \(game.home.score), \(game.statusText)")
        .help("Open game details")
    }

    @ViewBuilder
    func SportsInlineNotchActivity(game: SportsGame) -> some View {
        let side = max(18, vm.effectiveClosedNotchHeight - 12)

        HStack(spacing: 8) {
            HStack(spacing: 5) {
                SportsTeamLogo(team: game.away, size: side)
                Text(game.displayScore(for: game.away))
                    .font(.system(size: 13, weight: .bold, design: .rounded).monospacedDigit())
                    .foregroundStyle(.white)
            }
            .frame(width: 72, alignment: .trailing)

            Rectangle()
                .fill(.black)
                .frame(width: vm.closedNotchSize.width - cornerRadiusInsets.closed.top)

            HStack(spacing: 5) {
                Text(game.displayScore(for: game.home))
                    .font(.system(size: 13, weight: .bold, design: .rounded).monospacedDigit())
                    .foregroundStyle(.white)
                SportsTeamLogo(team: game.home, size: side)
            }
            .frame(width: 72, alignment: .leading)
        }
        .frame(height: vm.effectiveClosedNotchHeight, alignment: .center)
        .accessibilityLabel("\(game.away.name) \(game.away.score), \(game.home.name) \(game.home.score)")
    }

    @ViewBuilder
    func SportsTeamLane(team: SportsTeam, game: SportsGame, leading: Bool) -> some View {
        let logo = SportsTeamLogo(team: team, size: sportsActivityLogoSize)
        let score = Text(game.displayScore(for: team))
            .font(.system(size: sportsActivityScoreSize, weight: .bold, design: .rounded).monospacedDigit())
            .foregroundStyle(.white)
            .contentTransition(.numericText())

        HStack(spacing: 6) {
            if !leading { logo }

            if leading { score }
            Text(team.abbreviation)
                .font(.caption2.weight(.bold))
                .foregroundStyle(.white.opacity(0.78))
            if !leading { score }

            if leading { logo }
        }
        .frame(minWidth: 78)
        .frame(height: 34)
    }

    @ViewBuilder
    func SportsTeamLogo(team: SportsTeam, size: CGFloat) -> some View {
        AsyncImage(url: team.logoURL) { phase in
            if case .success(let image) = phase {
                image
                    .resizable()
                    .interpolation(.high)
                    .antialiased(true)
                    .scaledToFit()
            } else {
                ZStack {
                    Circle().fill(.white.opacity(0.12))
                    Text(String(team.abbreviation.prefix(1)))
                        .font(.system(size: max(8, size * 0.42), weight: .bold, design: .rounded))
                        .foregroundStyle(.white)
                }
            }
        }
        .frame(width: size, height: size)
    }

    @ViewBuilder
    func SportsScorePopdown(banner: SportsScoreBanner) -> some View {
        let game = banner.game

        Button {
            if let url = game.gameURL { NSWorkspace.shared.open(url) }
        } label: {
            HStack(spacing: 11) {
                ZStack {
                    SportsTeamLogo(team: game.away, size: 28)
                        .offset(x: -8)
                    SportsTeamLogo(team: game.home, size: 28)
                        .offset(x: 8)
                }
                .frame(width: 46, height: 32)

                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        if game.isLive {
                            Circle()
                                .fill(.red)
                                .frame(width: 6, height: 6)
                                .shadow(color: .red.opacity(0.65), radius: 3)
                        }
                        Text(banner.title)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.white)
                    }

                    Text("\(banner.detail)  •  \(game.statusText)")
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                Spacer(minLength: 8)

                Image(systemName: "chevron.right")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.tertiary)
            }
            .padding(.horizontal, 14)
            .frame(width: 342, height: 62)
            .background(.black, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .strokeBorder(.white.opacity(0.12), lineWidth: 0.75)
            }
            .shadow(color: .black.opacity(0.34), radius: 14, y: 7)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(banner.title), \(banner.detail), \(game.statusText)")
    }

    private func sportsColor(_ hex: String?) -> Color {
        guard let hex else { return .blue }
        let cleaned = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        guard cleaned.count == 6, let value = UInt64(cleaned, radix: 16) else { return .blue }
        return Color(
            red: Double((value >> 16) & 0xFF) / 255,
            green: Double((value >> 8) & 0xFF) / 255,
            blue: Double(value & 0xFF) / 255
        )
    }

    @ViewBuilder
    func WeatherAlertLiveActivity(weather: WeatherSnapshot) -> some View {
        let side = max(0, vm.effectiveClosedNotchHeight - 12)
        HStack(spacing: 8) {
            ZStack {
                RoundedRectangle(cornerRadius: max(6, side * 0.28), style: .continuous)
                    .fill(Color.indigo.gradient)
                Image(systemName: weather.symbol)
                    .symbolRenderingMode(.multicolor)
                    .font(.system(size: max(10, side * 0.46), weight: .semibold))
            }
            .frame(width: side, height: side)
            .frame(width: closedActivityDetailWidth, alignment: .trailing)
            Rectangle().fill(.black).frame(width: vm.closedNotchSize.width - cornerRadiusInsets.closed.top)
            VStack(alignment: .leading, spacing: 0) {
                Text("Weather alert").font(.caption2.weight(.semibold))
                Text("\(weather.condition) • \(weather.temperature, specifier: "%.0f")°")
                    .font(.caption2).foregroundStyle(.indigo).lineLimit(1)
            }
            .padding(.horizontal, 10)
            .frame(width: 154, height: side, alignment: .leading)
            .background(.black.opacity(0.72), in: Capsule())
            .liquidGlassCapsule(tint: .indigo)
        }
        .frame(height: vm.effectiveClosedNotchHeight)
    }

    @ViewBuilder
    func NotchscapeFaceAnimation() -> some View {
        HStack {
            HStack {
                Rectangle()
                    .fill(.clear)
                    .frame(
                        width: max(0, vm.effectiveClosedNotchHeight - 12),
                        height: max(0, vm.effectiveClosedNotchHeight - 12)
                    )
                Rectangle()
                    .fill(.black)
                    .frame(width: vm.closedNotchSize.width - 20)
                MinimalFaceFeatures()
            }
        }.frame(
            height: vm.effectiveClosedNotchHeight,
            alignment: .center
        )
    }

    @ViewBuilder
    func MusicLiveActivity() -> some View {
        HStack {
            Image(nsImage: musicManager.albumArt)
                .resizable()
                .clipped()
                .clipShape(
                    RoundedRectangle(
                        cornerRadius: MusicPlayerImageSizes.cornerRadiusInset.closed)
                )
                .matchedGeometryEffect(id: "albumArt", in: albumArtNamespace)
                .frame(
                    width: max(0, vm.effectiveClosedNotchHeight - 12),
                    height: max(0, vm.effectiveClosedNotchHeight - 12)
                )

            Rectangle()
                .fill(.black)
                .overlay(
                    HStack(alignment: .top) {
                        if coordinator.expandingView.show
                            && coordinator.expandingView.type == .music
                        {
                            MarqueeText(
                                .constant(musicManager.songTitle),
                                textColor: Defaults[.coloredSpectrogram]
                                    ? Color(nsColor: musicManager.avgColor) : Color.gray,
                                minDuration: 0.4,
                                frameWidth: 100
                            )
                            .opacity(
                                (coordinator.expandingView.show
                                    && Defaults[.sneakPeekStyles] == .inline)
                                    ? 1 : 0
                            )
                            Spacer(minLength: vm.closedNotchSize.width)
                            // Song Artist
                            Text(musicManager.artistName)
                                .lineLimit(1)
                                .truncationMode(.tail)
                                .foregroundStyle(
                                    Defaults[.coloredSpectrogram]
                                        ? Color(nsColor: musicManager.avgColor)
                                        : Color.gray
                                )
                                .opacity(
                                    (coordinator.expandingView.show
                                        && coordinator.expandingView.type == .music
                                        && Defaults[.sneakPeekStyles] == .inline)
                                        ? 1 : 0
                                )
                        }
                    }
                )
                .frame(
                    width: (coordinator.expandingView.show
                        && coordinator.expandingView.type == .music
                        && Defaults[.sneakPeekStyles] == .inline)
                        ? 380
                        : vm.closedNotchSize.width
                            + -cornerRadiusInsets.closed.top
                )

            HStack {
                if performance.suppressAnimations {
                    Image(systemName: "waveform").font(.system(size: 13, weight: .medium)).foregroundStyle(.secondary)
                        .frame(width: 50)
                } else if useMusicVisualizer {
                    Rectangle()
                        .fill(
                            Defaults[.coloredSpectrogram]
                                ? Color(nsColor: musicManager.avgColor).gradient
                                : Color.gray.gradient
                        )
                        .frame(width: 50, alignment: .center)
                        .matchedGeometryEffect(id: "spectrum", in: albumArtNamespace)
                        .mask {
                            AudioSpectrumView(isPlaying: $musicManager.isPlaying)
                                .frame(width: 16, height: 12)
                        }
                } else {
                    LottieAnimationContainer()
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
            .frame(
                width: max(
                    0,
                    vm.effectiveClosedNotchHeight - 12
                        + gestureProgress / 2
                ),
                height: max(
                    0,
                    vm.effectiveClosedNotchHeight - 12
                ),
                alignment: .center
            )
        }
        .frame(
            height: vm.effectiveClosedNotchHeight,
            alignment: .center
        )
    }

    @ViewBuilder
    func AgentLiveActivity(activity: AgentActivity) -> some View {
        let side = max(0, vm.effectiveClosedNotchHeight - 12)
        let isTerminal = activity.state == .completed || activity.state == .usageLimited

        HStack(spacing: 8) {
            AgentProviderMark(provider: activity.provider, state: activity.state, size: side)
            .frame(
                width: isTerminal ? side : (agentDetailExpanded ? closedActivityDetailWidth : side),
                alignment: .trailing
            )
            .transition(.scale(scale: 0.65).combined(with: .opacity))

            Rectangle()
                .fill(.black)
                .frame(width: vm.closedNotchSize.width - cornerRadiusInsets.closed.top)

            if isTerminal {
                // Completion and quota alerts intentionally pop on one side only.
                Color.clear.frame(width: side, height: side)
            } else {
                AgentActivityBadge(activity: activity, providerSymbol: false)
                    .frame(
                        width: agentDetailExpanded ? closedActivityDetailWidth : nil,
                        alignment: .leading
                    )
            }
        }
        .frame(height: vm.effectiveClosedNotchHeight, alignment: .center)
        .animation(.snappy(duration: 0.32, extraBounce: 0.12), value: activity.state)
    }

    @ViewBuilder
    var dragDetector: some View {
        if Defaults[.boringShelf] && vm.notchState == .closed {
            Color.clear
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .contentShape(Rectangle())
        .onDrop(of: [.fileURL, .url, .utf8PlainText, .plainText, .data], isTargeted: $vm.dragDetectorTargeting) { providers in
            vm.dropEvent = true
            ShelfStateViewModel.shared.load(providers)
            return true
        }
        } else {
            EmptyView()
        }
    }

    private func doOpen() {
        withAnimation(animationSpring) {
            vm.open()
        }
    }

    // MARK: - Hover Management

    private func handleHover(_ hovering: Bool) {
        if !hovering && vm.isEditingHomeLayout {
            hoverTask?.cancel(); isHovering = false
            return
        }
        if coordinator.firstLaunch { return }
        hoverTask?.cancel()
        
        if hovering {
            withAnimation(animationSpring) {
                isHovering = true
            }
            
            if vm.notchState == .closed && Defaults[.enableHaptics] {
                haptics.toggle()
            }
            
            guard vm.notchState == .closed,
                  !coordinator.sneakPeek.show,
                  WorkspaceModePolicy.hover(base: Defaults[.openNotchOnHover], mode: modes.active) else { return }
            
            hoverTask = Task {
                try? await Task.sleep(for: .seconds(Defaults[.minimumHoverDuration]))
                guard !Task.isCancelled else { return }
                
                await MainActor.run {
                    guard self.vm.notchState == .closed,
                          self.isHovering,
                          !self.coordinator.sneakPeek.show,
                          WorkspaceModePolicy.hover(base: Defaults[.openNotchOnHover], mode: self.modes.active) else { return }
                    
                    self.doOpen()
                }
            }
        } else {
            hoverTask = Task {
                try? await Task.sleep(for: .milliseconds(100))
                guard !Task.isCancelled else { return }
                
                await MainActor.run {
                    withAnimation(animationSpring) {
                        self.isHovering = false
                    }
                    
                    if self.vm.notchState == .open && !self.vm.isBatteryPopoverActive && !SharingStateManager.shared.preventNotchClose {
                        self.vm.close()
                    }
                }
            }
        }
    }

    // MARK: - Gesture Handling

    private func handleDownGesture(translation: CGFloat, phase: NSEvent.Phase) {
        guard vm.notchState == .closed else { return }

        if phase == .ended {
            withAnimation(animationSpring) { gestureProgress = .zero }
            return
        }

        withAnimation(animationSpring) {
            gestureProgress = (translation / Defaults[.gestureSensitivity]) * 20
        }

        if translation > Defaults[.gestureSensitivity] {
            if Defaults[.enableHaptics] {
                haptics.toggle()
            }
            withAnimation(animationSpring) {
                gestureProgress = .zero
            }
            doOpen()
        }
    }

    private func handleUpGesture(translation: CGFloat, phase: NSEvent.Phase) {
        guard vm.notchState == .open && !vm.isHoveringCalendar else { return }

        withAnimation(animationSpring) {
            gestureProgress = (translation / Defaults[.gestureSensitivity]) * -20
        }

        if phase == .ended {
            withAnimation(animationSpring) {
                gestureProgress = .zero
            }
        }

        if translation > Defaults[.gestureSensitivity] {
            withAnimation(animationSpring) {
                isHovering = false
            }
            if !SharingStateManager.shared.preventNotchClose { 
                gestureProgress = .zero
                vm.close()
            }

            if Defaults[.enableHaptics] {
                haptics.toggle()
            }
        }
    }
}

struct FullScreenDropDelegate: DropDelegate {
    @Binding var isTargeted: Bool
    let onDrop: () -> Void

    func dropEntered(info _: DropInfo) {
        isTargeted = true
    }

    func dropExited(info _: DropInfo) {
        isTargeted = false
    }

    func performDrop(info _: DropInfo) -> Bool {
        isTargeted = false
        onDrop()
        return true
    }

}

/// Intentionally has no access to calendars, media metadata, Shelf, account,
/// location or AI managers. Never insert the ordinary menu beneath this view.
struct LockedNotchHomeView: View {
    let closedSize: CGSize
    let hasPhysicalNotch: Bool
    let usesIsland: Bool
    var endPreview: (() -> Void)? = nil
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var expanded = false
    @State private var hoverTask: Task<Void, Never>?

    private var height: CGFloat { max(usesIsland ? 18 : 22, closedSize.height) }
    private var width: CGFloat { closedSize.width }

    var body: some View {
        VStack(spacing: 8) {
            if expanded {
                Spacer(minLength: hasPhysicalNotch ? height + 10 : 18)
                Image(systemName: "lock.fill")
                    .font(.system(size: 24, weight: .medium))
                    .accessibilityLabel("Mac locked. Unlock your Mac to see Home.")
                if let endPreview {
                    Button("End Preview", action: endPreview)
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                }
                Spacer(minLength: 14)
            } else {
                // The closed notch stays plain and at its original width.
                // Only the expanded Home dropdown shows the lock symbol.
                Color.clear.accessibilityHidden(true)
            }
        }
        .foregroundStyle(.white)
        .frame(width: expanded ? max(320, width) : width,
               height: expanded ? (hasPhysicalNotch ? height + 156 : 176) : height)
        .background(.black)
        .conditionalModifier(usesIsland) { view in
            view.clipShape(RoundedRectangle(cornerRadius: expanded ? 28 : height / 2, style: .continuous))
                .offset(y: 3)
        }
        .conditionalModifier(!usesIsland) { view in
            view.clipShape(NotchShape(topCornerRadius: 8, bottomCornerRadius: expanded ? 28 : 16))
        }
        .contentShape(Rectangle())
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Locked Home menu")
        .accessibilityAction(named: "Open menu") { expanded = true }
        .onTapGesture { expanded.toggle() }
        .onHover { hovering in
            hoverTask?.cancel()
            guard hovering else { expanded = false; return }
            guard Defaults[.openNotchOnHover] else { return }
            hoverTask = Task { @MainActor in
                do { try await Task.sleep(for: .seconds(Defaults[.minimumHoverDuration])) }
                catch { return }
                expanded = true
            }
        }
        .animation(reduceMotion ? nil : .spring(response: 0.38, dampingFraction: 0.88), value: expanded)
        .frame(maxWidth: windowSize.width, maxHeight: windowSize.height, alignment: .top)
        .preferredColorScheme(.dark)
        .onDisappear { hoverTask?.cancel() }
    }
}

struct GeneralDropTargetDelegate: DropDelegate {
    @Binding var isTargeted: Bool

    func dropEntered(info: DropInfo) {
        isTargeted = true
    }

    func dropExited(info: DropInfo) {
        isTargeted = false
    }

    func dropUpdated(info: DropInfo) -> DropProposal? {
        return DropProposal(operation: .cancel)
    }

    func performDrop(info: DropInfo) -> Bool {
        return false
    }
}

#Preview {
    let vm = NotchscapeViewModel()
    vm.open()
    return ContentView()
        .environmentObject(vm)
        .frame(width: vm.notchSize.width, height: vm.notchSize.height)
}
