import Foundation
import CoreGraphics

/// Geometry uses global Quartz points, matching CGEvent.location.
enum IslandClickProfile: Equatable {
    case appOwnedTestWindow
    case nativeUnverified
}

struct IslandClickGeometry: Equatable {
    let profile: IslandClickProfile
    let boundingRect: CGRect
    let allowedRects: [CGRect]
    let protectedRects: [CGRect]

    private init(profile: IslandClickProfile, boundingRect: CGRect,
                 allowedRects: [CGRect], protectedRects: [CGRect]) {
        self.profile = profile
        self.boundingRect = boundingRect
        self.allowedRects = allowedRects
        self.protectedRects = protectedRects
    }

    /// Invalid, overlapping or unbounded input fails open, rather than silently
    /// growing an interception region. Callers must include known camera/system
    /// areas in protectedRects; this type cannot discover private hardware UI.
    static func validated(profile: IslandClickProfile, boundingRect: CGRect,
                          allowedRects: [CGRect], protectedRects: [CGRect] = []) -> Self? {
        guard isValid(boundingRect), !allowedRects.isEmpty, allowedRects.count <= 16,
              protectedRects.count <= 32,
              allowedRects.allSatisfy({ isValid($0) && boundingRect.contains($0) }),
              protectedRects.allSatisfy({ isValid($0) && boundingRect.contains($0) }) else { return nil }
        for (index, allowed) in allowedRects.enumerated() {
            guard !protectedRects.contains(where: { !allowed.intersection($0).isEmpty }),
                  !allowedRects.prefix(index).contains(where: { !allowed.intersection($0).isEmpty }) else { return nil }
        }
        return .init(profile: profile, boundingRect: boundingRect,
                     allowedRects: allowedRects, protectedRects: protectedRects)
    }

    func containsAllowedPoint(_ point: CGPoint) -> Bool {
        point.x.isFinite && point.y.isFinite && boundingRect.contains(point)
            && !protectedRects.contains(where: {
                point.x >= $0.minX && point.x <= $0.maxX
                    && point.y >= $0.minY && point.y <= $0.maxY
            })
            && allowedRects.contains(where: { $0.contains(point) })
    }

    private static func isValid(_ rect: CGRect) -> Bool {
        !rect.isNull && !rect.isInfinite && rect.origin.x.isFinite && rect.origin.y.isFinite
            && rect.width.isFinite && rect.height.isFinite && rect.width > 0 && rect.height > 0
            && rect.maxX.isFinite && rect.maxY.isFinite
    }
}

struct IslandClickRuntime {
    var enabled = false
    var sessionIsActive = false
    var sessionIsUnlocked = false
    var displayIsAwake = false
    var appIsActive = false
    var testWindowIsActive = false
    var nativeRoutingAcknowledged = false
    var geometry: IslandClickGeometry?

    var isEligible: Bool {
        guard enabled, sessionIsActive, sessionIsUnlocked, displayIsAwake,
              let geometry else { return false }
        switch geometry.profile {
        case .appOwnedTestWindow: return appIsActive && testWindowIsActive
        case .nativeUnverified: return nativeRoutingAcknowledged
        }
    }
}

enum IslandClickEventKind { case leftDown, leftUp, leftDragged, other }

struct IslandClickEvent {
    let kind: IslandClickEventKind
    let location: CGPoint
    /// Monotonic seconds; event-tap adapters convert the CGEvent timestamp.
    let timestamp: Double
    var hasConflictingModifiers = false
}

enum IslandClickDecision: Equatable {
    case passThrough
    case consume
    case consumeAndActivate

    var consumesEvent: Bool { self != .passThrough }
}

/// No AppKit, event tap, permission request or side effect belongs in this state
/// machine. Only a claimed left gesture is consumed, including its drag remainder
/// and paired up; other drags, mouse moves and unrelated input remain untouched.
struct IslandClickPolicy {
    private struct Press {
        let geometry: IslandClickGeometry
        let origin: CGPoint
        let timestamp: Double
        var dragged = false
    }
    private var press: Press?
    private let maximumClickDuration = 1.0
    private let maximumClickDistanceSquared = 36.0

    mutating func reset() { press = nil }

    mutating func handle(_ event: IslandClickEvent, runtime: IslandClickRuntime) -> IslandClickDecision {
        // Unrelated input is never changed, even while a left press is pending.
        guard event.kind != .other else { return .passThrough }
        guard runtime.isEligible, let geometry = runtime.geometry,
              event.location.x.isFinite, event.location.y.isFinite,
              event.timestamp.isFinite, event.timestamp >= 0 else {
            reset()
            return .passThrough
        }
        if let press, press.geometry != geometry {
            reset()
            return .passThrough
        }

        switch event.kind {
        case .leftDown:
            // A second down without an up is not a new click to claim.
            guard press == nil else { reset(); return .passThrough }
            guard !event.hasConflictingModifiers, geometry.containsAllowedPoint(event.location) else {
                return .passThrough
            }
            press = .init(geometry: geometry, origin: event.location, timestamp: event.timestamp)
            return .consume
        case .leftDragged:
            guard press != nil else { return .passThrough }
            press?.dragged = true
            return .consume
        case .leftUp:
            guard let captured = press else { return .passThrough }
            reset()
            // Finish only a press we claimed, including an up outside the hit
            // region. A drag/move/modifier/long hold cancels activation. Lock,
            // invalidation or another safety barrier above instead fails open.
            let dx = Double(event.location.x - captured.origin.x)
            let dy = Double(event.location.y - captured.origin.y)
            let elapsed = event.timestamp - captured.timestamp
            let activate = !captured.dragged && !event.hasConflictingModifiers
                && elapsed >= 0 && elapsed <= maximumClickDuration
                && dx * dx + dy * dy <= maximumClickDistanceSquared
                && geometry.containsAllowedPoint(event.location)
            return activate ? .consumeAndActivate : .consume
        case .other:
            return .passThrough
        }
    }
}
