import Foundation

/// Rendering choices only. No preference changes, timers or provider demand.
struct GlassPresentationPolicy: Equatable, Sendable {
    var supportsNativeGlass: Bool
    var reduceTransparency: Bool
    var increasedContrast: Bool
    var lowImpact: Bool
    var reduceMotion: Bool

    var usesOpaqueSurfaces: Bool { reduceTransparency || increasedContrast || lowImpact }
    var usesNativeGlass: Bool { supportsNativeGlass && !usesOpaqueSurfaces }
    var allowsDecorativeMotion: Bool { !reduceMotion && !lowImpact && !reduceTransparency }

    static func controlDiameter(_ requested: Double) -> Double {
        requested.isFinite ? min(44, max(24, requested)) : 30
    }

    /// Keep related controls distinct at rest; the containing row owns its gaps.
    static func groupingSpacing(_ requested: Double) -> Double {
        requested.isFinite ? min(4, max(0, requested)) : 4
    }
}
