import AppKit
import Combine

/// One temporary overlay. Ending a mode reads the latest real preferences;
/// there is no stale snapshot to write back over edits made during the session.
@MainActor
final class WorkspaceModeManager: ObservableObject {
    static let shared = WorkspaceModeManager()
    @Published private(set) var session: WorkspaceModeSession?
    private var expirationTask: Task<Void, Never>?
    private var observations = Set<AnyCancellable>()
    var active: WorkspaceMode? { session?.mode }
    private init() {
        NSWorkspace.shared.notificationCenter.publisher(for: NSWorkspace.didWakeNotification)
            .receive(on: RunLoop.main).sink { [weak self] _ in self?.scheduleExpiry() }.store(in: &observations)
        NotificationCenter.default.publisher(for: .NSSystemClockDidChange)
            .receive(on: RunLoop.main).sink { [weak self] _ in self?.scheduleExpiry() }.store(in: &observations)
    }
    func activate(_ mode: WorkspaceMode, duration: WorkspaceModeDuration = .untilQuit) {
        expirationTask?.cancel()
        let value = WorkspaceModeSession(mode: mode, duration: duration)
        session = value
        if mode.hidesPrivateContent {
            // Privacy must not depend on a visible SwiftUI window receiving onChange.
            WebcamManager.shared.stopSession()
            NotchToolsWindowController.shared.close()
            WorkspaceToolsWindowController.shared.close()
            CommandPaletteController.shared.close()
            PinnedScratchpadController.shared.close()
            CaptureStudioController.shared.close()
            WindowToolsController.shared.close()
            MediaToolsManager.shared.privacyStop()
            NotchscapeCoordinator.shared.currentView = .home
            NotchscapeCoordinator.shared.sneakPeek.show = false
            NotchscapeCoordinator.shared.expandingView.show = false
        }
        scheduleExpiry()
    }
    /// Timed modes follow the displayed wall-clock end, including sleep and clock changes.
    private func scheduleExpiry() {
        expirationTask?.cancel(); expirationTask = nil
        guard let value = session, let expiry = value.expiresAt else { return }
        let seconds = expiry.timeIntervalSinceNow
        guard seconds > 0 else { end(); return }
        expirationTask = Task { [weak self] in
            do { try await Task.sleep(for: .seconds(seconds)) } catch { return }
            guard !Task.isCancelled, let self, self.session?.id == value.id else { return }
            self.scheduleExpiry()
        }
    }
    func end() { expirationTask?.cancel(); expirationTask = nil; session = nil }
}
