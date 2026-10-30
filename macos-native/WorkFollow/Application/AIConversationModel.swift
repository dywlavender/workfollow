import Combine
import Foundation

@MainActor
protocol AIConversationComposing: ObservableObject {
    var input: String { get set }
    var attachments: AIAttachmentDraft { get }
    var isRunning: Bool { get }
    var canSend: Bool { get }
    func stop()
}

struct AIConversationReference: Identifiable, Codable, Equatable {
    var id: UUID
    var kind: String
    var title: String
}

struct AIActionReceipt: Identifiable, Codable, Equatable {
    var id = UUID()
    var title: String
    var url: String?
    var details: String
    var undoID: UUID?
    var undone = false
}

struct AIConversationMessage: Identifiable, Codable, Equatable {
    enum Role: String, Codable { case user, assistant }
    enum State: String, Codable { case complete, generating, stopped, failed }
    var id = UUID()
    var role: Role
    var text: String
    var state: State = .complete
    var error: String?
    var actions: [AIActionReceipt]? = nil
    var attachments: [AIConversationAttachment]? = nil
    var preset: AIConversationPreset? = nil
    var source: AIConversationSource? = nil
    var artifacts: [AIConversationArtifact]? = nil
}

struct AIConversationRecord: Identifiable, Codable, Equatable {
    var id = UUID()
    var messages: [AIConversationMessage] = []
    var updatedAt = Date()
    var references: [AIConversationReference]? = nil
    var title: String {
        guard let first = messages.first(where: { $0.role == .user }) else { return "新对话" }
        return String((first.text.isEmpty ? first.attachments?.first?.name ?? "新对话" : first.text).prefix(28))
    }
}

@MainActor
final class AIConversationModel: ObservableObject, AIConversationComposing {
    enum Scene: String { case chat, selection, note }
    typealias Generate = (UUID, Scene, String, String, @escaping @Sendable (AITextUpdate) -> Void) async throws -> String
    @Published private(set) var record: AIConversationRecord
    @Published var input = ""
    @Published private(set) var status = "正在回复…"
    @Published private(set) var isRunning = false
    let scene: Scene
    let context: String
    let attachments: AIAttachmentDraft
    var onChange: ((AIConversationRecord) -> Void)?
    private var worker: _Concurrency.Task<Void, Never>?
    private var generation = UUID()
    private var attachmentObservation: AnyCancellable?

    init(record: AIConversationRecord = .init(), scene: Scene = .chat, context: String = "", directory: URL? = nil) {
        var restored = record
        for i in restored.messages.indices where restored.messages[i].state == .generating {
            restored.messages[i].state = .stopped
        }
        self.record = restored; self.scene = scene; self.context = context
        let root = directory ?? NativePreviewRepository.directory.appendingPathComponent("ai-conversations", isDirectory: true)
        attachments = AIAttachmentDraft(directory: AIConversationAttachmentFiles.directory(root: root, scene: scene.rawValue, id: record.id))
        attachmentObservation = attachments.objectWillChange.sink { [weak self] in self?.objectWillChange.send() }
        if scene != .chat { AIConversationRegistry.shared.register(self) }
    }

    var canSend: Bool { !isRunning && !attachments.isImporting && (!input.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || !attachments.items.isEmpty) }
    var submittedAttachments: [AIConversationAttachment] { record.messages.last(where: { $0.role == .user })?.attachments ?? [] }
    var submittedPreset: AIConversationPreset? { record.messages.last(where: { $0.role == .user })?.preset }
    var submittedSource: AIConversationSource? { record.messages.last(where: { $0.role == .user })?.source }
    var latestResult: String? {
        guard let last = record.messages.last, last.role == .assistant, last.state == .complete else { return nil }
        return last.text
    }
    var latestWritingResult: String? {
        record.messages.reversed().filter { $0.state == .complete }
            .compactMap { $0.artifacts?.last(where: { $0.kind == .writing })?.content }.first
    }

    func setReferences(_ values: [AIConversationReference]) { record.references = values; changed() }
    func appendAction(_ receipt: AIActionReceipt) {
        guard let index = record.messages.lastIndex(where: { $0.role == .assistant }) else { return }
        record.messages[index].actions = (record.messages[index].actions ?? []) + [receipt]; changed()
    }
    func markUndone(_ token: UUID) {
        for i in record.messages.indices {
            guard var actions = record.messages[i].actions else { continue }
            for j in actions.indices where actions[j].undoID == token { actions[j].undone = true }
            record.messages[i].actions = actions
        }
        changed()
    }
    func recordAdoption(artifactID: UUID, result: String) {
        for i in record.messages.indices {
            guard let j = record.messages[i].artifacts?.firstIndex(where: { $0.id == artifactID }) else { continue }
            record.messages[i].artifacts?[j].adoption = result; changed(); return
        }
    }
    func retry(_ messageID: UUID, using generate: @escaping Generate) {
        guard !isRunning, let index = record.messages.firstIndex(where: { $0.id == messageID }),
              let question = record.messages[..<index].last(where: { $0.role == .user }) else { return }
        let actions = record.messages[index].actions ?? []
        submit(message: question.text, files: question.attachments ?? [], preset: question.preset, source: question.source) { id, scene, context, message, updates in
            let completed = actions.filter { !$0.undone }.map { $0.title + "：" + $0.details }.joined(separator: "\n")
            let extra = completed.isEmpty ? "" : "\n本轮以下操作已经保存成功，不要再次创建或执行；核对后完成回复：\n" + completed
            return try await generate(id, scene, context + extra, message, updates)
        }
    }

    func send(source: AIConversationSource? = nil, using generate: @escaping Generate) {
        guard canSend else { return }
        let message = input.trimmingCharacters(in: .whitespacesAndNewlines)
        input = ""
        submit(message: message, files: attachments.take(), source: source ?? (scene == .chat ? nil : submittedSource), using: generate)
    }

    func ask(_ preset: AIConversationPreset, source: AIConversationSource, using generate: @escaping Generate) {
        guard !isRunning, !attachments.isImporting else { return }
        let extra = input.trimmingCharacters(in: .whitespacesAndNewlines)
        input = ""
        submit(message: preset.question + (extra.isEmpty ? "" : "\n" + extra), files: attachments.take(), preset: preset, source: source, using: generate)
    }

    private func submit(message: String, files: [AIConversationAttachment], preset: AIConversationPreset? = nil,
                        source: AIConversationSource? = nil, using generate: @escaping Generate) {
        record.messages.append(.init(role: .user, text: message, attachments: files.isEmpty ? nil : files, preset: preset, source: source))
        let answer = AIConversationMessage(role: .assistant, text: "", state: .generating)
        record.messages.append(answer)
        let token = UUID(); generation = token
        isRunning = true; status = "正在回复…"; changed()
        let id = record.id, scene = scene
        let references = (record.references ?? []).map { "\($0.kind) id=\($0.id) 标题=\($0.title)" }.joined(separator: "\n")
        let applied = record.messages.flatMap { $0.artifacts ?? [] }.compactMap(\.adoption)
        let operations = record.messages.flatMap { $0.actions ?? [] }.map { "\($0.undone ? "已撤销" : "已保存")：\($0.title)；\($0.details)；\($0.url ?? "")" }
        let state = (applied + operations).joined(separator: "\n")
        let context = context + (references.isEmpty ? "" : "\n用户明确引用的 App 资料，请通过 CLI 读取实际内容：\n" + references)
            + (state.isEmpty ? "" : "\n本会话原生操作的实际状态（区分候选与已保存记录）：\n" + state)
        worker = _Concurrency.Task { [weak self] in
            do {
                try _Concurrency.Task.checkCancellation()
                let text = try await generate(id, scene, context, message) { [weak self] update in
                    _Concurrency.Task { @MainActor in
                        guard let self, self.generation == token, self.isRunning else { return }
                        if update.kind == "text" { self.update(answer.id) { $0.text = AIConversationOutput.preview(update.text ?? "") } }
                        if update.kind == "status" { self.status = update.message ?? "正在回复…" }
                    }
                }
                try _Concurrency.Task.checkCancellation()
                guard let self, self.generation == token else { return }
                guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { throw SummaryPiError.emptyResult }
                let output = try AIConversationOutput.decode(text, preset: preset)
                self.update(answer.id) { $0.text = output.text; $0.artifacts = output.artifacts; $0.state = .complete }
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
    @Published private(set) var deletingIDs: Set<UUID> = []
    let sessionDirectory: URL
    private let persistence: JSONFileStore<Snapshot>

    init(directory: URL) {
        sessionDirectory = directory.appendingPathComponent("ai-conversations", isDirectory: true)
        persistence = JSONFileStore(filename: "ai-chat.json", directory: directory)
        let saved = persistence.load()
        records = saved?.records ?? []
        current = AIConversationModel(record: saved?.records.first(where: { $0.id == saved?.selectedID }) ?? .init(), directory: sessionDirectory)
        connect()
    }
    func newConversation() {
        current.stop()
        current.attachments.discard()
        guard !current.record.messages.isEmpty else { current.input = ""; current.setReferences([]); return }
        current = AIConversationModel(directory: sessionDirectory); connect(); save()
    }
    func select(_ id: UUID) {
        guard id != current.record.id, !deletingIDs.contains(id),
              let record = records.first(where: { $0.id == id }) else { return }
        current.stop(); current.attachments.discard()
        current = AIConversationModel(record: record, directory: sessionDirectory); connect(); save()
    }
    func delete(_ id: UUID, using removeSession: (UUID) async throws -> Void) async {
        guard records.contains(where: { $0.id == id }), deletingIDs.insert(id).inserted else { return }
        defer { deletingIDs.remove(id) }
        if current.record.id == id { current.stop(); current.attachments.discard() }
        do { try await removeSession(id) }
        catch { storageError = error.localizedDescription; return }
        records.removeAll { $0.id == id }
        if current.record.id == id {
            current.onChange = nil
            current = AIConversationModel(record: records.max(by: { $0.updatedAt < $1.updatedAt }) ?? .init(), directory: sessionDirectory)
            connect()
        }
        storageError = nil; save()
    }
    func recordAction(_ receipt: AIActionReceipt, conversationID: UUID) {
        if current.record.id == conversationID { current.appendAction(receipt); return }
        guard let index = records.firstIndex(where: { $0.id == conversationID }),
              let message = records[index].messages.lastIndex(where: { $0.role == .assistant }) else { return }
        records[index].messages[message].actions = (records[index].messages[message].actions ?? []) + [receipt]
        save()
    }
    func markUndone(_ token: UUID) {
        current.markUndone(token)
        for i in records.indices where records[i].id != current.record.id {
            for j in records[i].messages.indices {
                guard var actions = records[i].messages[j].actions else { continue }
                for k in actions.indices where actions[k].undoID == token { actions[k].undone = true }
                records[i].messages[j].actions = actions
            }
        }
        save()
    }
    private func connect() {
        current.onChange = { [weak self] value in
            guard let self, self.current.record.id == value.id else { return }
            guard !value.messages.isEmpty else { self.objectWillChange.send(); return }
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
