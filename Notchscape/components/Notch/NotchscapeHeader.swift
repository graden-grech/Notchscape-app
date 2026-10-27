//
//  NotchscapeHeader.swift
//  Notchscape
//
//  Created by Harsh Vardhan  Goswami  on 04/08/24.
//

import Defaults
import SwiftUI

struct NotchscapeHeader: View {
    @EnvironmentObject var vm: NotchscapeViewModel
    @ObservedObject var batteryModel = BatteryStatusViewModel.shared
    @ObservedObject var coordinator = NotchscapeCoordinator.shared
    @ObservedObject private var modes = WorkspaceModeManager.shared
    @StateObject var tvm = ShelfStateViewModel.shared
    @Default(.appTheme) private var appTheme
    @Default(.hideBatteryWhenAbsent) private var hideBatteryWhenAbsent
    @Default(.showBatteryIndicator) private var showBatteryIndicator
    var body: some View {
        HStack(spacing: 0) {
            HStack {
                if (!tvm.isEmpty || coordinator.alwaysShowTabs) && Defaults[.boringShelf] {
                    TabSelectionView()
                } else if vm.notchState == .open {
                    EmptyView()
                }
                if coordinator.currentView == .home,
                   !appTheme.hasHomeScene,
                   let decoration = appTheme.homeDecoration,
                   (vm.screenUUID.flatMap { NSScreen.screen(withUUID: $0) }?.safeAreaInsets.top ?? 0) > 0 {
                    Text(decoration)
                        .font(.system(size: 20))
                        .accessibilityHidden(true)
                        .allowsHitTesting(false)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .opacity(vm.notchState == .closed ? 0 : 1)
            .blur(radius: vm.notchState == .closed ? 20 : 0)
            .zIndex(2)

            if vm.notchState == .open {
                Rectangle()
                    .fill(NSScreen.screen(withUUID: coordinator.selectedScreenUUID)?.safeAreaInsets.top ?? 0 > 0 ? .black : .clear)
                    .frame(width: vm.closedNotchSize.width)
                    .mask {
                        NotchShape()
                    }
                    .overlay {
                        if coordinator.currentView == .home,
                           !appTheme.hasHomeScene,
                           let decoration = appTheme.homeDecoration,
                           (vm.screenUUID.flatMap { NSScreen.screen(withUUID: $0) }?.safeAreaInsets.top ?? 0) == 0 {
                            Text(decoration)
                                .font(.system(size: 23))
                                .accessibilityHidden(true)
                                .allowsHitTesting(false)
                        }
                    }
            }

            HStack(spacing: 4) {
                if vm.notchState == .open {
                    if vm.isEditingHomeLayout && coordinator.currentView == .home {
                        Button("Done") {
                            withAnimation(.smooth(duration: 0.2)) { vm.isEditingHomeLayout = false; vm.draggedHomeWidget = nil }
                        }
                        .buttonStyle(.plain).font(.caption.weight(.semibold))
                        .padding(.horizontal, 14).frame(height: NotchHeaderMetrics.controlHeight)
                        .liquidGlassCapsule(tint: .accentColor)
                        .accessibilityLabel("Done editing Home")
                    } else if isHUDType(coordinator.sneakPeek.type) && coordinator.sneakPeek.show && Defaults[.showOpenNotchHUD] {
                        OpenNotchHUD(type: $coordinator.sneakPeek.type, value: $coordinator.sneakPeek.value, icon: $coordinator.sneakPeek.icon)
                            .transition(.scale(scale: 0.8).combined(with: .opacity))
                    } else {
                        if Defaults[.showMirror] {
                            Button(action: {
                                vm.toggleCameraPreview()
                            }) {
                                Image(systemName: "web.camera")
                                    .foregroundStyle(.white)
                                    .frame(width: NotchHeaderMetrics.controlHeight, height: NotchHeaderMetrics.controlHeight)
                                    .liquidGlassCapsule()
                            }
                            .buttonStyle(PlainButtonStyle())
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
                                    .foregroundStyle(.white)
                                    .frame(width: NotchHeaderMetrics.controlHeight, height: NotchHeaderMetrics.controlHeight)
                                    .liquidGlassCapsule()
                            }
                            .buttonStyle(PlainButtonStyle())
                            .help("Settings")
                            .accessibilityLabel("Settings")
                            .contextMenu { WorkspaceModeMenu() }
                            .overlay(alignment: .topTrailing) {
                                if modes.active != nil { Circle().fill(Color.accentColor).frame(width: 5, height: 5).allowsHitTesting(false).accessibilityHidden(true) }
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
            .font(.system(.headline, design: .rounded))
            .frame(maxWidth: .infinity, alignment: .trailing)
            .opacity(vm.notchState == .closed ? 0 : 1)
            .blur(radius: vm.notchState == .closed ? 20 : 0)
            .zIndex(2)
        }
        .foregroundColor(.gray)
        .environmentObject(vm)
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
