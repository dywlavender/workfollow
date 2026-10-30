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
    private var models: [UUID: NoteAIConversationModel] = [:]
    func model(for noteID: UUID) -> NoteAIConversationModel {
        if let model = models[noteID] { return model }
        let model = NoteAIConversationModel(); models[noteID] = model; return model
    }
}

/// The note surface supplies context and projects result cards; conversation behavior belongs to AIConversationModel.
@MainActor
final class NoteAIConversationModel: ObservableObject {
    @Published private(set) var conversation: AIConversationModel
    @Published private(set) var exchanges: [NoteAIExchange] = []
    private let directory: URL
    private var observation: AnyCancellable?

    init(directory: URL? = nil) {
        self.directory = directory ?? NativePreviewRepository.directory.appendingPathComponent("modules/ai-conversations", isDirectory: true)
        conversation = AIConversationModel(scene: .note, directory: self.directory)
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
    func retry(messageID: UUID, using generate: @escaping AIConversationModel.Generate) {
        conversation.retry(messageID, using: generate)
    }
    func stop() { conversation.stop() }
    func reset() {
        guard !isRunning else { return }
        conversation.attachments.discard()
        AIConversationAttachmentFiles.remove(conversation.record.messages.flatMap { $0.attachments ?? [] })
        conversation = AIConversationModel(scene: .note, directory: directory)
        exchanges = []; connect()
    }
    func exchange(id: UUID) -> NoteAIExchange? { exchanges.first { $0.id == id } }
    func results(for message: AIConversationMessage) -> [NoteAIExchange] { exchanges.filter { $0.messageID == message.id } }
    private func connect() {
        observation = conversation.objectWillChange.sink { [weak self] in self?.objectWillChange.send() }
        conversation.onChange = { [weak self] record in self?.project(record) }
    }
    private func project(_ record: AIConversationRecord) {
        for (index, message) in record.messages.enumerated() where message.role == .assistant && message.state == .complete {
            guard let question = record.messages[..<index].last(where: { $0.role == .user }), let source = question.source, let id = source.id else { continue }
            let context = NoteAIContext(noteID: id, title: source.title, content: source.content, referenceDate: Date(), existingTitles: [])
            for artifact in message.artifacts ?? [] where !exchanges.contains(where: { $0.id == artifact.id }) {
                exchanges.append(NoteAIExchange(artifact: artifact, message: message, question: question, context: context,
                    onAdoption: { [weak conversation] value in conversation?.recordAdoption(artifactID: artifact.id, result: value) }))
            }
        }
    }
}
