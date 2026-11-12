import Foundation

/// Public builds explicitly disable the local protected companion.
enum FaceUnlockFeaturePolicy {
    static func permits(configurationValue: Any?, hasProtectedHelper: Bool) -> Bool {
        configurationValue as? Bool == true && hasProtectedHelper
    }
}

enum FaceUnlockPolicyError: Error { case invalidData, duplicateIdentity, identityLimit, identityNotFound }

/// The caller injects a version identifying exact weights and alignment/input
/// preprocessing. Dimensions and similarity thresholds are never guessed here.
struct FaceEmbeddingSchema: Codable, Equatable, Sendable {
    let modelVersion: String
    let dimension: Int

    init?(modelVersion: String, dimension: Int) {
        guard (16...2048).contains(dimension), !modelVersion.isEmpty,
              modelVersion.utf8.count <= 256,
              modelVersion.utf8.allSatisfy({ (33...126).contains($0) }) else { return nil }
        self.modelVersion = modelVersion
        self.dimension = dimension
    }

    private enum CodingKeys: String, CodingKey { case modelVersion, dimension }
    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        guard let value = Self(modelVersion: try values.decode(String.self, forKey: .modelVersion),
                               dimension: try values.decode(Int.self, forKey: .dimension)) else {
            throw FaceUnlockPolicyError.invalidData
        }
        self = value
    }
}

struct FaceNormalizedEmbedding: Codable, Equatable, Sendable, CustomDebugStringConvertible {
    let schema: FaceEmbeddingSchema
    let values: [Float]
    var debugDescription: String { "FaceNormalizedEmbedding(<redacted>, dimension: \(schema.dimension))" }

    init?(schema: FaceEmbeddingSchema, values: [Float]) {
        guard values.count == schema.dimension, values.allSatisfy(\.isFinite) else { return nil }
        let squared = values.reduce(0.0) { $0 + Double($1) * Double($1) }
        guard squared.isFinite, squared > 1e-24 else { return nil }
        let norm = squared.squareRoot()
        let normalized = values.map { Float(Double($0) / norm) }
        guard normalized.allSatisfy(\.isFinite) else { return nil }
        self.schema = schema
        self.values = normalized
    }

    private enum CodingKeys: String, CodingKey { case schema, values }
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let schema = try container.decode(FaceEmbeddingSchema.self, forKey: .schema)
        let values = try container.decode([Float].self, forKey: .values)
        // Serialized templates must already be normalized, rather than allowing
        // decode to silently repair malformed or incompatible enrollment data.
        let squared = values.reduce(0.0) { $0 + Double($1) * Double($1) }
        guard abs(squared - 1) <= 0.002,
              let value = Self(schema: schema, values: values) else { throw FaceUnlockPolicyError.invalidData }
        self = value
    }
}

struct FaceIdentityTemplate: Codable, Equatable, Sendable, CustomDebugStringConvertible {
    static let maximumSamples = 5
    let id: UUID
    let label: String
    let isEnabled: Bool
    let samples: [FaceNormalizedEmbedding]
    var debugDescription: String { "FaceIdentityTemplate(<redacted>, enabled: \(isEnabled), samples: \(samples.count))" }

    init?(id: UUID = UUID(), label: String, isEnabled: Bool = true, samples: [FaceNormalizedEmbedding]) {
        guard let clean = Self.validatedLabel(label), (1...Self.maximumSamples).contains(samples.count),
              let schema = samples.first?.schema, samples.allSatisfy({ $0.schema == schema }) else { return nil }
        self.id = id
        self.label = clean
        self.isEnabled = isEnabled
        self.samples = samples
    }

    static func validatedLabel(_ label: String) -> String? {
        let clean = label.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clean.isEmpty, clean.count <= 64, clean.utf8.count <= 256,
              clean.unicodeScalars.allSatisfy({ !CharacterSet.controlCharacters.contains($0) }) else { return nil }
        return clean
    }

    private enum CodingKeys: String, CodingKey { case id, label, isEnabled, samples }
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        guard let value = Self(id: try c.decode(UUID.self, forKey: .id),
            label: try c.decode(String.self, forKey: .label),
            isEnabled: try c.decode(Bool.self, forKey: .isEnabled),
            samples: try c.decode([FaceNormalizedEmbedding].self, forKey: .samples)) else {
            throw FaceUnlockPolicyError.invalidData
        }
        self = value
    }
}

struct FaceIdentityManifest: Codable, Equatable, Sendable {
    static let maximumIdentities = 8
    let formatVersion: Int
    let identities: [FaceIdentityTemplate]
    static var empty: Self { Self(identities: [])! }

    init?(identities: [FaceIdentityTemplate]) {
        guard identities.count <= Self.maximumIdentities,
              Set(identities.map(\.id)).count == identities.count,
              Set(identities.map { $0.label.folding(options: [.caseInsensitive], locale: Locale(identifier: "en_US_POSIX")) }).count == identities.count else { return nil }
        self.formatVersion = 1
        self.identities = identities
    }

    func enrolling(_ identity: FaceIdentityTemplate) throws -> Self {
        guard identities.count < Self.maximumIdentities else { throw FaceUnlockPolicyError.identityLimit }
        guard let updated = Self(identities: identities + [identity]) else { throw FaceUnlockPolicyError.duplicateIdentity }
        return updated
    }

    func settingEnabled(_ enabled: Bool, identityID: UUID) throws -> Self {
        try replacing(identityID) { FaceIdentityTemplate(id: $0.id, label: $0.label, isEnabled: enabled, samples: $0.samples) }
    }

    func renaming(_ identityID: UUID, label: String) throws -> Self {
        try replacing(identityID) { FaceIdentityTemplate(id: $0.id, label: label, isEnabled: $0.isEnabled, samples: $0.samples) }
    }

    func deleting(_ identityID: UUID) throws -> Self {
        guard identities.contains(where: { $0.id == identityID }) else { throw FaceUnlockPolicyError.identityNotFound }
        return Self(identities: identities.filter { $0.id != identityID })!
    }

    private func replacing(_ id: UUID, transform: (FaceIdentityTemplate) -> FaceIdentityTemplate?) throws -> Self {
        guard let index = identities.firstIndex(where: { $0.id == id }) else { throw FaceUnlockPolicyError.identityNotFound }
        var next = identities
        guard let replacement = transform(next[index]) else { throw FaceUnlockPolicyError.invalidData }
        next[index] = replacement
        guard let result = Self(identities: next) else { throw FaceUnlockPolicyError.duplicateIdentity }
        return result
    }

    private enum CodingKeys: String, CodingKey { case formatVersion, identities }
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        guard try c.decode(Int.self, forKey: .formatVersion) == 1,
              let result = Self(identities: try c.decode([FaceIdentityTemplate].self, forKey: .identities)) else {
            throw FaceUnlockPolicyError.invalidData
        }
        self = result
    }
}

struct FaceMatchThresholds: Equatable, Sendable {
    let minimumCosineSimilarity: Double
    let minimumRunnerUpMargin: Double

    init?(minimumCosineSimilarity: Double, minimumRunnerUpMargin: Double) {
        guard minimumCosineSimilarity.isFinite, (0...1).contains(minimumCosineSimilarity),
              minimumRunnerUpMargin.isFinite, minimumRunnerUpMargin > 0,
              minimumRunnerUpMargin <= 1 else { return nil }
        self.minimumCosineSimilarity = minimumCosineSimilarity
        self.minimumRunnerUpMargin = minimumRunnerUpMargin
    }
}

enum FaceMatchOutcome: Equatable, Sendable {
    case matched(identityID: UUID, cosineSimilarity: Double)
    case noMatch, ambiguous, noCompatibleEnrollment
}

enum FaceIdentityMatcher {
    /// Similarity is a vector measurement, not a biometric confidence/security
    /// probability. Callers must calibrate this centroid matcher per pipeline.
    static func match(_ query: FaceNormalizedEmbedding, manifest: FaceIdentityManifest,
                      thresholds: FaceMatchThresholds) -> FaceMatchOutcome {
        let scores = rankedScores(query, manifest: manifest)
        guard !scores.isEmpty else { return .noCompatibleEnrollment }
        guard let best = scores.first, best.1 >= thresholds.minimumCosineSimilarity else { return .noMatch }
        if scores.count > 1, best.1 - scores[1].1 < thresholds.minimumRunnerUpMargin { return .ambiguous }
        return .matched(identityID: best.0, cosineSimilarity: best.1)
    }

    /// Every enabled entry authorizes the SAME local Mac credential. Similar
    /// enrolled appearances (for example glasses/no glasses) therefore do not
    /// compete as different permission roles. Continuous camera proof remains
    /// the caller's responsibility; a high-scoring enabled entry is still needed.
    static func matchAuthorizedFace(_ query: FaceNormalizedEmbedding, manifest: FaceIdentityManifest,
                                    thresholds: FaceMatchThresholds) -> FaceMatchOutcome {
        let scores = rankedScores(query, manifest: manifest)
        guard !scores.isEmpty else { return .noCompatibleEnrollment }
        guard let best = scores.first, best.1 >= thresholds.minimumCosineSimilarity else { return .noMatch }
        return .matched(identityID: best.0, cosineSimilarity: best.1)
    }

    static func compatibleAppearances(for query: FaceNormalizedEmbedding, manifest: FaceIdentityManifest,
                                      minimumSimilarity: Double) -> Set<UUID> {
        guard minimumSimilarity.isFinite, (0...1).contains(minimumSimilarity) else { return [] }
        return Set(rankedScores(query, manifest: manifest).filter { $0.1 >= minimumSimilarity }.map(\.0))
    }

    private static func rankedScores(_ query: FaceNormalizedEmbedding, manifest: FaceIdentityManifest) -> [(UUID, Double)] {
        var scores: [(UUID, Double)] = []
        for identity in manifest.identities where identity.isEnabled {
            guard identity.samples.first?.schema == query.schema else { continue }
            let summed = (0..<query.schema.dimension).map { index in
                identity.samples.reduce(0.0) { $0 + Double($1.values[index]) }
            }
            let norm = summed.reduce(0.0) { $0 + $1 * $1 }.squareRoot()
            guard norm.isFinite, norm > 1e-12 else { continue }
            let cosine = zip(query.values, summed).reduce(0.0) { $0 + Double($1.0) * $1.1 / norm }
            guard cosine.isFinite else { continue }
            scores.append((identity.id, min(1, max(-1, cosine))))
        }
        return scores.sorted {
            $0.1 == $1.1 ? $0.0.uuidString < $1.0.uuidString : $0.1 > $1.1
        }
    }
}

enum FaceUnlockAuthorizationMode: Equatable, Sendable {
    case unlockedOnly, screenUnlockConvenience, automaticWhileRunning
}

enum FaceUnlockAuthorizationExpiration: Equatable, Sendable {
    case deadline(Double)
    case whileRunning
}

enum FaceUnlockInvalidationEvent: Sendable {
    case screenLocked, screenUnlocked, stop, timeout, logout, sessionInactive, privacyChanged, appTerminated, systemSleep, systemWake
}

struct FaceUnlockAuthorizationSession: Equatable, Sendable {
    static let maximumLifetime = 300.0
    let token: UUID
    let mode: FaceUnlockAuthorizationMode
    let issuedAt: Double
    let expiration: FaceUnlockAuthorizationExpiration
    private(set) var isInvalidated = false
    private(set) var isPausedForSleep = false

    var deadline: Double? {
        if case .deadline(let value) = expiration { return value }
        return nil
    }

    /// Compatibility for consumers that also impose a short, finite action
    /// deadline. Only the explicit automatic factory can have no expiry.
    var expiresAt: Double { deadline ?? .infinity }
    var permitsScreenUnlock: Bool {
        !isInvalidated && !isPausedForSleep && mode != .unlockedOnly
    }

    /// Monotonic seconds supplied by the vault; convenience has no default TTL.
    init?(mode: FaceUnlockAuthorizationMode, lifetime: Double, now: Double, token: UUID = UUID()) {
        guard mode != .automaticWhileRunning, now.isFinite, now >= 0, lifetime.isFinite, lifetime > 0,
              lifetime <= Self.maximumLifetime, (now + lifetime).isFinite, now + lifetime > now else { return nil }
        self.token = token
        self.mode = mode
        self.issuedAt = now
        self.expiration = .deadline(now + lifetime)
    }

    /// An explicit user-presence grant retained only in this app process. It is
    /// not a long TTL, persisted Keychain unlock, or biometric security claim.
    static func automaticWhileRunning(now: Double, token: UUID = UUID()) -> Self? {
        guard now.isFinite, now >= 0 else { return nil }
        return .init(token: token, issuedAt: now)
    }

    private init(token: UUID, issuedAt: Double) {
        self.token = token
        self.mode = .automaticWhileRunning
        self.issuedAt = issuedAt
        self.expiration = .whileRunning
    }

    /// Sleep pauses use without revoking an explicitly automatic volatile key.
    /// Revocation/expiry is separate from whether an operation may run now.
    func retainsAuthorization(now: Double, desktopIsActive: Bool) -> Bool {
        !isInvalidated && now.isFinite && now >= issuedAt && desktopIsActive
            && (deadline.map { now < $0 } ?? true)
    }

    func permitsRead(now: Double, desktopIsActive: Bool, desktopIsUnlocked: Bool) -> Bool {
        retainsAuthorization(now: now, desktopIsActive: desktopIsActive) && !isPausedForSleep
            && (desktopIsUnlocked || mode != .unlockedOnly)
    }

    mutating func handle(_ event: FaceUnlockInvalidationEvent, now: Double) {
        guard !isInvalidated, now.isFinite, now >= issuedAt,
              deadline.map({ now < $0 }) ?? true else { isInvalidated = true; return }
        switch event {
        case .screenLocked: if mode == .unlockedOnly { isInvalidated = true }
        case .screenUnlocked: break
        case .systemSleep:
            if mode == .automaticWhileRunning { isPausedForSleep = true }
            else { isInvalidated = true }
        case .systemWake: isPausedForSleep = false
        case .stop, .timeout, .logout, .sessionInactive, .privacyChanged, .appTerminated:
            isInvalidated = true
        }
    }
}
