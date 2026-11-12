import AppKit
import Darwin
import Foundation
import Security
import OSLog

/// A distinct, non-AppKit execution mode of the existing signed companion.
/// Only its fixed two-key store may touch Dock preferences. No widget IPC,
/// Dock tile, login item, shell, network, arbitrary path or privilege is used.
@MainActor final class DockVisibilityGuardian {
    private let owner: DockVisibilityOwner
    private let journal: DockVisibilityFileJournal
    private let preferences = DockVisibilityPreferences()
    private var sources: [any DispatchSourceProtocol] = []
    private var input = Data()
    private var finishing = false
    private var mayRestore = false

    static func run(arguments: [String]) -> Never {
        do {
            guard let pid = DockVisibilityPolicy.ownerPID(arguments: arguments), pid == getppid(),
                  DockWidgetController.validOwner(pid), let owner = ownerIdentity(pid),
                  getuid() == geteuid() else { throw DockVisibilityFailure.owner }
            let guardian = try DockVisibilityGuardian(owner: owner)
            guardian.begin()
            withExtendedLifetime(guardian) { dispatchMain() }
        } catch {
            let failure = (error as? DockVisibilityFailure) ?? .storage
            let message = "ERROR:\(failure.rawValue)\n"
            _ = message.withCString { Darwin.write(STDOUT_FILENO, $0, message.utf8.count) }
            exit(EXIT_FAILURE)
        }
    }

    private init(owner: DockVisibilityOwner) throws {
        self.owner = owner
        journal = try DockVisibilityFileJournal()
    }

    private func begin() {
        // A closed output pipe must never kill us before restoring the lease.
        signal(SIGPIPE, SIG_IGN)
        let parent = DispatchSource.makeProcessSource(identifier: owner.pid, eventMask: .exit, queue: .main)
        parent.setEventHandler { [weak self] in Task { @MainActor in self?.finish() } }
        sources.append(parent); parent.activate()
        for number in [SIGTERM, SIGINT, SIGHUP] {
            signal(number, SIG_IGN)
            let source = DispatchSource.makeSignalSource(signal: number, queue: .main)
            source.setEventHandler { [weak self] in Task { @MainActor in self?.finish() } }
            sources.append(source); source.activate()
        }
        let incoming = DispatchSource.makeReadSource(fileDescriptor: STDIN_FILENO, queue: .main)
        incoming.setEventHandler { [weak self] in Task { @MainActor in self?.readInput() } }
        sources.append(incoming); incoming.activate()
        // Recheck after monitoring is installed, including PID start identity.
        guard ownerIsCurrent else { finish(); return }
        do {
            if let stale = try journal.load() {
                // Never steal a lease from another still-running main instance.
                if stale.owner != owner, Self.ownerIdentity(stale.owner.pid) == stale.owner {
                    throw DockVisibilityFailure.busy
                }
                mayRestore = true
                _ = try DockVisibilityPolicy.restore(preferences: preferences, journal: journal)
            }
            mayRestore = true
            guard ownerIsCurrent else { finish(); return }
            if !emit("READY") { finish() }
        } catch { finish(failure: (error as? DockVisibilityFailure) ?? .recovery) }
    }

    private var ownerIsCurrent: Bool {
        getppid() == owner.pid && Self.ownerIdentity(owner.pid) == owner && DockWidgetController.validOwner(owner.pid)
    }

    private static func ownerIdentity(_ pid: Int32) -> DockVisibilityOwner? {
        var info = proc_bsdinfo()
        let size = Int32(MemoryLayout<proc_bsdinfo>.size)
        guard pid > 1, proc_pidinfo(pid, PROC_PIDTBSDINFO, 0, &info, size) == size,
              info.pbi_pid == UInt32(pid), info.pbi_uid == getuid(), info.pbi_ruid == getuid() else { return nil }
        let identity = DockVisibilityOwner(pid: pid, uid: info.pbi_uid,
            startSeconds: info.pbi_start_tvsec, startMicroseconds: info.pbi_start_tvusec)
        return identity.isValid ? identity : nil
    }

    private func readInput() {
        guard !finishing else { return }
        var bytes = [UInt8](repeating: 0, count: 256)
        let count = Darwin.read(STDIN_FILENO, &bytes, bytes.count)
        if count == 0 { finish(); return }
        if count < 0 { if errno != EINTR { finish(failure: .protocolViolation) }; return }
        input.append(contentsOf: bytes.prefix(count))
        guard input.count <= 1_024 else { finish(failure: .protocolViolation); return }
        while let end = input.firstIndex(of: 10) {
            let line = input.prefix(upTo: end)
            guard line.count <= 32, let command = String(data: line, encoding: .utf8) else {
                finish(failure: .protocolViolation); return
            }
            input.removeSubrange(...end)
            handle(command)
            if finishing { return }
        }
        if input.count > 32 { finish(failure: .protocolViolation) }
    }

    private func handle(_ command: String) {
        guard ownerIsCurrent else { finish(); return }
        do {
            switch command {
            case "APPLY":
                try preferences.validateApplyScope()
                if let existing = try journal.load() {
                    guard existing.owner == owner, try preferences.readSnapshot() == existing.applied else {
                        finish(message: "OVERRIDDEN"); return
                    }
                } else {
                    _ = try DockVisibilityPolicy.apply(owner: owner, preferences: preferences, journal: journal)
                }
                if !emit("APPLIED") { finish() }
            case "CHECK":
                do { try preferences.validateApplyScope() }
                catch { finish(message: "OVERRIDDEN"); return }
                if let existing = try journal.load(), try preferences.readSnapshot() != existing.applied {
                    finish(message: "OVERRIDDEN")
                }
            case "RESTORE": finish()
            default: finish(failure: .protocolViolation)
            }
        } catch { finish(failure: (error as? DockVisibilityFailure) ?? .recovery) }
    }

    @discardableResult private func emit(_ message: String) -> Bool {
        let bytes = Array((message + "\n").utf8)
        return bytes.withUnsafeBytes { buffer in
            var offset = 0
            while offset < buffer.count {
                let count = Darwin.write(STDOUT_FILENO, buffer.baseAddress!.advanced(by: offset), buffer.count - offset)
                if count < 0 { if errno == EINTR { continue }; return false }
                if count == 0 { return false }
                offset += count
            }
            return true
        }
    }

    private func finish(message: String = "RESTORED", failure: DockVisibilityFailure? = nil) {
        guard !finishing else { return }; finishing = true
        do {
            if mayRestore { _ = try DockVisibilityPolicy.restore(preferences: preferences, journal: journal) }
            emit(failure.map { "ERROR:\($0.rawValue)" } ?? message)
            exit(failure == nil ? EXIT_SUCCESS : EXIT_FAILURE)
        } catch {
            // Keep the durable journal; the next signed owner can recover it.
            emit("ERROR:recovery"); exit(EXIT_FAILURE)
        }
    }
}

/// Fixed current-user/any-host domain, never a caller-supplied domain or key.
private final class DockVisibilityPreferences: DockVisibilityPreferenceAccess {
    private let domain = "com.apple.dock" as CFString

    func validateApplyScope() throws {
        for key in DockVisibilityPreferenceKey.allCases {
            guard !CFPreferencesAppValueIsForced(key.rawValue as CFString, domain),
                  CFPreferencesCopyValue(key.rawValue as CFString, domain,
                                         kCFPreferencesCurrentUser, kCFPreferencesCurrentHost) == nil else {
                throw DockVisibilityFailure.preferences
            }
        }
    }

    func readSnapshot() throws -> DockVisibilitySnapshot {
        guard CFPreferencesSynchronize(domain, kCFPreferencesCurrentUser, kCFPreferencesAnyHost) else {
            throw DockVisibilityFailure.preferences
        }
        return try .init(autohide: read(.autohide), delay: read(.delay))
    }

    private func read(_ key: DockVisibilityPreferenceKey) throws -> DockVisibilityValue {
        guard let raw = CFPreferencesCopyValue(key.rawValue as CFString, domain,
                                               kCFPreferencesCurrentUser, kCFPreferencesAnyHost) else { return .absent }
        guard let number = raw as? NSNumber else { throw DockVisibilityFailure.preferences }
        if CFGetTypeID(number) == CFBooleanGetTypeID() { return .boolean(number.boolValue) }
        guard CFGetTypeID(number) == CFNumberGetTypeID() else { throw DockVisibilityFailure.preferences }
        let type = String(cString: number.objCType)
        if type == "d" || type == "f" {
            guard number.doubleValue.isFinite else { throw DockVisibilityFailure.preferences }
            return .real(number.doubleValue)
        }
        guard let exact = Int64(number.stringValue) else { throw DockVisibilityFailure.preferences }
        return .integer(exact)
    }

    func write(_ value: DockVisibilityValue, for key: DockVisibilityPreferenceKey) throws {
        guard value.isValid else { throw DockVisibilityFailure.preferences }
        let raw: CFPropertyList?
        switch value {
        case .absent: raw = nil
        case .boolean(let value): raw = NSNumber(value: value)
        case .integer(let value): raw = NSNumber(value: value)
        case .real(let value): raw = NSNumber(value: value)
        }
        CFPreferencesSetValue(key.rawValue as CFString, raw, domain, kCFPreferencesCurrentUser, kCFPreferencesAnyHost)
    }

    func synchronize() throws {
        guard CFPreferencesSynchronize(domain, kCFPreferencesCurrentUser, kCFPreferencesAnyHost) else {
            throw DockVisibilityFailure.preferences
        }
    }

    /// One targeted SIGTERM per actual transition, never a restart loop. Dock
    /// remains installed/running under launchd; no unrelated process is touched.
    func refreshDock() throws {
        let available = proc_listallpids(nil, 0)
        guard available > 0, available <= 262_144 else { throw DockVisibilityFailure.dockRestart }
        var pids = [pid_t](repeating: 0, count: Int(available) + 32)
        let count = pids.withUnsafeMutableBytes { proc_listallpids($0.baseAddress, Int32($0.count)) }
        guard count >= 0, Int(count) <= pids.count else { throw DockVisibilityFailure.dockRestart }
        for pid in pids.prefix(Int(count)) where pid > 1 {
            var before = proc_bsdinfo()
            let size = Int32(MemoryLayout<proc_bsdinfo>.size)
            guard proc_pidinfo(pid, PROC_PIDTBSDINFO, 0, &before, size) == size,
                  before.pbi_uid == getuid(), before.pbi_ruid == getuid() else { continue }
            var path = [CChar](repeating: 0, count: Int(MAXPATHLEN) * 4)
            guard proc_pidpath(pid, &path, UInt32(path.count)) > 0,
                  String(decoding: path.prefix(while: { $0 != 0 }).map { UInt8(bitPattern: $0) }, as: UTF8.self) ==
                    "/System/Library/CoreServices/Dock.app/Contents/MacOS/Dock" else { continue }
            var code: SecCode?; var requirement: SecRequirement?
            let attributes = [kSecGuestAttributePid as String: NSNumber(value: pid)] as CFDictionary
            guard SecCodeCopyGuestWithAttributes(nil, attributes, [], &code) == errSecSuccess, let code,
                  SecRequirementCreateWithString(#"identifier "com.apple.dock" and anchor apple"# as CFString,
                                                [], &requirement) == errSecSuccess, let requirement,
                  SecCodeCheckValidity(code, [], requirement) == errSecSuccess else { throw DockVisibilityFailure.dockRestart }
            var after = proc_bsdinfo()
            guard proc_pidinfo(pid, PROC_PIDTBSDINFO, 0, &after, size) == size,
                  before.pbi_start_tvsec == after.pbi_start_tvsec,
                  before.pbi_start_tvusec == after.pbi_start_tvusec,
                  after.pbi_uid == getuid(), after.pbi_ruid == getuid() else { throw DockVisibilityFailure.dockRestart }
            Logger(subsystem: "com.graden-grech.Notchscape", category: "DockNativeRefresh")
                .notice("phase=refreshSignal dockPID=\(pid, privacy: .public) ownerPID=\(getppid(), privacy: .public)")
            guard Darwin.kill(pid, SIGTERM) == 0 || errno == ESRCH else { throw DockVisibilityFailure.dockRestart }
            return
        }
        // No Dock process exists (for example during its normal restart). Do
        // not launch one or repeatedly search/kill while holding a lease.
    }
}

/// The lock lives for this process's lifetime. Journals and temporary files
/// use fixed names beneath a private directory and never follow final symlinks.
private final class DockVisibilityFileJournal: DockVisibilityJournalAccess {
    private let directoryFD: Int32
    private let lockFD: Int32
    private let name = "lease.json"

    init() throws {
        let directory = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/Notchscape/Dock Visibility", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true,
                                               attributes: [.posixPermissions: 0o700])
        let folder = Darwin.open(directory.path, O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC)
        guard folder >= 0 else { throw DockVisibilityFailure.storage }
        var info = stat()
        guard fstat(folder, &info) == 0, info.st_uid == getuid(), info.st_mode & 0o077 == 0 else {
            Darwin.close(folder); throw DockVisibilityFailure.storage
        }
        let lock = openat(folder, "lease.lock", O_RDWR | O_CREAT | O_NOFOLLOW | O_CLOEXEC, 0o600)
        guard lock >= 0, Self.safeFile(lock), flock(lock, LOCK_EX | LOCK_NB) == 0 else {
            if lock >= 0 { Darwin.close(lock) }; Darwin.close(folder); throw DockVisibilityFailure.busy
        }
        directoryFD = folder; lockFD = lock
    }

    deinit { Darwin.close(lockFD); Darwin.close(directoryFD) }

    private static func safeFile(_ fd: Int32) -> Bool {
        var info = stat()
        return fstat(fd, &info) == 0 && info.st_uid == getuid() && info.st_nlink == 1 &&
            info.st_mode & mode_t(S_IFMT) == mode_t(S_IFREG) && info.st_mode & 0o077 == 0
    }

    func load() throws -> DockVisibilityJournal? {
        let fd = openat(directoryFD, name, O_RDONLY | O_NOFOLLOW | O_CLOEXEC)
        if fd < 0 { if errno == ENOENT { return nil }; throw DockVisibilityFailure.storage }
        defer { Darwin.close(fd) }
        var info = stat()
        guard Self.safeFile(fd), fstat(fd, &info) == 0, info.st_size > 0,
              info.st_size <= DockVisibilityPolicy.maximumJournalBytes else { throw DockVisibilityFailure.journal }
        var data = Data(count: Int(info.st_size))
        let complete = data.withUnsafeMutableBytes { buffer -> Bool in
            var offset = 0
            while offset < buffer.count {
                let count = Darwin.read(fd, buffer.baseAddress!.advanced(by: offset), buffer.count - offset)
                if count < 0 { if errno == EINTR { continue }; return false }
                if count == 0 { return false }; offset += count
            }
            return true
        }
        guard complete else { throw DockVisibilityFailure.storage }
        let value = try DockVisibilityPolicy.decode(data)
        guard value.owner.uid == getuid() else { throw DockVisibilityFailure.journal }
        return value
    }

    func save(_ journal: DockVisibilityJournal) throws {
        let data = try DockVisibilityPolicy.encode(journal)
        let temporary = ".lease-\(UUID().uuidString).tmp"
        let fd = openat(directoryFD, temporary, O_WRONLY | O_CREAT | O_EXCL | O_NOFOLLOW | O_CLOEXEC, 0o600)
        guard fd >= 0 else { throw DockVisibilityFailure.storage }
        defer { Darwin.close(fd); unlinkat(directoryFD, temporary, 0) }
        let complete = data.withUnsafeBytes { buffer -> Bool in
            var offset = 0
            while offset < buffer.count {
                let count = Darwin.write(fd, buffer.baseAddress!.advanced(by: offset), buffer.count - offset)
                if count < 0 { if errno == EINTR { continue }; return false }
                if count == 0 { return false }; offset += count
            }
            return true
        }
        guard complete, fsync(fd) == 0, renameat(directoryFD, temporary, directoryFD, name) == 0,
              fsync(directoryFD) == 0 else { throw DockVisibilityFailure.storage }
    }

    func clear() throws {
        if unlinkat(directoryFD, name, 0) != 0, errno != ENOENT { throw DockVisibilityFailure.storage }
        guard fsync(directoryFD) == 0 else { throw DockVisibilityFailure.storage }
    }
}
