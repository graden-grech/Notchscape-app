import Foundation
import Darwin

@main struct FaceRecognitionSessionPolicyTests {
    struct Frame {
        var captureID: UUID
        var challengeID: UUID
        var timestamp: TimeInterval
        var pose: FaceCameraPose
        var progress: FaceHeadChallengeProgress
        var match: FaceMatchOutcome
    }

    static func main() {
        var checks = 0
        var failures: [String] = []
        func check(_ value: @autoclosure () -> Bool, _ name: String) {
            checks += 1
            if !value() { failures.append(name) }
        }
        let capture = UUID(), challenge = UUID(), identity = UUID(), otherIdentity = UUID()
        let centered = FaceCameraPose(yaw: 0, pitch: 0, roll: 0)!
        let left = FaceCameraPose(yaw: -0.4, pitch: 0, roll: 0)!
        let right = FaceCameraPose(yaw: 0.4, pitch: 0, roll: 0)!
        let match = FaceMatchOutcome.matched(identityID: identity, cosineSimilarity: 0.95)

        func sequence(direction: FaceHeadTurnDirection = .left, issuedAt: TimeInterval = 10,
                      id: UUID = challenge) -> [Frame] {
            var movement = FaceHeadMovementChallenge(id: id, direction: direction, issuedAt: issuedAt)!
            let turned = direction == .left ? left : right
            return [centered, centered, turned, turned, centered, centered].enumerated().map { index, pose in
                let timestamp = issuedAt + Double(index) * 0.35
                let progress = movement.observe(pose: pose, at: timestamp)
                return .init(captureID: capture, challengeID: id, timestamp: timestamp,
                    pose: pose, progress: progress, match: match)
            }
        }
        func observe(_ policy: inout FaceRecognitionSessionPolicy, _ frame: Frame) -> FaceRecognitionEvidence? {
            policy.observe(captureID: frame.captureID, challengeID: frame.challengeID, timestamp: frame.timestamp,
                pose: frame.pose, progress: frame.progress, match: frame.match)
        }
        func evidence(for frames: [Frame], startedAt: TimeInterval = 10) -> [FaceRecognitionEvidence] {
            var policy = FaceRecognitionSessionPolicy(captureID: capture, startedAt: startedAt)
            return frames.compactMap { observe(&policy, $0) }
        }
        let valid = sequence()
        check(valid.map(\.progress) == [.waitingForCenter,.turn(.left),.turn(.left),.returnToCenter,.returnToCenter,.completed],
              "fixture comes from the real pipeline movement policy")
        for direction in [FaceHeadTurnDirection.left, .right] {
            let frames = sequence(direction: direction)
            var policy = FaceRecognitionSessionPolicy(captureID: capture, startedAt: 10)
            for frame in frames.prefix(5) {
                check(observe(&policy, frame) == nil, "every prefix before six matches has no evidence")
            }
            let result = observe(&policy, frames[5])
            check(result == .init(captureID: capture, challengeID: challenge, identityID: identity, observedAt: frames[5].timestamp),
                  "same face across center/turn/return produces exact bounded evidence")
            var replay = frames[5]; replay.timestamp += 0.35
            check(observe(&policy, replay) == nil, "one proof at most per capture session")
        }

        for index in valid.indices {
            var frames = valid
            frames[index].match = .matched(identityID: otherIdentity, cosineSimilarity: 0.99)
            check(evidence(for: frames).isEmpty, "identity switch at any phase invalidates continuity")
            frames = valid; frames[index].challengeID = UUID()
            check(evidence(for: frames).isEmpty, "challenge switch at any phase cannot adopt old movement")
            frames = valid; frames[index].captureID = UUID()
            check(evidence(for: frames).isEmpty, "capture mismatch at any phase invalidates continuity")
            for outcome in [FaceMatchOutcome.noMatch,.ambiguous,.noCompatibleEnrollment] {
                frames = valid; frames[index].match = outcome
                check(evidence(for: frames).isEmpty, "rejected/ambiguous/incompatible match cannot count as six matches")
            }
        }
        let completedOnly = valid.map { frame -> Frame in var value = frame; value.pose = centered; value.progress = .completed; return value }
        check(evidence(for: completedOnly).isEmpty, "cannot adopt another face's completed challenge")
        let missingCenter = valid.map { frame -> Frame in
            var value = frame; if value.progress == .waitingForCenter { value.pose = left }; return value
        }
        check(evidence(for: missingCenter).isEmpty, "center observation must precede turn")
        var missingReturn = valid
        missingReturn[4].progress = .turn(.left)
        check(evidence(for: missingReturn).isEmpty, "actual centered return phase required before completion")
        var missingTurn = valid
        missingTurn[2].pose = centered; missingTurn[3].pose = centered
        check(evidence(for: missingTurn).isEmpty, "motion progress alone cannot replace a turned pose")
        var oppositeTurn = valid
        oppositeTurn[2].pose = right; oppositeTurn[3].pose = right
        check(evidence(for: oppositeTurn).isEmpty, "opposite direction cannot satisfy prompted turn")
        var incomplete = valid; incomplete[5].pose = left
        check(evidence(for: incomplete).isEmpty, "completion must be centered")
        var invalidPose = valid; invalidPose[2].pose = FaceCameraPose(yaw: -0.4,pitch: 0.6,roll: 0)!
        check(evidence(for: invalidPose).isEmpty, "unsupported pose clears accumulated proof")
        let fiveMatches = Array(valid.prefix(4)) + [valid[5]]
        check(evidence(for: fiveMatches).isEmpty, "five matches cannot meet the six-match floor")

        for boundary in 1..<valid.count {
            var policy = FaceRecognitionSessionPolicy(captureID: capture, startedAt: 10)
            for frame in valid.prefix(boundary) { _ = observe(&policy, frame) }
            policy.rejectFrame()
            check(valid.dropFirst(boundary).compactMap { observe(&policy, $0) }.isEmpty,
                  "explicit rejected frame breaks continuity at each phase")
        }
        var resetFrames = valid
        resetFrames[4].progress = .waitingForCenter
        check(evidence(for: resetFrames).isEmpty, "pipeline movement reset discards earlier turn")
        var longGap = valid
        for index in 3..<longGap.count { longGap[index].timestamp += 2 }
        check(evidence(for: longGap).isEmpty, "long observation gap cannot finish old challenge")
        var duplicate = valid
        duplicate[3].timestamp = duplicate[2].timestamp
        check(evidence(for: duplicate).isEmpty, "duplicate timestamp cannot count twice")
        var reverse = valid
        reverse[3].timestamp = reverse[2].timestamp - 0.01
        check(evidence(for: reverse).isEmpty, "reverse timestamp cannot preserve continuity")
        check(evidence(for: Array(valid.prefix(5)) + valid).isEmpty, "replaying old timestamped sequence cannot fabricate evidence")
        for invalidTime in [Double.nan,.infinity,-.infinity,-1] {
            var frames = valid; frames[2].timestamp = invalidTime
            check(evidence(for: frames).isEmpty, "invalid observation clock fails closed")
            check(evidence(for: valid, startedAt: invalidTime).isEmpty, "invalid capture start fails closed")
        }
        check(evidence(for: valid, startedAt: 20).isEmpty, "pre-capture observations fail closed")

        var expiredPolicy = FaceRecognitionSessionPolicy(captureID: capture, startedAt: 10)
        _ = observe(&expiredPolicy, valid[0])
        var expired = valid[1]; expired.progress = .expired
        check(observe(&expiredPolicy, expired) == nil, "expired movement cannot issue proof")
        check(sequence(issuedAt: 12).compactMap { observe(&expiredPolicy, $0) }.isEmpty,
              "expired capture cannot revive with a fabricated fresh sequence")
        var timedOut = FaceRecognitionSessionPolicy(captureID: capture, startedAt: 10)
        var late = valid[0]; late.timestamp = 40.0001
        check(observe(&timedOut, late) == nil, "capture age over thirty seconds fails closed")
        check(sequence(issuedAt: 12).compactMap { observe(&timedOut, $0) }.isEmpty,
              "timeout is terminal even if a later event replays an earlier time")
        let lateSequence = sequence(issuedAt: 39)
        check(evidence(for: lateSequence).isEmpty, "six matches spanning beyond capture deadline cannot issue proof")

        var rejected = FaceRecognitionSessionPolicy(captureID: capture, startedAt: 10)
        for frame in valid.prefix(4) { _ = observe(&rejected, frame) }
        rejected.rejectFrame()
        let fresh = sequence(issuedAt: 12, id: UUID())
        check(fresh.compactMap { observe(&rejected, $0) }.count == 1,
              "ordinary rejection still permits an entirely fresh continuous attempt")
        if !failures.isEmpty {
            failures.forEach { print("FAIL: \($0)") }
            print("FAILED \(failures.count) of \(checks) recognition-session checks")
            exit(1)
        }
        var appearanceFrames = valid
        for index in 3..<appearanceFrames.count {
            appearanceFrames[index].match = .matched(identityID: otherIdentity, cosineSimilarity: 0.95)
        }
        var appearancePolicy = FaceRecognitionSessionPolicy(captureID: capture, startedAt: 10)
        let appearanceEvidence = appearanceFrames.compactMap { frame in
            appearancePolicy.observe(captureID: frame.captureID, challengeID: frame.challengeID,
                timestamp: frame.timestamp, pose: frame.pose, progress: frame.progress, match: frame.match,
                compatibleIdentityAliases: [identity, otherIdentity])
        }
        check(appearanceEvidence.count == 1 && appearanceEvidence.first?.identityID == identity,
              "explicit compatible appearance IDs keep one continuous subject proof")
        check(evidence(for: appearanceFrames).isEmpty, "a different identity cannot be adopted without explicit compatibility")
        print("PASS \(checks) recognition-session checks; synthetic events only, no camera or authentication")
    }
}
