import AppKit
import Defaults
import SwiftUI
import UniformTypeIdentifiers

/// Deterministic, horizontal presentation only. The controller owns provider
/// demand, saved instances, timers and the separate anchored card window.
struct DockReplacementView: View {
    @ObservedObject var controller: DockReplacementController
    let layout: DockReplacementBarLayout
    @ObservedObject private var performance = AppPerformanceManager.shared
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var hoverTarget = DockReplacementHoverTarget()
    @Default(.appTheme) private var appTheme
    @Default(.useCustomAccentColor) private var useCustomAccentColor
    @Default(.customAccentColorData) private var customAccentColorData

    private var allowsMagnification: Bool {
        !reduceMotion && !performance.suppressAnimations && !performance.lowImpact && controller.expandedWidgetID == nil
    }
    private var motion: Animation? {
        allowsMagnification ? .easeOut(duration: 0.12) : nil
    }

    var body: some View {
        DockReplacementPresentation(controller: controller, layout: layout,
            pointerX: hoverTarget.pointerX, presence: allowsMagnification ? hoverTarget.presence : 0)
            .animation(motion, value: hoverTarget)
            .frame(width: layout.frame.width, height: layout.frame.height)
            // Track the fixed reserved canvas, never the magnified icon bounds.
            .contentShape(Rectangle())
            .accentColor(Color.effectiveAccent).tint(Color.effectiveAccent)
            .accessibilityElement(children: .contain)
            .accessibilityLabel("Notchscape Dock")
            .onContinuousHover { phase in
                switch phase {
                case .active(let location):
                    guard allowsMagnification, location.x.isFinite, location.y.isFinite else {
                        if hoverTarget.presence != 0 { hoverTarget.presence = 0 }
                        return
                    }
                    let next = DockReplacementHoverTarget(pointerX: Double(location.x), presence: 1)
                    if hoverTarget != next { hoverTarget = next }
                case .ended:
                    // Keep the last finite coordinate. The shared kernel fades
                    // to rest without snapping to a nearest-icon index.
                    if hoverTarget.presence != 0 { hoverTarget.presence = 0 }
                }
            }
            .onChange(of: allowsMagnification) { _, allowed in
                if !allowed { hoverTarget.presence = 0 }
            }
            .onKeyPress(.escape) { controller.collapse(); return .handled }
    }
}

private struct DockReplacementHoverTarget: Equatable {
    var pointerX = 0.0
    var presence = 0.0
}

/// Interpolate one input before deriving the entire presentation. Independent
/// width/position animations can put neighboring icons on different trajectories.
private struct DockReplacementPresentation: View, Animatable {
    @ObservedObject var controller: DockReplacementController
    let layout: DockReplacementBarLayout
    nonisolated var pointerX: Double
    nonisolated var presence: Double
    @State private var draggingWidget: UUID?
    @Default(.dockReplacementOverflow) private var overflow

    nonisolated var animatableData: AnimatablePair<Double, Double> {
        // Weight the coordinate by presence: entering from zero reveals the
        // actual pointer location rather than sweeping from a stale position.
        get { .init(pointerX * presence, presence) }
        set {
            let rawPresence = newValue.second
            guard rawPresence.isFinite, rawPresence > 0, newValue.first.isFinite else {
                presence = 0
                return
            }
            let nextX = newValue.first / rawPresence
            guard nextX.isFinite else { presence = 0; return }
            pointerX = nextX
            presence = min(1, rawPresence)
        }
    }

    private var magnification: DockReplacementMagnification? {
        DockReplacementPolicy.magnification(in: layout,
            pointerX: presence > 0 ? pointerX : nil, presence: presence)
    }
    private var appFrames: [CGRect] {
        DockReplacementPolicy.appPresentationFrames(in: layout,
            pointerX: presence > 0 ? pointerX : nil, presence: presence)
    }
    private var contentShift: CGFloat { CGFloat(magnification?.totalExtra ?? 0) / 2 }
    private var surfaceWidth: CGFloat {
        layout.frame.width - CGFloat(layout.magnificationReserve) + CGFloat(magnification?.totalExtra ?? 0)
    }
    private var surfaceOriginX: CGFloat { (layout.frame.width - surfaceWidth) / 2 }

    var body: some View {
        let icons = appFrames
        ZStack(alignment: .topLeading) {
            controlPlane
                .frame(width: surfaceWidth, height: layout.surfaceHeight)
                .modifier(DockReplacementSurface(cornerRadius: 21))
                .position(x: layout.frame.width / 2,
                          y: layout.frame.height - CGFloat(layout.surfaceHeight) / 2)
            ForEach(Array(controller.apps.prefix(icons.count).enumerated()), id: \.element.id) { index, app in
                appButton(app, frame: icons[index])
                    .position(x: icons[index].midX, y: layout.frame.height - icons[index].midY)
            }
        }
        .frame(width: layout.frame.width, height: layout.frame.height)
        // The parent animates this View's input vector. Derived layout must be
        // applied as one sample, without another implicit animation per child.
        .transaction { $0.animation = nil }
    }

    private var controlPlane: some View {
        ZStack(alignment: .topLeading) {
            if let first = layout.widgetSlots.first, !layout.appSlots.isEmpty || layout.hiddenAppCount > 0 {
                Rectangle().fill(Color.primary.opacity(0.13)).frame(width: 1, height: 30)
                    .position(x: first.frame.minX - 8 + contentShift - surfaceOriginX,
                              y: CGFloat(layout.surfaceHeight) / 2)
                    .accessibilityHidden(true)
            }
            if let frame = layout.appOverflowButtonFrame {
                appOverflow.frame(width: frame.width, height: frame.height).position(center(of: frame))
            }
            ForEach(layout.widgetSlots, id: \.index) { slot in
                if controller.layout.widgets.indices.contains(slot.index) {
                    let instance = controller.layout.widgets[slot.index]
                    widgetButton(instance, frame: slot.frame).position(center(of: slot.frame))
                }
            }
            if let frame = layout.overflowButtonFrame {
                Group {
                    if overflow == "stack" { stackMenu }
                    else { pageButton }
                }.frame(width: frame.width, height: frame.height).position(center(of: frame))
            }
            gallery.frame(width: layout.galleryButtonFrame.width, height: layout.galleryButtonFrame.height)
                .position(center(of: layout.galleryButtonFrame))
        }
    }

    private func center(of frame: CGRect) -> CGPoint {
        .init(x: frame.midX + contentShift - surfaceOriginX,
              y: CGFloat(layout.surfaceHeight) - frame.midY)
    }

    private func appButton(_ app: DockReplacementApp, frame: CGRect) -> some View {
        let side = max(16, min(frame.width, frame.height))
        return Button { controller.openApp(app.id, origin: .appIcon) } label: {
            Image(nsImage: app.icon).resizable().interpolation(.high).scaledToFit()
                .frame(width: side, height: side)
                .accessibilityHidden(true)
                .overlay(alignment: .bottom) {
                    Circle().fill(app.isRunning ? Color.primary.opacity(0.6) : .clear)
                        .frame(width: 3, height: 3).offset(y: frame.minY - 3.5).accessibilityHidden(true)
                }
            .frame(width: frame.width, height: frame.height)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(app.title)
        .accessibilityLabel(app.title)
        .accessibilityValue((app.isPinned ? "Pinned, " : "") + (app.isRunning ? "running" : "not running"))
        .contextMenu {
            Button("Open \(app.title)") { controller.openApp(app.id, origin: .appMenu) }
            Divider()
            if app.isPinned {
                Button("Remove from Dock") { controller.removeApp(app.id) }
                Button("Move Earlier") { controller.moveApp(app.id, by: -1) }
                    .disabled(controller.apps.first(where: \.isPinned)?.id == app.id)
                Button("Move Later") { controller.moveApp(app.id, by: 1) }
                    .disabled(controller.apps.last(where: \.isPinned)?.id == app.id)
            } else {
                Button("Keep in Dock") { controller.keepApp(app.id) }.disabled(!controller.canAddApp)
            }
            Divider()
            Button("Dock Settings…") { controller.showSettings() }
        }
    }

    private func widgetButton(_ instance: DockReplacementWidgetInstance, frame: CGRect) -> some View {
        let snapshot = controller.snapshot(for: instance)
        return Button { controller.quickAction(instance.id, origin: .widgetButton) } label: {
            DockReplacementCompactFace(kind: instance.kind, snapshot: snapshot)
                .padding(.horizontal, 10).padding(.vertical, 6)
                .frame(width: frame.width, height: frame.height)
                .background(Color.primary.opacity(controller.expandedWidgetID == instance.id ? 0.10 : 0.045),
                            in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                .contentShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
        .buttonStyle(.plain)
        .highPriorityGesture(
            LongPressGesture(minimumDuration: 0.45).exclusively(before: TapGesture())
                .onEnded { result in
                    switch result {
                    case .first: controller.expand(instance.id)
                    case .second: controller.quickAction(instance.id, origin: .widgetTap)
                    }
                }
        )
        .onKeyPress(keys: [.return, .space], phases: .down) { press in
            if press.modifiers.contains(.option) { controller.expand(instance.id) }
            else { controller.quickAction(instance.id, origin: .widgetKeyboard) }
            return .handled
        }
        .help("\(instance.kind.dockTitle). Click for its action; hold for controls.")
        .accessibilityLabel(instance.kind.dockTitle)
        .accessibilityValue("\(snapshot.primary), \(snapshot.secondary)")
        .accessibilityHint("Press to act, or Option-Return to show controls. The contextual menu offers the same controls and ordering actions.")
        .contextMenu {
            Button("Show Controls") { controller.expand(instance.id) }
            if [.nowPlaying, .upNext, .timer].contains(instance.kind) {
                Button(instance.kind.dockQuickActionTitle) { controller.quickAction(instance.id, origin: .widgetMenu) }
            }
            Divider()
            Button("Move Earlier") { controller.moveWidget(instance.id, by: -1) }
                .disabled(controller.isLayoutReadOnly || controller.layout.widgets.first?.id == instance.id)
            Button("Move Later") { controller.moveWidget(instance.id, by: 1) }
                .disabled(controller.isLayoutReadOnly || controller.layout.widgets.last?.id == instance.id)
            Button("Add Another \(instance.kind.dockTitle)") { controller.addWidget(instance.kind) }
                .disabled(controller.isLayoutReadOnly || controller.layout.widgets.count >= 48)
            Divider()
            Button("Remove Widget", role: .destructive) { controller.removeWidget(instance.id) }.disabled(controller.isLayoutReadOnly)
        }
        .onDrag {
            guard !controller.isLayoutReadOnly else { return NSItemProvider() }
            draggingWidget = instance.id
            let provider = NSItemProvider()
            provider.registerDataRepresentation(forTypeIdentifier: UTType.notchscapeReplacementWidget.identifier,
                                                visibility: .ownProcess) { completion in
                completion(Data(instance.id.uuidString.utf8), nil); return nil
            }
            return provider
        }
        .onDrop(of: [.notchscapeReplacementWidget], delegate: DockReplacementDropDelegate(
            target: instance.id, dragging: $draggingWidget,
            reorder: { if !controller.isLayoutReadOnly { controller.reorderWidget($0, before: $1) } }))
    }

    @ViewBuilder private var gallery: some View {
        if controller.isLayoutReadOnly {
            Button { controller.showSettings() } label: {
                Image(systemName: "exclamationmark.circle").font(.system(size: 14, weight: .medium)).frame(width: 16, height: 16)
            }.notchGlassButton(circular: true)
                .help(controller.errorMessage ?? "Layout editing is unavailable. Review Dock Settings.")
                .accessibilityLabel("Review Dock Settings")
        } else {
        Menu {
            Section("Add Widget") {
                ForEach(DockReplacementWidgetKind.allCases, id: \.self) { kind in
                    Button(kind.dockTitle, systemImage: kind.dockSymbol) { controller.addWidget(kind) }
                        .disabled(controller.layout.widgets.count >= 48)
                }
            }
            Divider()
            Button("Add App…", systemImage: "plus.app") { controller.addApp() }.disabled(!controller.canAddApp)
            Button("Dock Settings…", systemImage: "slider.horizontal.3") { controller.showSettings() }
            Divider()
            Button("Turn Off Dock Bar") { controller.disable() }
        } label: {
            Label("Add to Dock", systemImage: "plus").labelStyle(.iconOnly).font(.system(size: 15, weight: .medium))
                .frame(width: 26, height: 26).contentShape(Circle())
        }
        .menuStyle(.borderlessButton).menuIndicator(.hidden)
        .help(controller.errorMessage ?? "Add a widget or app").accessibilityLabel("Add to Dock")
        }
    }

    private var appOverflow: some View {
        Menu {
            ForEach(Array(controller.apps.dropFirst(layout.appSlots.count))) { app in
                Button(app.title) { controller.openApp(app.id, origin: .appOverflowMenu) }
            }
            Divider()
            Button("Add App…") { controller.addApp() }.disabled(!controller.canAddApp)
        } label: {
            Image(systemName: "ellipsis").font(.system(size: 14, weight: .semibold))
                .frame(width: 26, height: 26)
        }
        .menuStyle(.borderlessButton).menuIndicator(.hidden)
        .help("\(layout.hiddenAppCount) more apps").accessibilityLabel("More apps")
    }

    private var pageButton: some View {
        Button { controller.setPage((layout.page + 1) % max(1, layout.pageCount)) } label: {
            VStack(spacing: 3) {
                Image(systemName: "chevron.right").font(.system(size: 12, weight: .semibold))
                Text("\(layout.page + 1)/\(layout.pageCount)").font(.system(size: 9, weight: .medium)).monospacedDigit()
            }.frame(width: 30, height: 42).contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .help("Next widget page")
        .accessibilityLabel("Next widget page")
        .accessibilityValue("Page \(layout.page + 1) of \(layout.pageCount)")
        .contextMenu {
            Button("Previous Page") { controller.setPage((layout.page + layout.pageCount - 1) % max(1, layout.pageCount)) }
            Button("Next Page") { controller.setPage((layout.page + 1) % max(1, layout.pageCount)) }
            Divider()
            ForEach(0..<max(1, layout.pageCount), id: \.self) { page in
                Button("Page \(page + 1)") { controller.setPage(page) }
            }
        }
    }

    private var stackMenu: some View {
        Menu {
            ForEach(DockReplacementPolicy.hiddenWidgetIndices(count: controller.layout.widgets.count,
                       visibleRange: layout.visibleWidgetRange), id: \.self) { index in
                let instance = controller.layout.widgets[index]
                Button("\(index + 1). \(instance.kind.title)", systemImage: instance.kind.symbol) {
                    controller.expand(instance.id)
                }
            }
        } label: {
            Label("More widgets", systemImage: "square.stack.3d.up").labelStyle(.iconOnly)
                .font(.system(size: 14, weight: .medium)).frame(width: 30, height: 42)
        }
        .menuStyle(.borderlessButton).menuIndicator(.hidden)
        .accessibilityLabel("More widgets")
        .help("Open widgets in the stack")
    }
}

private struct DockReplacementCompactFace: View {
    let kind: DockReplacementWidgetKind
    let snapshot: DockReplacementFaceSnapshot

    var body: some View {
        Group {
            switch kind {
            case .nowPlaying:
                HStack(spacing: 7) {
                    artwork(side: 40)
                    VStack(alignment: .leading, spacing: 3) {
                        Text(snapshot.primary).font(.system(size: 12, weight: .medium)).lineLimit(1)
                        Text(snapshot.secondary).font(.system(size: 10)).foregroundStyle(.secondary).lineLimit(1)
                    }
                    Spacer(minLength: 0)
                    Image(systemName: snapshot.isActive ? "pause.fill" : "play.fill")
                        .font(.system(size: 11, weight: .semibold)).foregroundStyle(.secondary)
                }
            case .upNext:
                VStack(alignment: .leading, spacing: 3) {
                    Label("Up Next", systemImage: "calendar").font(.system(size: 9, weight: .semibold)).foregroundStyle(.secondary)
                    Text(snapshot.primary).font(.system(size: 12, weight: .medium)).lineLimit(1)
                    Text(snapshot.secondary).font(.system(size: 10)).foregroundStyle(.secondary).lineLimit(1)
                }.frame(maxWidth: .infinity, alignment: .leading)
            case .battery:
                HStack(spacing: 7) {
                    Image(systemName: snapshot.symbol).font(.system(size: 20)).foregroundStyle(.green)
                    VStack(alignment: .leading, spacing: 3) {
                        Text(snapshot.primary).font(.system(size: 18, weight: .medium, design: .rounded)).monospacedDigit().lineLimit(1).minimumScaleFactor(0.7)
                        Text(snapshot.secondary).font(.system(size: 9)).foregroundStyle(.secondary).lineLimit(1)
                    }
                }.frame(maxWidth: .infinity, alignment: .leading)
            case .timer:
                HStack(spacing: 7) {
                    timerRing(side: 28)
                    VStack(alignment: .leading, spacing: 3) {
                        Text(snapshot.primary).font(.system(size: 18, weight: .medium, design: .rounded)).monospacedDigit().lineLimit(1).minimumScaleFactor(0.7)
                        Text(snapshot.secondary).font(.system(size: 9)).foregroundStyle(.secondary).lineLimit(1)
                    }
                }.frame(maxWidth: .infinity, alignment: .leading)
            case .clock:
                VStack(alignment: .leading, spacing: 3) {
                    Text(snapshot.primary).font(.system(size: 20, weight: .medium, design: .rounded)).monospacedDigit().lineLimit(1).minimumScaleFactor(0.7)
                    Text(snapshot.secondary).font(.system(size: 10)).foregroundStyle(.secondary).lineLimit(1)
                }.frame(maxWidth: .infinity, alignment: .leading)
            case .calculator:
                VStack(alignment: .trailing, spacing: 3) {
                    Label("Calculator", systemImage: "equal").font(.system(size: 9, weight: .medium)).foregroundStyle(.secondary)
                    Text(snapshot.primary).font(.system(size: 21, weight: .medium, design: .rounded)).monospacedDigit().lineLimit(1).minimumScaleFactor(0.6)
                }.frame(maxWidth: .infinity, alignment: .trailing)
            case .weather:
                HStack(spacing: 8) {
                    Image(systemName: snapshot.symbol).symbolRenderingMode(.multicolor)
                        .font(.system(size: 25)).frame(width: 30)
                    VStack(alignment: .leading, spacing: 3) {
                        Text(snapshot.primary).font(.system(size: 22, weight: .medium, design: .rounded))
                            .monospacedDigit().lineLimit(1).minimumScaleFactor(0.6)
                        Text(snapshot.secondary).font(.system(size: 10)).foregroundStyle(.secondary).lineLimit(1)
                    }
                }.frame(maxWidth: .infinity, alignment: .leading)
            case .system:
                VStack(spacing: 5) {
                    ForEach(snapshot.metrics.prefix(2)) { metric in
                        HStack(spacing: 5) {
                            Text(metric.title).font(.system(size: 9, weight: .medium))
                                .foregroundStyle(.secondary).lineLimit(1).frame(width: 42, alignment: .leading)
                            if let fraction = metric.fraction {
                                GeometryReader { geometry in
                                    Capsule().fill(Color.secondary.opacity(0.2))
                                        .overlay(alignment: .leading) {
                                            Capsule().fill(Color.effectiveAccent)
                                                .frame(width: geometry.size.width * fraction)
                                        }
                                }.frame(height: 3).accessibilityHidden(true)
                            } else {
                                Capsule().fill(Color.secondary.opacity(0.2)).frame(height: 3)
                            }
                            Text(metric.value).font(.system(size: 10, weight: .medium)).monospacedDigit()
                                .frame(width: 31, alignment: .trailing)
                        }
                    }
                }.frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .foregroundStyle(.primary)
        .accessibilityElement(children: .ignore)
    }

    @ViewBuilder private func artwork(side: CGFloat) -> some View {
        if let image = snapshot.artwork {
            Image(nsImage: image).resizable().scaledToFill().frame(width: side, height: side)
                .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
        } else {
            Image(systemName: "music.note").font(.system(size: side * 0.42)).foregroundStyle(.secondary)
                .frame(width: side, height: side)
                .background(Color.primary.opacity(0.07), in: RoundedRectangle(cornerRadius: 9, style: .continuous))
        }
    }

    private func timerRing(side: CGFloat) -> some View {
        ZStack {
            Circle().strokeBorder(Color.orange.opacity(0.18), lineWidth: 2.5)
            Circle().trim(from: 0, to: min(1, max(0, (snapshot.progress?.isFinite == true ? snapshot.progress : nil) ?? 0)))
                .stroke(Color.orange, style: StrokeStyle(lineWidth: 2.5, lineCap: .round)).rotationEffect(.degrees(-90))
            Image(systemName: snapshot.isActive ? "pause.fill" : "timer").font(.system(size: 11, weight: .medium)).foregroundStyle(.orange)
        }.frame(width: side, height: side)
    }
}

/// The main controller places this single card above its original tile in a
/// separate panel. Nothing here measures or resizes the baseline Dock.
struct DockReplacementExpandedCard: View {
    @ObservedObject var controller: DockReplacementController
    let instance: DockReplacementWidgetInstance
    @Default(.appTheme) private var appTheme
    @Default(.useCustomAccentColor) private var useCustomAccentColor
    @Default(.customAccentColorData) private var customAccentColorData
    private var widget: DockReplacementWidgetInstance { controller.layout.widgets.first { $0.id == instance.id } ?? instance }
    private var snapshot: DockReplacementFaceSnapshot { controller.snapshot(for: widget) }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Label(widget.kind.dockTitle, systemImage: widget.kind.dockSymbol).font(.headline)
                Spacer(minLength: 0)
                Button { controller.collapse() } label: {
                    Image(systemName: "xmark").font(.system(size: 11, weight: .semibold)).frame(width: 14, height: 14)
                }.notchGlassButton(circular: true).accessibilityLabel("Close \(widget.kind.dockTitle) controls")
            }
            ScrollView {
                Group {
                    switch widget.kind {
                    case .nowPlaying: nowPlaying
                    case .upNext: upNext
                    case .battery: battery
                    case .timer: timer
                    case .clock: clock
                    case .calculator: calculator
                    case .weather: weather
                    case .system: system
                    }
                }.frame(maxWidth: .infinity, alignment: .topLeading)
            }.scrollIndicators(.automatic)
        }
        .padding(16).frame(maxWidth: .infinity, maxHeight: .infinity)
        .modifier(DockReplacementSurface(cornerRadius: 24))
        .accentColor(Color.effectiveAccent).tint(Color.effectiveAccent)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("\(widget.kind.dockTitle) controls")
        .onKeyPress(.escape) { controller.collapse(); return .handled }
    }

    private var nowPlaying: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 12) {
                Group {
                    if let image = snapshot.artwork { Image(nsImage: image).resizable().scaledToFill() }
                    else { Image(systemName: "music.note").font(.title).foregroundStyle(.secondary) }
                }.frame(width: 62, height: 62).clipped()
                    .background(Color.primary.opacity(0.06), in: RoundedRectangle(cornerRadius: 14))
                    .clipShape(RoundedRectangle(cornerRadius: 14))
                VStack(alignment: .leading, spacing: 5) {
                    Text(snapshot.primary).font(.headline).lineLimit(2)
                    Text(snapshot.secondary).font(.callout).foregroundStyle(.secondary).lineLimit(2)
                }
            }
            if let progress = snapshot.progress, progress.isFinite { ProgressView(value: min(1, max(0, progress))).accessibilityLabel("Playback progress") }
            NotchGlassControlGroup {
                HStack(spacing: 16) {
                    Spacer(minLength: 0)
                    playbackButton("Previous Track", symbol: "backward.end.fill", action: "previous")
                    playbackButton(snapshot.isActive ? "Pause" : "Play", symbol: snapshot.isActive ? "pause.fill" : "play.fill", action: "toggle", prominent: true)
                    playbackButton("Next Track", symbol: "forward.end.fill", action: "next")
                    Spacer(minLength: 0)
                }
            }
        }
    }

    private func playbackButton(_ title: String, symbol: String, action: String, prominent: Bool = false) -> some View {
        Button { controller.mediaAction(action) } label: {
            Image(systemName: symbol).font(.system(size: 14, weight: .semibold)).frame(width: 16, height: 16)
        }.notchGlassButton(prominent: prominent, circular: true, diameter: prominent ? 40 : 32)
            .accessibilityLabel(title).help(title)
    }

    private var upNext: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(snapshot.primary).font(.title3.weight(.semibold)).lineLimit(3)
            Text(snapshot.secondary).font(.callout).foregroundStyle(.secondary).lineLimit(3)
            Spacer(minLength: 0)
            Button("Open Calendar…", systemImage: "calendar") { controller.quickAction(widget.id, origin: .expandedControl) }.notchGlassButton()
        }
    }

    private var battery: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text(snapshot.primary).font(.system(size: 46, weight: .medium, design: .rounded)).monospacedDigit().lineLimit(1)
                Spacer()
                Image(systemName: snapshot.symbol).font(.system(size: 35)).foregroundStyle(.green)
            }
            if let progress = snapshot.progress, progress.isFinite { ProgressView(value: min(1, max(0, progress))).tint(.green).accessibilityLabel("Battery level") }
            Text(snapshot.secondary).font(.callout).foregroundStyle(.secondary)
        }
    }

    private var timer: some View {
        VStack(spacing: 16) {
            Text(snapshot.primary).font(.system(size: 42, weight: .medium, design: .rounded)).monospacedDigit()
                .frame(maxWidth: .infinity)
            Text(snapshot.secondary).font(.callout).foregroundStyle(.secondary)
            NotchGlassControlGroup {
                HStack(spacing: 12) {
                    Menu {
                        ForEach([60.0, 300, 900, 1500, 3600], id: \.self) { duration in
                            Button(durationLabel(duration)) { controller.setTimerDuration(widget.id, seconds: duration) }
                        }
                    } label: { Label(durationLabel(widget.timerDuration), systemImage: "timer") }
                        .menuStyle(.borderlessButton).frame(width: 118, height: 30)
                        .accessibilityLabel("Timer duration").disabled(controller.isLayoutReadOnly)
                    Button(snapshot.isActive ? "Pause" : "Start", systemImage: snapshot.isActive ? "pause.fill" : "play.fill") {
                        controller.quickAction(widget.id, origin: .expandedControl)
                    }.notchGlassButton(prominent: true)
                }
            }
        }.frame(maxWidth: .infinity)
    }

    private var clock: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(snapshot.primary).font(.system(size: 44, weight: .medium, design: .rounded)).monospacedDigit().lineLimit(1).minimumScaleFactor(0.7)
            Text(snapshot.secondary).font(.callout).foregroundStyle(.secondary)
            Spacer(minLength: 0)
            Picker("Time Zone", selection: Binding(get: { widget.timeZoneIdentifier ?? "" }, set: {
                controller.setClockTimeZone(widget.id, identifier: $0.isEmpty ? nil : $0)
            })) {
                Text("System Time").tag("")
                ForEach(clockZones, id: \.0) { zone in Text(zone.1).tag(zone.0) }
            }.pickerStyle(.menu).disabled(controller.isLayoutReadOnly)
        }
    }

    private var calculator: some View {
        VStack(spacing: 7) {
            Text(snapshot.primary).font(.system(size: 25, weight: .medium, design: .rounded)).monospacedDigit()
                .lineLimit(1).minimumScaleFactor(0.5).frame(maxWidth: .infinity, alignment: .trailing)
                .accessibilityLabel("Calculator result: \(snapshot.primary)")
            VStack(spacing: 4) {
                ForEach(Array(calculatorRows.enumerated()), id: \.offset) { _, row in
                    HStack(spacing: 5) {
                        ForEach(row, id: \.key) { key in
                            Button(key.label) { controller.calculatorInput(widget.id, key: key.key) }
                                .notchGlassButton(prominent: key.key == "=")
                                .frame(maxWidth: .infinity, minHeight: 25)
                                .accessibilityLabel(key.accessibility)
                        }
                    }
                }
            }.controlSize(.small)
        }
        .onKeyPress(characters: CharacterSet(charactersIn: "0123456789.+-*/()="), phases: .down) { press in
            controller.calculatorInput(widget.id, key: press.characters); return .handled
        }
        .onKeyPress(.delete) { controller.calculatorInput(widget.id, key: "backspace"); return .handled }
        .onKeyPress(.return) { controller.calculatorInput(widget.id, key: "="); return .handled }
    }

    private var weather: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                Image(systemName: snapshot.symbol).symbolRenderingMode(.multicolor).font(.system(size: 38))
                VStack(alignment: .leading, spacing: 4) {
                    Text(snapshot.primary).font(snapshot.primary.contains("°")
                        ? .system(size: 40, weight: .medium, design: .rounded) : .title2.weight(.semibold))
                        .monospacedDigit().lineLimit(1).minimumScaleFactor(0.6)
                    Text(snapshot.secondary).font(.callout).foregroundStyle(.secondary).lineLimit(2)
                }
            }
            ForEach(Array(snapshot.details.enumerated()), id: \.offset) { _, detail in
                Text(detail).font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
            Button("Weather Settings…", systemImage: "slider.horizontal.3") { controller.openWeatherSettings() }
                .notchGlassButton()
        }
    }

    private var system: some View {
        VStack(alignment: .leading, spacing: 14) {
            ForEach(snapshot.metrics) { metric in
                VStack(spacing: 5) {
                    HStack {
                        Text(metric.title).foregroundStyle(.secondary)
                        Spacer(minLength: 8)
                        Text(metric.value).monospacedDigit()
                    }.font(.callout)
                    if let fraction = metric.fraction {
                        ProgressView(value: fraction).tint(Color.effectiveAccent)
                            .accessibilityLabel("\(metric.title) usage")
                    }
                }
            }
            Button("Open Activity Monitor…", systemImage: "waveform.path.ecg") { controller.openActivityMonitor() }
                .notchGlassButton()
        }
    }

    private var clockZones: [(String, String)] {
        [("America/New_York", "New York"), ("America/Chicago", "Chicago"),
         ("America/Denver", "Denver"), ("America/Los_Angeles", "Los Angeles"),
         ("Europe/London", "London"), ("Asia/Tokyo", "Tokyo")]
    }
    private func durationLabel(_ seconds: Double) -> String { "\(Int(seconds / 60)) min" }
    private var calculatorRows: [[DockCalculatorKey]] {
        [[.init("AC", "clear", "Clear"), .init("⌫", "backspace", "Delete last digit"), .init("(", "(", "Open parenthesis"), .init(")", ")", "Close parenthesis")],
         [.init("7"), .init("8"), .init("9"), .init("÷", "/", "Divide")],
         [.init("4"), .init("5"), .init("6"), .init("×", "*", "Multiply")],
         [.init("1"), .init("2"), .init("3"), .init("−", "-", "Subtract")],
         [.init("0"), .init("."), .init("=", "=", "Equals"), .init("+", "+", "Add")]]
    }
}

private struct DockCalculatorKey {
    let label: String
    let key: String
    let accessibility: String
    init(_ label: String, _ key: String? = nil, _ accessibility: String? = nil) {
        self.label = label; self.key = key ?? label; self.accessibility = accessibility ?? label
    }
}

private struct DockReplacementSurface: ViewModifier {
    let cornerRadius: CGFloat
    @ObservedObject private var performance = AppPerformanceManager.shared
    @Environment(\.colorSchemeContrast) private var contrast
    @ViewBuilder func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        if performance.reduceTransparency || performance.lowImpact || contrast == .increased {
            content.background(Color(nsColor: .windowBackgroundColor), in: shape)
                .overlay { shape.strokeBorder(Color.primary.opacity(contrast == .increased ? 0.5 : 0.12), lineWidth: contrast == .increased ? 1 : 0.5) }
        } else if #available(macOS 26.0, *) {
            content.glassEffect(.regular, in: shape)
        } else {
            content.background(.regularMaterial, in: shape)
        }
    }
}

private extension DockReplacementWidgetKind {
    var dockTitle: String { title }
    var dockSymbol: String {
        switch self {
        case .nowPlaying: "music.note"
        case .upNext: "calendar"
        case .battery: "battery.100percent"
        case .timer: "timer"
        case .clock: "clock"
        case .calculator: "equal"
        case .weather, .system: symbol
        }
    }
    var dockQuickActionTitle: String {
        switch self {
        case .nowPlaying: "Play or Pause"
        case .upNext: "Open Calendar…"
        case .timer: "Start or Pause Timer"
        default: "Show Controls"
        }
    }
}

private struct DockReplacementDropDelegate: DropDelegate {
    let target: UUID
    @Binding var dragging: UUID?
    var reorder: (UUID, UUID) -> Void
    func validateDrop(info: DropInfo) -> Bool { dragging != nil }
    func dropEntered(info: DropInfo) {
        guard let dragging, dragging != target else { return }; reorder(dragging, target)
    }
    func dropUpdated(info: DropInfo) -> DropProposal? { .init(operation: .move) }
    func performDrop(info: DropInfo) -> Bool { dragging = nil; return true }
}

private extension UTType {
    static let notchscapeReplacementWidget = UTType(exportedAs: "com.notchscape.dock.replacement.widget")
}
