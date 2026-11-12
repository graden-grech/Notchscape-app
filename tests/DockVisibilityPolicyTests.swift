import Foundation

@main struct DockVisibilityPolicyTests {
    static func main() throws {
        var checks = 0
        func check(_ value: @autoclosure () -> Bool, _ message: String) {
            precondition(value(), message); checks += 1
        }
        func fails(_ operation: () throws -> Void, _ message: String) {
            do { try operation(); preconditionFailure(message) } catch { checks += 1 }
        }
        let original = DockVisibilitySnapshot(autohide: .absent, delay: .real(0.25))
        let restored = DockVisibilityPolicy.restoration(original: original,
                                                       applied: .hidden, current: .hidden)
        check(restored == original, "Restoration must preserve absent keys and the original numeric type")
        let owner = DockVisibilityOwner(pid: 42, uid: 501, startSeconds: 123, startMicroseconds: 45)
        let values: [DockVisibilityValue] = [.absent, .boolean(false), .boolean(true), .integer(0),
                                           .integer(3_600), .integer(Int64.max), .integer(Int64.min), .real(0), .real(0.25)]
        for hide in values {
            for delay in values {
                let saved = DockVisibilitySnapshot(autohide: hide, delay: delay)
                let journal = DockVisibilityJournal(transaction: UUID(), owner: owner, original: saved, applied: .hidden)
                let decoded = try DockVisibilityPolicy.decode(DockVisibilityPolicy.encode(journal))
                check(decoded == journal,
                      "Journal preserves exact supported value type and absence")
                for currentHide in values {
                    for currentDelay in values {
                        let current = DockVisibilitySnapshot(autohide: currentHide, delay: currentDelay)
                        let result = DockVisibilityPolicy.restoration(original: saved, applied: .hidden, current: current)
                        check(result.autohide == (currentHide == .boolean(true) ? hide : currentHide), "Autohide ownership")
                        check(result.delay == (currentDelay == .integer(3_600) ? delay : currentDelay), "Delay ownership")
                    }
                }
            }
        }
        for raw in [Data(), Data("{}".utf8), Data(repeating: 65, count: 8_193)] {
            fails({ _ = try DockVisibilityPolicy.decode(raw) }, "Invalid journal must fail closed")
        }
        for invalid in [Double.nan, .infinity, -.infinity] {
            let journal = DockVisibilityJournal(transaction: UUID(), owner: owner,
                original: .init(autohide: .boolean(false), delay: .real(invalid)), applied: .hidden)
            fails({ _ = try DockVisibilityPolicy.encode(journal) }, "Nonfinite journal must fail closed")
        }
        let valid = [DockVisibilityPolicy.guardianFlag, "--owner-pid", "42"]
        check(DockVisibilityPolicy.ownerPID(arguments: valid) == 42, "Strict guardian entry")
        for invalid in [[], Array(valid.dropLast()), valid + ["extra"], [valid[0], "--file", "42"],
                        [valid[0], valid[1], "0"], [valid[0], valid[1], "1"], [valid[0], valid[1], "-42"],
                        [valid[0], valid[1], "042"], [valid[0], valid[1], "2147483648"],
                        [valid[0], valid[1], "42\n"], [valid[0], valid[1], String(repeating: "9", count: 81)]] {
            check(DockVisibilityPolicy.ownerPID(arguments: invalid) == nil, "Reject unknown/malformed guardian arguments")
        }
        // These stores replace the only OS side effects, not policy behavior.
        let trace = Trace()
        let prefs = Preferences(original, trace: trace)
        let store = JournalStore(trace: trace)
        let applied = try DockVisibilityPolicy.apply(owner: owner, preferences: prefs, journal: store)
        check(applied.changed && prefs.value == .hidden && store.value != nil, "Apply starts an owned lease")
        check(trace.events.first == "save", "Durable journal must precede all preference writes")
        check(prefs.refreshes == 1, "One Dock refresh for one actual transition")
        let undone = try DockVisibilityPolicy.restore(preferences: prefs, journal: store)
        check(undone.changed && prefs.value == original && store.value == nil, "Disable restores exact snapshot")
        check(prefs.refreshes == 2, "Restoration refreshes once")
        _ = try DockVisibilityPolicy.restore(preferences: prefs, journal: store)
        check(prefs.refreshes == 2, "Repeated restore performs no preference transition")

        for changedKey in DockVisibilityPreferenceKey.allCases {
            let p = Preferences(original); let j = JournalStore()
            _ = try DockVisibilityPolicy.apply(owner: owner, preferences: p, journal: j)
            let manual: DockVisibilityValue = changedKey == .autohide ? .boolean(false) : .real(1.25)
            p.value[changedKey] = manual
            let result = try DockVisibilityPolicy.restore(preferences: p, journal: j)
            check(result.manualOverride && p.value[changedKey] == manual, "Manual changes win independently per key")
            let other: DockVisibilityPreferenceKey = changedKey == .autohide ? .delay : .autohide
            check(p.value[other] == original[other] && j.value == nil, "Untouched leased key still restores")
        }
        // Crash after journal creation or between the two writes.
        for interrupted in [original, .init(autohide: .boolean(true), delay: original.delay), .hidden] {
            let p = Preferences(interrupted); let j = JournalStore()
            j.value = .init(transaction: UUID(), owner: owner, original: original, applied: .hidden)
            _ = try DockVisibilityPolicy.restore(preferences: p, journal: j)
            check(p.value == original && j.value == nil, "Interrupted apply is recoverable")
        }
        do {
            let p = Preferences(original); let j = JournalStore(); j.failSave = true
            fails({ _ = try DockVisibilityPolicy.apply(owner: owner, preferences: p, journal: j) }, "Saving journal must succeed first")
            check(p.writes == 0 && p.value == original && p.refreshes == 0, "Journal failure never changes preferences")
        }
        for failingWrite in [1, 2] {
            let p = Preferences(original); let j = JournalStore(); p.failWrites = [failingWrite]
            fails({ _ = try DockVisibilityPolicy.apply(owner: owner, preferences: p, journal: j) }, "Apply failure is reported")
            check(p.value == original && j.value == nil, "Partial write rolls back")
        }
        do {
            let p = Preferences(original); let j = JournalStore(); p.failSyncs = 1
            fails({ _ = try DockVisibilityPolicy.apply(owner: owner, preferences: p, journal: j) }, "Sync failure is reported")
            check(p.value == original && j.value == nil, "Sync failure rolls back")
        }
        do {
            let p = Preferences(original); let j = JournalStore(); p.ignoreWrites = true
            fails({ _ = try DockVisibilityPolicy.apply(owner: owner, preferences: p, journal: j) }, "Readback verification catches ignored writes")
            check(p.value == original && p.refreshes == 0, "Unapplied values never restart Dock")
        }
        do {
            let p = Preferences(original); let j = JournalStore()
            _ = try DockVisibilityPolicy.apply(owner: owner, preferences: p, journal: j)
            p.failWrites = [p.writes + 1]
            fails({ _ = try DockVisibilityPolicy.restore(preferences: p, journal: j) }, "Failed restore must report failure")
            check(j.value != nil, "Failed restoration preserves journal for recovery")
            _ = try DockVisibilityPolicy.restore(preferences: p, journal: j)
            check(p.value == original && j.value == nil, "Later recovery restores failed transaction")
        }
        do {
            let p = Preferences(.hidden); let j = JournalStore()
            _ = try DockVisibilityPolicy.apply(owner: owner, preferences: p, journal: j)
            _ = try DockVisibilityPolicy.restore(preferences: p, journal: j)
            check(p.writes == 0 && p.refreshes == 0 && j.value == nil, "Already matching settings produce no Dock restarts")
        }
        do {
            let p = Preferences(original); let j = JournalStore()
            j.value = .init(transaction: UUID(), owner: owner, original: original, applied: .hidden)
            fails({ _ = try DockVisibilityPolicy.apply(owner: owner, preferences: p, journal: j) }, "Pending lease cannot be overwritten")
            check(p.writes == 0 && j.value?.original == original, "Pending original snapshot is retained")
        }
        do {
            let p = Preferences(original); let j = JournalStore(); p.failRefreshes = 1
            fails({ _ = try DockVisibilityPolicy.apply(owner: owner, preferences: p, journal: j) }, "Restart failure must report and roll back")
            check(p.value == original && j.value == nil, "Failed activation returns previous settings")
        }
        do {
            let p = Preferences(original); let j = JournalStore()
            _ = try DockVisibilityPolicy.apply(owner: owner, preferences: p, journal: j)
            p.ignoreWrites = true
            fails({ _ = try DockVisibilityPolicy.restore(preferences: p, journal: j) }, "Ignored restoration write fails verification")
            check(j.value != nil && p.value == .hidden, "Journal remains while our values still need recovery")
            p.ignoreWrites = false
            _ = try DockVisibilityPolicy.restore(preferences: p, journal: j)
            check(p.value == original && j.value == nil, "Retained transaction recovers after write failure")
        }
        do {
            let p = Preferences(original); let j = JournalStore()
            _ = try DockVisibilityPolicy.apply(owner: owner, preferences: p, journal: j)
            j.failClear = true
            fails({ _ = try DockVisibilityPolicy.restore(preferences: p, journal: j) }, "Journal deletion failure is reported")
            check(p.value == original && j.value != nil, "Restoration remains idempotent after deletion failure")
            j.failClear = false
            let refreshCount = p.refreshes
            _ = try DockVisibilityPolicy.restore(preferences: p, journal: j)
            check(p.value == original && j.value == nil && p.refreshes == refreshCount, "Already restored keys do not restart Dock again")
        }
        do {
            let p = Preferences(original); let j = JournalStore()
            _ = try DockVisibilityPolicy.apply(owner: owner, preferences: p, journal: j)
            p.onWrite = { key in
                if key == .autohide { p.value.delay = .real(2.5) }
            }
            _ = try DockVisibilityPolicy.restore(preferences: p, journal: j)
            check(p.value == .init(autohide: .absent, delay: .real(2.5)), "Rechecking each key preserves a concurrent manual change")
            p.onWrite = nil
        }
        do {
            let p = Preferences(original); let j = JournalStore(); p.scopeAllowed = false
            fails({ _ = try DockVisibilityPolicy.apply(owner: owner, preferences: p, journal: j) }, "Managed/host scope must block apply")
            check(p.writes == 0 && j.value == nil, "Unsupported effective scope does not create a lease or change any key")
            p.scopeAllowed = true
            _ = try DockVisibilityPolicy.apply(owner: owner, preferences: p, journal: j)
            p.scopeAllowed = false
            _ = try DockVisibilityPolicy.restore(preferences: p, journal: j)
            check(p.value == original && j.value == nil, "Scope becoming managed never blocks restoration of owned raw values")
        }
        print("PASS \(checks) Dock visibility ownership, transaction, recovery and input checks; synthetic stores only")
    }
}

private final class Trace { var events: [String] = [] }
private final class Preferences: DockVisibilityPreferenceAccess {
    var value: DockVisibilitySnapshot
    var writes = 0
    var refreshes = 0
    var failWrites: Set<Int> = []
    var failSyncs = 0
    var failRefreshes = 0
    var ignoreWrites = false
    var onWrite: ((DockVisibilityPreferenceKey) -> Void)?
    var scopeAllowed = true
    let trace: Trace
    init(_ value: DockVisibilitySnapshot, trace: Trace = Trace()) { self.value = value; self.trace = trace }
    func readSnapshot() throws -> DockVisibilitySnapshot { value }
    func validateApplyScope() throws {
        if !scopeAllowed { throw DockVisibilityFailure.preferences }
    }
    func write(_ value: DockVisibilityValue, for key: DockVisibilityPreferenceKey) throws {
        writes += 1; trace.events.append("write")
        if failWrites.remove(writes) != nil { throw DockVisibilityFailure.preferences }
        if !ignoreWrites { self.value[key] = value }
        onWrite?(key)
    }
    func synchronize() throws {
        if failSyncs > 0 { failSyncs -= 1; throw DockVisibilityFailure.preferences }
    }
    func refreshDock() throws {
        if failRefreshes > 0 { failRefreshes -= 1; throw DockVisibilityFailure.dockRestart }
        refreshes += 1
    }
}
private final class JournalStore: DockVisibilityJournalAccess {
    var value: DockVisibilityJournal?
    var failSave = false
    var failClear = false
    let trace: Trace
    init(trace: Trace = Trace()) { self.trace = trace }
    func load() throws -> DockVisibilityJournal? { value }
    func save(_ journal: DockVisibilityJournal) throws {
        if failSave { throw DockVisibilityFailure.storage }
        trace.events.append("save"); value = journal
    }
    func clear() throws {
        if failClear { throw DockVisibilityFailure.storage }
        value = nil
    }
}
