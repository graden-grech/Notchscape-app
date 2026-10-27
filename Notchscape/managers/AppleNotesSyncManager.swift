import AppKit
import Carbon
#if !APPLE_NOTES_SCRIPT_TEST
import Combine
import Defaults
#endif

struct RemoteAppleNote: Sendable {
    var id: String
    var text: String
    var html: String
    var writable: Bool
}

enum AppleNotesError: Error, LocalizedError {
    case permission, unavailable, changed, unsupported, failed, localStorage
    var errorDescription: String? {
        switch self {
        case .permission: "Allow Notchscape to control Notes in System Settings → Privacy & Security → Automation, then try again."
        case .unavailable: "The connected Notes account or app folder is unavailable. Nothing was replaced."
        case .changed: "This note changed in Apple Notes during sync. Both versions are safe; sync again to reconcile them."
        case .unsupported: "This note contains formatting, attachments, or protected content. Edit it in Apple Notes; its original has not been replaced."
        case .failed: "Apple Notes didn’t finish this request. Your local notes are safe. Try again with Notes open."
        case .localStorage: "Apple Notes was contacted, but the local copy couldn’t be saved. Keep Notchscape open and check the local storage warning."
        }
    }
}

/// All scripts execute on one utility queue, never the main/UI thread. Inputs
/// are escaped text literals, not shell commands or executable user content.
final class AppleNotesBridge: @unchecked Sendable {
    #if APPLE_NOTES_SCRIPT_TEST
    private let queue = DispatchQueue(label: "notch.apple-notes-test", qos: .utility)
    #else
    private let queue = AppleScriptHelper.executionQueue
    #endif
    private static let prefix = """
    with timeout of 10 seconds
    tell application id "com.apple.Notes"
    """ + "\n"
    private static let suffix = "\nend tell\nend timeout"

    private static func target(_ scope: AppleNotesScope) -> String {
        """
        set selectedAccounts to every account whose id is \(AppleNotesPolicy.scriptLiteral(scope.accountID))
        if (count selectedAccounts) is not 1 then error "scope unavailable" number -1728
        set targetAccount to item 1 of selectedAccounts
        set selectedFolders to every folder of targetAccount whose id is \(AppleNotesPolicy.scriptLiteral(scope.folderID))
        if (count selectedFolders) is not 1 then error "scope unavailable" number -1728
        set targetFolder to item 1 of selectedFolders
        if shared of targetFolder then error "unsupported" number -1700
        """
    }

    private func execute<T: Sendable>(_ source: String, prompt: Bool,
                                     decode: @escaping @Sendable (NSAppleEventDescriptor) throws -> T) async throws -> T {
        try await withCheckedThrowingContinuation { continuation in
            queue.async {
                autoreleasepool {
                    do {
                        if !prompt {
                            let target = NSAppleEventDescriptor(bundleIdentifier: "com.apple.Notes")
                            guard AEDeterminePermissionToAutomateTarget(target.aeDesc, typeWildCard, typeWildCard, false) == noErr else {
                                throw AppleNotesError.permission
                            }
                        }
                        guard let script = NSAppleScript(source: Self.prefix + source + Self.suffix) else { throw AppleNotesError.failed }
                        var error: NSDictionary?
                        #if APPLE_NOTES_SCRIPT_TEST
                        _ = script.compileAndReturnError(&error)
                        let output = NSAppleEventDescriptor.list()
                        #else
                        let output = script.executeAndReturnError(&error)
                        #endif
                        if let error {
                            // Never log raw script/error text: it can contain note content.
                            let code = (error[NSAppleScript.errorNumber] as? NSNumber)?.intValue
                            switch code {
                            case -1743: throw AppleNotesError.permission
                            case -1728: throw AppleNotesError.unavailable
                            case -1700: throw AppleNotesError.unsupported
                            case -10001: throw AppleNotesError.changed
                            default: throw AppleNotesError.failed
                            }
                        }
                        #if APPLE_NOTES_SCRIPT_TEST
                        throw AppleNotesScriptCompiled()
                        #else
                        continuation.resume(returning: try decode(output))
                        #endif
                    } catch { continuation.resume(throwing: error) }
                }
            }
        }
    }

    func connect() async throws -> AppleNotesScope {
        try await execute("""
        set targetAccount to default account
        set selectedFolders to every folder of targetAccount whose name is "Notchscape"
        if (count selectedFolders) > 1 then error "ambiguous folder" number -1728
        if (count selectedFolders) is 0 then
            set legacyFolders to every folder of targetAccount whose name is "Boring Notch"
            if (count legacyFolders) > 1 then error "ambiguous folder" number -1728
            if (count legacyFolders) is 1 then
                set targetFolder to item 1 of legacyFolders
                if shared of targetFolder then error "unsupported" number -1700
                set name of targetFolder to "Notchscape"
            else
                set targetFolder to make new folder at targetAccount with properties {name:"Notchscape"}
            end if
        else
            set targetFolder to item 1 of selectedFolders
        end if
        if shared of targetFolder then error "unsupported" number -1700
        return {id of targetAccount, id of targetFolder, name of targetAccount}
        """, prompt: true) { result in
            guard result.numberOfItems == 3,
                  let account = result.atIndex(1)?.stringValue, let folder = result.atIndex(2)?.stringValue,
                  let name = result.atIndex(3)?.stringValue else { throw AppleNotesError.failed }
            return AppleNotesScope(accountID: account, folderID: folder, accountName: name)
        }
    }

    func read(_ scope: AppleNotesScope, prompt: Bool) async throws -> [RemoteAppleNote] {
        try await execute(Self.target(scope) + """

        set resultRows to {}
        set folderNotes to every note of targetFolder
        if (count folderNotes) > 200 then error "folder limit" number -1700
        repeat with targetNote in folderNotes
            if (password protected of targetNote) or (shared of targetNote) then
                set end of resultRows to {id of targetNote, "", "", false}
            else if (count attachments of targetNote) > 0 then
                set end of resultRows to {id of targetNote, "", "", false}
            else
                set noteText to plaintext of targetNote
                set noteBody to body of targetNote
                if (length of noteText) > 200000 or (length of noteBody) > 1000000 then
                    set end of resultRows to {id of targetNote, "", "", false}
                else
                    set end of resultRows to {id of targetNote, noteText, noteBody, true}
                end if
            end if
        end repeat
        return resultRows
        """, prompt: prompt) { result in
            guard result.numberOfItems <= 200 else { throw AppleNotesError.failed }
            return try (1...max(1, result.numberOfItems)).compactMap { index in
                guard index <= result.numberOfItems else { return nil }
                guard let row = result.atIndex(index), row.numberOfItems == 4,
                      let id = row.atIndex(1)?.stringValue,
                      let text = row.atIndex(2)?.stringValue, let html = row.atIndex(3)?.stringValue else { throw AppleNotesError.failed }
                return RemoteAppleNote(id: id, text: AppleNotesPolicy.normalized(text), html: html,
                    writable: row.atIndex(4)?.booleanValue == true && AppleNotesPolicy.supported(text: text, html: html))
            }
        }
    }

    func create(_ text: String, in scope: AppleNotesScope, prompt: Bool) async throws -> String {
        try await execute(Self.target(scope) + """

        set createdNote to make new note at targetFolder with properties {body:\(AppleNotesPolicy.scriptLiteral(AppleNotesPolicy.html(text)))}
        return id of createdNote
        """, prompt: prompt) { result in
            guard let id = result.stringValue, !id.isEmpty else { throw AppleNotesError.failed }; return id
        }
    }

    func update(_ remote: RemoteAppleNote, text: String, in scope: AppleNotesScope, prompt: Bool) async throws {
        let _: Bool = try await execute(Self.target(scope) + """

        set selectedNotes to every note of targetFolder whose id is \(AppleNotesPolicy.scriptLiteral(remote.id))
        if (count selectedNotes) is not 1 then error "note moved or deleted" number -1728
        set targetNote to item 1 of selectedNotes
        if (password protected of targetNote) or (shared of targetNote) or ((count attachments of targetNote) > 0) then error "unsupported" number -1700
        if body of targetNote is not \(AppleNotesPolicy.scriptLiteral(remote.html)) then error "changed" number -10001
        set body of targetNote to \(AppleNotesPolicy.scriptLiteral(AppleNotesPolicy.html(text)))
        return true
        """, prompt: prompt) { $0.booleanValue }
    }
}

#if APPLE_NOTES_SCRIPT_TEST
struct AppleNotesScriptCompiled: Error {}
#else
@MainActor
final class AppleNotesSyncManager: ObservableObject {
    static let shared = AppleNotesSyncManager()
    @Published private(set) var busy = false
    @Published private(set) var message: String?
    @Published private(set) var lastSync: Date?
    private let bridge = AppleNotesBridge()
    private var observations = Set<AnyCancellable>()
    private var timer: Timer?
    private var editTask: Task<Void, Never>?
    private var locked = false
    private var started = false
    private var applying = false
    private var pending = false
    private var generation = 0
    private var tools: LocalToolsManager { .shared }

    func start() {
        guard !started else { return }; started = true
        Defaults.publisher(.appleNotesSyncEnabled).receive(on: RunLoop.main).sink { [weak self] _ in self?.configure() }.store(in: &observations)
        Defaults.publisher(.quickNotesEnabled).dropFirst().receive(on: RunLoop.main).sink { [weak self] _ in self?.configure() }.store(in: &observations)
        tools.$notes.dropFirst().receive(on: RunLoop.main).sink { [weak self] _ in
            guard let self, !applying, Defaults[.appleNotesSyncEnabled] else { return }
            editTask?.cancel()
            editTask = Task { @MainActor [weak self] in
                do { try await Task.sleep(for: .seconds(2)) } catch { return }
                await self?.sync(manual: false)
            }
        }.store(in: &observations)
    }
    func setLocked(_ value: Bool) { locked = value; configure() }
    private func configure() {
        generation += 1; editTask?.cancel(); timer?.invalidate(); timer = nil
        guard Defaults[.appleNotesSyncEnabled], Defaults[.quickNotesEnabled], !locked else { return }
        timer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in
            Task { @MainActor in await self?.sync(manual: false) }
        }
        timer?.tolerance = 15
        Task { await sync(manual: false) }
    }
    func connect() async {
        guard !busy, !locked, Defaults[.quickNotesEnabled] else { return }
        busy = true; message = nil
        let run = generation
        await tools.load()
        guard tools.loaded, run == generation, !locked else { busy = false; return }
        do {
            let scope = try await bridge.connect()
            guard run == generation, !locked else { busy = false; return }
            tools.setAppleNotesScope(scope)
            message = "Connected to \(scope.accountName) → Notchscape."
        } catch { message = error.localizedDescription }
        busy = false
    }
    func save(_ id: UUID) async { await sync(manual: true, only: id) }
    func sync(manual: Bool = true, only: UUID? = nil) async {
        guard !locked, Defaults[.quickNotesEnabled] else { return }
        guard !busy else { pending = true; return }
        guard manual || Defaults[.appleNotesSyncEnabled] else { return }
        // Background sync doesn't launch Notes or request fresh access.
        guard manual || !NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.Notes").isEmpty else {
            message = "Automatic sync resumes when Apple Notes is open."; return
        }
        busy = true; message = nil
        let run = generation
        var skipped = 0, conflicts = 0, missing = 0
        func valid() -> Bool { !locked && run == generation && Defaults[.quickNotesEnabled] }
        defer {
            busy = false
            if pending { pending = false; editTask = Task { await sync(manual: false) } }
        }
        await tools.load()
        guard valid(), tools.loaded else { return }
        do {
            if tools.appleNotesState.scope == nil {
                guard manual else { message = "Connect Apple Notes in Settings → Tools first."; return }
                let scope = try await bridge.connect()
                guard valid() else { return }
                tools.setAppleNotesScope(scope)
            }
            guard let scope = tools.appleNotesState.scope else { return }
            var remote = try await bridge.read(scope, prompt: manual)
            guard valid() else { return }
            applying = true
            defer { applying = false }
            let ids = only.map { [$0] } ?? tools.notes.map(\.id)
            for id in ids {
                guard valid(), let note = tools.notes.first(where: { $0.id == id }) else { continue }
                // A conflict copy is for review, not an automatic second upload.
                if note.isConflictCopy == true && only != id { continue }
                if let link = note.appleNote {
                    guard let other = remote.first(where: { $0.id == link.remoteID }) else { missing += 1; continue }
                    guard other.writable else { skipped += 1; continue }
                    switch AppleNotesPolicy.resolve(local: note.text, remote: other.text, base: link.baseText) {
                    case .unchanged:
                        if link.baseText != other.text { tools.updateAppleNote(id, remoteID: other.id, baseText: other.text) }
                    case .pull:
                        tools.updateAppleNote(id, remoteID: other.id, baseText: other.text, text: other.text)
                    case .push:
                        try await bridge.update(other, text: note.text, in: scope, prompt: manual)
                        guard valid() else { return }
                        tools.updateAppleNote(id, remoteID: other.id, baseText: AppleNotesPolicy.normalized(note.text))
                    case .conflict:
                        if tools.keepAppleNotesConflict(id, remoteID: other.id, remoteText: other.text) { conflicts += 1 }
                        else { skipped += 1 }
                    }
                } else {
                    guard !note.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, !note.text.contains("\0") else { continue }
                    // Recover an uncertain create without blindly making a duplicate.
                    let linked = Set(tools.notes.compactMap { $0.appleNote?.remoteID }).union(tools.appleNotesState.ignoredRemoteIDs)
                    let matches = remote.filter { $0.writable && !linked.contains($0.id) && $0.text == AppleNotesPolicy.normalized(note.text) }
                    let remoteID: String
                    if matches.count == 1 { remoteID = matches[0].id }
                    else { remoteID = try await bridge.create(note.text, in: scope, prompt: manual) }
                    guard valid() else { return }
                    if tools.notes.contains(where: { $0.id == id }) {
                        tools.updateAppleNote(id, remoteID: remoteID, baseText: AppleNotesPolicy.normalized(note.text))
                        remote.removeAll { $0.id == remoteID }
                    } else { tools.ignoreAppleNote(remoteID) }
                }
            }
            if only == nil {
                for note in remote where !tools.notes.contains(where: { $0.appleNote?.remoteID == note.id }) {
                    guard note.writable else { skipped += 1; continue }
                    if tools.appleNotesState.ignoredRemoteIDs.contains(note.id) { continue }
                    if !tools.importAppleNote(remoteID: note.id, text: note.text) { skipped += 1 }
                }
            }
            await tools.flush()
            guard valid() else { return }
            guard !tools.needsSave else { throw AppleNotesError.localStorage }
            lastSync = Date()
            var details = ["Synced with Apple Notes."]
            if conflicts > 0 { details.append("\(conflicts) conflict copies kept locally; review both versions.") }
            if missing > 0 { details.append("\(missing) linked notes were moved or deleted in Notes; local copies kept.") }
            if skipped > 0 { details.append("\(skipped) notes skipped (rich content, protection, or storage limits).") }
            message = details.joined(separator: " ")
        } catch { if valid() { message = error.localizedDescription } }
    }
}
#endif
