import Foundation

enum DockVisibilityValue: Codable, Equatable, Sendable {
    case absent, boolean(Bool), integer(Int64), real(Double)

    var isValid: Bool {
        if case .real(let value) = self { return value.isFinite }
        return true
    }
}

struct DockVisibilitySnapshot: Codable, Equatable, Sendable {
    var autohide: DockVisibilityValue
    var delay: DockVisibilityValue
    static let hidden = Self(autohide: .boolean(true), delay: .integer(3_600))
    var isValid: Bool { autohide.isValid && delay.isValid }

    subscript(_ key: DockVisibilityPreferenceKey) -> DockVisibilityValue {
        get { key == .autohide ? autohide : delay }
        set { if key == .autohide { autohide = newValue } else { delay = newValue } }
    }
}

enum DockVisibilityPreferenceKey: String, CaseIterable, Sendable {
    case autohide, delay = "autohide-delay"
}

struct DockVisibilityOwner: Codable, Equatable, Sendable {
    let pid: Int32
    let uid: UInt32
    let startSeconds: UInt64
    let startMicroseconds: UInt64
    var isValid: Bool { pid > 1 && startSeconds > 0 && startMicroseconds < 1_000_000 }
}

struct DockVisibilityJournal: Codable, Equatable, Sendable {
    var version = 1
    let transaction: UUID
    let owner: DockVisibilityOwner
    let original: DockVisibilitySnapshot
    let applied: DockVisibilitySnapshot
    var isValid: Bool {
        version == 1 && owner.isValid && original.isValid && applied == .hidden
    }
}

enum DockVisibilityFailure: String, Error, Sendable {
    case configuration, owner, busy, storage, journal, preferences, recovery, dockRestart, protocolViolation
}

/// IO boundaries are injected: policy tests never read or write real Dock preferences.
protocol DockVisibilityPreferenceAccess: AnyObject {
    func validateApplyScope() throws
    func readSnapshot() throws -> DockVisibilitySnapshot
    func write(_ value: DockVisibilityValue, for key: DockVisibilityPreferenceKey) throws
    func synchronize() throws
    func refreshDock() throws
}

protocol DockVisibilityJournalAccess: AnyObject {
    func load() throws -> DockVisibilityJournal?
    func save(_ journal: DockVisibilityJournal) throws
    func clear() throws
}

struct DockVisibilityTransition: Equatable, Sendable {
    let changed: Bool
    let manualOverride: Bool
}

enum DockVisibilityPolicy {
    static let maximumJournalBytes = 8_192
    static let guardianFlag = "--dock-visibility-guardian"

    static func ownerPID(arguments: [String]) -> Int32? {
        guard arguments.count == 3, arguments[0] == guardianFlag, arguments[1] == "--owner-pid",
              arguments.allSatisfy({ $0.utf8.count <= 80 }),
              arguments[2].range(of: #"^[1-9][0-9]{0,9}$"#, options: .regularExpression) != nil,
              let pid = Int32(arguments[2]), pid > 1 else { return nil }
        return pid
    }

    static func encode(_ journal: DockVisibilityJournal) throws -> Data {
        guard journal.isValid else { throw DockVisibilityFailure.journal }
        let data = try JSONEncoder().encode(journal)
        guard data.count <= maximumJournalBytes else { throw DockVisibilityFailure.journal }
        return data
    }

    static func decode(_ data: Data) throws -> DockVisibilityJournal {
        guard !data.isEmpty, data.count <= maximumJournalBytes,
              let value = try? JSONDecoder().decode(DockVisibilityJournal.self, from: data), value.isValid else {
            throw DockVisibilityFailure.journal
        }
        return value
    }

    /// Restore only values still owned by this lease; another app or a manual
    /// change wins independently for each key. Absence is a real saved value.
    static func restoration(original: DockVisibilitySnapshot, applied: DockVisibilitySnapshot,
                            current: DockVisibilitySnapshot) -> DockVisibilitySnapshot {
        .init(autohide: current.autohide == applied.autohide ? original.autohide : current.autohide,
              delay: current.delay == applied.delay ? original.delay : current.delay)
    }

    /// The journal must be durable before the first preference write. A failed
    /// apply rolls back through the same ownership-aware recovery path.
    static func apply(owner: DockVisibilityOwner, preferences: any DockVisibilityPreferenceAccess,
                      journal store: any DockVisibilityJournalAccess) throws -> DockVisibilityTransition {
        guard owner.isValid else { throw DockVisibilityFailure.owner }
        try preferences.validateApplyScope()
        guard try store.load() == nil else { throw DockVisibilityFailure.busy }
        let original = try preferences.readSnapshot()
        guard original.isValid else { throw DockVisibilityFailure.preferences }
        let journal = DockVisibilityJournal(transaction: UUID(), owner: owner, original: original, applied: .hidden)
        try store.save(journal)
        do {
            for key in DockVisibilityPreferenceKey.allCases where original[key] != journal.applied[key] {
                try preferences.write(journal.applied[key], for: key)
            }
            try preferences.synchronize()
            guard try preferences.readSnapshot() == journal.applied else { throw DockVisibilityFailure.preferences }
            let changed = original != journal.applied
            if changed { try preferences.refreshDock() }
            return .init(changed: changed, manualOverride: false)
        } catch {
            let applyError = error
            do { _ = try restore(preferences: preferences, journal: store) }
            catch { throw DockVisibilityFailure.recovery }
            throw applyError
        }
    }

    /// Safe for normal shutdown, parent exit, and a journal left before/during
    /// an interrupted apply. Keep the journal until verification succeeds.
    static func restore(preferences: any DockVisibilityPreferenceAccess,
                        journal store: any DockVisibilityJournalAccess) throws -> DockVisibilityTransition {
        guard let journal = try store.load() else { return .init(changed: false, manualOverride: false) }
        guard journal.isValid else { throw DockVisibilityFailure.journal }
        let initial = try preferences.readSnapshot()
        guard initial.isValid else { throw DockVisibilityFailure.preferences }
        var changed = false
        var overridden = initial != journal.applied
        var restoredKeys: [DockVisibilityPreferenceKey] = []
        for key in DockVisibilityPreferenceKey.allCases {
            // Recheck immediately before each write: do not overwrite a manual
            // change detected while another key was being restored.
            let current = try preferences.readSnapshot()
            guard current.isValid else { throw DockVisibilityFailure.preferences }
            guard current[key] == journal.applied[key] else { overridden = true; continue }
            if current[key] != journal.original[key] {
                try preferences.write(journal.original[key], for: key)
                restoredKeys.append(key); changed = true
            }
        }
        try preferences.synchronize()
        let verified = try preferences.readSnapshot()
        guard verified.isValid else { throw DockVisibilityFailure.preferences }
        for key in restoredKeys where verified[key] != journal.original[key] {
            // Still having our value indicates failed restoration. A different
            // new value belongs to the user and must be preserved.
            guard verified[key] != journal.applied[key] else { throw DockVisibilityFailure.recovery }
            overridden = true
        }
        if changed { try preferences.refreshDock() }
        try store.clear()
        return .init(changed: changed, manualOverride: overridden)
    }
}
