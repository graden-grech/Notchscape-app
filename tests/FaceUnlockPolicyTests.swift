import Foundation

@main struct FaceUnlockPolicyTests {
    static func main() throws {
        var checks = 0
        func check(_ condition: @autoclosure () -> Bool, _ message: String) {
            precondition(condition(), message); checks += 1
        }
        func rejects(_ message: String, _ operation: () throws -> Void) {
            do { try operation(); preconditionFailure(message) } catch { checks += 1 }
        }
        for value in [nil, false, "true"] as [Any?] {
            check(!FaceUnlockFeaturePolicy.permits(configurationValue: value, hasProtectedHelper: true), "Unconfigured/public Face Unlock cannot start")
        }
        check(!FaceUnlockFeaturePolicy.permits(configurationValue: true, hasProtectedHelper: false), "Missing protected helper disables Face Unlock")
        check(FaceUnlockFeaturePolicy.permits(configurationValue: true, hasProtectedHelper: true), "Explicit local feature with helper remains available")
        let schema = FaceEmbeddingSchema(modelVersion: "synthetic-weights-v1.align-v1", dimension: 16)!
        func axis(_ index: Int, schema: FaceEmbeddingSchema? = nil) -> FaceNormalizedEmbedding {
            let selected = schema ?? FaceEmbeddingSchema(modelVersion: "synthetic-weights-v1.align-v1", dimension: 16)!
            var vector = [Float](repeating: 0, count: selected.dimension)
            vector[index] = 3
            return FaceNormalizedEmbedding(schema: selected, values: vector)!
        }
        let one = axis(0), two = axis(1), three = axis(2)
        check(one.values[0] == 1, "raw embedding is normalized")
        check(abs(one.values.reduce(0.0) { $0 + Double($1 * $1) } - 1) < 1e-6, "unit length")
        check(FaceNormalizedEmbedding(schema: schema, values: [Float](repeating: 0, count: 16)) == nil, "zero vector rejected")
        check(FaceNormalizedEmbedding(schema: schema, values: [1, 0]) == nil, "wrong dimension rejected")
        var invalid = one.values; invalid[0] = .nan
        check(FaceNormalizedEmbedding(schema: schema, values: invalid) == nil, "nonfinite embedding rejected")
        invalid[0] = .infinity
        check(FaceNormalizedEmbedding(schema: schema, values: invalid) == nil, "infinite embedding rejected")
        invalid[0] = Float.greatestFiniteMagnitude
        check(FaceNormalizedEmbedding(schema: schema, values: invalid)?.values[0] == 1, "large finite input normalizes without Float overflow")
        for (version, dimension) in [("", 16), ("bad version", 16), ("line\nbreak", 16), ("v1", 0), ("v1", 4096)] {
            check(FaceEmbeddingSchema(modelVersion: version, dimension: dimension) == nil, "invalid schema rejected")
        }
        let roundTrip = try JSONDecoder().decode(FaceNormalizedEmbedding.self, from: JSONEncoder().encode(one))
        check(roundTrip == one, "validated normalized serialization roundtrip")
        var encoded = try JSONSerialization.jsonObject(with: JSONEncoder().encode(one)) as! [String: Any]
        encoded["values"] = [2] + [Int](repeating: 0, count: 15)
        rejects("serialized vectors must already be normalized") {
            _ = try JSONDecoder().decode(FaceNormalizedEmbedding.self, from: JSONSerialization.data(withJSONObject: encoded))
        }

        let first = FaceIdentityTemplate(label: "  Person One  ", samples: [one, one])!
        let second = FaceIdentityTemplate(label: "Person Two", samples: [two])!
        check(first.label == "Person One", "label trimming")
        check(FaceIdentityTemplate(label: " ", samples: [one]) == nil, "empty label rejected")
        check(FaceIdentityTemplate(label: "control\ncharacter", samples: [one]) == nil, "control character rejected")
        check(FaceIdentityTemplate(label: String(repeating: "x", count: 65), samples: [one]) == nil, "label bounded")
        check(FaceIdentityTemplate(label: "Empty", samples: []) == nil, "empty enrollment rejected")
        check(FaceIdentityTemplate(label: "Too many", samples: Array(repeating: one, count: 6)) == nil, "sample collection bounded")
        let otherSchema = FaceEmbeddingSchema(modelVersion: "synthetic-weights-v2.align-v1", dimension: 16)!
        check(FaceIdentityTemplate(label: "Mixed", samples: [one, axis(0, schema: otherSchema)]) == nil, "mixed model samples cannot enroll")
        check(!String(reflecting: first).contains("Person One"), "template debug output redacts labels and samples")

        var manifest = try FaceIdentityManifest.empty.enrolling(first).enrolling(second)
        check(manifest.identities.count == 2, "multiple identities supported")
        rejects("duplicate identity rejected") { _ = try manifest.enrolling(first) }
        let duplicateLabel = FaceIdentityTemplate(label: "PERSON ONE", samples: [three])!
        rejects("case-insensitive duplicate label rejected") { _ = try manifest.enrolling(duplicateLabel) }
        let thresholds = FaceMatchThresholds(minimumCosineSimilarity: 0.8, minimumRunnerUpMargin: 0.05)!
        if case .matched(let id, let cosine) = FaceIdentityMatcher.match(one, manifest: manifest, thresholds: thresholds) {
            check(id == first.id && cosine > 0.999, "correct identity selected")
        } else { preconditionFailure("expected synthetic identity match") }
        check(FaceIdentityMatcher.match(three, manifest: manifest, thresholds: thresholds) == .noMatch, "unrelated vector does not match")
        check(FaceIdentityMatcher.match(axis(0, schema: otherSchema), manifest: manifest, thresholds: thresholds) == .noCompatibleEnrollment, "cross-version matching rejected")
        manifest = try manifest.settingEnabled(false, identityID: first.id)
        check(FaceIdentityMatcher.match(one, manifest: manifest, thresholds: thresholds) == .noMatch, "disabled identity cannot match")
        manifest = try manifest.settingEnabled(true, identityID: first.id)
        manifest = try manifest.renaming(first.id, label: "Renamed")
        check(manifest.identities.first?.label == "Renamed", "identity rename preserved")
        rejects("rename cannot collide") { _ = try manifest.renaming(first.id, label: "Person Two") }
        let tied = try manifest.enrolling(FaceIdentityTemplate(label: "Ambiguous", samples: [one])!)
        check(FaceIdentityMatcher.match(one, manifest: tied, thresholds: thresholds) == .ambiguous, "runner-up ambiguity fails closed")
        manifest = try manifest.deleting(first.id)
        check(manifest.identities.count == 1 && manifest.identities.first?.id == second.id, "delete removes only selected identity")
        rejects("missing identity deletion rejected") { _ = try manifest.deleting(first.id) }
        let saved = try JSONDecoder().decode(FaceIdentityManifest.self, from: JSONEncoder().encode(manifest))
        check(saved == manifest, "manifest roundtrip")
        var full = FaceIdentityManifest.empty
        for index in 0..<8 { full = try full.enrolling(FaceIdentityTemplate(label: "Synthetic \(index)", samples: [one])!) }
        rejects("identity limit enforced") { _ = try full.enrolling(FaceIdentityTemplate(label: "Ninth", samples: [one])!) }
        var invalidManifest = try JSONSerialization.jsonObject(with: JSONEncoder().encode(full)) as! [String: Any]
        invalidManifest["formatVersion"] = 2
        rejects("unknown manifest version rejected") {
            _ = try JSONDecoder().decode(FaceIdentityManifest.self, from: JSONSerialization.data(withJSONObject: invalidManifest))
        }
        check(FaceMatchThresholds(minimumCosineSimilarity: .nan, minimumRunnerUpMargin: 0.1) == nil, "nonfinite threshold rejected")
        check(FaceMatchThresholds(minimumCosineSimilarity: 1.01, minimumRunnerUpMargin: 0.1) == nil, "out-of-range threshold rejected")
        check(FaceMatchThresholds(minimumCosineSimilarity: 0.8, minimumRunnerUpMargin: 0) == nil, "ambiguous tie cannot be configured as acceptable")

        for mode in [FaceUnlockAuthorizationMode.unlockedOnly, .screenUnlockConvenience] {
            var session = FaceUnlockAuthorizationSession(mode: mode, lifetime: 120, now: 10)!
            check(session.permitsRead(now: 11, desktopIsActive: true, desktopIsUnlocked: true), "explicit session usable")
            check(!session.permitsRead(now: 11, desktopIsActive: false, desktopIsUnlocked: true), "inactive desktop blocks every mode")
            check(!session.permitsRead(now: 9, desktopIsActive: true, desktopIsUnlocked: true), "reverse clock blocks every mode")
            check(!session.permitsRead(now: .nan, desktopIsActive: true, desktopIsUnlocked: true), "invalid clock blocks every mode")
            check(!session.permitsRead(now: 130, desktopIsActive: true, desktopIsUnlocked: true), "exact expiry cannot be used")
            session.handle(.screenLocked, now: 12)
            check(session.permitsRead(now: 13, desktopIsActive: true, desktopIsUnlocked: false) == (mode == .screenUnlockConvenience), "only explicit convenience can survive lock")
            session.handle(.screenUnlocked, now: 14)
            check(session.expiresAt == 130, "unlock does not extend authorization")
            for event in [FaceUnlockInvalidationEvent.stop, .timeout, .logout, .sessionInactive, .privacyChanged, .appTerminated, .systemSleep] {
                var candidate = FaceUnlockAuthorizationSession(mode: mode, lifetime: 120, now: 10)!
                candidate.handle(event, now: 12)
                check(candidate.isInvalidated, "safety event invalidates every mode")
                check(!candidate.permitsRead(now: 13, desktopIsActive: true, desktopIsUnlocked: true), "invalidation cannot revive")
            }
        }
        for lifetime in [0.0, -1, 301, .infinity, .nan] {
            check(FaceUnlockAuthorizationSession(mode: .screenUnlockConvenience, lifetime: lifetime, now: 0) == nil, "invalid convenience lifetime rejected")
        }
        check(FaceUnlockAuthorizationSession(mode: .screenUnlockConvenience, lifetime: 300, now: 0) != nil, "explicit five-minute upper bound supported")
        check(FaceUnlockAuthorizationSession(mode: .unlockedOnly, lifetime: 60, now: -1) == nil, "invalid clock cannot begin authorization")
        check(FaceUnlockAuthorizationSession(mode: .unlockedOnly, lifetime: 1, now: Double.greatestFiniteMagnitude) == nil, "unrepresentable expiry rejected")
        check(FaceUnlockAuthorizationSession(mode: .automaticWhileRunning, lifetime: 300, now: 10) == nil,
              "automatic authorization cannot be smuggled through a timed constructor")
        for invalidClock in [-1.0, .nan, .infinity] {
            check(FaceUnlockAuthorizationSession.automaticWhileRunning(now: invalidClock) == nil,
                  "automatic factory rejects an invalid monotonic clock")
        }
        let automaticToken = UUID()
        var automatic = FaceUnlockAuthorizationSession.automaticWhileRunning(now: 10, token: automaticToken)!
        check(automatic.mode == .automaticWhileRunning && automatic.expiration == .whileRunning && automatic.deadline == nil,
              "automatic authorization has an explicit app-lifetime expiration type")
        check(automatic.expiresAt == .infinity && automatic.permitsScreenUnlock,
              "compatibility expiry cannot add a hidden timer to automatic mode")
        check(automatic.permitsRead(now: 1_000_000, desktopIsActive: true, desktopIsUnlocked: false),
              "automatic authorization does not require a timed manual restart")
        check(!automatic.permitsRead(now: 11, desktopIsActive: false, desktopIsUnlocked: false),
              "an inactive desktop cannot use automatic authorization")
        check(!automatic.permitsRead(now: 9, desktopIsActive: true, desktopIsUnlocked: true),
              "reverse clocks remain refused in automatic mode")
        check(!automatic.permitsRead(now: .nan, desktopIsActive: true, desktopIsUnlocked: true),
              "nonfinite clocks remain refused in automatic mode")
        for instant in [11.0, 100, 1000] {
            automatic.handle(.screenLocked, now: instant)
            check(automatic.permitsRead(now: instant, desktopIsActive: true, desktopIsUnlocked: false),
                  "ordinary lock preserves the explicit automatic grant")
            automatic.handle(.screenUnlocked, now: instant + 1)
            check(automatic.permitsRead(now: instant + 1, desktopIsActive: true, desktopIsUnlocked: true),
                  "normal unlock leaves automatic authorization ready for the next lock")
            check(automatic.token == automaticToken && automatic.issuedAt == 10 && automatic.deadline == nil,
                  "lock/unlock never rotates or stretches the original automatic grant")
        }
        automatic.handle(.systemSleep, now: 2000)
        check(automatic.retainsAuthorization(now: 2001, desktopIsActive: true) && automatic.isPausedForSleep,
              "automatic volatile authorization may survive sleep without running output")
        check(!automatic.permitsRead(now: 2001, desktopIsActive: true, desktopIsUnlocked: false)
            && !automatic.permitsScreenUnlock, "sleep pauses every credential operation and screen action")
        automatic.handle(.screenUnlocked, now: 2002)
        check(!automatic.permitsRead(now: 2002, desktopIsActive: true, desktopIsUnlocked: true),
              "an unlock notification alone cannot bypass the sleep pause")
        automatic.handle(.systemWake, now: 2003)
        check(automatic.permitsRead(now: 2004, desktopIsActive: true, desktopIsUnlocked: false),
              "explicit wake resumes an automatic grant without another timed session")
        for event in [FaceUnlockInvalidationEvent.stop, .timeout, .logout, .sessionInactive, .privacyChanged, .appTerminated] {
            var candidate = FaceUnlockAuthorizationSession.automaticWhileRunning(now: 10, token: automaticToken)!
            candidate.handle(event, now: 12)
            check(candidate.isInvalidated && !candidate.permitsScreenUnlock,
                  "Off/logout/user switch/privacy/quit revoke automatic capability")
            candidate.handle(.systemWake, now: 13)
            candidate.handle(.screenUnlocked, now: 14)
            check(!candidate.permitsRead(now: 15, desktopIsActive: true, desktopIsUnlocked: true),
                  "wake/unlock cannot revive an explicitly revoked automatic grant")
        }
        let unlockedOnly = FaceUnlockAuthorizationSession(mode: .unlockedOnly, lifetime: 60, now: 0)!
        check(!unlockedOnly.permitsScreenUnlock && unlockedOnly.deadline == 60,
              "bounded editing-only authorization still cannot unlock the screen")
        let aliasSchema = FaceEmbeddingSchema(modelVersion: "synthetic-appearances-v1", dimension: 16)!
        let aliasVector = FaceNormalizedEmbedding(schema: aliasSchema, values: [1] + [Float](repeating: 0, count: 15))!
        let appearanceA = FaceIdentityTemplate(label: "Synthetic appearance A", samples: [aliasVector])!
        let appearanceB = FaceIdentityTemplate(label: "Synthetic appearance B", samples: [aliasVector])!
        let appearanceManifest = FaceIdentityManifest(identities: [appearanceA, appearanceB])!
        let aliasThresholds = FaceMatchThresholds(minimumCosineSimilarity: 0.8, minimumRunnerUpMargin: 0.1)!
        check(FaceIdentityMatcher.match(aliasVector, manifest: appearanceManifest, thresholds: aliasThresholds) == .ambiguous,
              "unique-identity matching still distinguishes ambiguity")
        if case .matched = FaceIdentityMatcher.matchAuthorizedFace(aliasVector, manifest: appearanceManifest, thresholds: aliasThresholds) {
            check(true, "two trusted appearances authorizing one local credential do not block one another")
        } else { check(false, "trusted appearance must be usable") }
        check(FaceIdentityMatcher.compatibleAppearances(for: aliasVector, manifest: appearanceManifest,
            minimumSimilarity: 0.8) == Set([appearanceA.id, appearanceB.id]), "matching appearances are explicit IDs")
        let disabledAppearances = try! appearanceManifest.settingEnabled(false, identityID: appearanceA.id)
            .settingEnabled(false, identityID: appearanceB.id)
        check(FaceIdentityMatcher.matchAuthorizedFace(aliasVector, manifest: disabledAppearances,
            thresholds: aliasThresholds) == .noCompatibleEnrollment, "disabled appearances never authorize")
        check(FaceIdentityMatcher.compatibleAppearances(for: aliasVector, manifest: appearanceManifest,
            minimumSimilarity: .nan).isEmpty, "invalid alias threshold fails closed")
        print("PASS \(checks) face policy behavior checks (synthetic vectors only)")
    }
}
