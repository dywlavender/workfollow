import Combine
import Foundation

@MainActor
protocol AIConversationComposing: ObservableObject {
    var input: String { get set }
    var attachments: AIAttachmentDraft { get }
    var isRunning: Bool { get }
    var canSend: Bool { get }
    /// 生成期间排队的话（steer）：本轮结束后自动作为新消息发出。
    var pendingSteerText: String? { get }
    func stop()
    func queueSteer(_ text: String)
    func cancelSteer()
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
    /// 本条回复结束输出（完成/停止/失败）的时刻。回看历史时据此知道回答时间；
    /// 旧快照没有该键，解码为 nil，界面不显示时间。
    var completedAt: Date? = nil
}

extension AIConversationMessage {
    /// 回复完成时间的展示文本：当天只显「时:分」，当年跨天补「月日」，
    /// 跨年再补年份。没有完成时间（旧快照/仍在生成）返回 nil。
    func completedAtLabel(now: Date = Date(), calendar: Calendar = .current) -> String? {
        guard let completedAt else { return nil }
        let time = String(format: "%02d:%02d",
                          calendar.component(.hour, from: completedAt),
                          calendar.component(.minute, from: completedAt))
        if calendar.isDate(completedAt, inSameDayAs: now) { return time }
        let month = calendar.component(.month, from: completedAt)
        let day = calendar.component(.day, from: completedAt)
        if calendar.component(.year, from: completedAt) == calendar.component(.year, from: now) {
            return "\(month)月\(day)日 \(time)"
        }
        return "\(calendar.component(.year, from: completedAt))年\(month)月\(day)日 \(time)"
    }
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
    @Published private(set) var pendingSteerText: String?
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
    func retry(_ messageID: UUID, using generate: @escaping Generate, guidance: String? = nil) {
        guard !isRunning, let index = record.messages.firstIndex(where: { $0.id == messageID }),
              let question = record.messages[..<index].last(where: { $0.role == .user }) else { return }
        let actions = record.messages[index].actions ?? []
        let trimmedGuidance = guidance.flatMap { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
        let instruction = (trimmedGuidance?.isEmpty == false) ? "\n\n（用户补充指示：\(trimmedGuidance!)）" : ""
        submit(message: question.text + instruction, files: question.attachments ?? [], preset: question.preset, source: question.source) { id, scene, context, message, updates in
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
        launchReply(preset: preset, source: source, using: generate)
    }

    /// 编辑重发：替换指定用户消息的文字、丢弃其后的回复，重新生成。
    /// 只允许对空闲会话操作；被编辑消息的附件与预设原样保留。
    func editAndResend(_ messageID: UUID, text: String, using generate: @escaping Generate) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !isRunning, !trimmed.isEmpty,
              let index = record.messages.firstIndex(where: { $0.id == messageID }),
              record.messages[index].role == .user else { return }
        record.messages[index].text = trimmed
        if record.messages.count > index + 1 { record.messages.removeSubrange((index + 1)...) }
        launchReply(preset: record.messages[index].preset, source: record.messages[index].source, using: generate)
    }

    /// 回复生成的主干：从最后一条用户消息发起一轮回复（submit 与编辑重发共用）。
    private func launchReply(preset: AIConversationPreset?, source: AIConversationSource?, using generate: @escaping Generate) {
        guard let question = record.messages.last(where: { $0.role == .user }) else { return }
        let message = question.text
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
                self.update(answer.id) { $0.text = output.text; $0.artifacts = output.artifacts; $0.state = .complete; $0.completedAt = Date() }
                self.isRunning = false; self.worker = nil; self.generation = UUID()
                self.deliverPendingSteer(using: generate)
            } catch {
                guard let self, self.generation == token else { return }
                self.update(answer.id) {
                    $0.state = error is CancellationError ? .stopped : .failed
                    $0.error = error is CancellationError ? nil : error.localizedDescription
                    $0.completedAt = Date()
                }
                self.isRunning = false; self.worker = nil; self.generation = UUID()
                self.deliverPendingSteer(using: generate)
            }
        }
    }

    /// 生成期间用户仍可输入：排队的话在本轮结束后自动作为新消息发出。
    func queueSteer(_ text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        pendingSteerText = trimmed
    }
    func cancelSteer() { pendingSteerText = nil }
    private func deliverPendingSteer(using generate: @escaping Generate) {
        guard let steer = pendingSteerText else { return }
        pendingSteerText = nil
        submit(message: steer, files: attachments.take(), source: submittedSource, using: generate)
    }

    func stop() {
        guard isRunning else { return }
        generation = UUID(); worker?.cancel(); worker = nil
        // 先落 .stopped 再关 isRunning：后台会话被停止时，未读点据此区分“手动停止”与“完成输出”。
        if let id = record.messages.last?.id { update(id) { $0.state = .stopped; $0.completedAt = Date() } }
        isRunning = false
    }

    private func update(_ id: UUID, _ action: (inout AIConversationMessage) -> Void) {
        guard let i = record.messages.firstIndex(where: { $0.id == id }) else { return }
        action(&record.messages[i]); changed()
    }
    private func changed() { record.updatedAt = Date(); onChange?(record) }
}

@MainActor
final class AIChatStore: ObservableObject, ModuleStoreFlushable {
    private struct Snapshot: Codable {
        var selectedID: UUID
        var records: [AIConversationRecord]
        var projects: ProjectFolders?
        var scheduledFolderID: UUID?
        /// 完成输出但还没点开看过的会话；跨启动保留，选中即清。
        var unviewedIDs: [UUID]? = nil
    }
    @Published private(set) var current: AIConversationModel
    @Published private(set) var records: [AIConversationRecord]
    @Published var projects = ProjectFolders() { didSet { save() } }
    @Published private(set) var storageError: String?
    @Published private(set) var deletingIDs: Set<UUID> = []
    @Published private(set) var runningIDs: Set<UUID> = []
    /// 后台完成输出、尚未点开查看的会话：历史行标题前显示蓝点，选中即清。
    @Published private(set) var unviewedIDs: Set<UUID> = []
    @Published private(set) var isAnyRunning = false
    let sessionDirectory: URL
    private let persistence: JSONFileStore<Snapshot>
    private var scheduledFolderID: UUID?
    private var models: [UUID: AIConversationModel] = [:]
    private var observations: [UUID: AnyCancellable] = [:]

    init(directory: URL) {
        sessionDirectory = directory.appendingPathComponent("ai-conversations", isDirectory: true)
        persistence = JSONFileStore(filename: "ai-chat.json", directory: directory)
        let saved = persistence.load()
        var restored = saved?.records ?? []
        for i in restored.indices {
            for j in restored[i].messages.indices where restored[i].messages[j].state == .generating {
                restored[i].messages[j].state = .stopped
            }
        }
        records = restored
        current = AIConversationModel(record: restored.first(where: { $0.id == saved?.selectedID }) ?? .init(), directory: sessionDirectory)
        projects = saved?.projects ?? ProjectFolders()
        scheduledFolderID = saved?.scheduledFolderID
        unviewedIDs = Set((saved?.unviewedIDs ?? []).filter { id in restored.contains { $0.id == id } })
        unviewedIDs.remove(current.record.id)
        connect(current)
    }
    func newConversation() {
        guard !current.record.messages.isEmpty else {
            current.input = ""; current.attachments.discard(); current.setReferences([]); return
        }
        current = AIConversationModel(directory: sessionDirectory); connect(current); save()
    }
    func select(_ id: UUID) {
        guard id != current.record.id, !deletingIDs.contains(id),
              let record = records.first(where: { $0.id == id }) else { return }
        current = model(for: record)
        unviewedIDs.remove(id)
        save()
    }
    func delete(_ id: UUID, using removeSession: (UUID) async throws -> Void) async {
        guard records.contains(where: { $0.id == id }), deletingIDs.insert(id).inserted else { return }
        defer { deletingIDs.remove(id) }
        let model = models[id]
        model?.stop(); model?.attachments.discard()
        do { try await removeSession(id) }
        catch { storageError = error.localizedDescription; return }
        model?.onChange = nil
        observations.removeValue(forKey: id)
        models.removeValue(forKey: id)
        records.removeAll { $0.id == id }
        if current.record.id == id {
            current = self.model(for: records.max(by: { $0.updatedAt < $1.updatedAt }) ?? .init())
        }
        if projects.folderID(for: id) != nil { projects.move(id, to: nil) }
        unviewedIDs.remove(id)
        storageError = nil; save()
    }
    /// A scheduled run writes to history without replacing the selected chat or draft.
    func trackScheduledRun(_ model: AIConversationModel) {
        connect(model)
        var folders = projects
        let name = "定时任务"
        let folderID = folders.folders.first { $0.id == scheduledFolderID }?.id
            ?? folders.folders.first { $0.name == name }?.id
            ?? folders.create(name)
        scheduledFolderID = folderID
        folders.move(model.record.id, to: folderID)
        projects = folders
    }
    func recordAction(_ receipt: AIActionReceipt, conversationID: UUID) {
        if let model = models[conversationID] { model.appendAction(receipt); return }
        guard let index = records.firstIndex(where: { $0.id == conversationID }),
              let message = records[index].messages.lastIndex(where: { $0.role == .assistant }) else { return }
        records[index].messages[message].actions = (records[index].messages[message].actions ?? []) + [receipt]
        save()
    }
    func markUndone(_ token: UUID) {
        for model in models.values { model.markUndone(token) }
        for i in records.indices where models[records[i].id] == nil {
            for j in records[i].messages.indices {
                guard var actions = records[i].messages[j].actions else { continue }
                for k in actions.indices where actions[k].undoID == token { actions[k].undone = true }
                records[i].messages[j].actions = actions
            }
        }
        save()
    }
    private func model(for record: AIConversationRecord) -> AIConversationModel {
        if let model = models[record.id] { return model }
        let model = AIConversationModel(record: record, directory: sessionDirectory)
        connect(model); return model
    }
    private func connect(_ model: AIConversationModel) {
        let id = model.record.id
        guard models[id] !== model else { return }
        models[id] = model
        AIConversationRegistry.shared.register(model)
        model.onChange = { [weak self, weak model] value in
            guard let self, let model, self.models[value.id] === model else { return }
            guard !value.messages.isEmpty else { self.objectWillChange.send(); return }
            if let i = self.records.firstIndex(where: { $0.id == value.id }) { self.records[i] = value }
            else { self.records.append(value) }
            self.save()
        }
        observations[id] = model.$isRunning.removeDuplicates().sink { [weak self, weak model] running in
            guard let self else { return }
            let wasRunning = self.runningIDs.contains(id)
            var ids = self.runningIDs
            if running { ids.insert(id) } else { ids.remove(id) }
            if ids != self.runningIDs { self.runningIDs = ids }
            if self.isAnyRunning != !ids.isEmpty { self.isAnyRunning = !ids.isEmpty }
            // 一轮在用户没停留的会话里结束：历史行标题前的转圈换成蓝点，点开才清。
            // 手动停止不算完成输出，不留点。
            if wasRunning && !running, id != self.current.record.id,
               model?.record.messages.last?.state != .stopped,
               self.records.contains(where: { $0.id == id }),
               self.unviewedIDs.insert(id).inserted { self.save() }
        }
    }
    private func save() {
        persistence.schedule(Snapshot(selectedID: current.record.id, records: records,
                                      projects: projects, scheduledFolderID: scheduledFolderID,
                                      unviewedIDs: Array(unviewedIDs)))
    }
    func flush(_ completion: @escaping (Error?) -> Void) {
        persistence.flush { [weak self] error in
            _Concurrency.Task { @MainActor in self?.storageError = error?.localizedDescription }
            completion(error)
        }
    }
}
