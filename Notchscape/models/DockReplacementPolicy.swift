import Foundation
import CoreGraphics

enum DockActionOrigin: String, Sendable {
    case unspecified, widgetButton, widgetTap, widgetKeyboard, widgetMenu, appIcon, appMenu, appOverflowMenu, expandedControl
}

enum DockReplacementOverflowMode: String, Codable, CaseIterable, Sendable {
    case pages, stack
}

struct DockReplacementSlot: Equatable, Sendable {
    let index: Int
    let frame: CGRect
}

/// `frame` is global AppKit screen geometry. Every slot/control rectangle is
/// LOCAL AppKit geometry: origin at the bar's bottom left, y increases upward.
/// SwiftUI positions use (slot.midX, frame.height - slot.midY).
struct DockReplacementBarLayout: Equatable, Sendable {
    let frame: CGRect
    let surfaceHeight: Double
    let magnificationReserve: Double
    let appSlots: [CGRect]
    let appOverflowButtonFrame: CGRect?
    let hiddenAppCount: Int
    let widgetSlots: [DockReplacementSlot]
    let visibleWidgetRange: Range<Int>
    let page: Int
    let pageCount: Int
    let overflowButtonFrame: CGRect?
    let galleryButtonFrame: CGRect
    let widgetEnvelopeWidth: Double
    let overflow: DockReplacementOverflowMode
}

struct DockReplacementMagnification: Equatable, Sendable {
    let scales: [Double]
    let offsets: [Double]
    let totalExtra: Double
}

enum DockReplacementPolicy {
    static func permitsUserAction(contentAllowed: Bool, visible: Bool, panelVisible: Bool) -> Bool {
        contentAllowed && visible && panelVisible
    }

    static func shouldTraceFocus(startedAt: TimeInterval?, now: TimeInterval) -> Bool {
        guard let startedAt, startedAt.isFinite, now.isFinite else { return false }
        let age = now - startedAt
        return age >= 0 && age < 60
    }
    static let padding = 8.0
    static let gap = 6.0
    static let sectionGap = 16.0
    static let barHeight = 76.0
    static let tileHeight = 60.0
    static let overflowWidth = 36.0
    static let galleryWidth = 32.0
    static let maximumWidgets = 48
    static let maximumApps = 24

    static func faceWidth(for kind: DockReplacementWidgetKind, iconSize: Double = 48) -> Double? {
        guard iconSize.isFinite, (32...64).contains(iconSize) else { return nil }
        let base: Double
        switch kind {
        case .nowPlaying: base = 220
        case .upNext: base = 200
        case .battery: base = 124
        case .timer: base = 128
        case .clock: base = 136
        case .calculator: base = 120
        case .weather: base = 168
        case .system: base = 180
        }
        return max(84, base * iconSize / 48)
    }

    /// Only visible faces or an expanded System card own a sampling lease.
    static func needsSystemSampling(widgets: [DockReplacementWidgetInstance], visibleRange: Range<Int>,
                                    expandedID: UUID?, active: Bool) -> Bool {
        active && widgets.enumerated().contains { index, widget in
            widget.kind == .system && (visibleRange.contains(index) || widget.id == expandedID)
        }
    }

    static func hiddenWidgetIndices(count: Int, visibleRange: Range<Int>) -> [Int] {
        guard (0...48).contains(count) else { return [] }
        return (0..<count).filter { !visibleRange.contains($0) }
    }

    static func usageFraction(_ value: Double?) -> Double? {
        guard let value, value.isFinite, (0...1).contains(value) else { return nil }
        return value
    }

    static func percentage(_ value: Double?) -> String {
        guard let value = usageFraction(value) else { return "—" }
        return (value * 100).formatted(.number.precision(.fractionLength(0))) + "%"
    }

    static func weatherIsCurrent(updatedAt: Date, now: Date, failed: Bool) -> Bool {
        let age = now.timeIntervalSince(updatedAt)
        return !failed && age.isFinite && (-300...900).contains(age)
    }

    /// No measurement callbacks or published geometry state. Width is a stable
    /// envelope computed from all pages; changing pages never moves controls.
    static func barLayout(in usableFrame: CGRect, appCount: Int,
                          widgetKinds: [DockReplacementWidgetKind], iconSize: Double = 48,
                          requestedPage: Int = 0,
                          overflow: DockReplacementOverflowMode = .pages) -> DockReplacementBarLayout? {
        guard validRect(usableFrame), usableFrame.width >= 320, usableFrame.height >= barHeight + 2 * padding,
              (0...maximumApps).contains(appCount), widgetKinds.count <= maximumWidgets,
              iconSize.isFinite, (32...64).contains(iconSize) else { return nil }
        let nominal = widgetKinds.compactMap { faceWidth(for: $0, iconSize: iconSize) }
        var reserve = appCount > 0 ? 48.0 : 0
        var contentLimit = Double(usableFrame.width) - 4 * padding - reserve
        let hasContent = appCount > 0 || !widgetKinds.isEmpty
        var beforeGallery = contentLimit - galleryWidth - (hasContent ? gap : 0)
        let minimumWidgets = widgetKinds.isEmpty ? 0 : 84 + (widgetKinds.count > 1 ? overflowWidth + gap : 0)
        let appsBudget = widgetKinds.isEmpty ? beforeGallery
            : min(beforeGallery * 0.4, beforeGallery - minimumWidgets - sectionGap)
        var visibleApps = appCount
        while visibleApps > 0 && appSectionWidth(visible: visibleApps, total: appCount, iconSize: iconSize) > appsBudget {
            visibleApps -= 1
        }
        if visibleApps == 0 {
            // A narrow bar can expose apps through its menu. Reserve hover
            // space only when an actual icon is visible, without oscillating
            // between a measured size and a newly published layout.
            reserve = 0
            contentLimit = Double(usableFrame.width) - 4 * padding
            beforeGallery = contentLimit - galleryWidth - (hasContent ? gap : 0)
        }
        let appsWidth = appSectionWidth(visible: visibleApps, total: appCount, iconSize: iconSize)
        let hasAppSection = appCount > 0
        let separation = hasAppSection && !widgetKinds.isEmpty ? sectionGap : 0
        let widgetBudget = beforeGallery - appsWidth - separation
        let fullWidgetWidth = nominal.reduce(0, +) + Double(max(0, nominal.count - 1)) * gap
        let hasWidgetOverflow = fullWidgetWidth > widgetBudget && widgetKinds.count > 1
        let faceBudget = widgetBudget - (hasWidgetOverflow ? overflowWidth + gap : 0)
        guard appsWidth <= beforeGallery, widgetKinds.isEmpty || faceBudget >= 84 else { return nil }
        // Narrow displays retain one useful compact face; text may truncate,
        // but neither its frame nor any navigation control escapes the bar.
        let widths = nominal.map { min($0, faceBudget) }
        let ranges = packedRanges(widths: widths, budget: max(0, faceBudget))
        guard !ranges.isEmpty else { return nil }
        let page = overflow == .stack ? 0 : max(0, min(ranges.count - 1, requestedPage))
        let range = ranges[page]
        let envelope = ranges.map { rangeWidth($0, widths: widths) }.max() ?? 0
        let navigation = ranges.count > 1 ? overflowWidth + gap : 0
        let totalWidth = 2 * padding + appsWidth + separation + envelope + navigation + galleryWidth + (hasContent ? gap : 0) + reserve
        guard totalWidth.isFinite, totalWidth > 0, totalWidth <= Double(usableFrame.width) - 2 * padding + 0.00001 else { return nil }
        let surfaceHeight = max(barHeight, iconSize + 16)
        let appBaseY = (surfaceHeight - iconSize) / 2
        let maximumScale = (0..<visibleApps).compactMap {
            magnification(appCount: visibleApps, hoveredIndex: $0, iconSize: iconSize, maxExtra: reserve)?.scales.max()
        }.max() ?? 1
        let windowHeight = max(surfaceHeight, appBaseY + iconSize * maximumScale + 4)
        guard windowHeight + 2 * padding <= usableFrame.height else { return nil }
        let frame = CGRect(x: usableFrame.midX - totalWidth / 2, y: usableFrame.minY + padding,
                           width: totalWidth, height: windowHeight)
        let tileY = (surfaceHeight - tileHeight) / 2
        var x = padding + reserve / 2
        var appSlots: [CGRect] = []
        for _ in 0..<visibleApps {
            appSlots.append(CGRect(x: x, y: appBaseY, width: iconSize, height: iconSize))
            x += iconSize + gap
        }
        var appOverflowFrame: CGRect?
        if visibleApps < appCount {
            appOverflowFrame = CGRect(x: x, y: tileY, width: overflowWidth, height: tileHeight)
        }
        x = padding + reserve / 2 + appsWidth + separation
        let widgetsStart = x
        var widgetSlots: [DockReplacementSlot] = []
        for index in range {
            widgetSlots.append(.init(index: index, frame: CGRect(x: x, y: tileY, width: widths[index], height: tileHeight)))
            x += widths[index] + gap
        }
        var overflowFrame: CGRect?
        x = widgetsStart + envelope
        if ranges.count > 1 {
            x += gap
            overflowFrame = CGRect(x: x, y: tileY, width: overflowWidth, height: tileHeight)
            x += overflowWidth
        }
        if hasContent { x += gap }
        let gallery = CGRect(x: x, y: tileY, width: galleryWidth, height: tileHeight)
        return .init(frame: frame, surfaceHeight: surfaceHeight, magnificationReserve: reserve,
            appSlots: appSlots, appOverflowButtonFrame: appOverflowFrame,
            hiddenAppCount: appCount - visibleApps, widgetSlots: widgetSlots, visibleWidgetRange: range,
            page: page, pageCount: ranges.count, overflowButtonFrame: overflowFrame,
            galleryButtonFrame: gallery, widgetEnvelopeWidth: envelope, overflow: overflow)
    }

    /// One expanded panel, anchored above a real local slot/control. The main
    /// bar never changes height; the card shrinks only when screen space requires.
    static func expandedCardFrame(for localSlot: CGRect, in layout: DockReplacementBarLayout,
                                  usableFrame: CGRect,
                                  preferredSize: CGSize = CGSize(width: 320, height: 280)) -> CGRect? {
        let localBounds = CGRect(origin: .zero, size: layout.frame.size)
        guard validRect(usableFrame), validRect(layout.frame), validRect(localSlot),
              localBounds.contains(localSlot), usableFrame.contains(layout.frame),
              preferredSize.width.isFinite, preferredSize.height.isFinite,
              (160...2048).contains(preferredSize.width), (96...2048).contains(preferredSize.height) else { return nil }
        let margin = 8.0
        let surfaceTop = layout.frame.minY + layout.surfaceHeight
        let availableHeight = usableFrame.maxY - margin - surfaceTop - 8
        let width = min(preferredSize.width, usableFrame.width - 2 * margin)
        let height = min(preferredSize.height, availableHeight)
        guard width >= 160, height >= 96 else { return nil }
        let desiredX = layout.frame.minX + localSlot.midX - width / 2
        let x = min(usableFrame.maxX - margin - width, max(usableFrame.minX + margin, desiredX))
        return CGRect(x: x, y: surfaceTop + 8, width: width, height: height)
    }

    /// Hover uses a constant region and rest centers. Moving icons never feed
    /// new measurements back into hover state or the NSWindow frame.
    static func hoveredAppIndex(at point: CGPoint, in layout: DockReplacementBarLayout) -> Int? {
        guard point.x.isFinite, point.y.isFinite, let first = layout.appSlots.first, let last = layout.appSlots.last,
              point.x >= first.minX - gap / 2, point.x <= last.maxX + gap / 2,
              point.y >= 0, point.y <= layout.frame.height else { return nil }
        return layout.appSlots.indices.min { abs(layout.appSlots[$0].midX - point.x) < abs(layout.appSlots[$1].midX - point.x) }
    }

    static func magnification(appCount: Int, hoveredIndex: Int?, iconSize: Double,
                              maxExtra: Double = 48) -> DockReplacementMagnification? {
        guard (0...maximumApps).contains(appCount), iconSize.isFinite, (32...64).contains(iconSize),
              maxExtra.isFinite, (0...48).contains(maxExtra) else { return nil }
        guard let hoveredIndex, (0..<appCount).contains(hoveredIndex) else {
            return .init(scales: Array(repeating: 1, count: appCount), offsets: Array(repeating: 0, count: appCount), totalExtra: 0)
        }
        let extras = (0..<appCount).map { index -> Double in
            switch abs(index - hoveredIndex) {
            case 0: iconSize * 0.35
            case 1: iconSize * 0.15
            case 2: iconSize * 0.025
            default: 0
            }
        }
        return coupledMagnification(extras: extras, iconSize: iconSize, maxExtra: maxExtra)
    }

    static func appPresentationFrames(in layout: DockReplacementBarLayout, hoveredIndex: Int?) -> [CGRect] {
        guard let iconSize = layout.appSlots.first?.width,
              let values = magnification(appCount: layout.appSlots.count, hoveredIndex: hoveredIndex,
                  iconSize: iconSize, maxExtra: layout.magnificationReserve) else { return layout.appSlots }
        return presentationFrames(in: layout, values: values)
    }

    /// Pointer and presence are the animation inputs, never independently
    /// animated icon rectangles. Every intermediate pair yields one coupled
    /// extras vector, so adjacent gaps are the exact original resting gaps.
    /// `pointerX` and rest centers use the bar's fixed LOCAL AppKit coordinates.
    static func magnification(appCount: Int, pointerX: Double?, iconSize: Double,
                              maxExtra: Double = 48, restCenters: [Double],
                              presence: Double = 1) -> DockReplacementMagnification? {
        guard (0...maximumApps).contains(appCount), restCenters.count == appCount,
              iconSize.isFinite, (32...64).contains(iconSize), maxExtra.isFinite, (0...48).contains(maxExtra),
              presence.isFinite, restCenters.allSatisfy({ $0.isFinite && abs($0) <= 1_000_000 }),
              zip(restCenters, restCenters.dropFirst()).allSatisfy({ $0.1 - $0.0 >= iconSize }) else { return nil }
        let resting = DockReplacementMagnification(scales: Array(repeating: 1, count: appCount),
            offsets: Array(repeating: 0, count: appCount), totalExtra: 0)
        guard let pointerX else { return resting }
        guard pointerX.isFinite else { return nil }
        let influence = max(0, min(1, presence))
        guard influence > 0, maxExtra > 0, let first = restCenters.first, let last = restCenters.last else { return resting }
        let pitch = iconSize + gap
        let edgeDistance = min(pointerX - (first - pitch / 2), (last + pitch / 2) - pointerX)
        let edgeFraction = max(0, min(1, edgeDistance / (pitch / 2)))
        // C1 fade reaches zero at either end without changing an index, and
        // reaches full strength by the first/last icon's resting center.
        let edgeFade = edgeFraction * edgeFraction * (3 - 2 * edgeFraction)
        guard edgeFade > 0 else { return resting }
        let radius = 2.5 * pitch
        let extras = restCenters.map { center -> Double in
            let distance = abs(center - pointerX)
            guard distance < radius else { return 0 }
            let raisedCosine = (1 + cos(.pi * distance / radius)) / 2
            return iconSize * 0.35 * raisedCosine * influence * edgeFade
        }
        return coupledMagnification(extras: extras, iconSize: iconSize, maxExtra: maxExtra)
    }

    static func magnification(in layout: DockReplacementBarLayout, pointerX: Double?,
                              presence: Double = 1) -> DockReplacementMagnification? {
        magnification(appCount: layout.appSlots.count, pointerX: pointerX,
            iconSize: layout.appSlots.first.map { Double($0.width) } ?? 48,
            maxExtra: layout.magnificationReserve, restCenters: layout.appSlots.map { Double($0.midX) }, presence: presence)
    }

    static func appPresentationFrames(in layout: DockReplacementBarLayout, pointerX: Double?,
                                      presence: Double = 1) -> [CGRect] {
        guard let values = magnification(in: layout, pointerX: pointerX, presence: presence) else { return layout.appSlots }
        return presentationFrames(in: layout, values: values)
    }

    private static func coupledMagnification(extras requestedExtras: [Double], iconSize: Double,
                                             maxExtra: Double) -> DockReplacementMagnification {
        let requested = requestedExtras.reduce(0, +)
        let factor = requested > 0 ? min(1, maxExtra / requested) : 0
        let extras = requestedExtras.map { $0 * factor }
        let total = extras.reduce(0, +)
        var preceding = 0.0
        var offsets: [Double] = []
        for extra in extras {
            offsets.append(preceding + extra / 2 - total / 2)
            preceding += extra
        }
        return .init(scales: extras.map { 1 + $0 / iconSize }, offsets: offsets, totalExtra: total)
    }

    private static func presentationFrames(in layout: DockReplacementBarLayout,
                                           values: DockReplacementMagnification) -> [CGRect] {
        layout.appSlots.enumerated().map { index, rest in
            let size = rest.width * values.scales[index]
            return CGRect(x: rest.midX + values.offsets[index] - size / 2, y: rest.minY, width: size, height: size)
        }
    }

    /// Optional adapter for callers whose visible frame can include an
    /// auto-hidden menu bar. Always intersect with the measured hardware inset.
    static func usableFrame(screenFrame: CGRect, visibleFrame: CGRect, topSafeInset: Double) -> CGRect? {
        guard validRect(screenFrame), validRect(visibleFrame), topSafeInset.isFinite,
              topSafeInset >= 0, topSafeInset < screenFrame.height else { return nil }
        let hardwareSafe = CGRect(x: screenFrame.minX, y: screenFrame.minY,
                                  width: screenFrame.width, height: screenFrame.height - topSafeInset)
        let result = visibleFrame.intersection(hardwareSafe)
        return validRect(result) ? result : nil
    }

    static func moving(_ id: UUID, by direction: Int, in layout: DockReplacementLayout) -> DockReplacementLayout? {
        guard layout.isValid, direction == -1 || direction == 1,
              let source = layout.widgets.firstIndex(where: { $0.id == id }) else { return nil }
        guard layout.widgets.indices.contains(source + direction) else { return layout }
        var result = layout; result.widgets.swapAt(source, source + direction); return result
    }

    static func placing(_ id: UUID, at target: UUID, in layout: DockReplacementLayout) -> DockReplacementLayout? {
        guard layout.isValid, let sourceIndex = layout.widgets.firstIndex(where: { $0.id == id }),
              let destination = layout.widgets.firstIndex(where: { $0.id == target }) else { return nil }
        guard id != target else { return layout }
        var result = layout
        let instance = result.widgets.remove(at: sourceIndex)
        result.widgets.insert(instance, at: min(destination, result.widgets.count))
        return result
    }

    static func adding(_ instance: DockReplacementWidgetInstance, to layout: DockReplacementLayout) -> DockReplacementLayout? {
        guard layout.isValid, instance.isValid, layout.widgets.count < maximumWidgets,
              !layout.widgets.contains(where: { $0.id == instance.id }) else { return nil }
        var result = layout; result.widgets.append(instance); return result
    }

    static func removing(_ id: UUID, from layout: DockReplacementLayout) -> DockReplacementLayout? {
        guard layout.isValid, layout.widgets.contains(where: { $0.id == id }) else { return nil }
        var result = layout; result.widgets.removeAll { $0.id == id }; return result
    }

    static func validRect(_ frame: CGRect) -> Bool {
        !frame.isNull && !frame.isInfinite && frame.width > 0 && frame.height > 0 &&
        [frame.minX, frame.minY, frame.width, frame.height, frame.maxX, frame.maxY].allSatisfy {
            $0.isFinite && abs($0) <= 1_000_000
        }
    }

    private static func appSectionWidth(visible: Int, total: Int, iconSize: Double) -> Double {
        let extra = visible < total ? 1 : 0
        return Double(visible) * iconSize + Double(extra) * overflowWidth + Double(max(0, visible + extra - 1)) * gap
    }
    private static func rangeWidth(_ range: Range<Int>, widths: [Double]) -> Double {
        range.reduce(0) { $0 + widths[$1] } + Double(max(0, range.count - 1)) * gap
    }
    private static func packedRanges(widths: [Double], budget: Double) -> [Range<Int>] {
        guard !widths.isEmpty else { return [0..<0] }
        var result: [Range<Int>] = [], start = 0, current = 0.0
        for index in widths.indices {
            let needed = widths[index] + (index > start ? gap : 0)
            if index > start, current + needed > budget + 0.00001 {
                result.append(start..<index); start = index; current = widths[index]
            } else { current += needed }
        }
        result.append(start..<widths.count)
        return result
    }
}
