import SwiftUI

struct SystemDashboardView: View {
    @ObservedObject private var performance = SystemPerformanceManager.shared
    @ObservedObject private var rendering = AppPerformanceManager.shared

    var body: some View {
        VStack(spacing: 8) {
            HStack(spacing: 10) {
                metricCard("CPU", symbol: "cpu", value: performance.cpuUsage, detail: "Thermal: " + performance.thermalState, color: .blue)
                metricCard(
                    "Memory",
                    symbol: "memorychip",
                    value: performance.memoryUsage,
                    detail: byteSummary(performance.usedMemory, performance.totalMemory),
                    color: .purple
                )
                metricCard(
                    "Storage",
                    symbol: "internaldrive",
                    value: performance.diskUsage,
                    detail: byteSummary(UInt64(max(0, performance.usedDisk)), UInt64(max(0, performance.totalDisk))),
                    color: .orange
                )
            }

            HStack(spacing: 10) {
                Label("↓ \(rate(performance.networkReceived))   ↑ \(rate(performance.networkSent))", systemImage: "network")
                Spacer(minLength: 0)
                Text("Memory pressure: \(performance.memoryPressure)")
            }.font(.caption2).foregroundStyle(.secondary)
            HStack {
                Label("Read \(rate(performance.diskReadRate)) · Write \(rate(performance.diskWriteRate))", systemImage: "internaldrive")
                Spacer(minLength: 0)
            }.font(.caption2).foregroundStyle(.secondary)

            if #available(macOS 26.0, *), !rendering.lowImpact, !rendering.reduceTransparency {
                GlassEffectContainer(spacing: 8) { controls }
            } else { controls }
        }
        // Participate in the expanded page's height, just like Home and Live.
        // An intrinsic-height dashboard is otherwise centered by the physical
        // notch's outer frame, leaving a transparent gap above its header.
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .padding(.horizontal, 8)
        .padding(.bottom, 5)
        .onAppear { performance.startSampling() }
        .onDisappear { performance.stopSampling() }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("System performance")
    }

    private var controls: some View {
        HStack(spacing: 8) {
            controlButton("Activity Monitor", icon: "chart.xyaxis.line", action: performance.openActivityMonitor)
            controlButton("Settings", icon: "gearshape", action: performance.openSystemSettings)
            controlButton("Sleep Display", icon: "display", action: performance.sleepDisplay)
            controlButton("Lock", icon: "lock", action: performance.lockMac)
        }
    }

    private func metricCard(_ title: String, symbol: String, value: Double, detail: String, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 5) {
                Image(systemName: symbol).foregroundStyle(color)
                Text(title).foregroundStyle(.secondary)
            }
            .font(.caption.weight(.medium))
            Text(value, format: .percent.precision(.fractionLength(0)))
                .font(.system(size: 26, weight: .medium)).monospacedDigit()
                .contentTransition(.numericText())
            ProgressView(value: min(max(value, 0), 1)).tint(color).controlSize(.mini)
                .accessibilityLabel("\(title) usage")
            Text(detail).font(.caption2).foregroundStyle(.secondary).lineLimit(1).minimumScaleFactor(0.85)
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .standardMaterialPanel(tint: .white, cornerRadius: 18)
    }

    private func controlButton(_ title: String, icon: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(title, systemImage: icon)
                .font(.caption.weight(.medium))
                .frame(maxWidth: .infinity)
                .lineLimit(1).minimumScaleFactor(0.85)
                .padding(.vertical, 5)
        }
        .buttonStyle(.plain)
        .liquidGlassCapsule(tint: .accentColor)
    }

    private func byteSummary(_ used: UInt64, _ total: UInt64) -> String {
        guard total > 0 else { return "Loading…" }
        return "\(ByteCountFormatter.string(fromByteCount: Int64(used), countStyle: .memory)) / \(ByteCountFormatter.string(fromByteCount: Int64(total), countStyle: .memory))"
    }
    private func rate(_ value: Double?) -> String {
        guard let value, value.isFinite, value >= 0 else { return "Unavailable" }
        return ByteCountFormatter.string(fromByteCount: Int64(min(value, Double(Int64.max/2))), countStyle: .file) + "/s"
    }
}
