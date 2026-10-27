//
//  HoverButton.swift
//  Notchscape
//
//  Created by Kraigo on 04.09.2024.
//

import SwiftUI

struct HoverButton: View {
    @ObservedObject private var performance = AppPerformanceManager.shared
    var icon: String
    var iconColor: Color = .primary
    var scale: Image.Scale = .medium
    var action: () -> Void
    
    @State private var isHovering = false

    var body: some View {
        let size = CGFloat(scale == .large ? 40 : 30)

        Group {
            if #available(macOS 26.0, *), !performance.lowImpact, !performance.reduceTransparency {
                button(size: size)
                    .buttonStyle(.plain)
                    .glassEffect(.regular, in: Circle())
            } else {
                button(size: size)
                    .buttonStyle(.plain)
            }
        }
        .onHover { hovering in
            withAnimation(.smooth(duration: 0.3)) {
                isHovering = hovering
            }
        }
        .help(controlLabel)
        .accessibilityLabel(controlLabel)
    }

    private var controlLabel: String {
        switch icon {
        case "shuffle": "Shuffle"
        case "backward.fill": "Previous track"
        case "forward.fill": "Next track"
        case "play.fill": "Play"
        case "pause.fill": "Pause"
        case "repeat": "Repeat"
        case "repeat.1": "Repeat one track"
        case "gobackward.15": "Back 15 seconds"
        case "goforward.15": "Forward 15 seconds"
        default: icon
        }
    }

    private func button(size: CGFloat) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .foregroundColor(iconColor)
                .font(scale == .large ? .largeTitle : .body)
                .frame(width: size, height: size)
                .background(isHovering ? Color.white.opacity(0.08) : .clear, in: Circle())
                .contentShape(Circle())
        }
    }
}
