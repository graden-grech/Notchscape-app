import SwiftUI
import Defaults

private struct HomeTileSurfaceModifier: ViewModifier {
    @Default(.homeTileStyle) private var style
    @Default(.homeTileTransparency) private var transparency
    @ObservedObject private var performance = AppPerformanceManager.shared
    @Environment(\.colorSchemeContrast) private var contrast

    func body(content: Content) -> some View {
        content.background {
            if style != .original {
                Color.clear.standardMaterialPanel(cornerRadius: 16)
                    .opacity(HomeTileSurfacePolicy.opacity(style: style, transparency: transparency,
                        reduceTransparency: performance.reduceTransparency,
                        increasedContrast: contrast == .increased))
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
            }
        }
    }
}

enum NotchHeaderMetrics {
    static let controlHeight = CGFloat(NotchHeaderLayoutPolicy.controlHeight)
    static let topInset = CGFloat(NotchHeaderLayoutPolicy.topInset)
}

/// Only chooses Apple's small size; drawing, drag tracking and glass remain native.
struct CompactSwitchToggleStyle: ToggleStyle {
    @Environment(\.isEnabled) private var isEnabled
    func makeBody(configuration: Configuration) -> some View {
        Toggle(isOn: configuration.$isOn) { configuration.label }
            .toggleStyle(.switch)
            .controlSize(.small)
            .saturation(isEnabled ? 1 : 0)
            .opacity(isEnabled ? 1 : 0.5)
    }
}

enum AgentProviderStyle {
    static func isClaude(_ provider: String) -> Bool {
        provider.localizedCaseInsensitiveContains("claude")
    }

    static func accent(for provider: String) -> Color {
        isClaude(provider)
            ? Color(red: 0.86, green: 0.40, blue: 0.24)
            : Color(red: 0.34, green: 0.20, blue: 0.72)
    }

    static func secondary(for provider: String) -> Color {
        isClaude(provider)
            ? Color(red: 0.96, green: 0.62, blue: 0.34)
            : Color(red: 0.52, green: 0.36, blue: 0.88)
    }

    static func symbol(for provider: String) -> String {
        isClaude(provider) ? "sparkle" : "terminal.fill"
    }
}

struct AgentProviderMark: View {
    @ObservedObject private var performance = AppPerformanceManager.shared
    let provider: String
    let state: AgentActivityState
    let size: CGFloat
    var symbolOverride: String?

    private var accent: Color {
        switch state {
        case .completed: .green
        case .usageLimited: .red
        default: AgentProviderStyle.accent(for: provider)
        }
    }

    private var symbol: String {
        if let symbolOverride { return symbolOverride }
        switch state {
        case .completed: return "checkmark"
        case .interrupted: return "pause.fill"
        case .needsInput: return "exclamationmark"
        case .usageLimited: return "exclamationmark"
        case .working: return AgentProviderStyle.symbol(for: provider)
        }
    }

    @Environment(\.colorSchemeContrast) private var contrast

    private var rendering: GlassPresentationPolicy {
        glassRenderingPolicy(performance: performance, increasedContrast: contrast == .increased)
    }

    private var glyph: some View {
        Image(systemName: symbol)
            .font(.system(size: max(9, size * 0.4), weight: .semibold, design: .rounded))
            .foregroundStyle(.white)
    }

    @ViewBuilder private var statusGlyph: some View {
        if rendering.allowsDecorativeMotion {
            glyph.symbolEffect(.bounce, value: state == .completed || state == .usageLimited)
        } else { glyph }
    }

    var body: some View {
        Group {
            if #available(macOS 26.0, *), rendering.usesNativeGlass {
                Color.clear.frame(width: size, height: size)
                    .glassEffect(.regular, in: Circle())
                    .overlay {
                        statusGlyph.frame(width: max(1, size - 4), height: max(1, size - 4))
                            .background(accent, in: Circle())
                    }
            } else {
                statusGlyph.frame(width: size, height: size)
                    .background(accent, in: Circle())
            }
        }
        .accessibilityHidden(true)
    }
}

struct LiquidGlassSettingsBackground: View {
    var body: some View {
        Rectangle()
            .fill(Color(nsColor: .windowBackgroundColor))
        .ignoresSafeArea()
        .allowsHitTesting(false)
    }
}

/// One accessibility/performance decision shared by controls and static marks.
@MainActor
private func glassRenderingPolicy(performance: AppPerformanceManager, increasedContrast: Bool) -> GlassPresentationPolicy {
    let native: Bool
    if #available(macOS 26.0, *) { native = true } else { native = false }
    return .init(supportsNativeGlass: native,
                 reduceTransparency: performance.reduceTransparency,
                 increasedContrast: increasedContrast,
                 lowImpact: performance.lowImpact, reduceMotion: performance.reduceMotion)
}

/// Group only related controls. Content stays on its own readable surface.
struct NotchGlassControlGroup<Content: View>: View {
    @ObservedObject private var performance = AppPerformanceManager.shared
    @Environment(\.colorSchemeContrast) private var contrast
    let spacing: CGFloat
    let content: Content

    init(spacing: CGFloat = 4, @ViewBuilder content: () -> Content) {
        self.spacing = CGFloat(GlassPresentationPolicy.groupingSpacing(Double(spacing)))
        self.content = content()
    }

    @ViewBuilder var body: some View {
        if #available(macOS 26.0, *), glassRenderingPolicy(performance: performance, increasedContrast: contrast == .increased).usesNativeGlass {
            GlassEffectContainer(spacing: spacing) { content }
        } else { content }
    }
}

private struct NotchGlassButtonModifier: ViewModifier {
    @ObservedObject private var performance = AppPerformanceManager.shared
    @Environment(\.colorSchemeContrast) private var contrast
    let prominent: Bool
    let circular: Bool
    let diameter: CGFloat

    @ViewBuilder private func styled(_ content: Content) -> some View {
        if #available(macOS 26.0, *), glassRenderingPolicy(performance: performance, increasedContrast: contrast == .increased).usesNativeGlass {
            if prominent { content.buttonStyle(.glassProminent).tint(Color.accentColor) }
            else { content.buttonStyle(.glass).tint(Color.gray.opacity(0.25)).foregroundStyle(.primary) }
        } else {
            if prominent { content.buttonStyle(.borderedProminent).tint(Color.accentColor) }
            else { content.buttonStyle(.bordered).tint(Color.gray).foregroundStyle(.primary) }
        }
    }

    @ViewBuilder func body(content: Content) -> some View {
        if circular {
            if #available(macOS 26.0, *) {
                styled(content).buttonBorderShape(.circle).frame(width: diameter, height: diameter)
            } else {
                styled(content).buttonBorderShape(.capsule).frame(width: diameter, height: diameter)
            }
        } else { styled(content) }
    }
}

private struct ContentPanelModifier: ViewModifier {
    @ObservedObject private var performance = AppPerformanceManager.shared
    @Environment(\.colorSchemeContrast) private var contrast
    let tint: Color
    let cornerRadius: CGFloat

    @ViewBuilder func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        let opaque = glassRenderingPolicy(performance: performance, increasedContrast: contrast == .increased).usesOpaqueSurfaces
        if opaque {
            content.background(Color(nsColor: .controlBackgroundColor), in: shape)
                .overlay { shape.strokeBorder(Color.primary.opacity(contrast == .increased ? 0.5 : 0.12), lineWidth: contrast == .increased ? 1 : 0.5) }
        } else {
            content.background(.regularMaterial, in: shape)
                .overlay { shape.strokeBorder(tint.opacity(0.12), lineWidth: 0.5) }
        }
    }
}

private struct LiquidGlassCapsuleModifier: ViewModifier {
    @ObservedObject private var performance = AppPerformanceManager.shared
    @Environment(\.colorSchemeContrast) private var contrast
    let tint: Color
    let interactive: Bool

    @ViewBuilder func body(content: Content) -> some View {
        let rendering = glassRenderingPolicy(performance: performance, increasedContrast: contrast == .increased)
        if rendering.usesOpaqueSurfaces {
            content.background(Color(nsColor: .controlBackgroundColor), in: Capsule())
                .overlay { Capsule().strokeBorder(Color.primary.opacity(contrast == .increased ? 0.5 : 0.12), lineWidth: contrast == .increased ? 1 : 0.5) }
        } else if #available(macOS 26.0, *), rendering.usesNativeGlass {
            content.glassEffect(.regular.tint(tint.opacity(0.2)).interactive(interactive && rendering.allowsDecorativeMotion), in: Capsule())
        } else {
            content.background(.ultraThinMaterial, in: Capsule())
                .overlay { Capsule().strokeBorder(Color.primary.opacity(0.12), lineWidth: 0.5) }
        }
    }
}

extension View {
    func homeTileSurface() -> some View {
        modifier(HomeTileSurfaceModifier())
    }

    func notchGlassButton(prominent: Bool = false, circular: Bool = false, diameter: CGFloat = 30) -> some View {
        modifier(NotchGlassButtonModifier(prominent: prominent, circular: circular, diameter: CGFloat(GlassPresentationPolicy.controlDiameter(Double(diameter)))))
    }

    func standardMaterialPanel(tint: Color = .white, cornerRadius: CGFloat = 18) -> some View {
        modifier(ContentPanelModifier(tint: tint, cornerRadius: cornerRadius))
    }

    func liquidGlassCapsule(tint: Color = .white, interactive: Bool = true) -> some View {
        modifier(LiquidGlassCapsuleModifier(tint: tint, interactive: interactive))
    }
}
