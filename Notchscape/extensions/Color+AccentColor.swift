//
//  Color+AccentColor.swift
//  Notchscape
//
//  Created by Alexander on 2025-10-24.
//

import SwiftUI
import Defaults

enum LightsaberColors {
    static func resolve(mode: LightsaberColorMode, theme: AppTheme, album: NSColor, customData: Data?) -> Color {
        let themeColor = theme.starWarsVariant?.accentColor ?? StarWarsThemeVariant.jedi.accentColor
        switch mode {
        case .theme: return Color(nsColor: themeColor)
        case .albumArtwork: return Color(nsColor: album).ensureMinimumBrightness(factor: 0.7)
        case .custom:
            guard let data = customData, data.count < 16_384,
                  let saved = try? NSKeyedUnarchiver.unarchivedObject(ofClass: NSColor.self, from: data)
            else { return Color(nsColor: themeColor) }
            return Color(nsColor: saved.withAlphaComponent(1))
        }
    }
}

extension Color {
    static var effectiveAccent: Color {
        Color(nsColor: .effectiveAccent)
    }

    static var effectiveAccentForeground: Color {
        Color(nsColor: .effectiveAccentForeground)
    }
    
    /// Returns a darker version of the accent color suitable for backgrounds
    static var effectiveAccentBackground: Color {
        effectiveAccent.opacity(0.25)
    }
}

extension NSColor {
    static var effectiveAccent: NSColor {
        resolvedAccent(theme: Defaults[.appTheme], customEnabled: Defaults[.useCustomAccentColor], customData: Defaults[.customAccentColorData])
    }

    /// Choose readable text for a solid accent fill, including manual colors.
    /// Keep resolution dynamic so light/dark appearance changes stay in sync.
    static var effectiveAccentForeground: NSColor {
        let accent = effectiveAccent
        return NSColor(name: nil) { appearance in
            var foreground = NSColor.white
            appearance.performAsCurrentDrawingAppearance {
                guard let rgb = accent.usingColorSpace(.sRGB) else { return }
                let channels = [rgb.redComponent, rgb.greenComponent, rgb.blueComponent]
                guard channels.allSatisfy(\.isFinite) else { return }
                let linear = channels.map { component -> CGFloat in
                    let value = min(1, max(0, component))
                    return value <= 0.04045 ? value / 12.92 : pow((value + 0.055) / 1.055, 2.4)
                }
                let luminance = 0.2126 * linear[0] + 0.7152 * linear[1] + 0.0722 * linear[2]
                // The crossover chooses the greater black/white contrast ratio.
                foreground = luminance <= 0.1791287847 ? .white : .black
            }
            return foreground
        }
    }

    /// Manual choices override every theme. Invalid/missing saved colors
    /// safely fall back to the theme, then the macOS system accent.
    static func resolvedAccent(theme: AppTheme, customEnabled: Bool, customData: Data?) -> NSColor {
        if customEnabled,
           let colorData = customData,
           let nsColor = try? NSKeyedUnarchiver.unarchivedObject(ofClass: NSColor.self, from: colorData) {
            return nsColor.withAlphaComponent(1)
        }
        return theme.accentColor ?? NSColor.controlAccentColor
    }
    
    /// Returns a darker version of the accent color as NSColor suitable for backgrounds
    static var effectiveAccentBackground: NSColor {
        effectiveAccent.withAlphaComponent(0.25)
    }
}
