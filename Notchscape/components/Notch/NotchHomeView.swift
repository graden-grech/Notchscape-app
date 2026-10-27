//
//  NotchHomeView.swift
//  Notchscape
//
//  Created by Hugo Persson on 2024-08-18.
//  Modified by Harsh Vardhan Goswami & Richard Kunkli & Mustafa Ramadan
//

import Combine
import Defaults
import SwiftUI
import UniformTypeIdentifiers

@MainActor
enum StarWarsArtworkAvailability {
    // Resolve once per launch, not on the music player's update timeline.
    static let vaderSceneAvailable = NSImage(named: "StarWarsVaderSceneBackdrop") != nil
}

/// Home and its previews use the same single panoramic artwork. No separate
/// portrait layer or online costume photo is composited over the scene.
struct HomeThemeScene: View {
    let theme: AppTheme
    let vaderArtwork: StarWarsCharacterArtwork
    var imageAlignment: Alignment = .center
    var preserveEntirePhoto: Bool = false
    var detailsOverride: Bool?
    @Default(.themeDetailsEnabled) private var detailsEnabled
    @ObservedObject private var performance = AppPerformanceManager.shared

    init(theme: AppTheme, vaderArtwork: StarWarsCharacterArtwork, imageAlignment: Alignment = .center, detailsOverride: Bool? = nil, preserveEntirePhoto: Bool = false) {
        self.theme = theme; self.vaderArtwork = vaderArtwork; self.imageAlignment = imageAlignment; self.detailsOverride = detailsOverride
        self.preserveEntirePhoto = preserveEntirePhoto
    }

    var body: some View {
        GeometryReader { geometry in
            if let style = theme.nativeSceneStyle {
                nativeScene(style)
                    .overlay(alignment: .bottomTrailing) {
                        if (detailsOverride ?? detailsEnabled) && !performance.lowImpact {
                            Image(systemName: style.symbol).font(.system(size: 22, weight: .ultraLight))
                                .foregroundStyle(.white.opacity(0.32)).padding(20)
                        }
                    }
            } else if let backdrop = theme.homeBackdrop(characterArtwork: vaderArtwork,
                characterArtworkAvailable: StarWarsArtworkAvailability.vaderSceneAvailable) {
                if preserveEntirePhoto {
                    Image(backdrop).resizable().scaledToFit()
                        .frame(width: geometry.size.width, height: geometry.size.height)
                        .background(.black)
                } else {
                    Image(backdrop).resizable().scaledToFill()
                        .frame(width: geometry.size.width, height: geometry.size.height,
                               alignment: theme.usesArchitecturalPhotoLayout ? .trailing : imageAlignment)
                        .clipped()
                }
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
        .transaction { if performance.suppressAnimations { $0.animation = nil; $0.disablesAnimations = true } }
    }

    /// Deterministic vector content: no random values, timers, videos, blur loops
    /// or image transfers. Keep detail to the right of Home's information tiles.
    private func nativeScene(_ style: NativeAppearanceStyle) -> some View {
        Canvas { context, size in
            let w = size.width, h = size.height
            let colors = style.sky.map { hex -> Color in
                let (r, g, b) = AppearanceRecipe.rgb(hex) ?? (0, 0, 0)
                return Color(red: Double(r)/255, green: Double(g)/255, blue: Double(b)/255)
            }
            context.fill(Path(CGRect(origin: .zero, size: size)), with: .linearGradient(Gradient(colors: colors),
                         startPoint: .zero, endPoint: CGPoint(x: w, y: h)))
            if style == .nightSky {
                for index in 0..<18 {
                    let x = w * (0.48 + CGFloat((index * 37) % 49) / 100)
                    let y = h * (0.10 + CGFloat((index * 19) % 48) / 100)
                    let radius: CGFloat = index % 3 == 0 ? 1.2 : 0.65
                    context.fill(Path(ellipseIn: CGRect(x: x, y: y, width: radius * 2, height: radius * 2)), with: .color(.white.opacity(0.5)))
                }
            }
            if [.nightSky, .summerCoast, .desertDusk].contains(style) {
                let diameter = min(h * 0.28, w * 0.07)
                context.fill(Path(ellipseIn: CGRect(x: w * 0.84, y: h * 0.18, width: diameter, height: diameter)),
                             with: .color((style == .nightSky ? Color.white : Color.orange).opacity(style == .nightSky ? 0.72 : 0.6)))
            }
            for layer in 0..<3 {
                let offset = CGFloat(layer) * h * 0.10
                var path = Path()
                path.move(to: CGPoint(x: 0, y: h * 0.76 + offset))
                path.addCurve(to: CGPoint(x: w, y: h * 0.64 + offset),
                              control1: CGPoint(x: w * 0.38, y: h * (style == .summerCoast ? 0.85 : 0.38) + offset),
                              control2: CGPoint(x: w * 0.70, y: h * 0.98 + offset))
                path.addLine(to: CGPoint(x: w, y: h)); path.addLine(to: CGPoint(x: 0, y: h)); path.closeSubpath()
                context.fill(path, with: .color(colors[layer % colors.count].opacity(0.78)))
                if style == .graphite || style == .summerCoast {
                    context.stroke(path, with: .color(.white.opacity(0.08)), lineWidth: 0.8)
                }
            }
            if style == .botanical || style == .springBloom {
                for index in 0..<5 {
                    var leaf = context
                    leaf.translateBy(x: w * (0.79 + CGFloat(index % 2) * 0.08), y: h * (0.26 + CGFloat(index) * 0.12))
                    leaf.rotate(by: .degrees(index % 2 == 0 ? -35 : 35))
                    leaf.fill(Path(ellipseIn: CGRect(x: -h * 0.12, y: -h * 0.045, width: h * 0.24, height: h * 0.09)),
                              with: .color((style == .springBloom ? Color.pink : Color.green).opacity(0.25)))
                }
            }
        }
    }
}

// MARK: - Music Player Components

struct MusicPlayerView: View {
    @EnvironmentObject var vm: NotchscapeViewModel
    let albumArtNamespace: Namespace.ID

    var body: some View {
        HStack {
            AlbumArtView(vm: vm, albumArtNamespace: albumArtNamespace).padding(.all, 5)
            MusicControlsView()
        }
    }
}

struct AlbumArtView: View {
    @ObservedObject private var performance = AppPerformanceManager.shared
    @ObservedObject var musicManager = MusicManager.shared
    @ObservedObject var vm: NotchscapeViewModel
    let albumArtNamespace: Namespace.ID

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            if Defaults[.lightingEffect] && !performance.lowImpact {
                albumArtBackground
            }
            albumArtButton
        }
    }

    private var albumArtBackground: some View {
        Image(nsImage: musicManager.albumArt)
            .resizable()
            .clipped()
            .clipShape(
                RoundedRectangle(
                    cornerRadius: Defaults[.cornerRadiusScaling]
                        ? MusicPlayerImageSizes.cornerRadiusInset.opened
                        : MusicPlayerImageSizes.cornerRadiusInset.closed)
            )
            .aspectRatio(1, contentMode: .fit)
            .scaleEffect(x: 1.3, y: 1.4)
            .rotationEffect(.degrees(92))
            .blur(radius: 40)
            .opacity(musicManager.isPlaying ? 0.5 : 0)
    }

    private var albumArtButton: some View {
        ZStack {
            Button {
                musicManager.openMusicApp()
            } label: {
                ZStack(alignment:.bottomTrailing) {
                    albumArtImage
                    appIconOverlay
                }
            }
            .buttonStyle(PlainButtonStyle())
            .scaleEffect(musicManager.isPlaying ? 1 : 0.85)
            
            albumArtDarkOverlay
        }
    }

    private var albumArtDarkOverlay: some View {
        Rectangle()
            .aspectRatio(1, contentMode: .fit)
            .foregroundColor(Color.black)
            .opacity(musicManager.isPlaying ? 0 : performance.lowImpact ? 0.25 : 0.8)
            .blur(radius: performance.lowImpact ? 0 : 50)
            .clipShape(RoundedRectangle(cornerRadius: MusicPlayerImageSizes.cornerRadiusInset.opened))
    }
                

    private var albumArtImage: some View {
        Image(nsImage: musicManager.albumArt)
            .resizable()
            .aspectRatio(1, contentMode: .fit)
            .matchedGeometryEffect(id: "albumArt", in: albumArtNamespace)
            .clipped()
            .clipShape(
                RoundedRectangle(
                    cornerRadius: Defaults[.cornerRadiusScaling]
                        ? MusicPlayerImageSizes.cornerRadiusInset.opened
                        : MusicPlayerImageSizes.cornerRadiusInset.closed)
            )
    }

    @ViewBuilder
    private var appIconOverlay: some View {
        if vm.notchState == .open && !musicManager.usingAppIconForArtwork {
            AppIcon(for: musicManager.bundleIdentifier ?? "com.apple.Music")
                .resizable()
                .aspectRatio(contentMode: .fill)
                .frame(width: 30, height: 30)
                .offset(x: 10, y: 10)
                .transition(.scale.combined(with: .opacity))
                .zIndex(2)
        }
    }
}

struct MusicControlsView: View {
    @ObservedObject private var performance = AppPerformanceManager.shared
    @ObservedObject var musicManager = MusicManager.shared
        @EnvironmentObject var vm: NotchscapeViewModel
        @ObservedObject var webcamManager = WebcamManager.shared
    @State private var sliderValue: Double = 0
    @State private var dragging: Bool = false
    @State private var lastDragged: Date = .distantPast
    @Default(.musicControlSlots) private var slotConfig
    @Default(.musicControlSlotLimit) private var slotLimit

    var body: some View {
        VStack(alignment: .leading) {
            songInfoAndSlider
            slotToolbar
        }
        .buttonStyle(PlainButtonStyle())
    }

    private var songInfoAndSlider: some View {
        GeometryReader { geo in
            VStack(alignment: .leading, spacing: 4) {
                songInfo(width: geo.size.width)
                musicSlider
            }
        }
        .padding(.top, 10)
        .padding(.leading, 5)
    }

    private func songInfo(width: CGFloat) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            MarqueeText(
                $musicManager.songTitle, font: .headline, nsFont: .headline, textColor: .white,
                frameWidth: width)
            MarqueeText(
                $musicManager.artistName,
                font: .headline,
                nsFont: .headline,
                textColor: Defaults[.playerColorTinting]
                    ? Color(nsColor: musicManager.avgColor)
                        .ensureMinimumBrightness(factor: 0.6) : .gray,
                frameWidth: width
            )
            .fontWeight(.medium)
            if Defaults[.enableLyrics] {
                TimelineView(.animation(minimumInterval: performance.mediaInterval, paused: !musicManager.isPlaying)) { timeline in
                    let currentElapsed: Double = {
                        guard musicManager.isPlaying else { return musicManager.elapsedTime }
                        let delta = timeline.date.timeIntervalSince(musicManager.timestampDate)
                        let progressed = musicManager.elapsedTime + (delta * musicManager.playbackRate)
                        return min(max(progressed, 0), musicManager.songDuration)
                    }()
                    let line: String = {
                        if musicManager.isFetchingLyrics { return "Loading lyrics…" }
                        if !musicManager.syncedLyrics.isEmpty {
                            return musicManager.lyricLine(at: currentElapsed)
                        }
                        let trimmed = musicManager.currentLyrics.trimmingCharacters(in: .whitespacesAndNewlines)
                        return trimmed.isEmpty ? "No lyrics found" : trimmed.replacingOccurrences(of: "\n", with: " ")
                    }()
                    let isPersian = line.unicodeScalars.contains { scalar in
                        let v = scalar.value
                        return v >= 0x0600 && v <= 0x06FF
                    }
                    MarqueeText(
                        .constant(line),
                        font: .subheadline,
                        nsFont: .subheadline,
                        textColor: musicManager.isFetchingLyrics ? .gray.opacity(0.7) : .gray,
                        frameWidth: width
                    )
                    .font(isPersian ? .custom("Vazirmatn-Regular", size: NSFont.preferredFont(forTextStyle: .subheadline).pointSize) : .subheadline)
                    .lineLimit(1)
                    .opacity(musicManager.isPlaying ? 1 : 0)
                    .transition(.opacity.combined(with: .move(edge: .top)))
                }
            }
        }
    }

    private var musicSlider: some View {
        TimelineView(.animation(minimumInterval: performance.mediaInterval, paused: !musicManager.isPlaying || musicManager.playbackRate <= 0)) { timeline in
            MusicSliderView(
                sliderValue: $sliderValue,
                duration: $musicManager.songDuration,
                lastDragged: $lastDragged,
                color: musicManager.avgColor,
                dragging: $dragging,
                currentDate: timeline.date,
                timestampDate: musicManager.timestampDate,
                elapsedTime: musicManager.elapsedTime,
                playbackRate: musicManager.playbackRate,
                isPlaying: musicManager.isPlaying
            ) { newValue in
                MusicManager.shared.seek(to: newValue)
            }
            .padding(.top, 5)
            .frame(height: 36)
        }
    }

    private var slotToolbar: some View {
        let slots = activeSlots
        return HStack(spacing: 6) {
            ForEach(Array(slots.enumerated()), id: \.offset) { index, slot in
                slotView(for: slot)
                    .frame(alignment: .center)
            }
        }
        .frame(maxWidth: .infinity, alignment: .center)
    }

    private var activeSlots: [MusicControlButton] {
        let sanitizedLimit = min(
            max(slotLimit, MusicControlButton.minSlotCount),
            MusicControlButton.maxSlotCount
        )
        let padded = slotConfig.padded(to: sanitizedLimit, filler: .none)
        let result = Array(padded.prefix(sanitizedLimit))
        // If calendar and camera are both visible alongside music, hide the edge slots
        let shouldHideEdges = Defaults[.showCalendar] && Defaults[.showMirror] && webcamManager.cameraAvailable && vm.isCameraExpanded
        if shouldHideEdges && result.count >= 5 {
            return Array(result.dropFirst().dropLast())
        }

        return result
    }

    @ViewBuilder
    private func slotView(for slot: MusicControlButton) -> some View {
        switch slot {
        case .shuffle:
            HoverButton(icon: "shuffle", iconColor: musicManager.isShuffled ? .red : .primary, scale: .medium) {
                MusicManager.shared.toggleShuffle()
            }
        case .previous:
            HoverButton(icon: "backward.fill", scale: .medium) {
                MusicManager.shared.previousTrack()
            }
        case .playPause:
            HoverButton(
                icon: musicManager.isPlaying ? "pause.fill" : "play.fill",
                scale: .large,
                action: {
                MusicManager.shared.togglePlay()
                }
            )
        case .next:
            HoverButton(icon: "forward.fill", scale: .medium) {
                MusicManager.shared.nextTrack()
            }
        case .repeatMode:
            HoverButton(icon: repeatIcon, iconColor: repeatIconColor, scale: .medium) {
                MusicManager.shared.toggleRepeat()
            }
        case .volume:
            VolumeControlView()
        case .favorite:
            FavoriteControlButton()
        case .goBackward:
            HoverButton(icon: "gobackward.15", scale: .medium) {
                MusicManager.shared.skip(seconds: -15)
            }
        case .goForward:
            HoverButton(icon: "goforward.15", scale: .medium) {
                MusicManager.shared.skip(seconds: 15)
            }
        case .none:
            Color.clear.frame(height: 1)
        }
    }

    private var repeatIcon: String {
        switch musicManager.repeatMode {
        case .off:
            return "repeat"
        case .all:
            return "repeat"
        case .one:
            return "repeat.1"
        }
    }

    private var repeatIconColor: Color {
        switch musicManager.repeatMode {
        case .off:
            return .primary
        case .all, .one:
            return .red
        }
    }
}

struct FavoriteControlButton: View {
    @ObservedObject var musicManager = MusicManager.shared

    var body: some View {
        HoverButton(icon: iconName, iconColor: iconColor, scale: .medium) {
            MusicManager.shared.toggleFavoriteTrack()
        }
        .disabled(!musicManager.canFavoriteTrack)
        .opacity(musicManager.canFavoriteTrack ? 1 : 0.35)
    }

    private var iconName: String {
        musicManager.isFavoriteTrack ? "heart.fill" : "heart"
    }

    private var iconColor: Color {
        musicManager.isFavoriteTrack ? .red : .primary
    }
}

private extension Array where Element == MusicControlButton {
    func padded(to length: Int, filler: MusicControlButton) -> [MusicControlButton] {
        if count >= length { return self }
        return self + Array(repeating: filler, count: length - count)
    }
}

// MARK: - Volume Control View

struct VolumeControlView: View {
    @ObservedObject var musicManager = MusicManager.shared
    @State private var volumeSliderValue: Double = 0.5
    @State private var dragging: Bool = false
    @State private var showVolumeSlider: Bool = false
    @State private var lastVolumeUpdateTime: Date = Date.distantPast
    private let volumeUpdateThrottle: TimeInterval = 0.1
    
    var body: some View {
        HStack(spacing: 4) {
            Button(action: {
                if musicManager.volumeControlSupported {
                    withAnimation(.easeInOut(duration: 0.12)) {
                        showVolumeSlider.toggle()
                    }
                }
            }) {
                Image(systemName: volumeIcon)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(musicManager.volumeControlSupported ? .white : .gray)
            }
            .buttonStyle(PlainButtonStyle())
            .disabled(!musicManager.volumeControlSupported)
            .frame(width: 24)
            .help("Volume controls")
            .accessibilityLabel("Volume controls")

            if showVolumeSlider && musicManager.volumeControlSupported {
                CustomSlider(
                    value: $volumeSliderValue,
                    range: 0.0...1.0,
                    color: .white,
                    dragging: $dragging,
                    lastDragged: .constant(Date.distantPast),
                    onValueChange: { newValue in
                        MusicManager.shared.setVolume(to: newValue)
                    },
                    onDragChange: { newValue in
                        let now = Date()
                        if now.timeIntervalSince(lastVolumeUpdateTime) > volumeUpdateThrottle {
                            MusicManager.shared.setVolume(to: newValue)
                            lastVolumeUpdateTime = now
                        }
                    }
                )
                .frame(width: 48, height: 8)
                .accessibilityLabel("Volume")
                .accessibilityValue("\(Int(volumeSliderValue * 100)) percent")
                .transition(.scale.combined(with: .opacity))
            }
        }
        .clipped()
        .onReceive(musicManager.$volume) { volume in
            if !dragging {
                volumeSliderValue = volume
            }
        }
        .onReceive(musicManager.$volumeControlSupported) { supported in
            if !supported {
                withAnimation(.easeInOut(duration: 0.2)) {
                    showVolumeSlider = false
                }
            }
        }
        .onChange(of: showVolumeSlider) { _, isShowing in
            if isShowing {
                // Sync volume from app when slider appears
                Task {
                    await MusicManager.shared.syncVolumeFromActiveApp()
                }
            }
        }
        .onDisappear {
            // volumeUpdateTask?.cancel() // No longer needed
        }
    }
    
    
    private var volumeIcon: String {
        if !musicManager.volumeControlSupported {
            return "speaker.slash"
        } else if volumeSliderValue == 0 {
            return "speaker.slash.fill"
        } else if volumeSliderValue < 0.33 {
            return "speaker.1.fill"
        } else if volumeSliderValue < 0.66 {
            return "speaker.2.fill"
        } else {
            return "speaker.3.fill"
        }
    }
}

// MARK: - Main View

struct NotchHomeView: View {
    @EnvironmentObject var vm: NotchscapeViewModel
    @ObservedObject private var modes = WorkspaceModeManager.shared
    @ObservedObject var webcamManager = WebcamManager.shared
    @ObservedObject var batteryModel = BatteryStatusViewModel.shared
    @ObservedObject var coordinator = NotchscapeCoordinator.shared
    let albumArtNamespace: Namespace.ID
    @Default(.weatherTilePosition) private var weatherTilePosition
    @Default(.weatherOnLiveTab) private var weatherOnLiveTab
    @Default(.appTheme) private var appTheme

    @Default(.homeWidgetOrder) private var widgetOrder
    @Default(.hiddenHomeWidgets) private var hiddenWidgets
    @Default(.weatherEnabled) private var weatherEnabled
    @Default(.showCalendar) private var showCalendar
    @Default(.quickActions) private var quickActions
    @Default(.quickNotesEnabled) private var quickNotesEnabled

    var body: some View {
        Group {
            if !coordinator.firstLaunch {
                mainContent
            }
        }
        // simplified: use a straightforward opacity transition
        .contentShape(Rectangle())
        .transition(.opacity)
        .contextMenu {
            Button(vm.isEditingHomeLayout ? "Done Editing Home" : "Edit Home…", systemImage: "square.grid.2x2") {
                withAnimation(.smooth(duration: 0.2)) {
                    vm.isEditingHomeLayout.toggle()
                    widgetOrder = HomeLayoutPolicy.normalized(widgetOrder, legacyWeatherPosition: weatherTilePosition.rawValue)
                }
            }.disabled(modes.active?.homePriority.isEmpty == false)
            Menu("Show Tiles") {
                ForEach(HomeWidget.allCases) { widget in
                    Toggle(widget.title, isOn: Binding(get: { visibleWidgets.contains(widget) }, set: { show in
                        if show {
                            hiddenWidgets.remove(widget)
                            if widget == .weather { weatherEnabled = true; weatherOnLiveTab = false }
                            if widget == .calendar { showCalendar = true }
                        } else { hiddenWidgets.insert(widget) }
                    }))
                }
            }
            Divider()
            if quickNotesEnabled {
                Button("New Quick Note…", systemImage: "square.and.pencil") {
                    Task { @MainActor in
                        await LocalToolsManager.shared.load()
                        LocalToolsManager.shared.addNote()
                        NotchToolsWindowController.shared.show(.notes)
                    }
                }
            }
            Button("Open Tools…", systemImage: "square.grid.2x2") { NotchToolsWindowController.shared.show() }
        }
    }

    private var shouldShowCamera: Bool {
        Defaults[.showMirror] && webcamManager.cameraAvailable && vm.isCameraExpanded
    }

    private var visibleWidgets: [HomeWidget] {
        let base = HomeLayoutPolicy.normalized(widgetOrder, legacyWeatherPosition: weatherTilePosition.rawValue).filter { widget in
            !hiddenWidgets.contains(widget)
                && (widget != .calendar || showCalendar)
                && (widget != .weather || (weatherEnabled && !weatherOnLiveTab))
                && (widget != .quickActions || !quickActions.isEmpty)
        }
        return WorkspaceModePolicy.homeOrder(base.map(\.rawValue), mode: modes.active).compactMap(HomeWidget.init(rawValue:))
    }

    private var mainContent: some View {
        HStack(alignment: .top, spacing: (shouldShowCamera && Defaults[.showCalendar]) ? 10 : 15) {
            ForEach(visibleWidgets) { widget in
                homeWidget(widget)
                    .overlay {
                        if vm.isEditingHomeLayout {
                            RoundedRectangle(cornerRadius: 16, style: .continuous)
                                .strokeBorder(.white.opacity(0.5), style: StrokeStyle(lineWidth: 1, dash: [4, 4]))
                                .allowsHitTesting(false)
                        }
                    }
                    .overlay(alignment: .topLeading) {
                        if vm.isEditingHomeLayout {
                            Label(widget.title, systemImage: "line.3.horizontal")
                                .font(.caption2.weight(.medium)).padding(.horizontal, 7).padding(.vertical, 4)
                                .liquidGlassCapsule().allowsHitTesting(false)
                        }
                    }
                    .conditionalModifier(vm.isEditingHomeLayout) { content in
                        content.overlay {
                            Color.white.opacity(0.001).contentShape(Rectangle())
                            .onDrag {
                            vm.draggedHomeWidget = widget
                            let provider = NSItemProvider()
                            provider.registerDataRepresentation(forTypeIdentifier: UTType.notchHomeWidget.identifier, visibility: .ownProcess) { completion in
                                completion(Data(widget.rawValue.utf8), nil); return nil
                            }
                            return provider
                        } preview: {
                            Label(widget.title, systemImage: widget.symbol).font(.headline).padding(14)
                                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 18))
                        }
                        .onDrop(of: [.notchHomeWidget], delegate: HomeTileReorderDelegate(target: widget,
                            order: $widgetOrder, dragged: $vm.draggedHomeWidget))
                        }
                    }
                }

            if visibleWidgets.isEmpty && !shouldShowCamera {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Make Home yours").font(.headline)
                    Text("Choose your tiles in Appearance → Home layout.").font(.caption).foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, minHeight: 130, alignment: .leading)
            }

            if shouldShowCamera {
                CameraPreviewView(webcamManager: webcamManager)
                    .scaledToFit()
                    .opacity(vm.notchState == .closed ? 0 : 1)
                    .blur(radius: vm.notchState == .closed ? 20 : 0)
                    .animation(.interactiveSpring(response: 0.32, dampingFraction: 0.76, blendDuration: 0), value: shouldShowCamera)
            }


            if appTheme.hasHomeScene {
                // Seasonal scenery belongs to the single shared background.
                // Keep content to its left without placing a second photo here.
                Color.clear
                    .frame(width: 128, height: 130)
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .animation(.smooth(duration: 0.22), value: widgetOrder)
        .transition(.asymmetric(insertion: .opacity.combined(with: .move(edge: .top)), removal: .opacity))
        .blur(radius: vm.notchState == .closed ? 30 : 0)
    }

    @ViewBuilder private func homeWidget(_ widget: HomeWidget) -> some View {
        switch widget {
        case .music: MusicPlayerView(albumArtNamespace: albumArtNamespace)
        case .calendar:
            CalendarView().frame(width: (shouldShowCamera || visibleWidgets.contains(.weather)) ? 190 : 215)
                .onHover { vm.isHoveringCalendar = $0 }.environmentObject(vm)
        case .weather: HomeWeatherTile()
        case .quickActions: QuickActionsHomeTile()
        }
    }
}

extension UTType {
    static let notchHomeWidget = UTType(exportedAs: "theboringteam.boringnotch.home-widget", conformingTo: .item)
}

struct HomeTileReorderDelegate: DropDelegate {
    let target: HomeWidget
    @Binding var order: [HomeWidget]
    @Binding var dragged: HomeWidget?
    func validateDrop(info: DropInfo) -> Bool { dragged != nil && info.hasItemsConforming(to: [.notchHomeWidget]) }
    func dropEntered(info: DropInfo) {
        guard let dragged else { return }
        withAnimation(.smooth(duration: 0.2)) { order = HomeLayoutPolicy.reordered(dragged, over: target, in: order) }
    }
    func dropUpdated(info: DropInfo) -> DropProposal? { DropProposal(operation: .move) }
    func performDrop(info: DropInfo) -> Bool { dragged = nil; return true }
}

/// A static vector decoration: crisp at every display scale, with no animation timer.
private struct ChristmasHomeTree: View {
    var body: some View {
        Canvas { context, size in
            let scale = min(size.width / 81, size.height / 130)
            context.scaleBy(x: scale, y: scale)
            let gold = Color(red: 1, green: 0.78, blue: 0.30)
            let trunk = Path(roundedRect: CGRect(x: 35, y: 105, width: 12, height: 18), cornerRadius: 3)
            context.fill(trunk, with: .color(Color(red: 0.48, green: 0.29, blue: 0.16)))

            for (top, bottom, halfWidth) in [(18.0, 60.0, 23.0), (39.0, 85.0, 31.0), (65.0, 113.0, 39.0)] {
                var branch = Path()
                branch.move(to: CGPoint(x: 40.5, y: top))
                branch.addQuadCurve(to: CGPoint(x: 40.5 - halfWidth, y: bottom - 5), control: CGPoint(x: 34, y: top + 22))
                branch.addQuadCurve(to: CGPoint(x: 40.5 + halfWidth, y: bottom - 5), control: CGPoint(x: 40.5, y: bottom + 7))
                branch.addQuadCurve(to: CGPoint(x: 40.5, y: top), control: CGPoint(x: 48, y: top + 22))
                branch.closeSubpath()
                context.fill(branch, with: .linearGradient(
                    Gradient(colors: [Color(red: 0.27, green: 0.68, blue: 0.46), Color(red: 0.04, green: 0.29, blue: 0.19)]),
                    startPoint: CGPoint(x: 12, y: top), endPoint: CGPoint(x: 64, y: bottom)))
            }

            var star = Path()
            for index in 0..<10 {
                let angle = Double(index) * .pi / 5 - .pi / 2
                let radius = index.isMultiple(of: 2) ? 10.0 : 4.5
                let point = CGPoint(x: 40.5 + cos(angle) * radius, y: 13 + sin(angle) * radius)
                if index == 0 { star.move(to: point) } else { star.addLine(to: point) }
            }
            star.closeSubpath()
            context.fill(star, with: .color(gold))

            for (x, y, red) in [(33.0, 43.0, true), (49.0, 55.0, false), (24.0, 71.0, false), (48.0, 78.0, true), (32.0, 94.0, true), (61.0, 99.0, false), (18.0, 104.0, true)] {
                let ornament = Path(ellipseIn: CGRect(x: x - 3.5, y: y - 3.5, width: 7, height: 7))
                context.fill(ornament, with: .color(red ? Color(red: 0.91, green: 0.25, blue: 0.28) : gold))
                context.fill(Path(ellipseIn: CGRect(x: x - 2, y: y - 2, width: 2, height: 2)), with: .color(.white.opacity(0.65)))
            }

            for (x, y, width, color) in [(10.0, 114.0, 21.0, Color(red: 0.76, green: 0.18, blue: 0.23)), (49.0, 117.0, 22.0, Color(red: 0.43, green: 0.36, blue: 0.72))] {
                context.fill(Path(roundedRect: CGRect(x: x, y: y, width: width, height: 12), cornerRadius: 2), with: .color(color))
                context.fill(Path(CGRect(x: x + width / 2 - 1.5, y: y, width: 3, height: 12)), with: .color(gold))
            }
        }
    }
}

struct MusicSliderView: View {
    @Default(.appTheme) private var appTheme
    @Default(.lightsaberMusicBar) private var lightsaberMusicBar
    @Default(.lightsaberColorMode) private var lightsaberColorMode
    @Default(.lightsaberCustomColorData) private var lightsaberCustomColorData
    @Default(.useCustomAccentColor) private var useCustomAccentColor
    @Default(.customAccentColorData) private var customAccentColorData
    @Binding var sliderValue: Double
    @Binding var duration: Double
    @Binding var lastDragged: Date
    var color: NSColor
    @Binding var dragging: Bool
    let currentDate: Date
    let timestampDate: Date
    let elapsedTime: Double
    let playbackRate: Double
    let isPlaying: Bool
    var onValueChange: (Double) -> Void

    private var safeDuration: Double { duration.isFinite ? max(0, duration) : 0 }
    private var usesLightsaber: Bool { appTheme.isStarWars && lightsaberMusicBar }

    var body: some View {
        VStack {
            Group {
                if usesLightsaber {
                    LightsaberSlider(value: $sliderValue, duration: safeDuration,
                        tint: LightsaberColors.resolve(mode: lightsaberColorMode, theme: appTheme,
                                                      album: color, customData: lightsaberCustomColorData),
                        dragging: $dragging, lastDragged: $lastDragged, onValueChange: onValueChange)
                } else {
                    CustomSlider(
                        value: $sliderValue,
                        range: 0...safeDuration,
                        color: Defaults[.sliderColor] == SliderColorEnum.albumArt
                            ? Color(nsColor: color).ensureMinimumBrightness(factor: 0.8)
                            : Defaults[.sliderColor] == SliderColorEnum.accent ? .effectiveAccent : .white,
                        dragging: $dragging,
                        lastDragged: $lastDragged,
                        onValueChange: onValueChange
                    )
                }
            }
            .frame(height: usesLightsaber ? 14 : 10, alignment: .center)
            .accessibilityLabel("Playback position")
            .accessibilityValue("\(timeString(from: sliderValue)) of \(timeString(from: duration))")

            HStack {
                Text(timeString(from: sliderValue))
                Spacer()
                Text(timeString(from: duration))
            }
            .fontWeight(.medium)
            .foregroundColor(
                Defaults[.playerColorTinting]
                    ? Color(nsColor: color).ensureMinimumBrightness(factor: 0.6) : .gray
            )
            .font(.caption)
        }
        .onChange(of: currentDate) {
           guard !dragging, timestampDate.timeIntervalSince(lastDragged) > -1 else { return }
            sliderValue = MusicManager.shared.estimatedPlaybackPosition(at: currentDate)
        }
        .onAppear {
            guard !dragging else { return }
            sliderValue = min(max(elapsedTime, 0), duration)
        }
        .onChange(of: elapsedTime) {
            guard !dragging, timestampDate.timeIntervalSince(lastDragged) > -1 else { return }
            sliderValue = min(max(elapsedTime, 0), duration)
        }
    }

    func timeString(from seconds: Double) -> String {
        let safeSeconds = seconds.isFinite ? min(max(0, seconds), 359_999) : 0
        let totalMinutes = Int(safeSeconds) / 60
        let remainingSeconds = Int(safeSeconds) % 60
        let hours = totalMinutes / 60
        let minutes = totalMinutes % 60

        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, remainingSeconds)
        } else {
            return String(format: "%d:%02d", minutes, remainingSeconds)
        }
    }
}

/// Static vector layers: no video, particle system, repeating glow, or new timer.
/// Progress is supplied by the same throttled timeline as the ordinary player.
struct LightsaberTrack: View {
    let progress: Double
    let tint: Color
    let dragging: Bool
    let lowImpact: Bool

    var body: some View {
        GeometryReader { geometry in
            let width = max(0, geometry.size.width)
            let hiltWidth = min(24, width * 0.2)
            let bladeWidth = max(0, width - hiltWidth - 2)
            let clamped = progress.isFinite ? min(1, max(0, progress)) : 0
            let filled = bladeWidth * clamped
            HStack(spacing: 2) {
                ZStack {
                    RoundedRectangle(cornerRadius: 2)
                        .fill(LinearGradient(colors: [Color(white: 0.27), Color(white: 0.84), Color(white: 0.35)], startPoint: .top, endPoint: .bottom))
                    HStack(spacing: 3) {
                        ForEach(0..<3) { _ in Capsule().fill(.black.opacity(0.6)).frame(width: 2) }
                        Circle().fill(tint).frame(width: 3, height: 3)
                    }.padding(.horizontal, 4).padding(.vertical, 1)
                }
                .frame(width: hiltWidth, height: dragging ? 10 : 8)

                ZStack(alignment: .leading) {
                    Capsule().fill(tint.opacity(0.15)).frame(height: 4)
                    Capsule().fill(tint).frame(width: filled, height: dragging ? 6 : 4)
                        .shadow(color: tint.opacity(lowImpact ? 0 : 0.9), radius: lowImpact ? 0 : 3)
                    Capsule().fill(.white.opacity(0.95)).frame(width: max(0, filled - 1), height: dragging ? 2.5 : 1.5)
                }
                .frame(width: bladeWidth)
            }
            .frame(height: geometry.size.height)
        }
    }
}

struct LightsaberSlider: View {
    @Binding var value: Double
    let duration: Double
    let tint: Color
    @Binding var dragging: Bool
    @Binding var lastDragged: Date
    let onValueChange: (Double) -> Void
    @ObservedObject private var performance = AppPerformanceManager.shared

    var body: some View {
        GeometryReader { geometry in
            LightsaberTrack(progress: LightsaberTrackPolicy.progress(value: value, duration: duration),
                            tint: tint, dragging: dragging, lowImpact: performance.lowImpact)
                .contentShape(Rectangle().inset(by: -4))
                .gesture(DragGesture(minimumDistance: 0)
                    .onChanged { gesture in
                        let hilt = min(24, geometry.size.width * 0.2) + 2
                        guard let time = LightsaberTrackPolicy.time(at: gesture.location.x - hilt,
                            width: geometry.size.width - hilt, duration: duration) else { return }
                        dragging = true
                        value = time
                    }
                    .onEnded { _ in
                        guard dragging else { return }
                        dragging = false
                        lastDragged = Date()
                        onValueChange(value)
                    })
                .animation(performance.suppressAnimations ? nil : .easeOut(duration: 0.16), value: dragging)
        }
        .focusable(duration > 0)
        .onMoveCommand { direction in
            if direction == .left { adjust(by: -5) }
            if direction == .right { adjust(by: 5) }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityAdjustableAction { direction in
            switch direction { case .increment: adjust(by: 5); case .decrement: adjust(by: -5); @unknown default: break }
        }
    }

    private func adjust(by delta: Double) {
        guard duration.isFinite, duration > 0 else { return }
        value = min(duration, max(0, (value.isFinite ? value : 0) + delta))
        lastDragged = Date()
        onValueChange(value)
    }
}

struct CustomSlider: View {
    @Binding var value: Double
    var range: ClosedRange<Double>
    var color: Color = .white
    @Binding var dragging: Bool
    @Binding var lastDragged: Date
    var onValueChange: ((Double) -> Void)?
    var onDragChange: ((Double) -> Void)?

    var body: some View {
        GeometryReader { geometry in
            let width = geometry.size.width
            let height = CGFloat(dragging ? 9 : 5)
            let rangeSpan = range.upperBound - range.lowerBound

            let progress = rangeSpan == .zero ? 0 : (value - range.lowerBound) / rangeSpan
            let filledTrackWidth = min(max(progress, 0), 1) * width

            ZStack(alignment: .leading) {
                Rectangle()
                    .fill(.gray.opacity(0.3))
                    .frame(height: height)

                Rectangle()
                    .fill(color)
                    .frame(width: filledTrackWidth, height: height)
            }
            .cornerRadius(height / 2)
            .frame(height: 10)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { gesture in
                        withAnimation {
                            dragging = true
                        }
                        let newValue = range.lowerBound + Double(gesture.location.x / width) * rangeSpan
                        value = min(max(newValue, range.lowerBound), range.upperBound)
                        onDragChange?(value)
                    }
                    .onEnded { _ in
                        onValueChange?(value)
                        dragging = false
                        lastDragged = Date()
                    }
            )
            .animation(.spring(response: 0.35, dampingFraction: 0.7), value: dragging)
            .accessibilityElement(children: .ignore)
            .accessibilityAdjustableAction { direction in
                let step = rangeSpan <= 1 ? 0.05 : 5.0
                switch direction {
                case .increment: value = min(range.upperBound, value + step)
                case .decrement: value = max(range.lowerBound, value - step)
                @unknown default: return
                }
                lastDragged = Date()
                onValueChange?(value)
            }
        }
    }
}
