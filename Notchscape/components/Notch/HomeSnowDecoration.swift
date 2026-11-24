import Defaults
import SwiftUI

extension Defaults.Keys {
    static let desktopSnowHomeWidgets = Key<Bool>("desktopSnowHomeWidgets", default: true)
}

/// A static cap within the tile's existing bounds. The desktop renderer owns
/// animation and session eligibility; this decoration never starts a sampler.
struct HomeSnowDecoration: View {
    let tileID: String
    @ObservedObject private var snow = DesktopSnowManager.shared
    @Default(.desktopSnowSeason) private var seasonID
    @Default(.desktopSnowEnabled) private var enabled
    @Default(.desktopSnowHomeWidgets) private var homeWidgets
    @Default(.desktopSnowMoundHeight) private var moundHeight
    @Default(.desktopSnowMoundWidth) private var moundWidth
    @Default(.desktopSnowMoundSpacing) private var moundSpacing
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.colorSchemeContrast) private var contrast
    private var season: DesktopSnowSeason { DesktopSnowSeason(rawValue: seasonID) ?? .winterDawn }

    var body: some View {
        Group {
            if enabled && homeWidgets && snow.isRunning && season.isSnow {
                HomeSnowCapShape(tileID: tileID, height: moundHeight, width: moundWidth, spacing: moundSpacing)
                    .fill(Color(nsColor: season.bankTint).opacity(reduceTransparency ? 1 : 0.94))
                    .overlay {
                        if contrast == .increased {
                            HomeSnowCapShape(tileID: tileID, height: moundHeight, width: moundWidth, spacing: moundSpacing)
                                .stroke(Color.black.opacity(0.45), lineWidth: 0.6)
                        }
                    }
            }
        }
        .frame(height: 12)
        // The mound baseline is eight points into its drawing canvas. Align
        // that baseline with the existing tile edge, without adding padding.
        .offset(y: -8)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
        .transaction { $0.animation = nil }
    }
}

private struct HomeSnowCapShape: Shape {
    let tileID: String
    var height: Double = 1
    var width: Double = 1
    var spacing: Double = 1

    func path(in rect: CGRect) -> Path {
        guard rect.width.isFinite, rect.height.isFinite, rect.width > 36, rect.width <= 16_384, rect.height > 0 else { return Path() }
        // Stable identity, unlike Swift's per-process randomized hashValue.
        let seed = tileID.utf8.prefix(64).reduce(UInt64(0xcbf29ce484222325)) { ($0 ^ UInt64($1)) &* 0x100000001b3 }
        let inset = min(16.0, Double(rect.width) * 0.12)
        let profileWidth = Double(rect.width) - inset * 2
        let count = max(12, min(48, Int(profileWidth / 8)))
        // Feed the shared mound contour a stable, multi-scale snow profile.
        // Broad shoulders, smaller lobes, and a few soft notches break up the
        // old regular wave without introducing per-frame randomness.
        func noise(_ coordinate: Int, salt: UInt64) -> Double {
            var value = seed ^ salt &+ UInt64(max(0, coordinate)) &* 0x9e3779b97f4a7c15
            value ^= value >> 30; value &*= 0xbf58476d1ce4e5b9
            value ^= value >> 27; value &*= 0x94d049bb133111eb
            value ^= value >> 31
            return Double(value & 0x00ff_ffff) / Double(0x00ff_ffff)
        }
        let heights = (0..<count).map { index -> Double in
            let broad = noise(index / 6, salt: 0x42524f4144) * 4.8
            let lobe = noise(index / 2, salt: 0x4c4f424553) * 3.8
            let grain = noise(index, salt: 0x475241494e) * 2.4
            let notch = noise(index / 3, salt: 0x4e4f544348) > 0.84 ? 2.6 : 0
            return min(10.5, max(0.25, 1.1 + broad + lobe + grain - notch))
        }
        let bank = DesktopSnowBank(surface: .init(id: seed, kind: .window, left: 0, right: profileWidth, y: 0), heights: heights)
        let baseline = min(Double(rect.height) - 0.5, 8.0)
        let options = DesktopSnowOptions(moundHeight: height, moundWidth: width, moundSpacing: spacing)
        var path = Path()
        func point(_ value: CGPoint) -> CGPoint {
            let safeHeight = min(baseline, max(0, Double(value.y)))
            return .init(x: Double(rect.minX) + inset + Double(value.x), y: Double(rect.minY) + baseline - safeHeight)
        }
        for mound in DesktopSnowPolicy.moundSilhouettes(for: bank, options: options) {
            guard let first = mound.points.first, let last = mound.points.last else { continue }
            path.move(to: point(first))
            for index in 1..<mound.points.count {
                let previous = mound.points[index - 1], current = mound.points[index]
                let midpoint = CGPoint(x: (previous.x + current.x) / 2, y: (previous.y + current.y) / 2)
                path.addQuadCurve(to: point(midpoint), control: point(previous))
            }
            path.addQuadCurve(to: point(last), control: point(last))
            path.closeSubpath()
        }
        return path
    }
}
