//
//  HoverButton.swift
//  Notchscape
//
//  Created by Kraigo on 04.09.2024.
//

import SwiftUI

struct HoverButton: View {
    var icon: String
    var iconColor: Color = .primary
    var scale: Image.Scale = .medium
    var accessibilityStatus: String = ""
    var action: () -> Void

    var body: some View {
        let size = CGFloat(scale == .large ? 40 : 30)

        button(size: size)
            .notchGlassButton(circular: true, diameter: size)
            .help(controlLabel)
            .accessibilityLabel(controlLabel)
            .accessibilityValue(accessibilityStatus)
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
        case "heart": "Add to favorites"
        case "heart.fill": "Remove from favorites"
        default: icon
        }
    }

    private func button(size: CGFloat) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .foregroundColor(iconColor)
                .font(scale == .large ? .title2 : .body)
                .frame(width: size == 40 ? 22 : 16, height: size == 40 ? 22 : 16)
                .contentShape(Circle())
        }
    }
}
