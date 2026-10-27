import AppKit
import Combine
import Defaults
import EventKit

/// In-session event selection only. Never creates events or asks for permission.
@MainActor
final class PinnedEventManager: ObservableObject {
    static let shared = PinnedEventManager()
    @Published private(set) var event: EventModel?
    private var observation: AnyCancellable?
    private init() {
        observation = CalendarManager.shared.$events.receive(on: RunLoop.main).sink { [weak self] events in
            guard let self, let selected = event else { return }
            // Pinning follows the loaded day, including deletions and calendar
            // selection changes. Never keep a stale deleted event in a countdown.
            event = events.first(where: { $0.id == selected.id && $0.end > Date() })
        }
    }
    func pin(_ value: EventModel) {
        guard WorkspaceAccess.privateToolsAllowed, Defaults[.showCalendar], EKEventStore.authorizationStatus(for: .event) == .fullAccess,
              value.type.isEvent, value.end > Date(), CalendarManager.shared.events.contains(value) else { return }
        event = value
    }
    func clear() { event = nil }
    var visibleEvent: EventModel? {
        guard WorkspaceAccess.privateToolsAllowed, Defaults[.showCalendar], EKEventStore.authorizationStatus(for: .event) == .fullAccess,
              let event, event.end > Date() else { return nil }
        return event
    }
}
