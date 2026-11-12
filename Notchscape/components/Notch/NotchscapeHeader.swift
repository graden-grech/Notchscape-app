//
//  NotchscapeHeader.swift
//  Notchscape
//
//  Created by Harsh Vardhan  Goswami  on 04/08/24.
//

import Defaults
import SwiftUI

@MainActor
struct NotchscapeHeader: View {
    @EnvironmentObject var vm: NotchscapeViewModel
    @ObservedObject var batteryModel = BatteryStatusViewModel.shared
    @ObservedObject var coordinator = NotchscapeCoordinator.shared
    @ObservedObject private var modes = WorkspaceModeManager.shared
    @ObservedObject private var performance = AppPerformanceManager.shared
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.colorSchemeContrast) private var contrast
    @StateObject var tvm = ShelfStateViewModel.shared
    @Default(.appTheme) private var appTheme
    @Default(.useCustomAccentColor) private var useCustomAccentColor
    @Default(.customAccentColorData) private var customAccentColorData
    @Default(.hideBatteryWhenAbsent) private var hideBatteryWhenAbsent
    @Default(.showBatteryIndicator) private var showBatteryIndicator
    @Default(.desktopSnowEnabled) private var desktopSnowEnabled

    private var accent: Color {
        Color(nsColor: NSColor.resolvedAccent(theme: appTheme, customEnabled: useCustomAccentColor, customData: customAccentColorData))
    }
    private var rendering: GlassPresentationPolicy {
        let native: Bool
        if #available(macOS 26.0, *) { native = true } else { native = false }
        return .init(supportsNativeGlass: native,
                     reduceTransparency: performance.reduceTransparency || reduceTransparency,
                     increasedContrast: contrast == .increased, lowImpact: performance.lowImpact,
                     reduceMotion: performance.reduceMotion || reduceMotion)
    }

    private var screen: NSScreen? {
        if let uuid = vm.screenUUID { return NSScreen.screen(withUUID: uuid) }
        return NSScreen.main
    }

    private var displayGeometry: DisplayGeometrySnapshot? {
        guard let screen else { return nil }
        return NSScreenDisplayGeometryAdapter.snapshot(for: screen)
    }

    private var physicalNotch: PhysicalNotchGeometry? {
        guard let gap = displayGeometry?.reportedTopGap else { return nil }
        return PhysicalNotchGeometry(width: gap.width, height: gap.height, centerOffset: gap.centerOffset)
    }

    private var headerRowHeight: CGFloat {
        CGFloat(NotchHeaderLayoutPolicy.rowHeight(
            closedHeight: Double(vm.effectiveClosedNotchHeight),
            hasPhysicalNotch: displayGeometry?.usesLegacyNotchLayout == true))
    }

    var body: some View {
        HStack(spacing: 0) {
            HStack {
                if (!tvm.isEmpty || coordinator.alwaysShowTabs) && Defaults[.boringShelf] {
                    TabSelectionView()
                } else if vm.notchState == .open {
                    EmptyView()
                }
                if desktopSnowEnabled, vm.notchState == .open,
                   (vm.notchSize.width - vm.closedNotchSize.width) / 2 - 24 >= 180 {
                    Button { desktopSnowEnabled = false } label: {
                        Image(systemName: "snowflake")
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(.white).frame(width: 14, height: 14)
                    }
                    .controlSize(.small).notchGlassButton(circular: true)
                    .help("Stop snow").accessibilityLabel("Stop snow")
                }
                if coordinator.currentView == .home,
                   !appTheme.hasHomeScene,
                   let decoration = appTheme.homeDecoration,
                   displayGeometry?.usesLegacyNotchLayout == true {
                    Text(decoration)
                        .font(.system(size: 20))
                        .accessibilityHidden(true)
                        .allowsHitTesting(false)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .opacity(vm.notchState == .closed ? 0 : 1)
            // The outer notch mask owns reveal; do not alpha-tween live glass.
            .animation(nil, value: vm.notchState)
            .zIndex(2)

            if vm.notchState == .open {
                Rectangle()
                    .fill(physicalNotch == nil ? Color.clear : Color.black)
                    .frame(width: CGFloat(physicalNotch?.width ?? Double(vm.closedNotchSize.width)),
                           height: CGFloat(physicalNotch?.height ?? Double(headerRowHeight)))
                    .mask {
                        NotchShape()
                    }
                    // Only the controls move down. The physical housing is
                    // measured independently and remains flush with the screen.
                    .offset(x: CGFloat(physicalNotch?.centerOffset ?? 0),
                            y: CGFloat(physicalNotch?.expandedHeaderTopOffset ?? 0))
                    .frame(width: vm.closedNotchSize.width, height: headerRowHeight, alignment: .top)
                    .overlay {
                        if coordinator.currentView == .home,
                           !appTheme.hasHomeScene,
                           let decoration = appTheme.homeDecoration,
                           displayGeometry?.usesLegacyNotchLayout != true {
                            Text(decoration)
                                .font(.system(size: 23))
                                .accessibilityHidden(true)
                                .allowsHitTesting(false)
                        }
                    }
            }

            NotchGlassControlGroup(spacing: 4) {
              HStack(spacing: 4) {
                if vm.notchState == .open {
                    if vm.isEditingHomeLayout && coordinator.currentView == .home {
                        Button {
                            vm.isEditingHomeLayout = false; vm.draggedHomeWidget = nil
                        } label: { Text("Done").foregroundStyle(Color.white) }
                        .font(.caption.weight(.semibold))
                        .controlSize(.small)
                        .notchGlassButton()
                        .buttonBorderShape(.capsule)
                        .frame(height: NotchHeaderMetrics.controlHeight)
                        .accessibilityLabel("Done editing Home")
                    } else if isHUDType(coordinator.sneakPeek.type) && coordinator.sneakPeek.show && Defaults[.showOpenNotchHUD] {
                        OpenNotchHUD(type: $coordinator.sneakPeek.type, value: $coordinator.sneakPeek.value, icon: $coordinator.sneakPeek.icon)
                            .transition(rendering.allowsDecorativeMotion ? .scale(scale: 0.8).combined(with: .opacity) : .identity)
                    } else {
                        if Defaults[.showMirror] {
                            Button(action: {
                                vm.toggleCameraPreview()
                            }) {
                                Image(systemName: "web.camera")
                                    .foregroundStyle(Color.white)
                                    .font(.system(size: 16, weight: .medium))
                                    .frame(width: NotchHeaderMetrics.controlHeight, height: NotchHeaderMetrics.controlHeight)
                                    .contentShape(Circle())
                                    .liquidGlassCapsule()
                            }
                            .buttonStyle(.plain)
                            .help("Mirror")
                            .accessibilityLabel("Mirror")
                            .disabled(modes.active?.hidesPrivateContent == true)
                        }
                        if Defaults[.settingsIconInNotch] {
                            Button(action: {
                                DispatchQueue.main.async {
                                    SettingsWindowController.shared.showWindow()
                                }
                                
                            }) {
                                Image(systemName: "gear")
                                    .foregroundStyle(Color.white)
                                    .font(.system(size: 16, weight: .medium))
                                    .frame(width: NotchHeaderMetrics.controlHeight, height: NotchHeaderMetrics.controlHeight)
                                    .contentShape(Circle())
                                    .liquidGlassCapsule()
                            }
                            .buttonStyle(.plain)
                            .help("Settings")
                            .accessibilityLabel("Settings")
                            .contextMenu { WorkspaceModeMenu() }
                            .overlay(alignment: .topTrailing) {
                                if modes.active != nil { Circle().fill(accent).frame(width: 5, height: 5).allowsHitTesting(false).accessibilityHidden(true) }
                            }
                        }
                        if BatteryPolicy.shouldShow(enabled: showBatteryIndicator,
                            hasBattery: batteryModel.hasBattery, hideWhenAbsent: hideBatteryWhenAbsent) {
                            NotchscapeBatteryView(
                                batteryWidth: 30,
                                isCharging: batteryModel.isCharging,
                                isInLowPowerMode: batteryModel.isInLowPowerMode,
                                isPluggedIn: batteryModel.isPluggedIn,
                                levelBattery: batteryModel.levelBattery,
                                maxCapacity: batteryModel.maxCapacity,
                                timeToFullCharge: batteryModel.timeToFullCharge,
                                isForNotification: false
                            )
                        }
                    }
                }
              }
            }
            .font(.system(.headline, design: .rounded))
            .frame(maxWidth: .infinity, alignment: .trailing)
            .opacity(vm.notchState == .closed ? 0 : 1)
            .animation(nil, value: vm.notchState)
            .zIndex(2)
        }
        .foregroundColor(.gray)
        .tint(accent)
        .accentColor(accent)
        .environmentObject(vm)
        .transaction {
            if !rendering.allowsDecorativeMotion { $0.animation = nil; $0.disablesAnimations = true }
        }
    }

    func isHUDType(_ type: SneakContentType) -> Bool {
        switch type {
        case .volume, .brightness, .backlight, .mic:
            return true
        default:
            return false
        }
    }
}

#Preview {
    NotchscapeHeader().environmentObject(NotchscapeViewModel())
}
