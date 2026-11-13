import Combine
import Foundation

struct MeetingFollowUp: Codable, Identifiable {
    let id: UUID
    let revision: UUID
    let title: String
    let createdAt: Date
    var drafts: [AITaskDraft] = []
    var error: String?
}

@MainActor
final class MeetingFollowUpStore: ObservableObject {
    private struct Snapshot: Codable {
        var enabled = false
        var batches: [UUID: MeetingFollowUp] = [:]
    }

    @Published private var snapshot = Snapshot()
    @Published private(set) var storageError: String?
    private let file: URL
    private let clock: () -> Date
    private var loadFailed = false
    private var workers: [UUID: _Concurrency.Task<Void, Never>] = [:]

    init(directory: URL, clock: @escaping () -> Date = Date.init) {
        file = directory.appendingPathComponent("meeting-follow-ups.json")
        self.clock = clock
        guard FileManager.default.fileExists(atPath: file.path) else { return }
        do { snapshot = try JSONDecoder().decode(Snapshot.self, from: Data(contentsOf: file)) }
        catch { loadFailed = true; storageError = error.localizedDescription }
    }

    var enabled: Bool { snapshot.enabled }
    var pending: [MeetingFollowUp] {
        snapshot.batches.values.filter { !$0.drafts.isEmpty || $0.error != nil }.sorted { $0.createdAt > $1.createdAt }
    }

    func hasProcessed(_ meeting: MeetingRecord) -> Bool {
        snapshot.batches[meeting.id]?.revision == meeting.evidenceRevision
    }

    func setEnabled(_ enabled: Bool) throws {
        var next = snapshot
        next.enabled = enabled
        try save(next)
        if !enabled { stop() }
    }

    func generate(for meeting: MeetingRecord, request: AITaskRequest, retry: Bool = false,
                  isCurrent: @escaping () -> Bool, using generate: @escaping (AITaskRequest) async throws -> String) {
        let id = meeting.id, revision = meeting.evidenceRevision
        guard enabled, !loadFailed, workers[id] == nil,
              snapshot.batches[id]?.revision != revision || (retry && snapshot.batches[id]?.error != nil) else { return }
        workers[id] = _Concurrency.Task { [weak self] in
            guard let self else { return }
            defer { self.workers[id] = nil }
            var batch = MeetingFollowUp(id: id, revision: revision, title: meeting.title, createdAt: self.clock())
            do {
                let result = try await generate(request)
                try _Concurrency.Task.checkCancellation()
                batch.drafts = try AITaskDraft.decode(result, request: request).map { value in
                    var draft = value
                    draft.sourceLineID = meeting.transcript.first { line in
                        !draft.quote.isEmpty && (line.speaker + "：" + line.text).contains(draft.quote)
                    }?.id
                    return draft
                }
            } catch is CancellationError { return }
            catch { batch.error = error.localizedDescription }
            guard !_Concurrency.Task.isCancelled, self.enabled, isCurrent() else { return }
            var next = self.snapshot
            next.batches[id] = batch
            do { try self.save(next) }
            catch { self.storageError = error.localizedDescription }
        }
    }

    func dismiss(_ batch: MeetingFollowUp) throws {
        guard var current = snapshot.batches[batch.id], current.revision == batch.revision else { return }
        var next = snapshot
        current.drafts = []
        current.error = nil
        next.batches[batch.id] = current
        try save(next)
    }

    func stop() { for worker in workers.values { worker.cancel() } }

    private func save(_ next: Snapshot) throws {
        guard !loadFailed else { throw AIBackendError.failed(storageError ?? "会后跟进资料读取失败。") }
        try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        try JSONEncoder().encode(next).write(to: file, options: .atomic)
        snapshot = next
        storageError = nil
    }
}
