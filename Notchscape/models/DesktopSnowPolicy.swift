import CoreGraphics
import Foundation

/// Original, content-free physics. All coordinates here are local AppKit
/// points: origin at the display's bottom-left, with positive y upwards.
struct DesktopSnowOptions: Equatable, Sendable {
    var intensity: Double = 0.5
    var speed: Double = 1
    var wind: Double = 0
    var accumulation = true
    var moundHeight: Double = 1
    var moundWidth: Double = 1
    var moundSpacing: Double = 1
    var pointerSweep = false
    var bottomLimit: Double = 18
    var baseDepth: Double = 0
    var customBottomLayout = false
    var authoredMounds: [DesktopSnowAuthoredMound] = []

    var bounded: Self {
        .init(intensity: DesktopSnowPolicy.clamp(intensity, 0...1, fallback: 0.5),
              speed: DesktopSnowPolicy.clamp(speed, 0.25...2.5, fallback: 1),
              wind: DesktopSnowPolicy.clamp(wind, -1...1, fallback: 0), accumulation: accumulation,
              moundHeight: DesktopSnowPolicy.clamp(moundHeight, 0.4...2, fallback: 1),
              moundWidth: DesktopSnowPolicy.clamp(moundWidth, 0.5...2, fallback: 1),
              moundSpacing: DesktopSnowPolicy.clamp(moundSpacing, 0.5...2, fallback: 1),
              pointerSweep: pointerSweep,
              bottomLimit: DesktopSnowPolicy.clamp(bottomLimit, 0...DesktopSnowPolicy.maximumBottomLimit, fallback: 18),
              baseDepth: min(DesktopSnowPolicy.clamp(baseDepth, 0...DesktopSnowPolicy.maximumBaseDepth, fallback: 0),
                             DesktopSnowPolicy.clamp(bottomLimit, 0...DesktopSnowPolicy.maximumBottomLimit, fallback: 18)),
              customBottomLayout: customBottomLayout,
              authoredMounds: Array(authoredMounds.filter(\.isValid).prefix(DesktopSnowPolicy.maximumAuthoredMounds)))
    }
}

/// A persistent bottom-edge snow pile positioned as fractions of its display.
/// Height is an individual point value and is clipped to available space.
struct DesktopSnowAuthoredMound: Codable, Equatable, Sendable {
    var center: Double
    var width: Double
    var height: Double

    var isValid: Bool {
        center.isFinite && (0...1).contains(center) && width.isFinite && (0.01...1).contains(width) &&
            height.isFinite && (0...DesktopSnowPolicy.maximumBottomLimit).contains(height)
    }
}

enum DesktopSnowBrushTool: String, CaseIterable, Sendable {
    case build
    case carve
    case move
}

struct DesktopSnowEligibility: Equatable, Sendable {
    var enabled = false
    var unlocked = false
    var awake = true
    var activeSession = true
    var presenting = false
    var reduceMotion = false
    var lowImpact = false
    var onBattery = false
    var criticalBattery = false
    var seriousThermal = false
    var capturing = false

    var framesPerSecond: Int? {
        guard enabled, unlocked, awake, activeSession, !presenting, !reduceMotion,
              !criticalBattery, !seriousThermal, !capturing else { return nil }
        return lowImpact || onBattery ? 15 : 30
    }

    var status: String {
        if !enabled { return "Off" }
        if !unlocked || !activeSession { return "Paused while your Mac is locked or another user is active." }
        if !awake { return "Paused while the display is asleep." }
        if presenting { return "Paused in Presentation mode." }
        if reduceMotion { return "Paused while Reduce Motion is enabled." }
        if criticalBattery { return "Paused to protect a very low battery." }
        if seriousThermal { return "Paused while your Mac needs to cool down." }
        if capturing { return "Paused while Notchscape is recording." }
        return lowImpact || onBattery ? "Snowing · Low impact" : "Snowing"
    }
}

struct DesktopSnowSurface: Equatable, Sendable {
    enum Kind: Int, Sendable { case bottom, dock, window }
    let id: UInt64
    let kind: Kind
    var left: Double
    var right: Double
    var y: Double
    /// Original full window bounds, independent of front-window clipping.
    /// Keeping this geometry-only provenance distinguishes a real move/resize
    /// from an exposed segment changing when another app receives focus.
    var sourceFrame: CGRect? = nil
}

/// Bounds/identity only, front-to-back; deliberately has no title, owner name,
/// application content, image, URL, or accessibility reference.
struct DesktopSnowWindowGeometry: Equatable, Sendable {
    let id: UInt32
    let frame: CGRect
    var isDock = false
}

struct DesktopSnowParticle: Equatable, Sendable {
    let id: UInt64
    var x: Double
    var y: Double
    var velocityX: Double
    var velocityY: Double
    var radius: Double
    var phase: Double
    var age: Double = 0
    var shedding = false
    /// A wrap is a discontinuous relocation of the same physical flake.
    /// Compositor interpolation must never sweep it across the whole display.
    var renderRevision: UInt64 = 0
}

struct DesktopSnowBank: Equatable, Sendable {
    var surface: DesktopSnowSurface
    var heights: [Double]
    var binWidth: Double { (surface.right - surface.left) / Double(heights.count) }
}

/// A separate soft pile, in local bank coordinates. Endpoints are on the
/// supporting edge; empty bins never create a full-span white hairline.
struct DesktopSnowMound: Equatable, Sendable {
    let points: [CGPoint]
}

/// One deterministic bounded simulation per display. Runtime supplies only
/// elapsed time and content-free edge segments; the policy performs no I/O.
struct DesktopSnowSimulation: Equatable, Sendable {
    let size: CGSize
    private(set) var particles: [DesktopSnowParticle] = []
    private(set) var banks: [DesktopSnowBank] = []
    private(set) var elapsed: Double = 0
    private var seed: UInt64
    private var spawnCredit: Double = 0
    private var nextParticleID: UInt64 = 0
    private var previousPointer: CGPoint?

    init?(size: CGSize, seed: UInt64) {
        guard DesktopSnowPolicy.validSize(size) else { return nil }
        self.size = size
        self.seed = seed == 0 ? 0x9e3779b97f4a7c15 : seed
    }

    mutating func clearAccumulation() {
        for index in banks.indices { banks[index].heights = Array(repeating: 0, count: banks[index].heights.count) }
        particles.removeAll { $0.shedding }
    }

    /// Returns the first bounded snow bank under a brush point. Coordinates
    /// are local display points with the AppKit bottom-left origin.
    func editableSurface(at point: CGPoint, radius: Double, options: DesktopSnowOptions) -> UInt64? {
        let options = options.bounded
        guard options.accumulation, point.x.isFinite, point.y.isFinite,
              radius.isFinite, (1...200).contains(radius) else { return nil }
        for bank in banks {
            guard bank.surface.kind != .bottom || !options.customBottomLayout else { continue }
            guard bank.surface.left.isFinite, bank.surface.right.isFinite, bank.surface.y.isFinite,
                  !bank.heights.isEmpty, bank.heights.count <= DesktopSnowPolicy.maximumBinsPerSurface else { continue }
            let visibleHeight = bank.surface.kind == .bottom
                ? max(18, DesktopSnowPolicy.bottomRenderHeight(options: options))
                : 11 * options.moundHeight
            let x = Double(point.x), y = Double(point.y)
            guard x >= bank.surface.left - radius, x <= bank.surface.right + radius,
                  y >= bank.surface.y - radius,
                  y <= bank.surface.y + visibleHeight + radius else { continue }
            return bank.surface.id
        }
        return nil
    }

    /// Applies a local build/carve or translates part of an existing pile.
    /// `strength` is normalized to 0...1; brush radii and coordinates are points.
    /// All work is bounded by the selected bank's existing (at most 128) bins.
    @discardableResult
    mutating func sculpt(surfaceID: UInt64, at point: CGPoint, tool: DesktopSnowBrushTool,
                         radius: Double, strength: Double, from previousPoint: CGPoint? = nil,
                         options rawOptions: DesktopSnowOptions) -> Bool {
        let options = rawOptions.bounded
        guard options.accumulation, point.x.isFinite, point.y.isFinite,
              radius.isFinite, (1...200).contains(radius),
              strength.isFinite, strength > 0,
              let bankIndex = banks.firstIndex(where: { $0.surface.id == surfaceID }),
              banks[bankIndex].heights.count >= 2,
              banks[bankIndex].heights.count <= DesktopSnowPolicy.maximumBinsPerSurface else { return false }

        let bank = banks[bankIndex]
        guard bank.surface.kind != .bottom || !options.customBottomLayout else { return false }
        let bottomEditHeight = max(36, DesktopSnowPolicy.bottomRenderHeight(options: options))
        guard bank.surface.left.isFinite, bank.surface.right.isFinite, bank.surface.y.isFinite,
              point.x >= bank.surface.left - radius, point.x <= bank.surface.right + radius,
              point.y >= bank.surface.y - radius,
              point.y <= bank.surface.y + (bank.surface.kind == .bottom ? bottomEditHeight : 22) + radius else { return false }
        let boundedStrength = min(1, strength)
        let cap = bank.surface.kind == .bottom ? max(0, options.bottomLimit - options.baseDepth) : 11.0
        guard cap > 0 else { return false }
        let binWidth = bank.binWidth
        guard binWidth.isFinite, binWidth > 0 else { return false }
        let center = (Double(point.x) - bank.surface.left) / binWidth - 0.5
        guard center.isFinite else { return false }

        switch tool {
        case .build, .carve:
            let lower = max(0, Int(floor(center - radius / binWidth)))
            let upper = min(bank.heights.count - 1, Int(ceil(center + radius / binWidth)))
            guard lower <= upper else { return false }
            var changed = false
            let amplitude = cap * 0.2 * boundedStrength
            for index in lower...upper {
                let x = bank.surface.left + (Double(index) + 0.5) * binWidth
                let distance = abs(x - Double(point.x))
                guard distance <= radius else { continue }
                let falloff = exp(-4.5 * (distance / radius) * (distance / radius))
                let delta = amplitude * falloff
                let old = banks[bankIndex].heights[index]
                let next = tool == .build ? min(cap, old + delta) : max(0, old - delta)
                if abs(next - old) > 0.000_001 {
                    banks[bankIndex].heights[index] = next
                    changed = true
                }
            }
            return changed

        case .move:
            guard let previousPoint, previousPoint.x.isFinite, previousPoint.y.isFinite,
                  previousPoint.x >= bank.surface.left - radius, previousPoint.x <= bank.surface.right + radius,
                  previousPoint.y >= bank.surface.y - radius,
                  previousPoint.y <= bank.surface.y + (bank.surface.kind == .bottom ? 36 : 22) + radius else { return false }
            let displacement = Double(point.x - previousPoint.x) / binWidth
            guard displacement.isFinite, displacement != 0,
                  abs(displacement) < Double(bank.heights.count) else { return false }
            let sourceCenter = (Double(previousPoint.x) - bank.surface.left) / binWidth - 0.5
            let lower = max(0, Int(floor(sourceCenter - radius / binWidth)))
            let upper = min(bank.heights.count - 1, Int(ceil(sourceCenter + radius / binWidth)))
            guard lower <= upper else { return false }

            let direction = displacement > 0 ? 1 : -1
            let distanceInBins = abs(displacement)
            let wholeBins = Int(distanceInBins)
            let fraction = distanceInBins - Double(wholeBins)
            let original = bank.heights
            var moved = original
            // Move the leading edge first so each source has only its original
            // snow to give and never loses snow to a full destination.
            for source in stride(from: direction > 0 ? upper : lower,
                                 through: direction > 0 ? lower : upper, by: -direction) {
                let sourceX = bank.surface.left + (Double(source) + 0.5) * binWidth
                let distance = abs(sourceX - Double(previousPoint.x))
                guard original[source] > 0, distance <= radius else { continue }
                let falloff = exp(-4.5 * (distance / radius) * (distance / radius))
                let amount = original[source] * boundedStrength * falloff
                // Fractional-bin transfers respond to small, slow mouse moves.
                for (offset, weight) in [(wholeBins, 1 - fraction), (wholeBins + 1, fraction)] where offset > 0 && weight > 0 {
                    let destination = source + direction * offset
                    guard moved.indices.contains(destination) else { continue }
                    let accepted = min(amount * weight, max(0, cap - moved[destination]))
                    moved[source] -= accepted
                    moved[destination] += accepted
                }
            }
            guard moved != original else { return false }
            banks[bankIndex].heights = moved
            return true
        }
    }

    /// Only a verified move/resize may release a few gentle fragments. Focus,
    /// occlusion, closing/minimizing and disappeared segments clear quietly.
    /// Existing airborne flakes retain their identity and motion unchanged.
    mutating func updateSurfaces(_ proposed: [DesktopSnowSurface], accumulating: Bool) {
        let surfaces = accumulating ? DesktopSnowPolicy.boundedSurfaces(proposed, size: size) : []
        var remaining = Dictionary(uniqueKeysWithValues: banks.map { ($0.surface.id, $0) })
        var next: [DesktopSnowBank] = []
        var shedBudget = DesktopSnowPolicy.maximumShedPerUpdate
        for surface in surfaces {
            if let previous = remaining.removeValue(forKey: surface.id) {
                let moved = abs(previous.surface.left - surface.left) > 0.75 ||
                    abs(previous.surface.right - surface.right) > 0.75 || abs(previous.surface.y - surface.y) > 0.75
                if moved {
                    if DesktopSnowPolicy.shouldShed(from: previous.surface, to: surface), shedBudget > 0 {
                        shedBudget -= shed(previous, horizontalMotion: surface.left - previous.surface.left, budget: shedBudget)
                    }
                    next.append(makeBank(surface))
                } else {
                    var preserved = previous; preserved.surface = surface; next.append(preserved)
                }
            } else { next.append(makeBank(surface)) }
        }
        // Do not turn a focus/occlusion or Space change into an avalanche.
        // Any unmatched old bank disappears silently, without RNG/ID changes.
        banks = next
    }

    mutating func seedInitialSnow(options: DesktopSnowOptions, lowImpact: Bool) {
        guard particles.isEmpty else { return }
        let options = options.bounded
        let count = DesktopSnowPolicy.targetParticles(size: size, intensity: options.intensity, lowImpact: lowImpact)
        for _ in 0..<count { particles.append(makeParticle(initial: true, options: options)) }
    }

    mutating func step(seconds: Double, options rawOptions: DesktopSnowOptions, lowImpact: Bool, pointer: CGPoint? = nil) {
        guard seconds.isFinite, seconds > 0 else { return }
        let dt = min(seconds, 0.1) // Never catch up after sleep or a blocked main run loop.
        let options = rawOptions.bounded
        elapsed = (elapsed + dt).truncatingRemainder(dividingBy: 3_600)
        if !options.accumulation && !banks.isEmpty { banks = [] }
        if options.pointerSweep, options.accumulation, let pointer,
           pointer.x.isFinite, pointer.y.isFinite,
           let previousPointer, previousPointer.x.isFinite, previousPointer.y.isFinite {
            sweepBanks(from: previousPointer, to: pointer)
        }
        self.previousPointer = options.pointerSweep && pointer?.x.isFinite == true && pointer?.y.isFinite == true ? pointer : nil
        let target = DesktopSnowPolicy.targetParticles(size: size, intensity: options.intensity, lowImpact: lowImpact)
        if particles.count > DesktopSnowPolicy.maximumParticles { particles.removeLast(particles.count - DesktopSnowPolicy.maximumParticles) }
        var kept: [DesktopSnowParticle] = []
        kept.reserveCapacity(DesktopSnowPolicy.maximumParticles)
        for var particle in particles {
            let previousY = particle.y
            particle.age += dt
            if particle.shedding {
                particle.velocityY = max(-DesktopSnowPolicy.maximumSheddingSpeed, particle.velocityY - 24 * dt)
                particle.velocityX += (options.wind * 14 - particle.velocityX) * min(1, dt * 0.7)
            } else {
                let destination = options.wind * 48 + sin(elapsed * 0.65 + particle.phase) * 12
                particle.velocityX += (destination - particle.velocityX) * min(1, dt * 2)
            }
            particle.x += particle.velocityX * dt
            // Fragment velocity is already in actual points/second. Applying
            // Speed again caused an abrupt accelerated shower after switches.
            particle.y += particle.velocityY * (particle.shedding ? 1 : options.speed) * dt
            if let pointer, pointer.x.isFinite, pointer.y.isFinite {
                let dx = particle.x - pointer.x, dy = particle.y - pointer.y
                let distance = hypot(dx, dy)
                if distance > 0.5 && distance < 110 {
                    let influence = pow(1 - distance / 110, 2)
                    // A gentle, bounded local eddy, with no pointer tracking
                    // retained by the simulation or event monitor involved.
                    particle.x += (-dy / distance * 30 + dx / distance * 16) * influence * dt
                    particle.y += dx / distance * 12 * influence * dt
                }
            }
            if particle.x < -8 { particle.x = Double(size.width) + 4; particle.renderRevision &+= 1 }
            if particle.x > Double(size.width) + 8 { particle.x = -4; particle.renderRevision &+= 1 }
            if particle.y < -12 || (particle.shedding && particle.age > DesktopSnowPolicy.maximumSheddingLifetime) { continue }
            if options.accumulation, particle.velocityY < 0,
               let hit = landing(x: particle.x, from: previousY, to: particle.y, options: options) {
                if banks[hit.bank].surface.kind != .bottom || !options.customBottomLayout {
                    deposit(at: hit.bank, bin: hit.bin, amount: particle.radius * 0.22, options: options)
                }
                continue
            }
            kept.append(particle)
        }
        particles = kept
        // Spawn credit and per-frame limits bound work even under hostile time
        // input or after an intensity change. Existing flakes finish naturally.
        let crossingSeconds = max(3, Double(size.height) / (65 * options.speed))
        spawnCredit = min(8, spawnCredit + Double(target) / crossingSeconds * dt)
        let count = min(8, min(max(0, target - particles.count), Int(spawnCredit)))
        if count > 0 {
            for _ in 0..<count { particles.append(makeParticle(initial: false, options: options)) }
            spawnCredit -= Double(count)
        }
    }

    private func makeBank(_ surface: DesktopSnowSurface) -> DesktopSnowBank {
        let count = min(DesktopSnowPolicy.maximumBinsPerSurface, max(2, Int(ceil((surface.right - surface.left) / 12))))
        return .init(surface: surface, heights: Array(repeating: 0, count: count))
    }

    private mutating func nextRandom() -> Double {
        seed = seed &* 6_364_136_223_846_793_005 &+ 1_442_695_040_888_963_407
        return Double(seed >> 11) / 9_007_199_254_740_992
    }

    private mutating func allocateParticleID() -> UInt64 {
        // A monotonic identity is independent of the RNG, position and array
        // index. The bounded fallback also avoids a live collision on UInt64
        // rollover, even though no real session could approach that lifetime.
        repeat { nextParticleID &+= 1 } while nextParticleID == 0 || particles.contains(where: { $0.id == nextParticleID })
        return nextParticleID
    }

    private mutating func makeParticle(initial: Bool, options: DesktopSnowOptions) -> DesktopSnowParticle {
        let x = nextRandom() * Double(size.width)
        let y = initial ? nextRandom() * Double(size.height) : Double(size.height) + nextRandom() * 12
        let radius = 1.1 + nextRandom() * 2
        let velocity = -(25 + nextRandom() * 42)
        return .init(id: allocateParticleID(), x: x, y: y, velocityX: options.wind * 36, velocityY: velocity,
                     radius: radius, phase: nextRandom() * .pi * 2)
    }

    private mutating func shed(_ bank: DesktopSnowBank, horizontalMotion: Double, budget: Int) -> Int {
        let nonempty = bank.heights.indices.filter { bank.heights[$0] > 0.25 }
        let totalAvailable = max(0, DesktopSnowPolicy.maximumParticles - particles.count)
        let fragmentAvailable = max(0, DesktopSnowPolicy.maximumSheddingParticles - particles.filter(\.shedding).count)
        let count = min(budget, min(fragmentAvailable, min(totalAvailable, nonempty.count)))
        guard count > 0, !nonempty.isEmpty else { return 0 }
        for index in 0..<count {
            let bin = nonempty[index % nonempty.count]
            let x = bank.surface.left + (Double(bin) + nextRandom()) * bank.binWidth
            let y = bank.surface.y + DesktopSnowPolicy.settledHeight(for: bank, at: x - bank.surface.left) * nextRandom()
            particles.append(.init(id: allocateParticleID(), x: x, y: y,
                velocityX: DesktopSnowPolicy.clamp(horizontalMotion * 0.2, -14...14, fallback: 0) + (nextRandom() - 0.5) * 16,
                velocityY: -12 - nextRandom() * 14, radius: 1 + nextRandom() * 1.6,
                phase: nextRandom() * .pi * 2, shedding: true))
        }
        return count
    }

    private func landing(x: Double, from: Double, to: Double,
                         options: DesktopSnowOptions) -> (bank: Int, bin: Int)? {
        var result: (bank: Int, bin: Int)?
        var highest = -Double.infinity
        for (index, bank) in banks.enumerated() {
            let limit = bank.surface.kind == .bottom ? DesktopSnowPolicy.bottomRenderHeight(options: options) : 11.0 * options.moundHeight
            guard x >= bank.surface.left, x <= bank.surface.right,
                  from >= bank.surface.y, to <= bank.surface.y + limit else { continue }
            let bin = min(bank.heights.count - 1, max(0, Int((x - bank.surface.left) / bank.binWidth)))
            let y = bank.surface.y + DesktopSnowPolicy.settledHeight(for: bank, at: x - bank.surface.left, boundedOptions: options)
            if from >= y && to <= y && y > highest { highest = y; result = (index, bin) }
        }
        return result
    }

    private mutating func deposit(at index: Int, bin: Int, amount: Double, options: DesktopSnowOptions) {
        let limit = banks[index].surface.kind == .bottom ? max(0, options.bottomLimit - options.baseDepth) : 11.0
        guard limit > 0 else { return }
        banks[index].heights[bin] = min(limit, banks[index].heights[bin] + amount)
        for adjacent in [bin - 1, bin + 1] where banks[index].heights.indices.contains(adjacent) {
            banks[index].heights[adjacent] = min(limit, banks[index].heights[adjacent] + amount * 0.22)
        }
    }

    /// A click-through pointer sample can lift a few nearby settled flakes.
    /// The sweep is capped per tick and per bank; the resulting fragments use
    /// the same gravity, lifetime, identity, and landing path as move fragments.
    private mutating func sweepBanks(from start: CGPoint, to end: CGPoint) {
        let dx = Double(end.x - start.x), dy = Double(end.y - start.y)
        let distance = hypot(dx, dy)
        guard distance > 0.5, distance <= 160, particles.count < DesktopSnowPolicy.maximumParticles else { return }
        let count = min(2, DesktopSnowPolicy.maximumSweepPerStep,
                        DesktopSnowPolicy.maximumSheddingParticles - particles.filter(\.shedding).count,
                        DesktopSnowPolicy.maximumParticles - particles.count)
        guard count > 0 else { return }
        var released = 0
        for bankIndex in banks.indices where released < count {
            let bank = banks[bankIndex]
            guard bank.surface.kind != .bottom, bank.binWidth.isFinite, bank.binWidth > 0 else { continue }
            for bin in bank.heights.indices where released < count && bank.heights[bin] > 0.25 {
                let x = bank.surface.left + (Double(bin) + 0.5) * bank.binWidth
                let y = bank.surface.y + bank.heights[bin]
                let px = Double(start.x), py = Double(start.y)
                let t = max(0, min(1, ((x - px) * dx + (y - py) * dy) / (distance * distance)))
                guard hypot(x - (px + t * dx), y - (py + t * dy)) <= max(5, bank.binWidth * 0.45) else { continue }
                let amount = min(bank.heights[bin], max(0.25, bank.heights[bin] * 0.18))
                banks[bankIndex].heights[bin] -= amount
                particles.append(.init(id: allocateParticleID(), x: x, y: y,
                    velocityX: DesktopSnowPolicy.clamp(dx * 0.18, -14...14, fallback: 0) + (nextRandom() - 0.5) * 8,
                    velocityY: -12 - nextRandom() * 8, radius: 1 + nextRandom() * 1.4,
                    phase: nextRandom() * .pi * 2, shedding: true))
                released += 1
            }
        }
    }
}

enum DesktopSnowPolicy {
    static let maximumDisplays = 8
    static let maximumParticles = 320
    static let maximumSurfaces = 24
    static let maximumBinsPerSurface = 128
    static let maximumShedPerUpdate = 8
    static let maximumSweepPerStep = 2
    static let maximumSheddingParticles = 12
    static let maximumSheddingSpeed = 75.0
    static let maximumSheddingLifetime = 4.0
    static let maximumWindowInputs = 96
    static let geometryInterval = 0.5

    static func backingScale(_ value: Double) -> Double {
        value.isFinite && value > 0 && value <= 8 ? value : 1
    }

    static func shouldShed(from previous: DesktopSnowSurface, to current: DesktopSnowSurface) -> Bool {
        guard previous.id == current.id, previous.kind == current.kind, current.kind != .bottom else { return false }
        if let old = previous.sourceFrame, let new = current.sourceFrame, validRect(old), validRect(new) {
            return abs(new.minX - old.minX) > 0.75 || abs(new.minY - old.minY) > 0.75 ||
                abs(new.width - old.width) > 0.75 || abs(new.height - old.height) > 0.75
        }
        // With no original frame, accept only a coherent horizontal shift or
        // changed edge height. A one-sided exposed segment resize is ambiguous.
        let left = current.left - previous.left, right = current.right - previous.right
        return (abs(left) > 0.75 && abs(left - right) <= 0.75) || abs(current.y - previous.y) > 0.75
    }

    /// Physics stays at 15/30 Hz. Core Animation bridges those samples with a
    /// small overlap so ordinary timer tolerance does not insert a visual stop.
    /// This is a finite animation, never an independent per-flake render loop.
    static func interpolationDuration(frameInterval: Double) -> Double {
        guard frameInterval.isFinite, frameInterval > 0, frameInterval <= 0.15 else { return 0 }
        return min(0.12, max(1 / 120, frameInterval * 1.2))
    }

    static func shouldInterpolate(from previous: DesktopSnowParticle?, to current: DesktopSnowParticle,
                                  frameInterval: Double) -> Bool {
        guard interpolationDuration(frameInterval: frameInterval) > 0,
              let previous, previous.id != 0, previous.id == current.id,
              previous.renderRevision == current.renderRevision,
              [previous.x, previous.y, current.x, current.y].allSatisfy(\.isFinite) else { return false }
        // Normal capped physics cannot traverse this much in one sample.
        // Treat any unexpected teleport as a new position rather than a sweep.
        return hypot(current.x - previous.x, current.y - previous.y) <= 160
    }

    static func moundSilhouettes(for bank: DesktopSnowBank, options rawOptions: DesktopSnowOptions = .init()) -> [DesktopSnowMound] {
        guard let width = moundBankWidth(bank), bank.heights.allSatisfy({ $0.isFinite && $0 >= 0 }) else { return [] }
        let options = rawOptions.bounded
        if bank.surface.kind == .bottom, options.customBottomLayout {
            return authoredBottomSilhouettes(width: width, options: options)
        }
        let count = moundCount(width: width, kind: bank.surface.kind, spacing: options.moundSpacing)
        var result: [DesktopSnowMound] = []
        result.reserveCapacity(count + 1)
        if bank.surface.kind == .bottom, options.baseDepth > 0 {
            result.append(baseSilhouette(width: width, depth: options.baseDepth))
        }
        for index in 0..<count {
            guard includesMound(seed: bank.surface.id, index: index, count: count) else { continue }
            let profile = moundProfile(bank: bank, width: width, index: index, count: count, widthScale: options.moundWidth)
            let points = (0...profile.segments).map {
                moundPoint(bank: bank, profile: profile, index: $0, heightScale: options.moundHeight, options: options)
            }
            if points.contains(where: { $0.y > 0 }) { result.append(.init(points: points)) }
        }
        return result
    }

    static let maximumMoundsPerSurface = 24
    static let maximumMoundPoints = 17
    static let maximumBottomLimit = 120.0
    static let maximumBaseDepth = 60.0
    static let maximumAuthoredMounds = 24

    static func bottomRenderHeight(options: DesktopSnowOptions) -> Double {
        options.bounded.bottomLimit
    }

    private static func baseSilhouette(width: Double, depth: Double) -> DesktopSnowMound {
        let bevel = min(2, width * 0.005)
        return .init(points: [
            .init(x: 0, y: 0), .init(x: bevel, y: depth),
            .init(x: width - bevel, y: depth), .init(x: width, y: 0)
        ])
    }

    private static func authoredBottomSilhouettes(width: Double, options: DesktopSnowOptions) -> [DesktopSnowMound] {
        var result: [DesktopSnowMound] = []
        if options.baseDepth > 0 { result.append(baseSilhouette(width: width, depth: options.baseDepth)) }
        let available = max(0, options.bottomLimit - options.baseDepth)
        guard available > 0 else { return result }
        for mound in options.authoredMounds where mound.isValid && mound.height > 0 {
            if let silhouette = authoredMoundSilhouette(width: width, mound: mound, options: options) {
                result.append(silhouette)
            }
        }
        return result
    }

    private static func authoredMoundSilhouette(width: Double, mound: DesktopSnowAuthoredMound,
                                                  options: DesktopSnowOptions) -> DesktopSnowMound? {
        let center = mound.center * width
        let halfWidth = mound.width * width / 2
        let originalLeft = center - halfWidth, originalRight = center + halfWidth
        let left = max(0, originalLeft), right = min(width, originalRight)
        guard right - left >= 1 else { return nil }
        let segments = min(maximumMoundPoints - 1, max(8, Int(ceil((right - left) / 12))))
        let peak = min(max(0, options.bottomLimit - options.baseDepth), mound.height)
        let points = (0...segments).map { index -> CGPoint in
            let x = left + (right - left) * Double(index) / Double(segments)
            let t = min(1, max(0, (x - originalLeft) / (originalRight - originalLeft)))
            let envelope = pow(max(0, sin(.pi * t)), 1.25)
            let height = (t <= 0 || t >= 1) ? 0 : options.baseDepth + peak * envelope
            return .init(x: x, y: height)
        }
        return .init(points: points)
    }

    private struct MoundProfile {
        let left: Double
        let right: Double
        let peak: Double
        let heightScale: Double
        let segments: Int
        var step: Double { (right - left) / Double(segments) }
    }

    private static func moundBankWidth(_ bank: DesktopSnowBank) -> Double? {
        let width = bank.surface.right - bank.surface.left
        guard !bank.heights.isEmpty, bank.heights.count <= maximumBinsPerSurface,
              bank.surface.left.isFinite, bank.surface.right.isFinite, bank.surface.y.isFinite,
              width.isFinite, width >= 1, width <= 16_384 else { return nil }
        return width
    }

    private static func moundCount(width: Double, kind: DesktopSnowSurface.Kind, spacing: Double = 1) -> Int {
        min(maximumMoundsPerSurface, max(1, Int((width / ((kind == .bottom ? 130 : 92) * spacing)).rounded())))
    }

    private static func includesMound(seed: UInt64, index: Int, count: Int) -> Bool {
        // Small Home caps always keep their piles. Longer edges have a stable
        // clearing between clusters, with their end zones kept as anchors.
        guard count >= 4, index > 0, index < count - 1 else { return true }
        let clearing = 1 + Int(coherentBankNoise(seed: seed ^ 0x434c4541, coordinate: 0) * Double(count - 2))
        return index != clearing && coherentBankNoise(seed: seed ^ 0x50415443, coordinate: Double(index)) >= 0.16
    }

    private static func moundProfile(bank: DesktopSnowBank, width: Double, index: Int, count: Int, widthScale: Double = 1) -> MoundProfile {
        let zone = width / Double(count)
        func noise(_ salt: UInt64) -> Double {
            coherentBankNoise(seed: bank.surface.id ^ salt, coordinate: Double(index))
        }
        // The footprint stays inside its lookup zone, but its width and
        // free position vary independently. Small neighbors can cluster near
        // their shared boundary while another part of the edge stays clear.
        let margin = zone * 0.04
        let pileWidth = min(bank.surface.kind == .bottom ? 150 : 105,
                            min(max(0, zone - 2 * margin), zone * (0.24 + noise(0x57494454) * 0.58) * widthScale))
        let left = Double(index) * zone + margin + noise(0x43454e54) * (zone - 2 * margin - pileWidth)
        return .init(left: left, right: left + pileWidth,
                     peak: 0.34 + noise(0x5045414b) * 0.32,
                     heightScale: 0.60 + noise(0x48454947) * 0.38,
                     segments: min(maximumMoundPoints - 1, max(8, Int(ceil(pileWidth / 8)))))
    }

    private static func moundPoint(bank: DesktopSnowBank, profile: MoundProfile, index: Int,
                                   heightScale: Double = 1, options: DesktopSnowOptions = .init()) -> CGPoint {
        let x = profile.left + Double(index) * profile.step
        guard index > 0, index < profile.segments else { return .init(x: x, y: 0) }
        let coordinate = min(Double(bank.heights.count - 1), max(0, x / bank.binWidth - 0.5))
        let lower = Int(coordinate), upper = min(bank.heights.count - 1, lower + 1)
        let a = bank.heights[lower], b = bank.heights[upper]
        guard a.isFinite, b.isFinite, a >= 0, b >= 0 else { return .init(x: x, y: 0) }
        let limit = bank.surface.kind == .bottom ? max(0, options.bottomLimit - options.baseDepth) : 11.0
        let fraction = coordinate - Double(lower)
        let deposited = min(limit, a) * (1 - fraction) + min(limit, b) * fraction
        guard deposited > 0.24, limit > 0 else { return .init(x: x, y: 0) }
        let position = Double(index) / Double(profile.segments)
        let shoulder = position < profile.peak ? position / profile.peak : (1 - position) / (1 - profile.peak)
        let envelope = pow(sin(max(0, min(1, shoulder)) * .pi / 2), 1.2)
        let height = limit * pow(deposited / limit, 0.82) * profile.heightScale * envelope * heightScale
        let base = bank.surface.kind == .bottom ? options.baseDepth : 0
        let cap = bank.surface.kind == .bottom ? options.bottomLimit : 11 * heightScale
        return .init(x: x, y: min(cap, base + max(0, height)))
    }

    /// Exact height of the renderer's quadratic contour. At most three control
    /// points are evaluated: no silhouette allocation or bin scan per flake.
    /// Deliberately clear gaps land at the underlying support, never raw height.
    static func settledHeight(for bank: DesktopSnowBank, at localX: Double, options rawOptions: DesktopSnowOptions = .init()) -> Double {
        settledHeight(for: bank, at: localX, boundedOptions: rawOptions.bounded)
    }

    /// Hot-path overload for simulation callers that already bounded options.
    static func settledHeight(for bank: DesktopSnowBank, at localX: Double, boundedOptions options: DesktopSnowOptions) -> Double {
        guard localX.isFinite, let width = moundBankWidth(bank), localX >= 0, localX <= width else { return 0 }
        if bank.surface.kind == .bottom, options.customBottomLayout {
            return authoredBottomHeight(width: width, x: localX, options: options)
        }
        let count = moundCount(width: width, kind: bank.surface.kind, spacing: options.moundSpacing)
        let index = min(count - 1, Int(localX / (width / Double(count))))
        let moundHeight: Double
        if includesMound(seed: bank.surface.id, index: index, count: count) {
            let profile = moundProfile(bank: bank, width: width, index: index, count: count, widthScale: options.moundWidth)
            let points = (0...profile.segments).map {
                moundPoint(bank: bank, profile: profile, index: $0, heightScale: options.moundHeight, options: options)
            }
            moundHeight = contourHeight(for: .init(points: points), at: localX)
        } else { moundHeight = 0 }
        if bank.surface.kind == .bottom, options.baseDepth > 0 {
            return max(moundHeight, contourHeight(for: baseSilhouette(width: width, depth: options.baseDepth), at: localX))
        }
        return moundHeight
    }

    private static func authoredBottomHeight(width: Double, x: Double, options: DesktopSnowOptions) -> Double {
        var height = options.baseDepth > 0 ? contourHeight(for: baseSilhouette(width: width, depth: options.baseDepth), at: x) : 0
        guard options.bottomLimit > options.baseDepth else { return height }
        for mound in options.authoredMounds where mound.isValid && mound.height > 0 {
            let center = mound.center * width
            let halfWidth = mound.width * width / 2
            guard x >= max(0, center - halfWidth), x <= min(width, center + halfWidth),
                  let silhouette = authoredMoundSilhouette(width: width, mound: mound, options: options) else { continue }
            height = max(height, contourHeight(for: silhouette, at: x))
        }
        return height
    }

    /// Evaluates the same midpoint-smoothed quadratic path used by both snow renderers.
    private static func contourHeight(for mound: DesktopSnowMound, at x: Double) -> Double {
        let points = mound.points
        guard points.count >= 2, x.isFinite, x >= Double(points[0].x), x <= Double(points[points.count - 1].x) else { return 0 }
        for controlIndex in points.indices {
            let control = points[controlIndex]
            let start: CGPoint = controlIndex == 0 ? control : {
                let prior = points[controlIndex - 1]
                return CGPoint(x: (prior.x + control.x) / 2, y: (prior.y + control.y) / 2)
            }()
            let end: CGPoint = controlIndex == points.count - 1 ? control : {
                let next = points[controlIndex + 1]
                return CGPoint(x: (control.x + next.x) / 2, y: (control.y + next.y) / 2)
            }()
            guard x >= Double(start.x), x <= Double(end.x) else { continue }
            let a = Double(start.x - 2 * control.x + end.x)
            let b = Double(2 * (control.x - start.x))
            let distance = x - Double(start.x)
            let denominator = b + sqrt(max(0, b * b + 4 * a * distance))
            guard denominator > 0 else { return max(0, Double(start.y)) }
            let t = min(1, max(0, 2 * distance / denominator)), u = 1 - t
            return max(0, u * u * Double(start.y) + 2 * u * t * Double(control.y) + t * t * Double(end.y))
        }
        return 0
    }

    private static func coherentBankNoise(seed: UInt64, coordinate: Double) -> Double {
        func value(_ index: Int) -> Double {
            var bits = seed ^ (UInt64(index) &* 0x9e3779b97f4a7c15)
            bits = (bits ^ (bits >> 30)) &* 0xbf58476d1ce4e5b9
            bits = (bits ^ (bits >> 27)) &* 0x94d049bb133111eb
            bits ^= bits >> 31
            return Double(bits >> 11) / 9_007_199_254_740_992
        }
        let cell = Int(coordinate.rounded(.down))
        let fraction = coordinate - Double(cell)
        let blend = fraction * fraction * (3 - 2 * fraction)
        return value(cell) * (1 - blend) + value(cell + 1) * blend
    }

    static func shouldSampleGeometry(active: Bool, windowEdges: Bool, accumulation: Bool,
                                     now: Double, lastSample: Double?) -> Bool {
        guard active, windowEdges, accumulation, now.isFinite, now >= 0 else { return false }
        guard let lastSample else { return true }
        return lastSample.isFinite && now - lastSample >= geometryInterval
    }

    static func clamp(_ value: Double, _ range: ClosedRange<Double>, fallback: Double) -> Double {
        value.isFinite ? min(range.upperBound, max(range.lowerBound, value)) : fallback
    }

    static func validSize(_ size: CGSize) -> Bool {
        size.width.isFinite && size.height.isFinite && (160...16_384).contains(size.width) && (160...16_384).contains(size.height)
    }

    static func validRect(_ rect: CGRect) -> Bool {
        !rect.isNull && !rect.isInfinite && [rect.minX, rect.minY, rect.maxX, rect.maxY, rect.width, rect.height]
            .allSatisfy { $0.isFinite && abs($0) <= 1_000_000 } && rect.width > 0 && rect.height > 0
    }

    static func targetParticles(size: CGSize, intensity: Double, lowImpact: Bool) -> Int {
        guard validSize(size), intensity.isFinite, intensity > 0 else { return 0 }
        let area = min(2, max(0.4, Double(size.width * size.height) / 1_500_000))
        return min(lowImpact ? 110 : 240, max(1, Int((36 + 105 * min(1, intensity)) * area * (lowImpact ? 0.65 : 1))))
    }

    static func boundedSurfaces(_ surfaces: [DesktopSnowSurface], size: CGSize) -> [DesktopSnowSurface] {
        guard validSize(size) else { return [] }
        var seen = Set<UInt64>()
        return surfaces.prefix(maximumSurfaces * 4).compactMap { surface in
            guard seen.insert(surface.id).inserted, surface.left.isFinite, surface.right.isFinite, surface.y.isFinite,
                  surface.right > 0, surface.left < size.width, surface.y >= 0, surface.y <= size.height else { return nil }
            var value = surface
            value.left = max(0, surface.left); value.right = min(size.width, surface.right)
            return value.right - value.left >= 12 ? value : nil
        }.prefix(maximumSurfaces).map { $0 }
    }

    /// Quartz window bounds use the main display's top-left origin. This
    /// conversion retains negative-coordinate displays without guessing scale.
    static func appKitFrame(quartz: CGRect, primaryTop: Double) -> CGRect? {
        guard validRect(quartz), primaryTop.isFinite, abs(primaryTop) <= 1_000_000 else { return nil }
        let frame = CGRect(x: quartz.minX, y: primaryTop - quartz.maxY, width: quartz.width, height: quartz.height)
        return validRect(frame) ? frame : nil
    }

    /// Front-to-back subtraction means snow collects only on exposed pieces
    /// of a window's top edge, rather than floating across a foreground app.
    static func surfaces(displayFrame: CGRect, windows: [DesktopSnowWindowGeometry], includeWindows: Bool,
                         ownDockFrame: CGRect? = nil, usableFrame: CGRect? = nil,
                         topSafeInset: Double = 0) -> [DesktopSnowSurface] {
        guard validRect(displayFrame), validSize(displayFrame.size) else { return [] }
        var result = [DesktopSnowSurface(id: 1, kind: .bottom, left: 0, right: displayFrame.width, y: 1)]
        var occluders: [CGRect] = []
        if let ownDockFrame, validRect(ownDockFrame), ownDockFrame.intersects(displayFrame) {
            let clipped = ownDockFrame.intersection(displayFrame)
            result.append(.init(id: 2, kind: .dock, left: clipped.minX - displayFrame.minX,
                                right: clipped.maxX - displayFrame.minX, y: min(displayFrame.height, clipped.maxY - displayFrame.minY),
                                sourceFrame: ownDockFrame))
        }
        guard includeWindows else { return boundedSurfaces(result, size: displayFrame.size) }
        var seen = Set<UInt32>()
        for window in windows.prefix(maximumWindowInputs) {
            guard seen.insert(window.id).inserted, validRect(window.frame), window.frame.intersects(displayFrame) else { continue }
            defer { if !window.isDock { occluders.append(window.frame) } }
            guard window.frame.width >= 60, window.frame.height >= 40,
                  window.frame.maxY > displayFrame.minY + 5, window.frame.maxY < displayFrame.maxY - 20 else { continue }
            if !window.isDock && excludesTopBank(windowFrame: window.frame, displayFrame: displayFrame,
                                                usableFrame: usableFrame, topSafeInset: topSafeInset) { continue }
            let left = max(displayFrame.minX, window.frame.minX), right = min(displayFrame.maxX, window.frame.maxX)
            var segments: [ClosedRange<Double>] = [left...right]
            for covering in occluders where covering.minY < window.frame.maxY + 1 && covering.maxY > window.frame.maxY - 1 {
                segments = segments.flatMap { segment -> [ClosedRange<Double>] in
                    guard covering.maxX > segment.lowerBound, covering.minX < segment.upperBound else { return [segment] }
                    var visible: [ClosedRange<Double>] = []
                    if covering.minX > segment.lowerBound { visible.append(segment.lowerBound...min(segment.upperBound, covering.minX)) }
                    if covering.maxX < segment.upperBound { visible.append(max(segment.lowerBound, covering.maxX)...segment.upperBound) }
                    return visible
                }
                if segments.isEmpty { break }
            }
            for (index, segment) in segments.prefix(4).enumerated() where segment.upperBound - segment.lowerBound >= 24 {
                result.append(.init(id: (UInt64(window.id) << 8) | UInt64(index + 16), kind: window.isDock ? .dock : .window,
                    left: segment.lowerBound - displayFrame.minX, right: segment.upperBound - displayFrame.minX,
                    y: window.frame.maxY - displayFrame.minY, sourceFrame: window.frame))
            }
            if result.count >= maximumSurfaces { break }
        }
        return boundedSurfaces(result, size: displayFrame.size)
    }

    /// A current-desktop maximizer is not necessarily a native full-screen
    /// Space. Skip its top snow ledge using geometry alone, while the caller
    /// still retains its bounds as an occluder for windows behind it.
    static func excludesTopBank(windowFrame: CGRect, displayFrame: CGRect,
                                usableFrame: CGRect?, topSafeInset: Double = 0) -> Bool {
        guard validRect(windowFrame), validRect(displayFrame) else { return true }
        let proposed = usableFrame.flatMap { validRect($0) ? $0.intersection(displayFrame) : nil }
        let usable = proposed.flatMap { validRect($0) ? $0 : nil } ?? displayFrame
        let tolerance = 12.0
        let coversUsable = windowFrame.minX <= usable.minX + tolerance && windowFrame.maxX >= usable.maxX - tolerance &&
            windowFrame.minY <= usable.minY + tolerance && windowFrame.maxY >= usable.maxY - tolerance
        if coversUsable { return true }
        let safeInset = clamp(topSafeInset, 0...160, fallback: 0)
        let topBoundary = min(usable.maxY, displayFrame.maxY - safeInset)
        let nearFullWidth = windowFrame.minX <= usable.minX + 36 && windowFrame.maxX >= usable.maxX - 36
        let nearFullHeight = windowFrame.height >= usable.height * 0.88
        return nearFullWidth && nearFullHeight && windowFrame.maxY >= topBoundary - 36
    }
}
