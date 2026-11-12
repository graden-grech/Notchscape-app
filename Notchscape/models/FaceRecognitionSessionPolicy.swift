import Foundation

/// A short-lived result of one continuous camera challenge. It contains no
/// image, embedding, credential or assertion of Apple biometric authentication.
struct FaceRecognitionEvidence: Equatable, Sendable {
    let captureID: UUID
    let challengeID: UUID
    let identityID: UUID
    let observedAt: TimeInterval
}

/// Requires the same enrolled identity throughout a complete fresh movement
/// sequence. A completed challenge from a different face cannot be adopted.
struct FaceRecognitionSessionPolicy {
    private let captureID: UUID
    private let startedAt: TimeInterval
    private var challengeID: UUID?
    private var identityID: UUID?
    private var identityAliases: Set<UUID> = []
    private var lastTimestamp: TimeInterval?
    private var matchCount = 0
    private var sawCenter = false
    private var turnDirection: FaceHeadTurnDirection?
    private var sawTurn = false
    private var sawReturn = false
    private var hasIssuedEvidence = false

    init(captureID: UUID, startedAt: TimeInterval) {
        self.captureID = captureID
        self.startedAt = startedAt
    }

    mutating func observe(captureID: UUID, challengeID: UUID, timestamp: TimeInterval,
                          pose: FaceCameraPose, progress: FaceHeadChallengeProgress,
                          match: FaceMatchOutcome, compatibleIdentityAliases: Set<UUID> = []) -> FaceRecognitionEvidence? {
        if timestamp.isFinite, timestamp - startedAt > 30 { hasIssuedEvidence = true }
        guard !hasIssuedEvidence, captureID == self.captureID,
              startedAt.isFinite, startedAt >= 0, timestamp.isFinite,
              timestamp >= startedAt, timestamp - startedAt <= 30,
              lastTimestamp.map({ timestamp > $0 }) ?? true,
              pose.permitsAlignment else { clear(); return nil }
        if let lastTimestamp, timestamp - lastTimestamp > 1.2 { clear() }
        defer { lastTimestamp = timestamp }
        guard case .matched(let identity, _) = match else { clear(); return nil }

        if self.challengeID != challengeID || (identityID != identity && !identityAliases.contains(identity)) {
            clear()
            self.challengeID = challengeID
            identityID = identity
            identityAliases = compatibleIdentityAliases.union([identity])
        }
        // A pipeline reset invalidates previously accumulated movement even
        // when the camera's challenge identifier itself remains the same.
        if case .waitingForCenter = progress, sawTurn || turnDirection != nil {
            clear()
            self.challengeID = challengeID
            identityID = identity
            identityAliases = compatibleIdentityAliases.union([identity])
        }
        matchCount += 1
        let centered = abs(pose.yaw) <= 0.13
        switch progress {
        case .waitingForCenter:
            if centered { sawCenter = true }
        case .turn(let direction):
            if sawCenter {
                turnDirection = direction
                if pose.yaw * Double(direction.rawValue) >= 0.30 { sawTurn = true }
            }
        case .returnToCenter:
            if sawCenter, let direction = turnDirection,
               pose.yaw * Double(direction.rawValue) >= 0.30 { sawTurn = true }
            if sawTurn, centered { sawReturn = true }
        case .completed:
            guard sawCenter, sawTurn, sawReturn, centered, matchCount >= 6 else { return nil }
            hasIssuedEvidence = true
            return .init(captureID: captureID, challengeID: challengeID,
                         identityID: identityID ?? identity, observedAt: timestamp)
        case .expired:
            clear()
            hasIssuedEvidence = true
        }
        return nil
    }

    mutating func rejectFrame() { clear() }

    private mutating func clear() {
        challengeID = nil
        identityID = nil
        identityAliases.removeAll()
        matchCount = 0
        sawCenter = false
        turnDirection = nil
        sawTurn = false
        sawReturn = false
    }
}
