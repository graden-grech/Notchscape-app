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
    @Default(.desktopSnowEnabled) private var enabled
    @Default(.desktopSnowHomeWidgets) private var homeWidgets
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.colorSchemeContrast) private var contrast

    var body: some View {
        Group {
            if enabled && homeWidgets && snow.isRunning {
                HomeSnowCapShape(tileID: tileID)
                    .fill(Color.white.opacity(reduceTransparency ? 1 : 0.94))
                    .overlay {
                        if contrast == .increased {
                            HomeSnowCapShape(tileID: tileID).stroke(Color.black.opacity(0.45), lineWidth: 0.6)
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

    func path(in rect: CGRect) -> Path {
        guard rect.width.isFinite, rect.height.isFinite, rect.width > 36, rect.width <= 16_384, rect.height > 0 else { return Path() }
        // Stable identity, unlike Swift's per-process randomized hashValue.
        let seed = tileID.utf8.prefix(64).reduce(UInt64(0xcbf29ce484222325)) { ($0 ^ UInt64($1)) &* 0x100000001b3 }
        let inset = min(16.0, Double(rect.width) * 0.12)
        let width = Double(rect.width) - inset * 2
        let count = max(12, min(48, Int(width / 8)))
        let phase = Double(seed % 29) * 0.31
        // The shared mound profile supplies separate peaks and clear gaps.
        // A gentle, stable deposit varies their heights without a tiled wave.
        let heights = (0..<count).map { 7.2 + sin(Double($0) * 0.47 + phase) * 0.7 }
        let bank = DesktopSnowBank(surface: .init(id: seed, kind: .window, left: 0, right: width, y: 0), heights: heights)
        let baseline = min(Double(rect.height) - 0.5, 8.0)
        var path = Path()
        func point(_ value: CGPoint) -> CGPoint {
            .init(x: Double(rect.minX) + inset + Double(value.x), y: Double(rect.minY) + baseline - Double(value.y))
        }
        for mound in DesktopSnowPolicy.moundSilhouettes(for: bank) {
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
