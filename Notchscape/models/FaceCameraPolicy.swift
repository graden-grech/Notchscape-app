import Foundation
import CoreGraphics

enum FaceScanPreviewPolicy {
    static func previewScale(width: Double, height: Double) -> Double? {
        guard width.isFinite, height.isFinite, width > 0, height > 0,
              width <= 16_384, height <= 16_384 else { return nil }
        return min(1, 640 / max(width, height))
    }
    static func permits(session: UUID, currentSession: UUID?, capturing: Bool, authorized: Bool,
                        desktopUnlocked: Bool, automaticAttempt: Bool, timestamp: Double, now: Double) -> Bool {
        guard session == currentSession, capturing, authorized, desktopUnlocked, !automaticAttempt,
              timestamp.isFinite, now.isFinite, timestamp >= 0 else { return false }
        let age = now - timestamp
        return age >= 0 && age <= 1.2
    }
    static func progress(_ value: Double) -> Double { value.isFinite ? min(1, max(0, value)) : 0 }
}

/// Processing limits, not measured biometric security thresholds.
struct FaceCameraConfiguration: Sendable {
    let minimumFrameInterval: TimeInterval
    let minimumFacePixels: CGFloat
    let maximumSessionDuration: TimeInterval

    init?(minimumFrameInterval: TimeInterval = 0.35, minimumFacePixels: CGFloat = 112,
          maximumSessionDuration: TimeInterval = 30) {
        guard minimumFrameInterval.isFinite, (0.25...2).contains(minimumFrameInterval),
              minimumFacePixels.isFinite, (112...512).contains(minimumFacePixels),
              maximumSessionDuration.isFinite, (5...60).contains(maximumSessionDuration) else { return nil }
        self.minimumFrameInterval = minimumFrameInterval
        self.minimumFacePixels = minimumFacePixels
        self.maximumSessionDuration = maximumSessionDuration
    }

    func acceptsFace(_ bounds: CGRect, imageSize: CGSize) -> Bool {
        guard bounds.origin.x.isFinite, bounds.origin.y.isFinite,
              bounds.width.isFinite, bounds.height.isFinite, !bounds.isNull, !bounds.isInfinite,
              bounds.width > 0, bounds.height > 0,
              bounds.minX >= 0, bounds.minY >= 0, bounds.maxX <= 1, bounds.maxY <= 1,
              imageSize.width.isFinite, imageSize.height.isFinite,
              imageSize.width >= minimumFacePixels, imageSize.height >= minimumFacePixels else { return false }
        return bounds.width * imageSize.width >= minimumFacePixels &&
            bounds.height * imageSize.height >= minimumFacePixels
    }
}

struct FaceCameraPose: Equatable, Sendable {
    let yaw: Double
    let pitch: Double
    let roll: Double

    init?(yaw: Double, pitch: Double, roll: Double) {
        guard [yaw, pitch, roll].allSatisfy(\.isFinite), abs(yaw) <= .pi / 2,
              abs(pitch) <= .pi / 2, abs(roll) <= .pi else { return nil }
        self.yaw = yaw; self.pitch = pitch; self.roll = roll
    }

    var permitsAlignment: Bool { abs(yaw) <= 0.65 && abs(pitch) <= 0.35 && abs(roll) <= 0.35 }
}

enum FaceHeadTurnDirection: Int, Sendable { case left = -1, right = 1 }
enum FaceHeadChallengeProgress: Equatable, Sendable {
    case waitingForCenter, turn(FaceHeadTurnDirection), returnToCenter, completed, expired
}

/// A short, challenge-driven motion check. Ordinary RGB video cannot establish
/// Face ID-like liveness or reject every photograph, replay, mask or injection.
struct FaceHeadMovementChallenge: Sendable {
    let id: UUID
    let direction: FaceHeadTurnDirection
    let issuedAt: TimeInterval
    let expiresAt: TimeInterval
    private(set) var progress: FaceHeadChallengeProgress = .waitingForCenter
    private var lastTimestamp: TimeInterval?
    private var dwellStarted: TimeInterval?
    private var dwellSamples = 0

    init?(id: UUID = UUID(), direction: FaceHeadTurnDirection, issuedAt: TimeInterval,
          duration: TimeInterval = 12) {
        guard issuedAt.isFinite, issuedAt >= 0, duration.isFinite, (5...20).contains(duration),
              (issuedAt + duration).isFinite else { return nil }
        self.id = id; self.direction = direction; self.issuedAt = issuedAt; expiresAt = issuedAt + duration
    }

    mutating func observe(pose: FaceCameraPose?, at timestamp: TimeInterval) -> FaceHeadChallengeProgress {
        guard timestamp.isFinite, timestamp >= issuedAt,
              lastTimestamp.map({ timestamp > $0 }) ?? true else { reset(); return progress }
        guard timestamp < expiresAt else { progress = .expired; return progress }
        if let lastTimestamp, timestamp - lastTimestamp > 1.2 { reset() }
        lastTimestamp = timestamp
        guard let pose, pose.permitsAlignment else { reset(); return progress }
        let centered = abs(pose.yaw) <= 0.13
        let turned = pose.yaw * Double(direction.rawValue) >= 0.30
        let expected: Bool
        switch progress {
        case .waitingForCenter, .returnToCenter: expected = centered
        case .turn: expected = turned
        case .completed:
            if !centered { reset() }
            return progress
        case .expired: return progress
        }
        guard expected else { dwellStarted = nil; dwellSamples = 0; return progress }
        if dwellStarted == nil { dwellStarted = timestamp }
        dwellSamples += 1
        guard dwellSamples >= 2, timestamp - (dwellStarted ?? timestamp) >= 0.18 else { return progress }
        dwellStarted = nil; dwellSamples = 0
        switch progress {
        case .waitingForCenter: progress = .turn(direction)
        case .turn: progress = .returnToCenter
        case .returnToCenter: progress = .completed
        default: break
        }
        return progress
    }

    private mutating func reset() {
        progress = .waitingForCenter; dwellStarted = nil; dwellSamples = 0
    }
}

enum FaceAlignmentPolicy {
    /// Published OpenCV SFace reference coordinates, in top-left pixel space.
    static let referencePoints: [CGPoint] = [
        .init(x: 38.2946, y: 51.6963), .init(x: 73.5318, y: 51.5014),
        .init(x: 56.0252, y: 71.7366), .init(x: 41.5493, y: 92.3655),
        .init(x: 70.7299, y: 92.2041)
    ]

    /// Least-squares orientation-preserving similarity transform. Both arrays
    /// must use the same coordinate convention. Mirrored/degenerate points fail.
    static func similarityTransform(source: [CGPoint], destination: [CGPoint] = referencePoints) -> CGAffineTransform? {
        guard source.count == 5, destination.count == 5,
              (source + destination).allSatisfy({ $0.x.isFinite && $0.y.isFinite }),
              source[1].x > source[0].x, destination[1].x > destination[0].x else { return nil }
        let s = CGPoint(x: source.map(\.x).reduce(0, +) / 5, y: source.map(\.y).reduce(0, +) / 5)
        let d = CGPoint(x: destination.map(\.x).reduce(0, +) / 5, y: destination.map(\.y).reduce(0, +) / 5)
        var denominator: CGFloat = 0, real: CGFloat = 0, imaginary: CGFloat = 0
        for (start, end) in zip(source, destination) {
            let x = start.x - s.x, y = start.y - s.y
            let u = end.x - d.x, v = end.y - d.y
            denominator += x*x + y*y; real += x*u + y*v; imaginary += x*v - y*u
        }
        guard denominator > 1e-8 else { return nil }
        let a = real / denominator, b = imaginary / denominator
        let scale = hypot(a, b)
        guard scale.isFinite, scale > 0.001, scale <= 100 else { return nil }
        let transform = CGAffineTransform(a: a, b: b, c: -b, d: a,
            tx: d.x - a*s.x + b*s.y, ty: d.y - b*s.x - a*s.y)
        // Reject reflected or grossly inconsistent landmark arrangements.
        let error = zip(source, destination).map { start, end -> CGFloat in
            let p = start.applying(transform); return hypot(p.x - end.x, p.y - end.y)
        }.reduce(0, +) / 5
        guard error.isFinite, error <= 12 else { return nil }
        return transform
    }
}
