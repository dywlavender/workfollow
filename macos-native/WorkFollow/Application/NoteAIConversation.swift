import Combine
import Foundation

/// 笔记编辑栏右侧 AI 栏里的三个动作。标题/说明与图标只在这里维护，
/// 面板与测试都读同一份，避免按钮和提示各写一套。
enum NoteAIAction: String, CaseIterable, Identifiable {
    case organize
    case polish
    case extract

    var id: String { rawValue }
    var preset: AIConversationPreset { AIConversationPreset(rawValue: rawValue)! }

    var title: String {
        switch self {
        case .organize: "整理要点"
        case .polish: "润色笔记"
        case .extract: "提取待办"
        }
    }

    var subtitle: String {
        switch self {
        case .organize: "提炼关键结论，按要点组织"
        case .polish: "保留原意，改善表达与结构"
        case .extract: "把行动项整理成任务"
        }
    }

    var symbol: String {
        switch self {
        case .organize: "list.bullet"
        case .polish: "wand.and.sparkles"
        case .extract: "checkmark"
        }
    }

    var rewriteAction: NoteRewriteRequest.Action? {
        switch self {
        case .organize: .organize
        case .polish: .polish
        case .extract: nil
        }
    }

    /// 既有 UI 测试按这三个锚点找动作；菜单改成侧栏后锚点名保持不变。
    var workflowAnchor: String {
        switch self {
        case .organize: "note.ai.organize"
        case .polish: "note.ai.polish"
        case .extract: "note.ai.tasks"
        }
    }
}

/// 一次生成使用的笔记快照。动作在点击时取最新正文，避免侧栏一直握着一份旧文本。
struct NoteAIContext {
    let noteID: UUID
    let title: String
    let content: String
    let referenceDate: Date
    let existingTitles: [String]

    var source: AIConversationSource { .init(id: noteID, kind: "note", title: title, content: content) }

    var isEmpty: Bool {
        title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
}

/// A native adapter for an adoptable result. It never starts another model request.
@MainActor
final class NoteAIExchange: ObservableObject, Identifiable {
    let id: UUID
    let messageID: UUID
    let action: NoteAIAction
    let context: NoteAIContext
    let taskRequest: AITaskRequest?
    let rewriteRequest: NoteRewriteRequest?
    let taskSession: AITaskDraftSession?
    let rewriteSession: NoteRewriteSession?
    @Published private(set) var appliedIDs: [UUID] = []
    @Published var applyError: String?
    @Published private(set) var savedNoteID: UUID?
    @Published private(set) var didReplaceBody = false
    @Published var saveError: String?
    private let onAdoption: (String) -> Void

    init(artifact: AIConversationArtifact, message: AIConversationMessage, question: AIConversationMessage, context: NoteAIContext,
         onAdoption: @escaping (String) -> Void) {
        id = artifact.id; messageID = message.id; self.context = context
        self.onAdoption = onAdoption
        action = artifact.kind == .tasks ? .extract : (question.preset == .organize ? .organize : .polish)
        if artifact.kind == .tasks {
            let request = AITaskRequest(source: .note(context.noteID), title: context.title, content: context.content,
                referenceDate: context.referenceDate, existingTitles: context.existingTitles,
                instruction: question.text, attachments: question.attachments ?? [], requiresSourceQuote: question.preset == .extract)
            taskRequest = request; rewriteRequest = nil; rewriteSession = nil
            let session = AITaskDraftSession(); session.load(artifact.content, request: request); taskSession = session
        } else {
            taskRequest = nil; taskSession = nil
            rewriteRequest = NoteRewriteRequest(noteID: context.noteID, title: context.title.isEmpty ? "未命名笔记" : context.title,
                content: context.content, action: action.rewriteAction ?? .polish, instruction: question.text)
            let session = NoteRewriteSession(); session.load(artifact.content); rewriteSession = session
        }
    }
    var isApplied: Bool { !appliedIDs.isEmpty }
    var selectedCount: Int { taskSession?.selectedCount ?? 0 }
    func markApplied(_ ids: [UUID]) {
        appliedIDs = ids; applyError = nil
        onAdoption("候选已创建为待办：" + ids.map { NativeResourceLink.task($0).url.absoluteString }.joined(separator: "、"))
    }
    func markUnapplied() { appliedIDs = []; onAdoption("本轮候选创建的待办已撤销。") }
    func markSaved(noteID: UUID) {
        savedNoteID = noteID; saveError = nil
        onAdoption("文稿已另存为笔记：" + NativeResourceLink.note(noteID).url.absoluteString)
    }
    func markReplaced() {
        didReplaceBody = true; saveError = nil
        onAdoption("文稿已替换到当前笔记：" + NativeResourceLink.note(context.noteID).url.absoluteString)
    }
}

@MainActor
final class NoteAIConversationStore: ObservableObject {
    static let shared = NoteAIConversationStore()
    /// 任意一条笔记的 AI 正在生成：小伙伴据此显示“一起想”的常驻状态。
    @Published private(set) var isAnyRunning = false
    private var models: [UUID: NoteAIConversationModel] = [:]
    private var observations: [UUID: AnyCancellable] = [:]

    func model(for noteID: UUID) -> NoteAIConversationModel {
        if let model = models[noteID] { return model }
        let model = NoteAIConversationModel(noteID: noteID); models[noteID] = model
        // 模型会转发内部会话的 objectWillChange；它先于值更新发出，
        // 推到下一轮主线程再读 isRunning，顺带覆盖 reset 更换会话的情况。
        observations[noteID] = model.objectWillChange.sink { [weak self] in
            DispatchQueue.main.async { self?.refreshRunning() }
        }
        return model
    }

    private func refreshRunning() {
        let running = models.values.contains { $0.isRunning }
        if running != isAnyRunning { isAnyRunning = running }
    }
}

/// The note surface supplies context and projects result cards; conversation behavior belongs to AIConversationModel.
@MainActor
final class NoteAIConversationModel: ObservableObject {
    @Published private(set) var conversation: AIConversationModel
    @Published private(set) var exchanges: [NoteAIExchange] = []
    /// 选中文字的 AI 事务快照，按「触发提问的用户消息」逐条绑定。挂在「每篇
    /// 笔记的会话模型」上：主窗口 AI 栏和浮窗笔记 AI 栏读同一份。多轮润色后
    /// 每条结果下方都有自己的替换/插入（用户要求），互不覆盖；回写靠各自的
    /// 快照重建选区，不依赖点击时选区是否还在，快照失效由 apply 校验兜底。
    @Published private(set) var selectionTargets: [UUID: AISelectionTarget] = [:]
    /// 本笔记归档的历史会话（「新会话」把旧会话存到这里），最新的在前，
    /// 磁盘持久化——清空会话记录不等于销毁历史（用户要求）。上限 30 条。
    @Published private(set) var history: [AIConversationRecord] = []
    /// 正在只读查看的历史会话；nil 表示当前会话。
    @Published private(set) var viewingHistory: AIConversationModel?
    /// 最近一次写入原文的选区快照：面板的「撤销本次写入」按它回退。
    struct LastWrite { let target: AISelectionTarget; let kind: String }
    @Published private(set) var lastWrite: LastWrite?
    private let noteID: UUID?
    private let directory: URL
    private var observation: AnyCancellable?
    private let persistence: JSONFileStore<SessionSnapshot>?

    private struct SessionSnapshot: Codable { var current: AIConversationRecord?; var history: [AIConversationRecord] }

    /// 带 noteID 时当前会话与历史都按笔记持久化（重启后回到同一会话）；
    /// 不带时仅内存存活（预览与旧测试的用法不变）。
    init(noteID: UUID? = nil, directory: URL? = nil) {
        self.noteID = noteID
        self.directory = directory ?? NativePreviewRepository.directory.appendingPathComponent("modules/ai-conversations", isDirectory: true)
        if let noteID {
            let store = JSONFileStore<SessionSnapshot>(filename: noteID.uuidString + ".json",
                directory: self.directory.appendingPathComponent("note-sessions", isDirectory: true))
            persistence = store
            let saved = store.load()
            history = saved?.history ?? []
            conversation = AIConversationModel(record: saved?.current ?? .init(), scene: .note, directory: self.directory)
        } else {
            persistence = nil
            conversation = AIConversationModel(scene: .note, directory: self.directory)
        }
        connect()
    }
    var input: String { get { conversation.input } set { conversation.input = newValue } }
    var attachments: AIAttachmentDraft { conversation.attachments }
    var isRunning: Bool { conversation.isRunning }
    var canSend: Bool { conversation.canSend }

    func ask(_ action: NoteAIAction, context: NoteAIContext, using generate: @escaping AIConversationModel.Generate) {
        conversation.ask(action.preset, source: context.source, using: generate)
    }
    func send(context: NoteAIContext, using generate: @escaping AIConversationModel.Generate) {
        conversation.send(source: context.source, using: generate)
    }

    /// 选中级 AI 走右侧 AI 栏：source 只带选中文字，不带整篇笔记。
    /// 刻意不给 `id`：`project(_:)` 只应把「整篇笔记」的文稿投影成
    /// 可另存/替换正文的结果卡，选区结果不该出现「替换正文」按钮。
    /// 快照在提问落进会话后按这条用户消息绑定，供该条结果的动作使用。
    func askSelection(_ preset: AIConversationPreset, target: AISelectionTarget,
                      using generate: @escaping AIConversationModel.Generate) {
        conversation.ask(preset,
                         source: .init(kind: "selection", title: "选中文字", content: target.text),
                         using: generate)
        if let question = conversation.record.messages.last(where: { $0.role == .user }) {
            selectionTargets[question.id] = target
        }
    }
    /// 某条回复对应的选区快照：取它前面最近的一条用户提问所绑定的快照。
    func selectionTarget(for message: AIConversationMessage) -> AISelectionTarget? {
        guard let index = conversation.record.messages.firstIndex(where: { $0.id == message.id }) else { return nil }
        guard let question = conversation.record.messages[..<index].last(where: { $0.role == .user }) else { return nil }
        return selectionTargets[question.id]
    }
    /// 回写成功后消费掉该条快照：对应结果的动作行随之收起。
    func consumeSelectionTarget(for message: AIConversationMessage) {
        guard let index = conversation.record.messages.firstIndex(where: { $0.id == message.id }) else { return }
        guard let question = conversation.record.messages[..<index].last(where: { $0.role == .user }) else { return }
        selectionTargets[question.id] = nil
    }
    func clearSelectionTargets() { selectionTargets = [:] }
    func noteLastWrite(target: AISelectionTarget, kind: String) {
        target.noteApplied()
        lastWrite = LastWrite(target: target, kind: kind)
    }
    /// 不执行撤销，只是收起「撤销本次写入」提示。
    func dismissLastWrite() { lastWrite = nil }
    /// 撤销最近一次写入；成功返回 true（快照随之清除），文档已再变过则返回 false。
    func undoLastWriteAsync() async -> Bool {
        guard let lastWrite else { return false }
        let applied = await lastWrite.target.undoWriteAsync()
        if applied { self.lastWrite = nil }
        return applied
    }

    /// 这条回复是否来自选区会话。右栏对选区结果改用通用结果视图，
    /// 不投影成 `NoteAIExchange`（那是整篇笔记改写/提取待办专用的）。
    func isSelectionResult(_ message: AIConversationMessage) -> Bool {
        guard let index = conversation.record.messages.firstIndex(where: { $0.id == message.id }) else { return false }
        return conversation.record.messages[..<index].last(where: { $0.role == .user })?.source?.kind == "selection"
    }
    func retry(messageID: UUID, using generate: @escaping AIConversationModel.Generate, guidance: String? = nil) {
        conversation.retry(messageID, using: generate, guidance: guidance)
    }
    func editAndResend(_ messageID: UUID, text: String, using generate: @escaping AIConversationModel.Generate) {
        conversation.editAndResend(messageID, text: text, using: generate)
    }
    func stop() { conversation.stop() }
    /// 不留历史的彻底清空（旧测试与个别清理路径使用；面板的「新会话」走
    /// `startNewSession()`，会把旧会话归档进历史）。
    func reset() {
        guard !isRunning else { return }
        conversation.attachments.discard()
        AIConversationAttachmentFiles.remove(conversation.record.messages.flatMap { $0.attachments ?? [] })
        conversation = AIConversationModel(scene: .note, directory: directory)
        exchanges = []; selectionTargets = [:]; lastWrite = nil; connect()
        saveSnapshot()
    }
    /// 清空会话记录并新开一个 session：旧会话先归档进 history（磁盘持久化，
    /// 历史还在），未发送的草稿附件随之丢弃；进行中的回复要先停止。
    func startNewSession() {
        guard !isRunning else { return }
        conversation.attachments.discard()
        if !conversation.record.messages.isEmpty {
            history.insert(conversation.record, at: 0)
            if history.count > 30 { history.removeLast(history.count - 30) }
        }
        viewingHistory = nil
        conversation = AIConversationModel(scene: .note, directory: directory)
        exchanges = []; selectionTargets = [:]; connect()
        saveSnapshot()
    }
    /// 只读查看某条归档会话；`backToCurrent()` 回到当前会话。
    func viewHistory(_ id: UUID) {
        guard viewingHistory?.record.id != id,
              let record = history.first(where: { $0.id == id }) else { return }
        viewingHistory = AIConversationModel(record: record, scene: .note, directory: directory)
    }
    func backToCurrent() { viewingHistory = nil }
    func exchange(id: UUID) -> NoteAIExchange? { exchanges.first { $0.id == id } }
    func results(for message: AIConversationMessage) -> [NoteAIExchange] { exchanges.filter { $0.messageID == message.id } }
    private func connect() {
        observation = conversation.objectWillChange.sink { [weak self] in self?.objectWillChange.send() }
        conversation.onChange = { [weak self] record in
            self?.project(record)
            self?.saveSnapshot(current: record)
        }
    }
    private func saveSnapshot(current: AIConversationRecord? = nil) {
        guard let persistence else { return }
        persistence.schedule(SessionSnapshot(current: current ?? conversation.record, history: history))
    }
    private func project(_ record: AIConversationRecord) {
        for (index, message) in record.messages.enumerated() where message.role == .assistant && message.state == .complete {
            guard let question = record.messages[..<index].last(where: { $0.role == .user }),
                  let source = question.source, source.kind == "note", let id = source.id else { continue }
            let context = NoteAIContext(noteID: id, title: source.title, content: source.content, referenceDate: Date(), existingTitles: [])
            for artifact in message.artifacts ?? [] where !exchanges.contains(where: { $0.id == artifact.id }) {
                exchanges.append(NoteAIExchange(artifact: artifact, message: message, question: question, context: context,
                    onAdoption: { [weak conversation] value in conversation?.recordAdoption(artifactID: artifact.id, result: value) }))
            }
        }
    }
}
