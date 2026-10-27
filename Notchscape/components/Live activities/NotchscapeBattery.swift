import SwiftUI
import Defaults
import Charts

/// A view that displays the battery status with an icon and charging indicator.
struct BatteryView: View {

    var levelBattery: Float
    var isPluggedIn: Bool
    var isCharging: Bool
    var isInLowPowerMode: Bool
    var batteryWidth: CGFloat = 26
    var isForNotification: Bool

    var icon: String = "battery.0"

    /// Determines the icon to display when charging.
    var iconStatus: String {
        if isCharging {
            return "bolt"
        }
        else if isPluggedIn {
            return "plug"
        }
        else {
            return ""
        }
    }

    /// Determines the color of the battery based on its status.
    var batteryColor: Color {
        if isInLowPowerMode {
            return .yellow
        } else if levelBattery <= 20 && !isCharging && !isPluggedIn {
            return .red
        } else if isCharging || isPluggedIn || levelBattery == 100 {
            return .green
        } else {
            return .white
        }
    }

    var body: some View {
        ZStack(alignment: .leading) {

            Image(systemName: icon)
                .resizable()
                .fontWeight(.thin)
                .aspectRatio(contentMode: .fit)
                .foregroundColor(.white.opacity(0.5))
                .frame(
                    width: batteryWidth + 1
                )

            RoundedRectangle(cornerRadius: 2.5)
                .fill(batteryColor)
                .frame(
                    width: CGFloat(((CGFloat(CFloat(levelBattery)) / 100) * (batteryWidth - 6))),
                    height: (batteryWidth - 2.75) - 18
                )
                .padding(.leading, 2)

            if iconStatus != "" && (isForNotification || Defaults[.showPowerStatusIcons]) {
                ZStack {
                    Image(iconStatus)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .foregroundColor(.white)
                        .frame(
                            width: 17,
                            height: 17
                        )
                }
                .frame(width: batteryWidth, height: batteryWidth)
            }
        }
    }
}

struct ScaleButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.95 : 1.0)
            .animation(.easeInOut(duration: 0.2), value: configuration.isPressed)
    }
}

/// A view that displays detailed battery information and settings.
struct BatteryMenuView: View {
    
    var isPluggedIn: Bool
    var isCharging: Bool
    var levelBattery: Float
    var maxCapacity: Float
    var timeToFullCharge: Int
    var isInLowPowerMode: Bool
    var onDismiss: () -> Void

    @Environment(\.openURL) private var openURL

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {

            HStack {
                Text("Battery Status")
                    .font(.headline)
                    .fontWeight(.semibold)
                Spacer()
                Text("\(Int(levelBattery))%")
                    .font(.headline)
                    .fontWeight(.semibold)
            }
            
            VStack(alignment: .leading, spacing: 8) {
                if !isPluggedIn && !isCharging {
                    Label("On battery", systemImage: "battery.100percent")
                        .font(.subheadline)
                }
                if isInLowPowerMode {
                    Label("Low Power Mode", systemImage: "bolt.circle")
                        .font(.subheadline)
                        .fontWeight(.regular)
                }
                if isCharging {
                    Label("Charging", systemImage: "bolt.fill")
                        .font(.subheadline)
                        .fontWeight(.regular)
                }
                if isPluggedIn {
                    Label("Plugged In", systemImage: "powerplug.fill")
                        .font(.subheadline)
                        .fontWeight(.regular)
                }
                if isCharging && timeToFullCharge > 0 {
                    Label("Time to Full Charge: \(timeToFullCharge) min", systemImage: "clock")
                        .font(.subheadline)
                        .fontWeight(.regular)
                }
                if !isCharging && isPluggedIn && levelBattery >= 80 {
                    Label("Connected to power · Not charging", systemImage: "powerplug.fill")
                        .font(.subheadline)
                        .fontWeight(.regular)
                }
                    
            }
            .padding(.vertical, 8)

            Divider().background(Color.white)

            Button(action: openBatteryPreferences) {
                Label("Battery Settings", systemImage: "gearshape")
                    .fontWeight(.regular)
            }
            .frame(maxWidth: .infinity)
            .buttonStyle(.plain)
            .padding(.vertical, 8)
        }
        .padding()
        .frame(width: 280)
        .foregroundColor(.white)
    }

    private func openBatteryPreferences() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.battery") {
            openURL(url)
            onDismiss()
        }
    }
}

/// A view that displays the battery status and allows interaction to show detailed information.
struct NotchscapeBatteryView: View {
    @Default(.batteryPresentation) private var presentation
    @Default(.batteryIndicatorDisplay) private var display
    @Default(.showBatteryPercentage) private var showPercentage
    @Default(.showPowerStatusIcons) private var showPowerIcons
    @ObservedObject private var batteryModel = BatteryStatusViewModel.shared
    
    @State var batteryWidth: CGFloat = 26
    var isCharging: Bool = false
    var isInLowPowerMode: Bool = false
    var isPluggedIn: Bool = false
    var levelBattery: Float = 0
    var maxCapacity: Float = 0
    var timeToFullCharge: Int = 0
    @State var isForNotification: Bool = false
    
    @State private var showPopupMenu: Bool = false
    @State private var isPressed: Bool = false
    @State private var isHoveringButton: Bool = false
    @State private var isHoveringPopover: Bool = false
    @State private var hideTask: Task<Void, Never>? = nil

    @EnvironmentObject var vm: NotchscapeViewModel

    var body: some View {
        Button(action: {
            withAnimation {
                showPopupMenu.toggle()
            }
        }) {
            if presentation == .enhanced && !isForNotification {
                indicator.padding(.horizontal, 8).frame(height: NotchHeaderMetrics.controlHeight)
                    .liquidGlassCapsule()
            } else {
                indicator
            }
        }
        .buttonStyle(ScaleButtonStyle())
        .accessibilityLabel("Battery")
        .accessibilityValue(batteryModel.dataAvailable ? "\(Int(levelBattery)) percent" : batteryModel.statusText)
        .help("Battery status")
        .popover(
            isPresented: $showPopupMenu,
            arrowEdge: .bottom) {
            Group {
            if presentation == .enhanced {
                EnhancedBatteryMenuView(onDismiss: { showPopupMenu = false })
            } else if !batteryModel.dataAvailable {
                Text(batteryModel.statusText).padding()
            } else {
              BatteryMenuView(
                isPluggedIn: isPluggedIn,
                isCharging: isCharging,
                levelBattery: levelBattery,
                maxCapacity: maxCapacity,
                timeToFullCharge: timeToFullCharge,
                isInLowPowerMode: isInLowPowerMode,
                onDismiss: { 
                    showPopupMenu = false
                }
            )
            }
            }
            .onHover { hovering in
                isHoveringPopover = hovering
                if hovering {
                    hideTask?.cancel()
                    hideTask = nil
                } else {
                    scheduleHideIfNeeded()
                }
            }
        }
        .onChange(of: showPopupMenu) {
            vm.isBatteryPopoverActive = showPopupMenu
        }
        .onDisappear {
            hideTask?.cancel()
            hideTask = nil
            vm.isBatteryPopoverActive = false
        }
    }

    private var indicator: some View {
        HStack(spacing: 5) {
            if presentation == .original ? showPercentage : display != .iconOnly {
                Text(batteryModel.dataAvailable ? "\(Int(levelBattery))%" : "—")
                    .font(.callout).monospacedDigit().foregroundStyle(.white)
            }
            if presentation == .original || display != .percentageOnly {
                if presentation == .enhanced && !isForNotification {
                    Image(systemName: BatteryPolicy.symbol(level: Double(levelBattery),
                        charging: batteryModel.dataAvailable && isCharging && showPowerIcons))
                        .font(.system(size: 17))
                        .foregroundStyle(isInLowPowerMode ? Color.yellow : isCharging ? Color.green : Color.white)
                        .frame(width: 26, height: 18)
                        .accessibilityHidden(true)
                } else {
                  BatteryView(levelBattery: batteryModel.dataAvailable ? levelBattery : 0,
                    isPluggedIn: batteryModel.dataAvailable && isPluggedIn,
                    isCharging: batteryModel.dataAvailable && isCharging,
                    isInLowPowerMode: isInLowPowerMode, batteryWidth: batteryWidth,
                    isForNotification: isForNotification)
                }
            }
        }
    }

    private func scheduleHideIfNeeded() {
        if isHoveringButton || isHoveringPopover { return }
        hideTask?.cancel()
        hideTask = Task {
            try? await Task.sleep(for: .milliseconds(350))
            guard !Task.isCancelled else { return }
            await MainActor.run { withAnimation { showPopupMenu = false } }
        }
    }
}

struct EnhancedBatteryMenuView: View {
    @ObservedObject private var battery = BatteryStatusViewModel.shared
    @Default(.batteryHistoryEnabled) private var historyEnabled
    @Environment(\.openURL) private var openURL
    var onDismiss: () -> Void

    private var status: String {
        guard battery.dataAvailable else { return battery.statusText }
        return BatteryReading(level: Double(battery.levelBattery), pluggedIn: battery.isPluggedIn,
            charging: battery.isCharging, fullyCharged: battery.isFullyCharged).status
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .center) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Battery").font(.headline)
                    Text(battery.dataAvailable ? "\(Int(battery.levelBattery))%" : "—")
                        .font(.system(size: 34, weight: .semibold, design: .rounded)).monospacedDigit()
                }
                Spacer()
                BatteryView(levelBattery: battery.dataAvailable ? battery.levelBattery : 0,
                    isPluggedIn: battery.dataAvailable && battery.isPluggedIn,
                    isCharging: battery.dataAvailable && battery.isCharging,
                    isInLowPowerMode: battery.isInLowPowerMode, batteryWidth: 38,
                    isForNotification: true).accessibilityHidden(true)
            }
            Text(status).font(.subheadline).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            if battery.dataAvailable {
                if battery.isCharging && battery.timeToFullCharge > 0 {
                    Label("About \(battery.timeToFullCharge) min until full", systemImage: "clock")
                        .font(.subheadline)
                }
                if battery.isInLowPowerMode {
                    Label("Low Power Mode", systemImage: "leaf.fill").font(.subheadline)
                        .foregroundStyle(.yellow)
                }
                if historyEnabled {
                    BatteryHistoryChart(samples: BatteryHistoryPolicy.retained(battery.history, now: Date()))
                }
            }
            Divider()
            Button {
                if let url = URL(string: "x-apple.systempreferences:com.apple.preference.battery") {
                    openURL(url)
                    onDismiss()
                }
            } label: { Label("Battery Settings…", systemImage: "gearshape") }
                .buttonStyle(.bordered)
        }
        .padding(20)
        .frame(width: 300)
        .foregroundStyle(.white)
        .background(.regularMaterial)
        .preferredColorScheme(.dark)
    }
}

private struct BatteryHistoryChart: View {
    var samples: [BatteryHistorySample]
    private struct Point: Identifiable {
        var sample: BatteryHistorySample
        var segment: Int
        var id: Date { sample.date }
    }
    private var points: [Point] {
        var segment = 0
        return samples.enumerated().map { index, sample in
            if index > 0, sample.date.timeIntervalSince(samples[index - 1].date) > 1800 { segment += 1 }
            return Point(sample: sample, segment: segment)
        }
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Battery history").font(.subheadline.weight(.medium))
            if samples.isEmpty {
                Text("History will appear as your battery changes.")
                    .font(.caption).foregroundStyle(.secondary).frame(height: 90)
            } else {
                Chart(points) { point in
                    LineMark(x: .value("Time", point.sample.date), y: .value("Battery", point.sample.level),
                        series: .value("Segment", point.segment))
                        .foregroundStyle(Color.effectiveAccent).lineStyle(StrokeStyle(lineWidth: 2))
                    PointMark(x: .value("Time", point.sample.date), y: .value("Battery", point.sample.level))
                        .foregroundStyle(point.sample.pluggedIn ? Color.green : Color.effectiveAccent)
                        .symbolSize(12)
                }
                .chartYScale(domain: 0...100)
                .chartXScale(domain: Date().addingTimeInterval(-86400)...Date())
                .chartYAxis { AxisMarks(values: [0, 50, 100]) { value in
                    AxisGridLine()
                    AxisValueLabel { if let level = value.as(Int.self) { Text("\(level)%") } }
                } }
                .chartXAxis { AxisMarks(values: .automatic(desiredCount: 3)) { _ in
                    AxisValueLabel(format: .dateTime.hour())
                } }
                .frame(height: 90)
                .accessibilityLabel("Battery level over the last 24 hours")
            }
            Text("Last 24 hours · Recorded locally while Enhanced is active")
                .font(.caption2).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

#Preview {
    NotchscapeBatteryView(
        batteryWidth: 30,
        isCharging: false,
        isInLowPowerMode: false,
        isPluggedIn: true,
        levelBattery: 80,
        maxCapacity: 100,
        timeToFullCharge: 10,
        isForNotification: false
    ).frame(width: 200, height: 200)
}
