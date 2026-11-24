import CoreGraphics
import Foundation

@main struct DesktopSnowPolicyTests {
    static func main() {
        var checks = 0
        func check(_ value: @autoclosure () -> Bool, _ explanation: String) {
            precondition(value(), explanation); checks += 1
        }
        var eligible = DesktopSnowEligibility(enabled: true, unlocked: true)
        check(eligible.framesPerSecond == 30, "enabled eligible desktop uses at most 30 fps")
        eligible.lowImpact = true
        check(eligible.framesPerSecond == 15, "low impact reduces cadence")
        eligible.lowImpact = false; eligible.onBattery = true
        check(eligible.framesPerSecond == 15, "battery operation reduces cadence")
        for gate in 0..<9 {
            var state = DesktopSnowEligibility(enabled: true, unlocked: true)
            switch gate {
            case 0: state.enabled = false
            case 1: state.unlocked = false
            case 2: state.awake = false
            case 3: state.activeSession = false
            case 4: state.presenting = true
            case 5: state.reduceMotion = true
            case 6: state.criticalBattery = true
            case 7: state.seriousThermal = true
            default: state.capturing = true
            }
            check(state.framesPerSecond == nil, "every suppression fence disables all render ticks")
            check(!state.status.hasPrefix("Snowing"), "paused status remains accurate")
        }
        for invalid in [Double.nan, .infinity, -.infinity, Double.greatestFiniteMagnitude, -Double.greatestFiniteMagnitude] {
            let options = DesktopSnowOptions(intensity: invalid, speed: invalid, wind: invalid).bounded
            check(options.intensity.isFinite && (0...1).contains(options.intensity), "intensity sanitizes untrusted preferences")
            check(options.speed.isFinite && (0.25...2.5).contains(options.speed), "speed remains bounded")
            check(options.wind.isFinite && (-1...1).contains(options.wind), "wind remains bounded")
        }
        for invalid in [Double.nan, .infinity, -.infinity, -100, 100] {
            let options = DesktopSnowOptions(moundHeight: invalid, moundWidth: invalid, moundSpacing: invalid).bounded
            check((0.4...2).contains(options.moundHeight), "mound height preference remains in a safe finite range")
            check((0.5...2).contains(options.moundWidth), "mound width preference remains in a safe finite range")
            check((0.5...2).contains(options.moundSpacing), "mound spacing preference remains in a safe finite range")
        }
        let invalidLayout = DesktopSnowOptions(bottomLimit: .infinity, baseDepth: .nan, customBottomLayout: true,
            authoredMounds: [.init(center: .nan, width: 1, height: 5), .init(center: 0.5, width: 0.1, height: 200)]) .bounded
        check(invalidLayout.bottomLimit == 18 && invalidLayout.baseDepth == 0,
              "invalid bottom depth preferences fall back to the original cap and zero base")
        check(invalidLayout.authoredMounds.isEmpty, "invalid authored mound data is rejected before rendering")
        check(DesktopSnowOptions(bottomLimit: 8, baseDepth: 40).bounded.baseDepth == 8,
              "fixed base is always clipped to the selected total snow cap")
        for size in [CGSize.zero, CGSize(width: CGFloat.nan, height: 1000), CGSize(width: 1000, height: CGFloat.infinity),
                     CGSize(width: 159, height: 1000), CGSize(width: 1000, height: 16_385)] {
            check(DesktopSnowSimulation(size: size, seed: 1) == nil, "invalid display sizes refused before allocation")
        }
        let display = CGRect(x: -1000, y: -300, width: 1000, height: 800)
        let front = DesktopSnowWindowGeometry(id: 100, frame: CGRect(x: -700, y: -100, width: 400, height: 400))
        let back = DesktopSnowWindowGeometry(id: 200, frame: CGRect(x: -900, y: -200, width: 800, height: 300))
        let surfaces = DesktopSnowPolicy.surfaces(displayFrame: display, windows: [front, back], includeWindows: true)
        let rearSurfaces = surfaces.filter { $0.id >> 8 == 200 }
        check(rearSurfaces.count == 2, "foreground bounds split the covered rear top edge")
        check(rearSurfaces.map(\.left) == [100, 700] && rearSurfaces.map(\.right) == [300, 900], "only exposed rear pieces collect")
        check(rearSurfaces.allSatisfy { $0.y == 400 }, "negative-coordinate display converts to local bottom-left")
        let offSurfaces = DesktopSnowPolicy.surfaces(displayFrame: display, windows: [front, back], includeWindows: false)
        check(offSurfaces.count == 1 && offSurfaces[0].kind == .bottom, "window edges off does not use supplied app geometry")
        let ownDock = CGRect(x: -800, y: -290, width: 600, height: 76)
        let dockSurfaces = DesktopSnowPolicy.surfaces(displayFrame: display, windows: [], includeWindows: false, ownDockFrame: ownDock)
        check(dockSurfaces.contains { $0.kind == .dock && $0.left == 200 && $0.right == 800 && $0.y == 86 },
              "our Dock collects from known app-owned bounds without querying other windows")
        let converted = DesktopSnowPolicy.appKitFrame(quartz: CGRect(x: -900, y: 900, width: 400, height: 200), primaryTop: 1000)
        check(converted == CGRect(x: -900, y: -100, width: 400, height: 200), "Quartz conversion supports monitors below/left of main")
        check(DesktopSnowPolicy.appKitFrame(quartz: .infinite, primaryTop: 1000) == nil, "invalid window rect refused")
        for (frame, usable, safe) in [
            (CGRect(x: 0, y: 0, width: 1512, height: 982), CGRect(x: 0, y: 82, width: 1512, height: 865), 37.0),
            (CGRect(x: -1920, y: -400, width: 1920, height: 1080), CGRect(x: -1920, y: -320, width: 1920, height: 1055 - 80), 25.0),
            (CGRect(x: 300, y: 1000, width: 1280, height: 800), CGRect(x: 370, y: 1000, width: 1210, height: 800), 0.0)
        ] {
            for gap in [0.0, 4, 12, 24, 32] {
                let maximized = usable.insetBy(dx: gap, dy: gap)
                check(DesktopSnowPolicy.excludesTopBank(windowFrame: maximized, displayFrame: frame, usableFrame: usable, topSafeInset: safe),
                      "current-desktop maximization with ordinary margins has no menu-bar/physical-notch ledge")
            }
            check(DesktopSnowPolicy.excludesTopBank(windowFrame: frame, displayFrame: frame, usableFrame: usable, topSafeInset: safe),
                  "native full-screen bounds cannot create a top bank")
            let wideNormal = CGRect(x: usable.minX, y: usable.minY + 40, width: usable.width, height: usable.height * 0.55)
            check(!DesktopSnowPolicy.excludesTopBank(windowFrame: wideNormal, displayFrame: frame, usableFrame: usable, topSafeInset: safe),
                  "a wide ordinary window retains accumulation")
            let movedLarge = usable.insetBy(dx: 8, dy: 8).offsetBy(dx: 0, dy: -100)
            check(!DesktopSnowPolicy.excludesTopBank(windowFrame: movedLarge, displayFrame: frame, usableFrame: usable, topSafeInset: safe),
                  "a large window moved away from the top retains accumulation")
            let rear = DesktopSnowWindowGeometry(id: 52, frame: CGRect(x: usable.minX + 80, y: usable.minY + 60,
                width: usable.width - 160, height: usable.height * 0.5))
            let covering = DesktopSnowWindowGeometry(id: 51, frame: usable)
            let covered = DesktopSnowPolicy.surfaces(displayFrame: frame, windows: [covering, rear], includeWindows: true,
                usableFrame: usable, topSafeInset: safe)
            check(!covered.contains { $0.kind == .window }, "maximized windows remain occluders even when their own top snowbank is omitted")
        }
        let moundSurface = DesktopSnowSurface(id: 0x57494e, kind: .window, left: 0, right: 240, y: 100)
        let emptyBank = DesktopSnowBank(surface: moundSurface, heights: Array(repeating: 0, count: 20))
        check(DesktopSnowPolicy.moundSilhouettes(for: emptyBank).isEmpty, "zero-height banks have no hairline/path")
        let splitBank = DesktopSnowBank(surface: moundSurface, heights: [0, 0, 1, 2, 1, 0, 0, 3, 5, 3, 0, 0, 0, 1, 1, 1, 0, 0, 0, 0])
        let mounds = DesktopSnowPolicy.moundSilhouettes(for: splitBank)
        check(mounds.count == 3, "empty bins separate real rounded piles rather than bridging a whole edge")
        for mound in mounds {
            check(mound.points.first?.y == 0 && mound.points.last?.y == 0, "each pile has zero-height rounded shoulders")
            check(mound.points.allSatisfy { $0.x.isFinite && $0.y.isFinite && (0...11).contains($0.y) }, "silhouette heights stay finite and capped")
            check(zip(mound.points, mound.points.dropFirst()).allSatisfy { $0.x < $1.x }, "rounded mound control points never fold back")
        }
        check(zip(mounds, mounds.dropFirst()).allSatisfy { $0.points.last!.x < $1.points.first!.x }, "empty gaps remain genuinely empty")
        let fullBank = DesktopSnowBank(surface: moundSurface, heights: Array(repeating: 11, count: 20))
        let fullMounds = DesktopSnowPolicy.moundSilhouettes(for: fullBank)
        let positivePeaks = fullMounds.flatMap(\.points).map(\.y).filter { $0 > 0 }
        check((positivePeaks.max()! - positivePeaks.min()!) > 2, "saturated accumulation has coherent uneven crests rather than a ruler-flat top")
        check(DesktopSnowPolicy.moundSilhouettes(for: fullBank) == fullMounds, "unchanged bank silhouettes are exactly stable without random frame flicker")
        check(fullMounds.count >= 2, "a fully deposited window edge keeps several distinct piles")
        check(DesktopSnowPolicy.moundSilhouettes(for: fullBank, options: .init()) == fullMounds,
              "default mound sliders preserve the original deterministic shape exactly")
        let tallerMounds = DesktopSnowPolicy.moundSilhouettes(for: fullBank, options: .init(moundHeight: 2))
        let originalPeak = fullMounds.flatMap(\.points).map(\.y).max() ?? 0
        let tallerPeak = tallerMounds.flatMap(\.points).map(\.y).max() ?? 0
        check(tallerPeak > originalPeak * 1.8, "height control reshapes already-visible saturated piles immediately")
        let narrowerMounds = DesktopSnowPolicy.moundSilhouettes(for: fullBank, options: .init(moundWidth: 0.5))
        let originalSpan = fullMounds.reduce(0.0) { $0 + Double($1.points.last!.x - $1.points.first!.x) }
        let narrowSpan = narrowerMounds.reduce(0.0) { $0 + Double($1.points.last!.x - $1.points.first!.x) }
        check(narrowSpan < originalSpan, "width control changes the visible mound footprints")
        let closerMounds = DesktopSnowPolicy.moundSilhouettes(for: fullBank, options: .init(moundSpacing: 0.5))
        check(closerMounds.count >= fullMounds.count, "spacing control creates a denser bounded mound layout")
        let bottomSurface = DesktopSnowSurface(id: 0x424f54, kind: .bottom, left: 0, right: 1_200, y: 0)
        let emptyBottom = DesktopSnowBank(surface: bottomSurface, heights: Array(repeating: 0, count: 100))
        let authored = [DesktopSnowAuthoredMound(center: 0.25, width: 0.1, height: 14),
                        DesktopSnowAuthoredMound(center: 0.76, width: 0.16, height: 9)]
        let customOptions = DesktopSnowOptions(bottomLimit: 30, baseDepth: 0, customBottomLayout: true, authoredMounds: authored)
        let customMounds = DesktopSnowPolicy.moundSilhouettes(for: emptyBottom, options: customOptions)
        check(customMounds.count == 2, "zero-base custom mode renders only the authored piles")
        check(customMounds.map { Double($0.points.first!.x + $0.points.last!.x) / 2 }.sorted() == [300, 912],
              "authored pile centers track their normalized positions exactly")
        check(customMounds.map { $0.points.map(\.y).max()! }.sorted() == [9, 14],
              "authored heights use individual fixed point values")
        check(DesktopSnowPolicy.settledHeight(for: emptyBottom, at: 600, options: customOptions) == 0,
              "zero-base custom mode has no automatic snow in clear zones")
        let edgeOptions = DesktopSnowOptions(bottomLimit: 30, customBottomLayout: true,
            authoredMounds: [.init(center: 0, width: 0.2, height: 14), .init(center: 1, width: 0.2, height: 11)])
        let edgeMounds = DesktopSnowPolicy.moundSilhouettes(for: emptyBottom, options: edgeOptions)
        check(edgeMounds.count == 2 && abs(Double(edgeMounds[0].points.first!.y) - 14) < 0.000_001 &&
              abs(Double(edgeMounds[1].points.last!.y) - 11) < 0.000_001,
              "mounds clipped at either display edge keep their authored peak at the authored center")
        check(abs(DesktopSnowPolicy.settledHeight(for: emptyBottom, at: 0, options: edgeOptions) - 14) < 0.000_001 &&
              abs(DesktopSnowPolicy.settledHeight(for: emptyBottom, at: 1_200, options: edgeOptions) - 11) < 0.000_001,
              "edge-clipped authored peaks collide at their exact normalized centers")
        let baseOptions = DesktopSnowOptions(bottomLimit: 22, baseDepth: 7, customBottomLayout: true)
        let baseOnlyMounds = DesktopSnowPolicy.moundSilhouettes(for: emptyBottom, options: baseOptions)
        check(baseOnlyMounds.count == 1 && abs(DesktopSnowPolicy.settledHeight(for: emptyBottom, at: 600, options: baseOptions) - 7) < 0.001,
              "fixed base renders and collides across an otherwise empty display")
        let clippedOptions = DesktopSnowOptions(bottomLimit: 20, baseDepth: 7, customBottomLayout: true,
            authoredMounds: [.init(center: 0.5, width: 0.2, height: 80)])
        let clippedMound = DesktopSnowPolicy.moundSilhouettes(for: emptyBottom, options: clippedOptions).last!
        check(clippedMound.points.map(\.y).max()! <= 20 &&
              DesktopSnowPolicy.settledHeight(for: emptyBottom, at: 600, options: clippedOptions) <= 20,
              "authored profiles and collision respect the absolute bottom cap")
        check(DesktopSnowPolicy.bottomRenderHeight(options: clippedOptions) == 20,
              "renderer layer bounds use the same absolute bottom cap")
        let automaticWithAuthored = DesktopSnowPolicy.moundSilhouettes(for: emptyBottom,
            options: DesktopSnowOptions(authoredMounds: authored))
        check(automaticWithAuthored == DesktopSnowPolicy.moundSilhouettes(for: emptyBottom),
              "automatic mode retains deterministic piles and ignores custom definitions")
        let denseCoverage = fullMounds.reduce(0.0) { $0 + Double($1.points.last!.x - $1.points.first!.x) }
        check(denseCoverage < (moundSurface.right - moundSurface.left) * 0.75, "saturation cannot turn the whole supporting edge into a white strip")
        for pair in zip(fullMounds, fullMounds.dropFirst()) {
            let gap = Double(pair.1.points.first!.x - pair.0.points.last!.x)
            check(gap > 4, "dense neighboring piles retain a visible baseline gap")
            let middle = Double(pair.0.points.last!.x) + gap / 2
            check(DesktopSnowPolicy.settledHeight(for: fullBank, at: middle) == 0,
                  "flakes in a clear gap land on the real supporting edge, not invisible raw accumulation")
        }
        // Independently evaluate the exact production quadratic drawing loop.
        // This detects a physics/render mismatch without copying its inverse-x solver.
        for bank in [fullBank, splitBank,
                     DesktopSnowBank(surface: .init(id: 58, kind: .bottom, left: 0, right: 1512, y: 0), heights: Array(repeating: 18, count: 126)),
                     DesktopSnowBank(surface: .init(id: 91, kind: .window, left: 0, right: 170, y: 0), heights: Array(repeating: 7.2, count: 21))] {
            let silhouettes = DesktopSnowPolicy.moundSilhouettes(for: bank)
            check(!silhouettes.isEmpty, "dense and sparse fixtures retain visible settled snow")
            let limit = bank.surface.kind == .bottom ? 18.0 : 11.0
            for mound in silhouettes {
                var start = mound.points[0]
                for index in 1...mound.points.count {
                    let control = mound.points[index - 1]
                    let end: CGPoint
                    if index == mound.points.count { end = control }
                    else {
                        let next = mound.points[index]
                        end = .init(x: (control.x + next.x) / 2, y: (control.y + next.y) / 2)
                    }
                    for sample in 0...16 {
                        let t = Double(sample) / 16, u = 1 - t
                        let x = u*u*Double(start.x) + 2*u*t*Double(control.x) + t*t*Double(end.x)
                        let visibleHeight = u*u*Double(start.y) + 2*u*t*Double(control.y) + t*t*Double(end.y)
                        let collisionHeight = DesktopSnowPolicy.settledHeight(for: bank, at: x)
                        check(abs(collisionHeight - visibleHeight) < 0.000_001, "landing follows the same soft contour that is actually drawn")
                        check(collisionHeight.isFinite && collisionHeight >= 0 && collisionHeight <= limit,
                              "collision heights stay finite and within the established11/18point caps")
                    }
                    start = end
                }
            }
        }

        var editable = DesktopSnowSimulation(size: CGSize(width: 320, height: 220), seed: 81)!
        let editableEdge = DesktopSnowSurface(id: 500, kind: .window, left: 0, right: 240, y: 80)
        editable.updateSurfaces([editableEdge], accumulating: true)
        let brushOptions = DesktopSnowOptions()
        check(editable.editableSurface(at: CGPoint(x: 48, y: 84), radius: 18, options: brushOptions) == 500,
              "edit hit testing identifies the nearby local snow bank")
        check(editable.editableSurface(at: CGPoint(x: 300, y: 180), radius: 18, options: brushOptions) == nil,
              "edit hit testing does not select distant surfaces")
        check(editable.sculpt(surfaceID: 500, at: CGPoint(x: 48, y: 84), tool: .build,
                              radius: 24, strength: 1, options: brushOptions),
              "build brush deposits a bounded local mound")
        let built = editable.banks[0].heights
        check(built.contains(where: { $0 > 0 }) && built.filter { $0 > 0 }.count < built.count,
              "build affects only bins inside its soft local footprint")
        let massBeforeMove = built.reduce(0, +)
        var fineMove = editable
        check(fineMove.sculpt(surfaceID: 500, at: CGPoint(x: 50, y: 84), tool: .move,
                              radius: 24, strength: 1, from: CGPoint(x: 48, y: 84), options: brushOptions),
              "a short drag moves snow even when the pointer travels less than half a bin")
        check(abs(fineMove.banks[0].heights.reduce(0, +) - massBeforeMove) < 0.000_01,
              "a short drag preserves the amount of snow")
        check(editable.sculpt(surfaceID: 500, at: CGPoint(x: 84, y: 84), tool: .move,
                              radius: 24, strength: 1, from: CGPoint(x: 48, y: 84), options: brushOptions),
              "move brush translates the selected local pile")
        let moved = editable.banks[0].heights
        check(abs(moved.reduce(0, +) - massBeforeMove) < 0.000_01,
              "move brush preserves the amount of snow when destinations have capacity")
        check(moved.enumerated().reduce(0.0) { $0 + Double($1.offset) * $1.element } >
              built.enumerated().reduce(0.0) { $0 + Double($1.offset) * $1.element },
              "move brush follows the drag direction")
        check(editable.sculpt(surfaceID: 500, at: CGPoint(x: 84, y: 84), tool: .carve,
                              radius: 24, strength: 1, options: brushOptions),
              "carve brush removes a local amount")
        check(editable.banks[0].heights.reduce(0, +) < moved.reduce(0, +), "carve reduces accumulated snow")
        let beforeInvalidBrush = editable
        for (point, radius, strength) in [
            (CGPoint(x: CGFloat.nan, y: 0), 20.0, 0.5),
            (CGPoint(x: 10, y: 10), .infinity, 0.5),
            (CGPoint(x: 10, y: 10), 20, Double.nan)
        ] {
            check(!editable.sculpt(surfaceID: 500, at: point, tool: .build, radius: radius,
                                   strength: strength, options: brushOptions),
                  "invalid brush input is rejected")
        }
        check(editable == beforeInvalidBrush, "invalid brush input leaves all simulation state untouched")
        editable.clearAccumulation()
        check(editable.banks[0].heights.allSatisfy { $0 == 0 }, "clear removes manually sculpted snow too")
        var tallBottom = DesktopSnowSimulation(size: CGSize(width: 1_200, height: 800), seed: 92)!
        let tallEdge = DesktopSnowSurface(id: 501, kind: .bottom, left: 0, right: 1_200, y: 1)
        tallBottom.updateSurfaces([tallEdge], accumulating: true)
        let tallOptions = DesktopSnowOptions(bottomLimit: 100, baseDepth: 0)
        check(tallBottom.editableSurface(at: CGPoint(x: 420, y: 70), radius: 12, options: tallOptions) == tallEdge.id,
              "brush hit testing reaches banks taller than the legacy 18-point bottom")
        for _ in 0..<12 {
            _ = tallBottom.sculpt(surfaceID: tallEdge.id, at: CGPoint(x: 420, y: 70), tool: .build,
                                  radius: 18, strength: 1, options: tallOptions)
        }
        check((tallBottom.banks[0].heights.max() ?? 0) > 18 && (tallBottom.banks[0].heights.max() ?? 0) <= 100,
              "tall-bank sculpting uses the selected cap while retaining bounded physical mass")
        let customBottomOptions = DesktopSnowOptions(bottomLimit: 60, baseDepth: 5, customBottomLayout: true,
            authoredMounds: [.init(center: 0.5, width: 0.2, height: 20)])
        let customBankHeight = tallBottom.banks[0].heights
        check(tallBottom.editableSurface(at: CGPoint(x: 600, y: 10), radius: 12, options: customBottomOptions) == nil,
              "custom authored bottom banks are not brush-selectable")
        check(!tallBottom.sculpt(surfaceID: tallEdge.id, at: CGPoint(x: 600, y: 10), tool: .build,
                                 radius: 18, strength: 1, options: customBottomOptions) &&
              tallBottom.banks[0].heights == customBankHeight,
              "custom authored bottom banks cannot allocate invisible sculpted bins")
        var footprintWidths = Set<Int>(), footprintPeaks = Set<Int>()
        for seed in 1...24 {
            for width in [1.0, 36, 132, 170, 240, 640, 1512, 16_384] {
                for kind in [DesktopSnowSurface.Kind.window, .dock, .bottom] {
                    let bank = DesktopSnowBank(surface: .init(id: UInt64(seed), kind: kind, left: 20, right: 20 + width, y: 100),
                                              heights: Array(repeating: kind == .bottom ? 18 : 11, count: 128))
                    let piles = DesktopSnowPolicy.moundSilhouettes(for: bank)
                    check(!piles.isEmpty && piles.count <= DesktopSnowPolicy.maximumMoundsPerSurface,
                          "all supported widths have a bounded number of separate mountains")
                    check(piles == DesktopSnowPolicy.moundSilhouettes(for: bank), "rendering is deterministic for the same identity and deposits")
                    let limit = kind == .bottom ? 18.0 : 11.0
                    for mound in piles {
                        check(mound.points.count <= DesktopSnowPolicy.maximumMoundPoints, "vector detail has a fixed work/memory cap")
                        check(mound.points.first!.y == 0 && mound.points.last!.y == 0, "every mountain returns softly to the baseline")
                        check(mound.points.allSatisfy { $0.x.isFinite && $0.y.isFinite && $0.x >= 0 && $0.x <= width && $0.y >= 0 && $0.y <= limit },
                              "control points stay within their supporting edge and unchanged height cap")
                        check(zip(mound.points, mound.points.dropFirst()).allSatisfy { $0.x < $1.x }, "soft profiles never fold or self-intersect")
                        footprintWidths.insert(Int((mound.points.last!.x - mound.points.first!.x) * 10))
                        footprintPeaks.insert(Int((mound.points.map(\.y).max() ?? 0) * 10))
                    }
                    check(zip(piles, piles.dropFirst()).allSatisfy { $0.points.last!.x < $1.points.first!.x }, "pile footprints never bridge their baseline gaps")
                }
            }
        }
        check(footprintWidths.count > 10 && footprintPeaks.count > 10, "fixed spatial seeds provide visibly varied widths and crests")
        let organicBank = DesktopSnowBank(surface: .init(id: 0x57494e, kind: .window, left: 0, right: 640, y: 0),
                                          heights: Array(repeating: 11, count: 54))
        let organicPiles = DesktopSnowPolicy.moundSilhouettes(for: organicBank)
        let organicWidths = organicPiles.map { Double($0.points.last!.x - $0.points.first!.x) }
        let organicGaps = zip(organicPiles, organicPiles.dropFirst()).map { Double($1.points.first!.x - $0.points.last!.x) }
        check(organicPiles.count >= 2 && organicPiles.count < 7, "a long dense edge has stable clear zones between clusters")
        check(organicWidths.max()! > organicWidths.min()! * 1.6, "organic footprints have clearly different widths, not a row of identical humps")
        check(organicGaps.max()! > organicGaps.min()! * 2 && organicGaps.max()! > 100,
              "clustered piles and broad empty stretches visibly break an evenly spaced row")
        for pair in zip(organicPiles, organicPiles.dropFirst()) {
            let center = Double(pair.0.points.last!.x + pair.1.points.first!.x) / 2
            check(DesktopSnowPolicy.settledHeight(for: organicBank, at: center) == 0,
                  "larger organic clearings use the same zero-height collision as rendering")
        }
        for seed in 0..<32 {
            for width in [70.0, 132, 170, 240, 308] {
                let smallCap = DesktopSnowBank(surface: .init(id: UInt64(seed), kind: .window, left: 0, right: width, y: 0),
                                               heights: Array(repeating: 7.2, count: 24))
                let piles = DesktopSnowPolicy.moundSilhouettes(for: smallCap)
                check(!piles.isEmpty, "stable clear zones never blank every pile on a Home-sized cap")
                check(piles == DesktopSnowPolicy.moundSilhouettes(for: smallCap), "small caps keep stable positions across frames")
            }
        }

        for heights in [[], [Double.nan], [Double.infinity], [-1], Array(repeating: 1.0, count: DesktopSnowPolicy.maximumBinsPerSurface + 1)] {
            let invalid = DesktopSnowBank(surface: moundSurface, heights: heights)
            check(DesktopSnowPolicy.moundSilhouettes(for: invalid).isEmpty, "invalid deposited arrays cannot allocate a path")
            check(DesktopSnowPolicy.settledHeight(for: invalid, at: 120).isFinite, "hostile arrays cannot produce a nonfinite collision height")
        }
        for coordinate in [Double.nan, .infinity, -.infinity, -1, 241] {
            check(DesktopSnowPolicy.settledHeight(for: fullBank, at: coordinate) == 0, "invalid and outside coordinates have no raised collision")
        }
        for invalidWidth in [Double.nan, .infinity, -1, 0, 16_385, Double.greatestFiniteMagnitude] {
            let invalid = DesktopSnowBank(surface: .init(id: 1, kind: .window, left: 0, right: invalidWidth, y: 0), heights: [11, 11])
            check(DesktopSnowPolicy.moundSilhouettes(for: invalid).isEmpty, "invalid or oversized spans are refused before integer conversion")
            check(DesktopSnowPolicy.settledHeight(for: invalid, at: 1) == 0, "invalid spans have no raised collision")
        }

        for interval in [1 / 30.0, 1 / 15.0] {
            check(DesktopSnowPolicy.interpolationDuration(frameInterval: interval) > interval, "finite compositor bridge overlaps ordinary timer tolerance")
            check(DesktopSnowPolicy.interpolationDuration(frameInterval: interval) <= 0.12, "animation lifetime is bounded independently of timer stalls")
        }
        for invalid in [Double.nan, .infinity, -.infinity, -1, 0, 1] {
            check(DesktopSnowPolicy.interpolationDuration(frameInterval: invalid) == 0, "invalid or stalled cadence does not create a long animation")
        }
        let previousFlake = DesktopSnowParticle(id: 10, x: 319, y: 100, velocityX: 20, velocityY: -30, radius: 2, phase: 0)
        var wrappedFlake = previousFlake; wrappedFlake.x = -4; wrappedFlake.renderRevision += 1
        check(!DesktopSnowPolicy.shouldInterpolate(from: previousFlake, to: wrappedFlake, frameInterval: 1 / 15), "same-ID wraps never sweep across a display")
        var continuousFlake = previousFlake; continuousFlake.x -= 1; continuousFlake.y -= 2
        check(DesktopSnowPolicy.shouldInterpolate(from: previousFlake, to: continuousFlake, frameInterval: 1 / 15), "normal same-ID movement interpolates")
        check(!DesktopSnowPolicy.shouldInterpolate(from: nil, to: continuousFlake, frameInterval: 1 / 15), "new layers never animate from a recycled layer's old position")
        let unrelated = DesktopSnowParticle(id: 11, x: 318, y: 98, velocityX: 20, velocityY: -30, radius: 2, phase: 0)
        check(!DesktopSnowPolicy.shouldInterpolate(from: previousFlake, to: unrelated, frameInterval: 1 / 15), "array/index replacement cannot animate a different identity")
        for scale in [1.0, 1.25, 1.5, 2, 3] {
            check(DesktopSnowPolicy.backingScale(scale) == scale, "renderer retains exact display backing scale without raster downsampling")
        }
        for scale in [Double.nan, .infinity, -.infinity, 0, -1, 100] {
            check(DesktopSnowPolicy.backingScale(scale) == 1, "invalid backing scale has a finite nonzero fallback")
        }
        let sourceFrame = CGRect(x: 0, y: 0, width: 320, height: 100)
        let sourceEdge = DesktopSnowSurface(id: 77, kind: .window, left: 0, right: 320, y: 100, sourceFrame: sourceFrame)
        var clippedEdge = sourceEdge; clippedEdge.left = 140
        check(!DesktopSnowPolicy.shouldShed(from: sourceEdge, to: clippedEdge), "an exposed segment clipped by a newly focused window is not physical motion")
        var translatedEdge = sourceEdge; translatedEdge.left += 10; translatedEdge.right += 10
        translatedEdge.sourceFrame = sourceFrame.offsetBy(dx: 10, dy: 0)
        check(DesktopSnowPolicy.shouldShed(from: sourceEdge, to: translatedEdge), "actual original window translation can gently shed")
        var resizedEdge = sourceEdge; resizedEdge.right -= 10
        resizedEdge.sourceFrame = CGRect(x: 0, y: 0, width: 310, height: 100)
        check(DesktopSnowPolicy.shouldShed(from: sourceEdge, to: resizedEdge), "known original window resize can gently shed")
        var ambiguousEdge = sourceEdge; ambiguousEdge.sourceFrame = nil
        var ambiguousClip = clippedEdge; ambiguousClip.sourceFrame = nil
        check(!DesktopSnowPolicy.shouldShed(from: ambiguousEdge, to: ambiguousClip), "unknown one-sided segment change clears quietly")
        for active in [false, true] {
            for windowEdges in [false, true] {
                for accumulation in [false, true] {
                    check(DesktopSnowPolicy.shouldSampleGeometry(active: active, windowEdges: windowEdges, accumulation: accumulation,
                        now: 5, lastSample: nil) == (active && windowEdges && accumulation), "geometry access needs all three explicit gates")
                }
            }
        }
        check(!DesktopSnowPolicy.shouldSampleGeometry(active: true, windowEdges: true, accumulation: true, now: 5.49, lastSample: 5),
              "geometry never polls faster than two Hz")
        check(DesktopSnowPolicy.shouldSampleGeometry(active: true, windowEdges: true, accumulation: true, now: 5.5, lastSample: 5),
              "geometry may refresh at the two-Hz boundary")
        check(!DesktopSnowPolicy.shouldSampleGeometry(active: true, windowEdges: true, accumulation: true, now: .nan, lastSample: nil),
              "invalid clocks never trigger enumeration")
        check(!DesktopSnowPolicy.shouldSampleGeometry(active: true, windowEdges: true, accumulation: true, now: 4, lastSample: 5),
              "clock reversal cannot cause a rapid scan")
        var many = (0..<500).map { index in
            DesktopSnowSurface(id: UInt64(index + 1), kind: .window, left: -20, right: 1_200, y: Double(index))
        }
        many.append(.init(id: 1, kind: .window, left: 0, right: 100, y: 20))
        many.append(.init(id: 900, kind: .window, left: .nan, right: 100, y: 20))
        let bounded = DesktopSnowPolicy.boundedSurfaces(many, size: display.size)
        check(bounded.count <= DesktopSnowPolicy.maximumSurfaces, "surface allocation is capped")
        check(Set(bounded.map(\.id)).count == bounded.count, "duplicate edge identity is discarded")
        check(bounded.allSatisfy { $0.left >= 0 && $0.right <= display.width }, "surfaces clip to their display")
        let tiny = CGSize(width: 320, height: 220)
        let landingEdge = DesktopSnowSurface(id: 99, kind: .window, left: 0, right: 320, y: 100)
        var first = DesktopSnowSimulation(size: tiny, seed: 42)!
        var second = DesktopSnowSimulation(size: tiny, seed: 42)!
        let standard = DesktopSnowOptions(intensity: 1, speed: 1, wind: 0.1)
        check(!DesktopSnowOptions().pointerSweep && DesktopSnowOptions(pointerSweep: true).bounded.pointerSweep,
              "settled-bank pointer sweep is opt-in and survives option bounding")
        first.updateSurfaces([landingEdge], accumulating: true)
        second.updateSurfaces([landingEdge], accumulating: true)
        first.seedInitialSnow(options: standard, lowImpact: false)
        second.seedInitialSnow(options: standard, lowImpact: false)
        var seenIDs = Set(first.particles.map(\.id))
        for index in 0..<1_800 {
            let previousByID = Dictionary(uniqueKeysWithValues: first.particles.map { ($0.id, $0) })
            let pointer = CGPoint(x: 60 + Double(index % 250), y: 150)
            first.step(seconds: 1 / 30, options: standard, lowImpact: false, pointer: pointer)
            second.step(seconds: 1 / 30, options: standard, lowImpact: false, pointer: pointer)
            check(Set(first.particles.map(\.id)).count == first.particles.count && first.particles.allSatisfy { $0.id != 0 },
                  "all live flakes have unique nonzero stable identities")
            for particle in first.particles {
                if let previous = previousByID[particle.id] {
                    check(previous.radius == particle.radius && previous.shedding == particle.shedding,
                          "surviving identities still represent the same physical flake after compaction/removal")
                } else { check(!seenIDs.contains(particle.id), "a removed identity is never reused by a later flake") }
            }
            seenIDs.formUnion(first.particles.map(\.id))
            if index % 30 == 0 {
                check(first == second, "same seed/input produces exact deterministic physics including pointer disturbance")
                check(first.particles.count <= DesktopSnowPolicy.maximumParticles, "all normal and shedding particles remain capped")
                check(first.particles.allSatisfy { [$0.x, $0.y, $0.velocityX, $0.velocityY, $0.radius, $0.phase, $0.age].allSatisfy(\.isFinite) },
                      "all physics stays finite during sustained motion")
            }
        }
        check(first.banks.first?.heights.contains(where: { $0 > 0.25 }) == true, "falling flakes accumulate on a real top-edge surface")
        check(first.banks.allSatisfy { $0.heights.count <= DesktopSnowPolicy.maximumBinsPerSurface && $0.heights.allSatisfy { $0 <= 11 } },
              "bank bins/heights remain bounded under sustained snowfall")
        var sweep = DesktopSnowSimulation(size: tiny, seed: 701)!
        sweep.updateSurfaces([landingEdge], accumulating: true)
        check(sweep.sculpt(surfaceID: landingEdge.id, at: CGPoint(x: 160, y: 105), tool: .build,
                           radius: 30, strength: 1, options: standard), "sweep fixture builds a settled bank")
        let bankMassBeforeSweep = sweep.banks[0].heights.reduce(0, +)
        let sweepBin = sweep.banks[0].heights.indices.max(by: { sweep.banks[0].heights[$0] < sweep.banks[0].heights[$1] })!
        let pointerX = sweep.banks[0].surface.left + sweep.banks[0].binWidth * (Double(sweepBin) + 0.5)
        let pointerY = sweep.banks[0].surface.y + DesktopSnowPolicy.settledHeight(for: sweep.banks[0], at: pointerX)
        var sweepOptions = standard; sweepOptions.pointerSweep = true
        sweep.step(seconds: 1 / 30, options: sweepOptions, lowImpact: false, pointer: CGPoint(x: pointerX - 35, y: pointerY))
        let beforeSweepRelease = sweep.particles.filter(\.shedding).count
        sweep.step(seconds: 1 / 30, options: sweepOptions, lowImpact: false, pointer: CGPoint(x: pointerX + 35, y: pointerY))
        let releasedBySweep = sweep.particles.filter(\.shedding).count - beforeSweepRelease
        check(releasedBySweep > 0 && releasedBySweep <= DesktopSnowPolicy.maximumSweepPerStep,
              "a click-through pointer sweep releases only a tiny bounded number of flakes")
        check(sweep.banks[0].heights.reduce(0, +) < bankMassBeforeSweep,
              "pointer sweep removes flakes from the visible settled bank")
        let airborneSweepIDs = Set(sweep.particles.filter(\.shedding).map(\.id))
        for _ in 0..<240 { sweep.step(seconds: 1 / 30, options: sweepOptions, lowImpact: false, pointer: CGPoint(x: pointerX + 35, y: pointerY)) }
        check(airborneSweepIDs.isDisjoint(with: Set(sweep.particles.filter(\.shedding).map(\.id))),
              "swept flakes finish their bounded fall and can settle again")
        check(sweep.particles.filter(\.shedding).count <= DesktopSnowPolicy.maximumSheddingParticles,
              "repeated pointer samples cannot exceed the shared shedding cap")
        var quietSwitch = first
        var unmodified = first
        var quietSource = landingEdge; quietSource.sourceFrame = sourceFrame
        quietSwitch.updateSurfaces([quietSource], accumulating: true)
        let beforeFocusChange = quietSwitch.particles
        for index in 0..<80 {
            var exposed = quietSource
            exposed.left = index % 2 == 0 ? 140 : 0
            quietSwitch.updateSurfaces([exposed], accumulating: true)
            check(quietSwitch.particles == beforeFocusChange, "repeated focus/occlusion changes preserve every existing airborne flake exactly")
        }
        quietSwitch.updateSurfaces([], accumulating: true)
        check(quietSwitch.particles == beforeFocusChange, "closing/minimizing or a disappeared bank emits no avalanche")
        quietSwitch.updateSurfaces([quietSource], accumulating: true)
        var quietOptions = standard; quietOptions.accumulation = false
        for _ in 0..<60 {
            quietSwitch.step(seconds: 1 / 30, options: quietOptions, lowImpact: false)
            unmodified.step(seconds: 1 / 30, options: quietOptions, lowImpact: false)
            check(quietSwitch.particles == unmodified.particles, "focus changes do not consume RNG, IDs, timing, speed or future snowfall state")
        }
        let beforeMove = first.particles.filter(\.shedding).count
        first.updateSurfaces([.init(id: 99, kind: .window, left: 25, right: 320, y: 110)], accumulating: true)
        check(first.particles.filter(\.shedding).count > beforeMove, "moving/resizing a window releases its old snow as falling fragments")
        check(first.banks.first?.heights.allSatisfy { $0 == 0 } == true, "new window location starts with an empty bank")
        check(first.particles.count <= DesktopSnowPolicy.maximumParticles, "movement burst shares the total particle cap")
        check(first.particles.filter(\.shedding).count - beforeMove <= DesktopSnowPolicy.maximumShedPerUpdate,
              "one real geometry update releases at most eight fragments")
        let movedSnow = first
        for speed in [0.25, 1.0, 2.5] {
            var gentle = movedSnow
            let gentleOptions = DesktopSnowOptions(intensity: 1, speed: speed, wind: 1, accumulation: false)
            for _ in 0..<90 {
                let previous = Dictionary(uniqueKeysWithValues: gentle.particles.filter(\.shedding).map { ($0.id, $0) })
                gentle.step(seconds: 1 / 30, options: gentleOptions, lowImpact: false)
                for flake in gentle.particles where flake.shedding {
                    check(flake.velocityY >= -DesktopSnowPolicy.maximumSheddingSpeed && abs(flake.velocityX) <= 22.0001,
                          "movement fragments have gentle bounded gravity and horizontal motion")
                    if let old = previous[flake.id] {
                        check((old.y - flake.y) * 30 <= DesktopSnowPolicy.maximumSheddingSpeed + 0.0001,
                              "actual fragment speed is capped even when user Speed is2.5; no double multiplication")
                    }
                }
            }
        }
        var several = DesktopSnowSimulation(size: tiny, seed: 91)!
        let severalEdges = (0..<4).map { index in
            DesktopSnowSurface(id: UInt64(1_000 + index), kind: .window, left: Double(index * 80), right: Double((index + 1) * 80),
                y: 100, sourceFrame: CGRect(x: index * 80, y: 0, width: 80, height: 100))
        }
        several.updateSurfaces(severalEdges, accumulating: true); several.seedInitialSnow(options: standard, lowImpact: false)
        for _ in 0..<900 { several.step(seconds: 1 / 30, options: standard, lowImpact: false) }
        check(several.banks.filter { $0.heights.contains(where: { $0 > 0.25 }) }.count == 4, "burst fixture fills several independent banks")
        let severalBeforeMove = several.particles.filter { !$0.shedding }
        let severalMoved = severalEdges.map { edge -> DesktopSnowSurface in
            var next = edge; next.y += 10; next.sourceFrame = edge.sourceFrame?.offsetBy(dx: 0, dy: 10); return next
        }
        several.updateSurfaces(severalMoved, accumulating: true)
        check(several.particles.filter(\.shedding).count > 0 && several.particles.filter(\.shedding).count <= 8,
              "eight-fragment budget is shared across all banks, not eight per bank")
        check(several.particles.filter { !$0.shedding } == severalBeforeMove, "moving several windows never accelerates/reassigns ordinary snowfall")
        for index in 0..<20 {
            for _ in 0..<15 { several.step(seconds: 1 / 30, options: standard, lowImpact: false) }
            let shifted = severalMoved.map { edge -> DesktopSnowSurface in
                var next = edge; next.y += Double(index % 2); next.sourceFrame = edge.sourceFrame?.offsetBy(dx: 0, dy: CGFloat(index % 2)); return next
            }
            several.updateSurfaces(shifted, accumulating: true)
            check(several.particles.filter(\.shedding).count <= DesktopSnowPolicy.maximumSheddingParticles,
                  "repeated real moves cannot accumulate an unpleasant wall of fragments")
        }
        for _ in 0..<300 { first.step(seconds: 1 / 15, options: standard, lowImpact: true) }
        check(first.particles.allSatisfy { !$0.shedding }, "movement fragments have a finite lifetime")
        first.updateSurfaces([], accumulating: true)
        check(first.banks.isEmpty, "closing/minimizing removes old edge banks")
        first.updateSurfaces([landingEdge], accumulating: true)
        for _ in 0..<300 { first.step(seconds: 1 / 15, options: standard, lowImpact: true) }
        first.clearAccumulation()
        check(first.banks.allSatisfy { $0.heights.allSatisfy { $0 == 0 } }, "clear resets banks without changing settings")
        check(first.particles.allSatisfy { !$0.shedding }, "clear also removes transient bank fragments")
        let beforeInvalidTime = first
        for invalid in [Double.nan, .infinity, -.infinity, -1, 0] {
            first.step(seconds: invalid, options: standard, lowImpact: false)
            check(first == beforeInvalidTime, "invalid elapsed input has no side effects")
        }
        var largeStep = beforeInvalidTime
        var cappedStep = beforeInvalidTime
        largeStep.step(seconds: 3_600, options: standard, lowImpact: false)
        cappedStep.step(seconds: 0.1, options: standard, lowImpact: false)
        check(largeStep == cappedStep, "main-thread stalls never create unbounded catch-up work")
        let highOptions = DesktopSnowOptions(intensity: 100, speed: 100, wind: -100)
        for lowImpact in [false, true] {
            var simulation = DesktopSnowSimulation(size: CGSize(width: 16_384, height: 16_384), seed: 17)!
            simulation.updateSurfaces(many, accumulating: true)
            simulation.seedInitialSnow(options: highOptions, lowImpact: lowImpact)
            for index in 0..<1_200 {
                simulation.step(seconds: 0.1, options: highOptions, lowImpact: lowImpact,
                                pointer: index % 2 == 0 ? CGPoint(x: CGFloat.nan, y: CGFloat.infinity) : CGPoint(x: 0, y: 0))
                check(simulation.particles.count <= DesktopSnowPolicy.maximumParticles, "maximum-size display cannot exceed particle cap")
                check(simulation.banks.count <= DesktopSnowPolicy.maximumSurfaces, "maximum-size display cannot exceed bank cap")
            }
            check(simulation.particles.allSatisfy { $0.x.isFinite && $0.y.isFinite }, "invalid pointer input is harmless")
        }
        var off = standard; off.accumulation = false
        second.step(seconds: 1 / 30, options: off, lowImpact: false)
        check(second.banks.isEmpty, "disabling accumulation immediately discards all banks")
        let resting = first
        first.step(seconds: 1 / 30, options: standard, lowImpact: false, pointer: CGPoint(x: CGFloat.nan, y: 0))
        var noPointer = resting
        noPointer.step(seconds: 1 / 30, options: standard, lowImpact: false)
        check(first == noPointer, "nonfinite pointer is exactly equivalent to no pointer")
        var wrapping = DesktopSnowSimulation(size: tiny, seed: 42)!
        let fastWind = DesktopSnowOptions(intensity: 1, speed: 0.25, wind: 1, accumulation: false)
        wrapping.seedInitialSnow(options: fastWind, lowImpact: true)
        var actualWraps = 0
        for _ in 0..<600 {
            let previous = Dictionary(uniqueKeysWithValues: wrapping.particles.map { ($0.id, $0) })
            wrapping.step(seconds: 1 / 15, options: fastWind, lowImpact: true)
            for current in wrapping.particles {
                if let old = previous[current.id], old.renderRevision != current.renderRevision {
                    actualWraps += 1
                    check(!DesktopSnowPolicy.shouldInterpolate(from: old, to: current, frameInterval: 1 / 15), "actual physics wraps explicitly break visual continuity")
                }
            }
        }
        check(actualWraps > 0, "wind fixture exercises actual side wrapping, not only a fabricated revision")
        print("PASS \(checks) desktop snow physics, geometry, cadence and privacy-gate checks")
    }
}
