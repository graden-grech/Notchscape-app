import Defaults
import SwiftUI

/// Desktop decoration is independent of menu themes and starts only by choice.
struct DesktopSnowSettings: View {
    @ObservedObject private var snow = DesktopSnowManager.shared
    @Default(.desktopSnowSeason) private var seasonID
    @Default(.desktopSnowPointerSweep) private var pointerSweep
    @Default(.desktopSnowPileLayouts) private var pileLayouts
    @Default(.desktopSnowMatchWallpaper) private var matchWallpaper
    @Default(.desktopSnowWallpaperSelections) private var wallpaperSelections
    @ObservedObject private var wallpapers = NotchWallpaperManager.shared
    @State private var showsSceneEditor = false
    @State private var showsPreview = false
    @State private var showsPileEditor = false
    private var season: DesktopSnowSeason { DesktopSnowSeason(rawValue: seasonID) ?? .winterDawn }

    @Default(.desktopSnowEnabled) private var enabled
    @Default(.desktopSnowIntensity) private var intensity
    @Default(.desktopSnowSpeed) private var speed
    @Default(.desktopSnowWind) private var wind
    @Default(.desktopSnowAccumulation) private var accumulation
    @Default(.desktopSnowWindowEdges) private var windowEdges
    @Default(.desktopSnowAllDisplays) private var allDisplays
    @Default(.desktopSnowHomeWidgets) private var homeWidgets
    @Default(.desktopSnowMoundHeight) private var moundHeight
    @Default(.desktopSnowMoundWidth) private var moundWidth
    @Default(.desktopSnowMoundSpacing) private var moundSpacing

    var body: some View {
        Section {
            Toggle(isOn: $enabled) {
                Label(season.isSnow ? "Let it snow" : "Show desktop weather", systemImage: season.isSnow ? "snowflake" : "cloud.sun")
            }
            Picker("Season", selection: Binding(get: { seasonID }, set: selectSeason)) {
                ForEach(DesktopSnowSeason.allCases) { choice in Text(choice.title).tag(choice.rawValue) }
            }
            HStack {
                Button("Preview…") { showsPreview = true }.notchGlassButton()
                Spacer()
                Button("Arrange scenery…") { showsSceneEditor = true }.notchGlassButton()
            }
            wallpaperControls

            if enabled {
                Text(snow.statusText).font(.caption).foregroundStyle(.secondary)
                LabeledContent(season.isSnow ? "Snowfall" : "Amount") {
                    Slider(value: $intensity, in: 0.15...1)
                        .frame(width: 170).accessibilityLabel("Snowfall amount")
                    Text(intensity < 0.4 ? "Light" : intensity < 0.75 ? "Steady" : "Heavy")
                        .font(.callout).foregroundStyle(.secondary).frame(width: 52, alignment: .trailing)
                }
                if season.canSettle {
                    Toggle(season.isSnow ? "Let snow settle" : "Let piles form", isOn: $accumulation)
                    if season.isSnow { Toggle("Snow on Home widgets", isOn: $homeWidgets) }
                    Toggle("Settle on windows, the Dock and desktop widgets", isOn: $windowEdges)
                        .disabled(!accumulation)
                    Toggle("Sweep piles with the pointer", isOn: $pointerSweep).disabled(!accumulation)
                    Text("Sweep near a pile to scatter it while clicks still pass through. Buildup can fall from moving windows onto surfaces below.")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }

            if season.canSettle {
                DisclosureGroup(season == .mapleAir ? "Leaf piles" : "Pile shape and buildup") {
                    Button("Arrange Bottom Piles…", systemImage: "slider.horizontal.3") {
                        showsPileEditor = true
                    }.notchGlassButton()
                    Text("Set the bottom buildup limit and base depth, or place individual piles.")
                        .font(.caption).foregroundStyle(.secondary)
                    LabeledContent("Automatic pile height") {
                        Slider(value: $moundHeight, in: 0.4...2)
                            .frame(width: 180).accessibilityLabel("Automatic pile height")
                        Text(moundHeight < 0.75 ? "Low" : moundHeight > 1.5 ? "Tall" : "Natural")
                            .font(.callout).foregroundStyle(.secondary).frame(width: 54, alignment: .trailing)
                    }
                    LabeledContent("Automatic pile width") {
                        Slider(value: $moundWidth, in: 0.5...2)
                            .frame(width: 180).accessibilityLabel("Automatic pile width")
                        Text(moundWidth < 0.8 ? "Narrow" : moundWidth > 1.5 ? "Wide" : "Natural")
                            .font(.callout).foregroundStyle(.secondary).frame(width: 54, alignment: .trailing)
                    }
                    LabeledContent("Automatic pile spacing") {
                        Slider(value: $moundSpacing, in: 0.5...2)
                            .frame(width: 180).accessibilityLabel("Automatic pile spacing")
                        Text(moundSpacing < 0.8 ? "Closer" : moundSpacing > 1.5 ? "Farther" : "Natural")
                            .font(.callout).foregroundStyle(.secondary).frame(width: 54, alignment: .trailing)
                    }
                    HStack {
                        Button("Reset pile style", systemImage: "arrow.counterclockwise") {
                            snow.resetMoundStyle()
                        }
                        .notchGlassButton()
                        Spacer()
                        Button(snow.isEditing ? "Finish editing" : "Brush Settled Piles…", systemImage: snow.isEditing ? "checkmark" : "hand.draw") {
                            if snow.isEditing { snow.endEditing() }
                            else { snow.beginEditing() }
                        }
                        .notchGlassButton()
                        .disabled(!snow.isEditing && (!snow.isRunning || !accumulation))
                    }
                }
            }

            if enabled {
                DisclosureGroup("Weather options") {
                    LabeledContent("Fall speed") {
                        Slider(value: $speed, in: 0.5...1.8)
                            .frame(width: 180).accessibilityLabel("Snowfall speed")
                    }
                    LabeledContent("Breeze") {
                        Slider(value: $wind, in: -1...1)
                            .frame(width: 180).accessibilityLabel("Snowfall breeze")
                    }
                    Toggle("Show on all enabled displays", isOn: $allDisplays)
                }
                HStack {
                    Button("Clear Settled Buildup", systemImage: "wind") {
                        DesktopSnowManager.shared.clearSnow()
                    }.notchGlassButton().disabled(!season.canSettle)
                    Spacer()
                    Button(season.isSnow ? "Stop snow" : "Stop weather", systemImage: "snowflake.slash") { enabled = false }
                        .notchGlassButton()
                }
            }
        } header: {
            Text("Desktop Snow & Seasons")
        } footer: {
            Text("Clicks pass through during normal use. The effect pauses on lock, sleep, Presentation mode and Reduce Motion.")
        }
        .sheet(isPresented: $showsSceneEditor) { DesktopSnowSceneryEditor(theme: seasonID) }
        .sheet(isPresented: $showsPreview) {
            DesktopSnowSeasonPreview(season: season, amount: intensity, speed: speed, wind: wind)
        }
        .sheet(isPresented: $showsPileEditor) {
            let current = season
            DesktopSnowPileEditor(season: current, layout: pileLayouts[current.rawValue] ?? .init()) {
                pileLayouts[current.rawValue] = $0
            }
        }
    }

    private var wallpaperControls: some View {
        DisclosureGroup("Mac Desktop Wallpaper") {
            if let wallpaper = selectedWallpaper(for: season) {
                Picker("Wallpaper", selection: Binding(get: { wallpaper.id }, set: selectWallpaper)) {
                    ForEach(season.wallpapers) { Text($0.name).tag($0.id) }
                }
                WallpaperThumbnail(url: wallpaper.previewURL)
                    .frame(height: 112)
                    .clipShape(.rect(cornerRadius: 10))
                    .accessibilityLabel(wallpaper.name)
                if let attribution = wallpaper.attribution {
                    Link(attribution.credit, destination: attribution.pageURL)
                        .font(.caption)
                }
                Toggle("Change wallpaper with the season", isOn: Binding(get: { matchWallpaper }, set: setWallpaperMatching))
                Text("Applies to your Mac desktop using the display selected in Wallpapers.")
                    .font(.caption).foregroundStyle(.secondary)
                HStack {
                    Button("Apply Wallpaper") { wallpapers.apply(wallpaper) }.disabled(wallpapers.busy)
                    if wallpapers.canUndo { Button("Undo Wallpaper Change") { wallpapers.undo() }.disabled(wallpapers.busy) }
                }
                if let status = wallpapers.status { Text(status).font(.caption).foregroundStyle(.secondary) }
            }
        }
    }

    private func selectedWallpaper(for season: DesktopSnowSeason) -> Wallpaper? {
        let choices = season.wallpapers
        return choices.first { $0.id == wallpaperSelections[season.rawValue] } ?? choices.first
    }

    private func selectSeason(_ id: String) {
        guard seasonID != id, let choice = DesktopSnowSeason(rawValue: id) else { return }
        seasonID = id
        if matchWallpaper, let wallpaper = selectedWallpaper(for: choice) { wallpapers.applySeasonal(wallpaper) }
    }

    private func selectWallpaper(_ id: String) {
        guard let wallpaper = season.wallpapers.first(where: { $0.id == id }) else { return }
        wallpaperSelections[season.rawValue] = id
        if matchWallpaper { wallpapers.applySeasonal(wallpaper) }
    }

    private func setWallpaperMatching(_ enabled: Bool) {
        matchWallpaper = enabled
        if !enabled { wallpapers.cancelSeasonalWallpaper() }
        else if let wallpaper = selectedWallpaper(for: season) { wallpapers.applySeasonal(wallpaper) }
    }
}

private struct DesktopSnowPileEditor: View {
    let season: DesktopSnowSeason
    let save: (DesktopSnowPileLayout) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var layout: DesktopSnowPileLayout
    @State private var selected = 0

    init(season: DesktopSnowSeason, layout: DesktopSnowPileLayout, save: @escaping (DesktopSnowPileLayout) -> Void) {
        self.season = season
        self.save = save
        var options = DesktopSnowOptions()
        layout.apply(to: &options)
        let bounded = options.bounded
        _layout = State(initialValue: .init(limit: bounded.bottomLimit, baseDepth: bounded.baseDepth,
                                           placed: bounded.customBottomLayout, mounds: bounded.authoredMounds))
    }

    private var availableHeight: Double { max(0, layout.limit - layout.baseDepth) }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Bottom Piles").font(.title2.bold())
                Text(season.title).foregroundStyle(.secondary)
            }
            preview.frame(height: 152)
            ScrollView {
                VStack(alignment: .leading, spacing: 10) {
                    Picker("Placement", selection: $layout.placed) {
                        Text("Automatic").tag(false)
                        Text("Place Piles").tag(true)
                    }.pickerStyle(.segmented)
                    pointSlider("Maximum buildup", value: Binding(get: { layout.limit }, set: {
                        layout.limit = $0
                        layout.baseDepth = min(layout.baseDepth, $0)
                    }), upperBound: DesktopSnowPolicy.maximumBottomLimit)
                    pointSlider("Base layer", value: $layout.baseDepth, upperBound: min(layout.limit, DesktopSnowPolicy.maximumBaseDepth))
                    if layout.placed {
                        HStack {
                            Button("Add Pile", systemImage: "plus", action: addPile)
                                .disabled(layout.mounds.count >= DesktopSnowPolicy.maximumAuthoredMounds || availableHeight == 0)
                            Spacer()
                            Button("Remove Pile", systemImage: "minus", action: removePile)
                                .disabled(!layout.mounds.indices.contains(selected))
                        }
                        if let mound = layout.mounds.indices.contains(selected) ? selected : nil {
                            Picker("Selected pile", selection: $selected) {
                                ForEach(layout.mounds.indices, id: \.self) { Text("Pile \($0 + 1)").tag($0) }
                            }
                            percentSlider("Position from left", value: moundValue(\.center, at: mound), range: 0...1)
                            percentSlider("Width", value: moundValue(\.width, at: mound, range: 0.01...1), range: 0.01...1)
                            pointSlider("Height above base", value: moundValue(\.height, at: mound, range: 0...availableHeight), upperBound: availableHeight)
                        } else {
                            Text(availableHeight == 0 ? "Raise maximum buildup or lower the base to make room for piles."
                                 : "Add a pile and drag its handle, or set its position and height with the sliders.")
                                .font(.callout).foregroundStyle(.secondary)
                        }
                    } else {
                        Text("Falling particles build up naturally to the maximum. A base of 0 pt leaves the screen edge clear until they settle.")
                            .font(.callout).foregroundStyle(.secondary)
                    }
                }
                .padding(12)
                .background(.quaternary.opacity(0.35), in: .rect(cornerRadius: 12))
            }
            .scrollBounceBehavior(.basedOnSize)
            HStack {
                Button("Reset") { layout = .init(); selected = 0 }
                Spacer()
                Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction)
                Button("Apply") { save(layout); dismiss() }.keyboardShortcut(.defaultAction)
                    .buttonStyle(.borderedProminent)
            }
        }
        .padding(20)
        .frame(width: 530, height: 550)
    }

    private var preview: some View {
        GeometryReader { geometry in
            let size = geometry.size
            let inset: CGFloat = 15
            let width = max(1, size.width - inset * 2)
            let baseline = size.height - 15
            ZStack(alignment: .topLeading) {
                LinearGradient(colors: season.previewColors, startPoint: .top, endPoint: .bottom)
                Canvas { context, _ in
                    var options = DesktopSnowOptions()
                    layout.apply(to: &options)
                    let bank = DesktopSnowBank(surface: .init(id: 1, kind: .bottom, left: 0, right: width, y: 0),
                        heights: Array(repeating: layout.placed ? 0 : layout.limit * 0.3, count: max(1, Int(width / 12))))
                    let mounds = DesktopSnowPolicy.moundSilhouettes(for: bank, options: options)
                    let transform = CGAffineTransform(a: 1, b: 0, c: 0, d: -1, tx: inset, ty: baseline)
                    let path = Path(DesktopSnowMound.filledPath(for: mounds)).applying(transform)
                    context.fill(path, with: .color(Color(nsColor: season.bankTint)))
                    let edge = Path { path in
                        path.move(to: CGPoint(x: inset, y: baseline))
                        path.addLine(to: CGPoint(x: inset + width, y: baseline))
                    }
                    context.stroke(edge, with: .color(.white.opacity(0.48)), lineWidth: 1)
                }.accessibilityHidden(true)
                if layout.placed {
                    ForEach(layout.mounds.indices, id: \.self) { index in
                        let mound = layout.mounds[index]
                        Image(systemName: "circle.circle.fill")
                            .font(.system(size: 16))
                            .foregroundStyle(index == selected ? Color.accentColor : .white, .black.opacity(0.68))
                            .frame(width: 28, height: 28)
                            .contentShape(Rectangle())
                            .onTapGesture { selected = index }
                            .gesture(DragGesture(coordinateSpace: .named("pilePreview")).onChanged { value in
                                guard layout.mounds.indices.contains(index) else { return }
                                selected = index
                                layout.mounds[index].center = min(1, max(0, (value.location.x - inset) / width))
                                layout.mounds[index].height = min(availableHeight, max(0, baseline - value.location.y - layout.baseDepth))
                            })
                            .accessibilityHidden(true)
                            .position(x: inset + mound.center * width,
                                      y: baseline - layout.baseDepth - min(mound.height, availableHeight))
                    }
                }
            }
            .coordinateSpace(name: "pilePreview")
            .clipShape(.rect(cornerRadius: 12))
        }
    }

    private func moundValue(_ key: WritableKeyPath<DesktopSnowAuthoredMound, Double>, at index: Int,
                            range: ClosedRange<Double> = 0...1) -> Binding<Double> {
        Binding(get: {
            guard layout.mounds.indices.contains(index) else { return range.lowerBound }
            return min(range.upperBound, max(range.lowerBound, layout.mounds[index][keyPath: key]))
        }, set: { value in
            guard layout.mounds.indices.contains(index) else { return }
            layout.mounds[index][keyPath: key] = value
        })
    }

    private func pointSlider(_ title: String, value: Binding<Double>, upperBound: Double) -> some View {
        let detail = "\(Int(value.wrappedValue.rounded())) pt"
        return HStack {
            sliderTitle(title)
            Slider(value: Binding(get: { value.wrappedValue }, set: { value.wrappedValue = $0.rounded() }), in: 0...max(1, upperBound))
                .accessibilityLabel(title).accessibilityValue(detail).disabled(upperBound < 1)
            Text(detail)
                .monospacedDigit().foregroundStyle(.secondary).frame(width: 50, alignment: .trailing)
                .accessibilityHidden(true)
        }
    }

    private func percentSlider(_ title: String, value: Binding<Double>, range: ClosedRange<Double>) -> some View {
        let detail = value.wrappedValue.formatted(.percent.precision(.fractionLength(0)))
        return HStack {
            sliderTitle(title)
            Slider(value: value, in: range).accessibilityLabel(title).accessibilityValue(detail)
            Text(detail)
                .monospacedDigit().foregroundStyle(.secondary).frame(width: 50, alignment: .trailing)
                .accessibilityHidden(true)
        }
    }

    private func sliderTitle(_ title: String) -> some View {
        Text(title).frame(width: 124, alignment: .leading).accessibilityHidden(true)
    }

    private func addPile() {
        let centers = ([0.5, 0.24, 0.76] + (1..<20).map { Double($0) / 20 })
        let center = centers.max { lhs, rhs in
            let a = layout.mounds.map { abs($0.center - lhs) }.min() ?? 1
            let b = layout.mounds.map { abs($0.center - rhs) }.min() ?? 1
            return a < b
        } ?? 0.5
        layout.mounds.append(.init(center: center, width: 0.14, height: min(16, availableHeight)))
        selected = layout.mounds.count - 1
    }

    private func removePile() {
        guard layout.mounds.indices.contains(selected) else { return }
        layout.mounds.remove(at: selected)
        selected = max(0, min(selected, layout.mounds.count - 1))
    }
}

private struct DesktopSnowSeasonPreview: View {
    let season: DesktopSnowSeason
    let amount: Double
    let speed: Double
    let wind: Double
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var start = Date()

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text(season.title).font(.title2.bold())
                Spacer()
                Button("Done") { dismiss() }.keyboardShortcut(.cancelAction)
            }
            TimelineView(.animation(minimumInterval: 1.0 / 15, paused: reduceMotion)) { timeline in
                Canvas { context, size in
                    let elapsed = reduceMotion ? 0 : timeline.date.timeIntervalSince(start)
                    let count = Int(12 + 44 * DesktopSnowPolicy.clamp(amount, 0...1, fallback: 0.5))
                    for index in 0..<count {
                        let phase = Double(index)
                        let fall = (25 + phase.truncatingRemainder(dividingBy: 19)) * speed * season.speedMultiplier
                        let y = positiveRemainder(phase * 47 + elapsed * fall, size.height)
                        let x = positiveRemainder(phase * 87 + elapsed * wind * 40 + sin(y / 45 + phase) * 8, size.width)
                        let diameter = 2 + phase.truncatingRemainder(dividingBy: 4)
                        let rect = CGRect(x: x, y: y, width: season.canSettle ? diameter : 1.5, height: season.canSettle ? diameter : diameter * 3)
                        context.fill(Path(season.particlePath(in: rect, variant: index)), with: .color(Color(nsColor: season.tint(variant: index)).opacity(0.88)))
                    }
                }
            }
            .background(LinearGradient(colors: season.previewColors, startPoint: .top, endPoint: .bottom), in: .rect(cornerRadius: 14))
            .clipShape(.rect(cornerRadius: 14))
            .accessibilityLabel("Preview of \(season.title)")
            Text("Preview the weather here before turning it on for your desktop.").foregroundStyle(.secondary)
        }
        .padding(20)
        .frame(width: 450, height: 290)
    }

    private func positiveRemainder(_ value: Double, _ divisor: Double) -> Double {
        guard value.isFinite, divisor > 0 else { return 0 }
        let remainder = value.truncatingRemainder(dividingBy: divisor)
        return remainder < 0 ? remainder + divisor : remainder
    }
}

/// Compact native control palette for the transient desktop snow editor.
/// The desktop surface itself is hosted by the manager and remains click-through
/// whenever edit mode is not active.
struct DesktopSnowEditorToolbar: View {
    @ObservedObject var snow: DesktopSnowManager

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Image(systemName: "snowflake")
                    .font(.headline)
                    .foregroundStyle(.tint)
                Text("Edit Snow Piles")
                    .font(.headline)
                Spacer()
                Button("Done", systemImage: "checkmark") { snow.endEditing() }
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.cancelAction)
            }

            Picker("Brush", selection: $snow.editTool) {
                Text("Build").tag(DesktopSnowBrushTool.build)
                Text("Carve").tag(DesktopSnowBrushTool.carve)
                Text("Move").tag(DesktopSnowBrushTool.move)
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .accessibilityLabel("Snow brush")

            HStack(spacing: 10) {
                Image(systemName: "circle.dotted").foregroundStyle(.secondary)
                Slider(value: $snow.editBrushRadius, in: 12...90)
                    .accessibilityLabel("Snow brush size")
                Text("\(Int(snow.editBrushRadius.rounded())) pt")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
                    .frame(width: 42, alignment: .trailing)
            }

            HStack(spacing: 8) {
                Text("Edit mode captures the pointer. Done, Escape, app switch, or 2 minutes idle exits. Changes clear when snow stops or the app relaunches.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
                Button("Show canvas", systemImage: "viewfinder") { snow.focusEditingCanvas() }
                    .buttonStyle(.bordered)
            }
        }
        .padding(16)
        .frame(width: 420, height: 190, alignment: .topLeading)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Desktop snow editing controls")
    }
}
