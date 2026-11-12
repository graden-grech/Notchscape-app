import AppKit
import Defaults
import SwiftUI
import UniformTypeIdentifiers

struct DockWorkspaceSettings: View {
    @Default(.dockReplacementEnabled) private var barEnabled
    @Default(.dockReplacementIconSize) private var barIconSize
    @Default(.dockReplacementOverflow) private var barOverflow
    @Default(.dockHideSystemDock) private var hideSystemDock
    @ObservedObject private var dockBar = DockReplacementController.shared
    @ObservedObject private var dockVisibility = DockVisibilityController.shared
    @Default(.dockWorkspaceEnabled) private var enabled
    @Default(.dockWidgetEnabled) private var widgetEnabled
    @Default(.dockWidgetKind) private var widgetKind
    @ObservedObject private var manager = DockWorkspaceManager.shared
    @ObservedObject private var dockWidget = DockWidgetManager.shared

    var body: some View {
        Form {
            Section("Dock Bar") {
                Toggle("Use Dock Bar Preview", isOn: $barEnabled)
                Text("Your apps and widgets in one bar. Use + to add items, or hold a widget for its controls.")
                    .font(.callout).foregroundStyle(.secondary)
                Button("Show Dock Bar", systemImage: "dock.rectangle") { dockBar.show() }
                    .notchGlassButton(prominent: true).disabled(!barEnabled)
                Toggle("Keep macOS Dock hidden", isOn: $hideSystemDock).disabled(!barEnabled)
                Text("Suppresses normal edge reveals while Dock Bar is visible. Your previous Dock settings return when Dock Bar turns off or Notchscape quits. macOS system commands can still reveal it.")
                    .font(.caption).foregroundStyle(.secondary)
                if let status = dockVisibility.statusText {
                    Text(status).font(.caption).foregroundStyle(.secondary)
                }
                Button("Restore macOS Dock Now", systemImage: "arrow.uturn.backward") {
                    hideSystemDock = false; dockVisibility.restoreNow()
                }.notchGlassButton().disabled(!hideSystemDock && dockVisibility.statusText == nil)
                DisclosureGroup("Layout Options") {
                    LabeledContent("App icon size") {
                        Slider(value: $barIconSize, in: 32...64, step: 4).frame(width: 180)
                            .accessibilityLabel("Dock bar app icon size")
                        Text("\(Int(barIconSize)) pt").monospacedDigit().frame(width: 44)
                    }.disabled(!barEnabled)
                    Picker("More widgets", selection: $barOverflow) {
                        Text("Pages").tag("pages")
                        Text("Stack").tag("stack")
                    }.disabled(!barEnabled)
                    Text("Weather shares your existing setup. System readings refresh only while their widget is visible. Stack opens extra widgets in a menu; Pages lets you browse them in the bar.")
                        .font(.caption).foregroundStyle(.secondary)
                    Text("The single Dock widget below pauses while Dock Bar is on; its saved setting is kept.")
                        .font(.caption).foregroundStyle(.secondary)
                }
                if let message = dockBar.errorMessage {
                    Label(message, systemImage: "exclamationmark.circle").foregroundStyle(.orange)
                }
            }
            Section("Dock Widget") {
                Toggle("Show Widget in macOS Dock", isOn: $widgetEnabled)
                    .accessibilityHint("Shows one live widget in the macOS Dock.")
                Picker("Widget", selection: $widgetKind) {
                    Label("Clock", systemImage: "clock").tag("clock")
                    Label("Battery", systemImage: "battery.75percent").tag("battery")
                    Label("Calendar", systemImage: "calendar").tag("calendar")
                }
                .pickerStyle(.menu)
                .disabled(!widgetEnabled)
                Text("Show one live tile in your Mac’s Dock. Calendar shows the current date. Click the tile to open Dock Workspace or its settings.")
                    .font(.callout).foregroundStyle(.secondary)
                if barEnabled {
                    Text("Paused while Dock Bar is enabled.").font(.caption).foregroundStyle(.secondary)
                } else if widgetEnabled {
                    if let message = dockWidget.errorMessage {
                        Label(message, systemImage: "exclamationmark.circle")
                            .font(.callout).foregroundStyle(.orange)
                        Button("Try Again") { dockWidget.restart() }.notchGlassButton()
                    } else {
                        Label(dockWidget.isRunning ? "Widget is running" : "Starting widget…",
                              systemImage: dockWidget.isRunning ? "checkmark.circle" : "clock")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
                Text("The Notchscape app icon has its own Show Dock Icon setting. Turning this widget off closes its running tile. If you choose Keep in Dock in macOS, remove that saved shortcut from the Dock separately.")
                    .font(.caption).foregroundStyle(.secondary)
            }.disabled(barEnabled)
            Section {
                Toggle("Use Dock Workspace", isOn: $enabled)
                Text("Open a separate workspace for your pinned apps, folders and widgets. Your Mac’s normal Dock stays available.")
                    .font(.callout).foregroundStyle(.secondary)
                Button("Open Workspace", systemImage: "dock.rectangle") { manager.show() }
                    .notchGlassButton(prominent: true)
                    .disabled(!enabled)
            } header: { Text("Dock Workspace") }

            Section("Pinned Apps & Folders") {
                if manager.layout.pins.isEmpty {
                    Label("Add the apps and folders you want close at hand.", systemImage: "plus.app")
                        .foregroundStyle(.secondary)
                }
                ForEach(Array(manager.layout.pins.enumerated()), id: \.element.id) { index, pin in
                    HStack(spacing: 12) {
                        Image(systemName: pin.kind == .application ? "app" : "folder")
                            .foregroundStyle(.secondary).frame(width: 22)
                        Text(pin.title).lineLimit(1)
                        Spacer()
                        moveButtons(title: pin.title, first: index == 0, last: index == manager.layout.pins.count - 1,
                                    earlier: { manager.movePin(pin.id, by: -1) }, later: { manager.movePin(pin.id, by: 1) })
                        Button { manager.removePin(pin.id) } label: { Image(systemName: "minus.circle") }
                            .notchGlassButton().accessibilityLabel("Remove \(pin.title) from Workspace")
                            .help("Remove only this pin. The app or folder is kept.")
                    }.disabled(manager.isLayoutReadOnly)
                }
                NotchGlassControlGroup {
                    HStack(spacing: 8) {
                        Button("Add App…", systemImage: "plus.app") { manager.addPin(kind: .application) }
                            .notchGlassButton()
                        Button("Add Folder…", systemImage: "folder.badge.plus") { manager.addPin(kind: .folder) }
                            .notchGlassButton()
                    }
                }.disabled(!enabled || manager.isLayoutReadOnly || manager.layout.pins.count >= DockWorkspacePolicy.maximumPins)
                Text("Up to 24 pins. Removing a pin keeps the original app and its files.")
                    .font(.caption).foregroundStyle(.secondary)
            }

            Section("Workspace Widgets") {
                ForEach(DockWorkspaceWidget.allCases) { widget in
                    Toggle(isOn: Binding(get: { manager.layout.widgets.contains(widget) }, set: { manager.setWidget(widget, enabled: $0) })) {
                        Label(widget.title, systemImage: widget.symbol)
                    }.disabled(manager.isLayoutReadOnly)
                }
                Text("Drag cards inside the workspace to arrange them. Their menus also offer Move Earlier and Move Later. System readings refresh only while the workspace is open and the System widget is enabled.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section {
                Label("The workspace closes when your Mac locks, sleeps, switches users or enters Presentation mode. Open it again when you are ready.", systemImage: "lock.shield")
                    .font(.callout).foregroundStyle(.secondary)
                Text("Included with this local preview. A separate downloadable Dock add-on is not published yet.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            if let message = manager.errorMessage {
                Section { Label(message, systemImage: "exclamationmark.circle").foregroundStyle(.orange) }
            }
        }
        .formStyle(.grouped)
        .navigationTitle("Dock")
        .onAppear { manager.start() }
    }

    private func moveButtons(title: String, first: Bool, last: Bool,
                             earlier: @escaping () -> Void, later: @escaping () -> Void) -> some View {
        NotchGlassControlGroup {
            HStack(spacing: 8) {
                Button(action: earlier) { Image(systemName: "chevron.up") }
                    .notchGlassButton()
                    .disabled(first).accessibilityLabel("Move \(title) earlier")
                Button(action: later) { Image(systemName: "chevron.down") }
                    .notchGlassButton()
                    .disabled(last).accessibilityLabel("Move \(title) later")
            }
        }.controlSize(.small)
    }
}

struct DockWorkspacePanelView: View {
    @ObservedObject var manager: DockWorkspaceManager
    var panelWidth: CGFloat = 620
    @ObservedObject private var performance = AppPerformanceManager.shared
    @Default(.appTheme) private var appTheme
    @Default(.useCustomAccentColor) private var useCustomAccentColor
    @Default(.customAccentColorData) private var customAccentColorData
    @State private var draggedPin: UUID?
    @State private var draggedWidget: DockWorkspaceWidget?
    private var contentWidth: CGFloat { max(0, panelWidth - 36) }
    private var widgetColumns: Int {
        DockWorkspacePolicy.columnCount(contentWidth: contentWidth, minimumItemWidth: 220, maximumColumns: 2)
    }
    private var widgetWidth: CGFloat { (contentWidth - CGFloat(widgetColumns - 1) * 12) / CGFloat(widgetColumns) }
    private var pinColumns: Int {
        DockWorkspacePolicy.columnCount(contentWidth: contentWidth, minimumItemWidth: 72, maximumColumns: 7)
    }
    private var pinWidth: CGFloat { (contentWidth - CGFloat(pinColumns - 1) * 12) / CGFloat(pinColumns) }
    private var accent: Color {
        Color(nsColor: NSColor.resolvedAccent(theme: appTheme, customEnabled: useCustomAccentColor, customData: customAccentColorData))
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                Image(systemName: "dock.rectangle").font(.title3).foregroundStyle(accent)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Dock Workspace").font(.headline)
                    Text("Apps, folders and widgets").font(.caption).foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
                NotchGlassControlGroup {
                    HStack(spacing: 8) {
                        Button { manager.hide(); SettingsWindowController.shared.showWindow(section: "Dock") } label: {
                            Image(systemName: "slider.horizontal.3").font(.system(size: 13, weight: .medium)).frame(width: 16, height: 16)
                        }.notchGlassButton(circular: true).frame(width: 30, height: 30)
                            .help("Dock Settings").accessibilityLabel("Dock Settings")
                        Button { manager.hide() } label: { Image(systemName: "xmark").font(.system(size: 12, weight: .semibold)).frame(width: 14, height: 14) }
                            .notchGlassButton(circular: true).frame(width: 30, height: 30)
                            .help("Close Workspace").accessibilityLabel("Close Workspace")
                    }
                }
            }.padding(18)
            Divider().opacity(0.45)
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    pinnedApps
                    if !manager.layout.widgets.isEmpty {
                        HStack {
                            Text("Widgets").font(.subheadline.weight(.semibold)).foregroundStyle(.secondary)
                            Spacer()
                            Text("Drag to arrange").font(.caption).foregroundStyle(.secondary)
                        }
                        // At most five cards: eager rows avoid lazy-placement
                        // churn when AppKit-backed menus scroll in and out.
                        VStack(alignment: .leading, spacing: 12) {
                            ForEach(DockWorkspacePolicy.rowRanges(itemCount: manager.layout.widgets.count, columns: widgetColumns), id: \.lowerBound) { range in
                                HStack(alignment: .top, spacing: 12) {
                                    ForEach(range, id: \.self) { index in
                                        let widget = manager.layout.widgets[index]
                                        widgetCard(widget, index: index)
                                            .frame(width: widgetWidth, height: 150, alignment: .topLeading)
                                            .onDrag { draggedWidget = widget; return localDrag(widget.rawValue, type: .dockWorkspaceWidget) }
                                            .onDrop(of: [.dockWorkspaceWidget], delegate: DockWorkspaceDropDelegate(
                                                target: widget, dragging: $draggedWidget,
                                                reorder: { manager.reorderWidget($0, before: $1) }))
                                    }
                                }.frame(width: contentWidth, alignment: .leading)
                            }
                        }
                    }
                    if let message = manager.errorMessage {
                        Label(message, systemImage: "exclamationmark.circle")
                            .font(.callout).foregroundStyle(.orange).fixedSize(horizontal: false, vertical: true)
                    }
                }.frame(width: contentWidth, alignment: .leading).padding(18)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background {
            let shape = RoundedRectangle(cornerRadius: 28, style: .continuous)
            if performance.reduceTransparency {
                shape.fill(Color(nsColor: .windowBackgroundColor))
            } else { shape.fill(.regularMaterial) }
        }
        .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
        .tint(accent)
        .accentColor(accent)
        .transaction { if performance.suppressAnimations { $0.animation = nil; $0.disablesAnimations = true } }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Notchscape Dock Workspace")
    }

    private var pinnedApps: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Pinned").font(.subheadline.weight(.semibold)).foregroundStyle(.secondary)
                Spacer()
                Menu {
                    Button("Add App…", systemImage: "plus.app") { manager.addPin(kind: .application) }
                    Button("Add Folder…", systemImage: "folder.badge.plus") { manager.addPin(kind: .folder) }
                } label: { Label("Add", systemImage: "plus") }
                    .menuStyle(.borderlessButton).frame(width: 64, height: 24)
                    .disabled(manager.isLayoutReadOnly || manager.layout.pins.count >= DockWorkspacePolicy.maximumPins)
            }
            if manager.layout.pins.isEmpty {
                HStack(spacing: 12) {
                    Image(systemName: "plus.app").font(.title3).foregroundStyle(.secondary).accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 4) {
                        Text("No pinned apps").font(.subheadline.weight(.medium))
                        Text("Add an app or folder to keep it close.").font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button("Add App…") { manager.addPin(kind: .application) }
                        .notchGlassButton().disabled(manager.isLayoutReadOnly)
                }.padding(12).standardMaterialPanel(tint: .clear, cornerRadius: 14)
            } else {
                VStack(alignment: .leading, spacing: 12) {
                    ForEach(DockWorkspacePolicy.rowRanges(itemCount: manager.layout.pins.count, columns: pinColumns), id: \.lowerBound) { range in
                        HStack(alignment: .top, spacing: 12) {
                            ForEach(range, id: \.self) { index in
                                let pin = manager.layout.pins[index]
                                pinButton(pin, index: index).frame(width: pinWidth, height: 76)
                            }
                        }.frame(width: contentWidth, alignment: .leading)
                    }
                }
            }
        }
    }

    private func pinButton(_ pin: DockWorkspacePin, index: Int) -> some View {
        Button { manager.open(pin) } label: {
            VStack(spacing: 6) {
                Group {
                    if let icon = manager.icon(for: pin) { Image(nsImage: icon).resizable().interpolation(.high).scaledToFit() }
                    else { Image(systemName: pin.kind == .application ? "app.dashed" : "folder.badge.questionmark").resizable().scaledToFit().foregroundStyle(.secondary).padding(7) }
                }.frame(width: 42, height: 42)
                Text(pin.title).font(.caption).lineLimit(1).frame(width: pinWidth)
            }.padding(.vertical, 4).contentShape(RoundedRectangle(cornerRadius: 12))
        }.buttonStyle(.plain).help("Open \(pin.title)").accessibilityLabel("Open \(pin.title)")
            .contextMenu {
                Button("Open") { manager.open(pin) }
                Divider()
                Button("Move Earlier") { manager.movePin(pin.id, by: -1) }.disabled(manager.isLayoutReadOnly || index == 0)
                Button("Move Later") { manager.movePin(pin.id, by: 1) }.disabled(manager.isLayoutReadOnly || index == manager.layout.pins.count - 1)
                Divider()
                Button("Remove Pin") { manager.removePin(pin.id) }.disabled(manager.isLayoutReadOnly)
            }
            .onDrag { draggedPin = pin.id; return localDrag(pin.id.uuidString, type: .dockWorkspacePin) }
            .onDrop(of: [.dockWorkspacePin], delegate: DockWorkspaceDropDelegate(target: pin.id, dragging: $draggedPin,
                reorder: { manager.reorderPin($0, before: $1) }))
    }

    private func widgetCard(_ widget: DockWorkspaceWidget, index: Int) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label(widget.title, systemImage: widget.symbol).font(.subheadline.weight(.medium)).foregroundStyle(.primary)
                Spacer()
                Menu {
                    Button("Move Earlier") { manager.moveWidget(widget, by: -1) }.disabled(manager.isLayoutReadOnly || index == 0)
                    Button("Move Later") { manager.moveWidget(widget, by: 1) }.disabled(manager.isLayoutReadOnly || index == manager.layout.widgets.count - 1)
                    Divider()
                    Button("Remove Widget") { manager.setWidget(widget, enabled: false) }.disabled(manager.isLayoutReadOnly)
                } label: { Image(systemName: "ellipsis").frame(width: 22, height: 20).contentShape(Rectangle()) }
                    .menuStyle(.borderlessButton).frame(width: 28, height: 24).help("\(widget.title) options")
                    .accessibilityLabel("\(widget.title) options")
            }
            Group {
                switch widget {
                case .clock:
                    VStack(alignment: .leading, spacing: 4) {
                        Text(manager.currentDate, format: .dateTime.hour().minute())
                            .font(.system(size: 32, weight: .medium, design: .rounded)).monospacedDigit()
                        Text(manager.currentDate, format: .dateTime.weekday(.wide).month().day())
                            .font(.callout).foregroundStyle(.secondary)
                    }
                case .calendar: DockWeekCard(date: manager.currentDate, accent: accent)
                case .battery: DockBatteryCard()
                case .system: DockSystemCard()
                case .music: DockMusicCard()
                }
            }.frame(maxWidth: .infinity, minHeight: 64, alignment: .leading)
        }
        .padding(12)
        .frame(width: widgetWidth, height: 150, alignment: .topLeading)
        .standardMaterialPanel(tint: .clear, cornerRadius: 14)
        .accessibilityElement(children: .contain)
    }

    private func localDrag(_ value: String, type: UTType) -> NSItemProvider {
        let provider = NSItemProvider()
        provider.registerDataRepresentation(forTypeIdentifier: type.identifier, visibility: .ownProcess) { completion in
            completion(Data(value.utf8), nil); return nil
        }
        return provider
    }
}

private struct DockWeekCard: View {
    let date: Date
    let accent: Color
    private var days: [Date] {
        let calendar = Calendar.current
        guard let start = calendar.dateInterval(of: .weekOfYear, for: date)?.start else { return [] }
        return (0..<7).compactMap { calendar.date(byAdding: .day, value: $0, to: start) }
    }
    var body: some View {
        HStack(spacing: 0) {
            ForEach(days, id: \.self) { day in
                let today = Calendar.current.isDate(day, inSameDayAs: date)
                VStack(spacing: 8) {
                    Text(day, format: .dateTime.weekday(.narrow)).font(.caption2).foregroundStyle(.secondary)
                    Text(day, format: .dateTime.day()).font(.callout.weight(today ? .bold : .regular))
                        .frame(width: 25, height: 25).background(today ? accent.opacity(0.22) : .clear, in: Circle())
                }.frame(maxWidth: .infinity).accessibilityElement(children: .ignore)
                    .accessibilityLabel(day.formatted(.dateTime.weekday(.wide).month().day()) + (today ? ", today" : ""))
            }
        }
    }
}

private struct DockBatteryCard: View {
    @ObservedObject private var battery = BatteryStatusViewModel.shared
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if battery.dataAvailable {
                HStack {
                    Text("\(Int(battery.levelBattery.rounded()))%").font(.system(size: 30, weight: .medium, design: .rounded)).monospacedDigit()
                    Spacer()
                    Image(systemName: battery.isPluggedIn ? "bolt.fill" : "battery.100percent")
                        .font(.title2).foregroundStyle(battery.isPluggedIn ? Color.green : Color.secondary)
                }
                ProgressView(value: Double(battery.levelBattery), total: 100).accessibilityLabel("Battery level")
                Text(battery.statusText).font(.caption).foregroundStyle(.secondary).lineLimit(1)
            } else {
                Text(battery.hasBattery ? "Battery unavailable" : "Connected to power")
                    .font(.headline).foregroundStyle(.secondary)
            }
        }
    }
}

private struct DockSystemCard: View {
    @ObservedObject private var system = SystemPerformanceManager.shared
    var body: some View {
        VStack(spacing: 10) {
            reading("CPU", value: system.cpuUsage, available: system.cpuDataAvailable, tint: .blue)
            reading("Memory", value: system.memoryUsage, available: system.memoryDataAvailable, tint: .purple)
        }
    }
    private func reading(_ title: String, value: Double, available: Bool, tint: Color) -> some View {
        VStack(spacing: 4) {
            HStack {
                Text(title).font(.caption).foregroundStyle(.secondary)
                Spacer()
                Text(available ? value.formatted(.percent.precision(.fractionLength(0))) : "—").font(.caption.monospacedDigit())
            }
            ProgressView(value: available && value.isFinite ? min(1, max(0, value)) : 0).tint(tint).accessibilityLabel(title)
        }
    }
}

private struct DockMusicCard: View {
    @ObservedObject private var music = MusicManager.shared
    var body: some View {
        HStack(spacing: 12) {
            if !music.isPlayerIdle {
                Image(nsImage: music.albumArt).resizable().scaledToFill().frame(width: 56, height: 56)
                    .clipShape(RoundedRectangle(cornerRadius: 10)).accessibilityHidden(true)
            } else { Image(systemName: "music.note").font(.title).foregroundStyle(.secondary).frame(width: 40) }
            VStack(alignment: .leading, spacing: 5) {
                Text(music.isPlayerIdle ? "Not Playing" : music.songTitle).font(.headline).lineLimit(2)
                Text(music.isPlayerIdle ? "Start music in your favorite app." : music.artistName).font(.caption).foregroundStyle(.secondary).lineLimit(2)
            }
        }
    }
}

private struct DockWorkspaceDropDelegate<T: Equatable>: DropDelegate {
    let target: T
    @Binding var dragging: T?
    var reorder: (T, T) -> Void
    func validateDrop(info: DropInfo) -> Bool { dragging != nil }
    func dropEntered(info: DropInfo) {
        guard let dragging, dragging != target else { return }; reorder(dragging, target)
    }
    func dropUpdated(info: DropInfo) -> DropProposal? { .init(operation: .move) }
    func performDrop(info: DropInfo) -> Bool { dragging = nil; return true }
}

private extension UTType {
    static let dockWorkspacePin = UTType(exportedAs: "com.notchscape.dock.pin")
    static let dockWorkspaceWidget = UTType(exportedAs: "com.notchscape.dock.widget")
}
