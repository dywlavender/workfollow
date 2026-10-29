import Combine
import Foundation

struct AIConversationMessage: Identifiable, Codable, Equatable {
    enum Role: String, Codable { case user, assistant }
    enum State: String, Codable { case complete, generating, stopped, failed }
    var id = UUID()
    var role: Role
    var text: String
    var state: State = .complete
    var error: String?
}

struct AIConversationRecord: Identifiable, Codable, Equatable {
    var id = UUID()
    var messages: [AIConversationMessage] = []
    var updatedAt = Date()
    var title: String { String(messages.first(where: { $0.role == .user })?.text.prefix(28) ?? "新对话") }
}

@MainActor
final class AIConversationModel: ObservableObject {
    enum Scene: String { case chat, selection, note }
    typealias Generate = (UUID, Scene, String, String, @escaping @Sendable (AITextUpdate) -> Void) async throws -> String
    @Published private(set) var record: AIConversationRecord
    @Published var input = ""
    @Published private(set) var status = "正在回复…"
    @Published private(set) var isRunning = false
    let scene: Scene
    let context: String
    var onChange: ((AIConversationRecord) -> Void)?
    private var worker: _Concurrency.Task<Void, Never>?
    private var generation = UUID()

    init(record: AIConversationRecord = .init(), scene: Scene = .chat, context: String = "") {
        var restored = record
        for i in restored.messages.indices where restored.messages[i].state == .generating {
            restored.messages[i].state = .stopped
        }
        self.record = restored; self.scene = scene; self.context = context
    }

    var canSend: Bool { !isRunning && !input.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
    var latestResult: String? {
        guard let last = record.messages.last, last.role == .assistant, last.state == .complete else { return nil }
        return last.text
    }

    func send(using generate: @escaping Generate) {
        guard canSend else { return }
        let message = input.trimmingCharacters(in: .whitespacesAndNewlines)
        input = ""
        record.messages.append(.init(role: .user, text: message))
        let answer = AIConversationMessage(role: .assistant, text: "", state: .generating)
        record.messages.append(answer)
        let token = UUID(); generation = token
        isRunning = true; status = "正在回复…"; changed()
        let id = record.id, scene = scene, context = context
        worker = _Concurrency.Task { [weak self] in
            do {
                let text = try await generate(id, scene, context, message) { [weak self] update in
                    _Concurrency.Task { @MainActor in
                        guard let self, self.generation == token, self.isRunning else { return }
                        if update.kind == "text" { self.update(answer.id) { $0.text = update.text ?? "" } }
                        if update.kind == "status" { self.status = update.message ?? "正在回复…" }
                    }
                }
                try _Concurrency.Task.checkCancellation()
                guard let self, self.generation == token else { return }
                guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { throw SummaryPiError.emptyResult }
                self.update(answer.id) { $0.text = text; $0.state = .complete }
                self.isRunning = false; self.worker = nil; self.generation = UUID()
            } catch {
                guard let self, self.generation == token else { return }
                self.update(answer.id) {
                    $0.state = error is CancellationError ? .stopped : .failed
                    $0.error = error is CancellationError ? nil : error.localizedDescription
                }
                self.isRunning = false; self.worker = nil; self.generation = UUID()
            }
        }
    }

    func stop() {
        guard isRunning else { return }
        generation = UUID(); worker?.cancel(); worker = nil; isRunning = false
        if let id = record.messages.last?.id { update(id) { $0.state = .stopped } }
    }

    private func update(_ id: UUID, _ action: (inout AIConversationMessage) -> Void) {
        guard let i = record.messages.firstIndex(where: { $0.id == id }) else { return }
        action(&record.messages[i]); changed()
    }
    private func changed() { record.updatedAt = Date(); onChange?(record) }
}

@MainActor
final class AIChatStore: ObservableObject, ModuleStoreFlushable {
    private struct Snapshot: Codable { var selectedID: UUID; var records: [AIConversationRecord] }
    @Published private(set) var current: AIConversationModel
    @Published private(set) var records: [AIConversationRecord]
    @Published private(set) var storageError: String?
    let sessionDirectory: URL
    private let persistence: JSONFileStore<Snapshot>

    init(directory: URL) {
        sessionDirectory = directory.appendingPathComponent("ai-conversations", isDirectory: true)
        persistence = JSONFileStore(filename: "ai-chat.json", directory: directory)
        let saved = persistence.load()
        records = saved?.records ?? []
        current = AIConversationModel(record: saved?.records.first(where: { $0.id == saved?.selectedID }) ?? .init())
        connect()
    }
    func newConversation() {
        current.stop()
        guard !current.record.messages.isEmpty else { current.input = ""; return }
        current = AIConversationModel(); connect(); save()
    }
    func select(_ id: UUID) {
        guard id != current.record.id, let record = records.first(where: { $0.id == id }) else { return }
        current.stop(); current = AIConversationModel(record: record); connect(); save()
    }
    private func connect() {
        current.onChange = { [weak self] value in
            guard let self else { return }
            if let i = self.records.firstIndex(where: { $0.id == value.id }) { self.records[i] = value }
            else { self.records.append(value) }
            self.save()
        }
    }
    private func save() { persistence.schedule(Snapshot(selectedID: current.record.id, records: records)) }
    func flush(_ completion: @escaping (Error?) -> Void) {
        persistence.flush { [weak self] error in
            _Concurrency.Task { @MainActor in self?.storageError = error?.localizedDescription }
            completion(error)
        }
    }
}
