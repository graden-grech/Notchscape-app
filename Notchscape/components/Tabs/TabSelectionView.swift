//
//  TabSelectionView.swift
//  Notchscape
//
//  Created by Hugo Persson on 2024-08-25.
//

import Defaults
import SwiftUI

struct TabModel: Identifiable {
    var id: String { label }
    let label: String
    let icon: String
    let view: NotchViews
}

let standardTabs = [
    TabModel(label: "Home", icon: "house.fill", view: .home),
    TabModel(label: "Live", icon: "sparkles", view: .live),
    TabModel(label: "Shelf", icon: "tray.fill", view: .shelf)
]

struct TabSelectionView: View {
    @ObservedObject private var performance = AppPerformanceManager.shared
    @ObservedObject var coordinator = NotchscapeCoordinator.shared
    @Default(.systemDashboardEnabled) private var systemDashboardEnabled
    @Default(.showToolsTab) private var showToolsTab
    @Default(.showWallpapersTab) private var showWallpapersTab
    @Default(.appTheme) private var appTheme
    @Default(.useCustomAccentColor) private var useCustomAccentColor
    @Default(.customAccentColorData) private var customAccentColorData
    @Namespace private var selectionAnimation
    @State private var dragX: CGFloat?
    private let trackWidth: CGFloat = 140
    private var cellWidth: CGFloat { (trackWidth - 6) / CGFloat(tabs.count) }
    private var selectedIndex: Int { tabs.firstIndex(where: { $0.view == coordinator.currentView }) ?? 0 }
    private var bubbleX: CGFloat {
        if let dragX { return min(max(4, dragX - (cellWidth - 2) / 2), trackWidth - cellWidth - 2) }
        return 4 + CGFloat(selectedIndex) * cellWidth
    }

    private var allTabs: [TabModel] {
        standardTabs
            + (showToolsTab ? [TabModel(label: "Tools", icon: "square.grid.2x2", view: .tools)] : [])
            + (systemDashboardEnabled ? [TabModel(label: "System", icon: "gauge.with.dots.needle.50percent", view: .system)] : [])
            + (showWallpapersTab ? [TabModel(label: "Wallpapers", icon: "photo.on.rectangle.angled", view: .wallpapers)] : [])
    }
    private var tabs: [TabModel] {
        guard allTabs.count > 5 else { return allTabs }
        let overflow = Array(allTabs.dropFirst(4))
        let selected = overflow.first { $0.view == coordinator.currentView } ?? overflow[0]
        return Array(allTabs.prefix(4)) + [TabModel(label: "More", icon: "ellipsis", view: selected.view)]
    }

    var body: some View {
        ZStack(alignment: .leading) {
            Capsule().fill(Color.white.opacity(performance.reduceTransparency ? 0.13 : 0.065))
            selectionBubble
                .frame(width: cellWidth - 2, height: 26)
                .offset(x: bubbleX)
                .allowsHitTesting(false)
            HStack(spacing: 0) {
                ForEach(tabs) { tab in tabControl(tab) }
            }.padding(.horizontal, 3)
        }
        .frame(width: trackWidth, height: 32)
        .contentShape(Capsule())
        .simultaneousGesture(
            DragGesture(minimumDistance: 2, coordinateSpace: .local)
                .onChanged { value in
                    dragX = value.location.x
                    select(at: value.location.x)
                }
                .onEnded { value in
                    select(at: value.location.x)
                    withAnimation(.spring(response: 0.26, dampingFraction: 0.82)) { dragX = nil }
                }
        )
        .onChange(of: systemDashboardEnabled) { _, enabled in
            if !enabled && coordinator.currentView == .system {
                coordinator.currentView = .home
            }
        }
        .onChange(of: showToolsTab) { _, enabled in
            if !enabled && coordinator.currentView == .tools { coordinator.currentView = .home }
        }
        .onChange(of: showWallpapersTab) { _, enabled in
            if !enabled && coordinator.currentView == .wallpapers { coordinator.currentView = .home }
        }
    }

    @ViewBuilder private var selectionBubble: some View {
        if #available(macOS 26.0, *), !performance.lowImpact, !performance.reduceTransparency {
            GlassEffectContainer {
                Color.clear
                    .glassEffect(.regular.tint(accent.opacity(0.28)).interactive(), in: Capsule())
                    .glassEffectID("selected-notch-tab", in: selectionAnimation)
            }
        } else {
            Capsule().fill(performance.reduceTransparency ? Color(white: 0.3) : accent.opacity(0.32))
        }
    }
    private var accent: Color {
        Color(nsColor: NSColor.resolvedAccent(theme: appTheme, customEnabled: useCustomAccentColor, customData: customAccentColorData))
    }

    @ViewBuilder private func tabControl(_ tab: TabModel) -> some View {
        let selected = coordinator.currentView == tab.view
        Group {
            if tab.label == "More" {
                Menu {
                    ForEach(Array(allTabs.dropFirst(4))) { extra in
                        Button { select(extra) } label: { Label(extra.label, systemImage: extra.icon) }
                    }
                } label: { Image(systemName: selected ? (allTabs.first { $0.view == coordinator.currentView }?.icon ?? tab.icon) : tab.icon).frame(width: cellWidth, height: 26) }
                .menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize()
                .help("More pages").accessibilityLabel("More pages")
            } else {
                TabButton(label: tab.label, icon: tab.icon, selected: selected, onClick: { select(tab) }, width: cellWidth)
                    .buttonStyle(.plain)
            }
        }.font(.system(size: 12, weight: .semibold))
            .foregroundStyle(selected ? .white : Color.white.opacity(0.58))
    }

    private func select(at x: CGFloat) {
        guard let index = NotchTabLayoutPolicy.index(at: Double(x - 3), width: Double(trackWidth - 6), count: tabs.count) else { return }
        guard tabs[index].label != "More" else { return }
        select(tabs[index])
    }

    private func select(_ tab: TabModel) {
        guard coordinator.currentView != tab.view else { return }
        if Defaults[.enableHaptics], !performance.suppressAnimations {
            NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .default)
        }
        withAnimation(.smooth(duration: 0.25)) {
            coordinator.currentView = tab.view
        }
    }
}

#Preview {
    NotchscapeHeader().environmentObject(NotchscapeViewModel())
}
