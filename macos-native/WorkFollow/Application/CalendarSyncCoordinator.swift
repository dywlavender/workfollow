import Foundation
import EventKit
import Combine

/// System calendars are read-only during normal use. The only writes here are
/// an explicit, recoverable cleanup of task copies created by older versions.
@MainActor
final class CalendarSyncCoordinator: ObservableObject, ModuleStoreFlushable {
    let store: CalendarIntegrationStore
    @Published private(set) var calendars: [SystemCalendarInfo] = []
    @Published private(set) var authorization: EKAuthorizationStatus = .notDetermined
    @Published private(set) var message: String?
    @Published private(set) var connecting = false
    @Published private(set) var cleaningUp = false
    @Published private(set) var cleanupResult: String?
    @Published private(set) var externalEvents: [SystemCalendarEvent] = []
    private let client: SystemCalendarClient
    private var displayRange: DateInterval?
    private var subscription: AnyCancellable?

    init(directory: URL = JSONFileStore<CalendarIntegrationSnapshot>.moduleDirectory,
         client: SystemCalendarClient? = nil) {
        store = CalendarIntegrationStore(directory: directory)
        self.client = client ?? SystemCalendarService()
        authorization = self.client.authorization
        self.client.onChange = { [weak self] in self?.refreshAccess() }
        store.onSettingsChange = { [weak self] in self?.reloadDisplayedEvents() }
        subscription = store.objectWillChange.sink { [weak self] in self?.objectWillChange.send() }
    }
    var legacyCopyCount: Int { store.snapshot.bindings.filter { !$0.detached }.count }
    var removedCopyCount: Int { store.snapshot.removedTaskCopies?.count ?? 0 }

    func refreshAccess() {
        authorization = client.authorization
        calendars = client.calendars()
        reloadDisplayedEvents()
    }
    func connect() async {
        guard !connecting else { return }
        connecting = true
        defer { connecting = false }
        do {
            let granted: Bool
            if client.authorization == .fullAccess { granted = true }
            else { granted = try await client.requestAccess() }
            refreshAccess()
            message = granted ? nil : "请在系统设置的日历权限中允许访问。"
            if granted { store.configure { $0.enabled = true } }
        } catch { message = error.localizedDescription }
    }
    func showEvents(in range: DateInterval) {
        displayRange = range
        refreshAccess()
    }
    private func reloadDisplayedEvents() {
        guard store.snapshot.enabled, authorization == .fullAccess, let range = displayRange else {
            externalEvents = []; return
        }
        externalEvents = client.events(in: range, calendarIDs: calendars.map(\.id)).filter { value in
            !store.snapshot.bindings.contains { !$0.detached && ($0.eventID == value.id || $0.reference.url == value.sourceURL) }
        }.sorted { $0.fields.start < $1.fields.start }
    }
    private func existingCopy(_ binding: CalendarTaskBinding) -> SystemCalendarEvent? {
        client.event(id: binding.eventID) ?? client.events(in: lookupRange(binding.lastSynced), calendarIDs: [binding.calendarID])
            .first { $0.sourceURL == binding.reference.url }
    }
    private func lookupRange(_ fields: CalendarEventFields) -> DateInterval {
        DateInterval(start: fields.start.addingTimeInterval(-86400), end: fields.end.addingTimeInterval(86400))
    }
    private func persist() async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            store.flush { error in
                if let error { continuation.resume(throwing: error) }
                else { continuation.resume() }
            }
        }
    }

    func cleanupLegacyCopies() async {
        guard !cleaningUp else { return }
        refreshAccess()
        guard authorization == .fullAccess else { message = "请先允许日历访问，再清理旧版任务副本。"; return }
        cleaningUp = true
        defer { cleaningUp = false; reloadDisplayedEvents() }
        var bindings = store.snapshot.bindings
        var candidates: [(CalendarTaskBinding, SystemCalendarEvent)] = []
        var retained = 0
        for binding in bindings where !binding.detached {
            guard let event = existingCopy(binding) else {
                bindings.removeAll { $0.id == binding.id }; continue
            }
            guard event.sourceURL == binding.reference.url, event.calendarID == binding.calendarID,
                  event.fields == binding.lastSynced, event.location.isEmpty, !event.hasAdditionalDetails else {
                if let index = bindings.firstIndex(where: { $0.id == binding.id }) { bindings[index].detached = true }
                retained += 1; continue
            }
            candidates.append((binding, event))
        }
        // Save the complete restorable copy before removing anything in EventKit.
        store.configure { state in
            var copies = state.removedTaskCopies ?? []
            for (_, event) in candidates where !copies.contains(where: { $0.id == event.id }) { copies.append(event) }
            state.removedTaskCopies = copies
        }
        do {
            try await persist()
            var errors: [String] = []
            var removed = 0
            for (binding, event) in candidates {
                do {
                    try client.removeLegacyCopy(id: event.id)
                    bindings.removeAll { $0.id == binding.id }; removed += 1
                } catch { errors.append(error.localizedDescription) }
            }
            store.configure { $0.bindings = bindings }
            try await persist()
            message = errors.first
            cleanupResult = "已清理 \(removed) 条旧任务日历副本。" + (retained > 0 ? "保留了 \(retained) 条已单独修改的日程。" : "")
        } catch { message = error.localizedDescription }
    }

    func undoLegacyCleanup() async {
        guard !cleaningUp else { return }
        refreshAccess()
        guard authorization == .fullAccess else { message = "请先允许日历访问，再撤销清理。"; return }
        cleaningUp = true
        defer { cleaningUp = false; reloadDisplayedEvents() }
        var remaining = store.snapshot.removedTaskCopies ?? []
        var bindings = store.snapshot.bindings
        var errors: [String] = []
        for original in remaining {
            do {
                let existing = client.event(id: original.id) ?? client.events(in: lookupRange(original.fields), calendarIDs: [original.calendarID])
                    .first { $0.sourceURL == original.sourceURL }
                if existing == nil { _ = try client.restoreLegacyCopy(original) }
                remaining.removeAll { $0.id == original.id }
                for index in bindings.indices where bindings[index].reference.url == original.sourceURL {
                    bindings[index].detached = true
                }
            } catch { errors.append(error.localizedDescription) }
        }
        store.configure { $0.removedTaskCopies = remaining; $0.bindings = bindings }
        do { try await persist(); message = errors.first }
        catch { message = error.localizedDescription }
        cleanupResult = remaining.isEmpty ? "已撤销清理，日程已恢复，不再与任务双向同步。" : "部分日程尚未恢复，可重试。"
    }

    func flush(_ completion: @escaping (Error?) -> Void) { store.flush(completion) }
}
