import Combine
import Foundation

/// 笔记编辑栏右侧 AI 栏里的三个动作。标题/说明与图标只在这里维护，
/// 面板与测试都读同一份，避免按钮和提示各写一套。
enum NoteAIAction: String, CaseIterable, Identifiable {
    case organize
    case polish
    case extract

    var id: String { rawValue }

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

    var isEmpty: Bool {
        title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
}

/// 面板只负责把 AppEnvironment 的文字模型变成两个生成闭包；模型本身不依赖环境，
/// 单测可以直接塞假闭包。
struct NoteAIGenerators {
    let tasks: (AITaskRequest, @escaping @Sendable (AITextUpdate) -> Void) async throws -> String
    let rewrite: (NoteRewriteRequest, @escaping @Sendable (AITextUpdate) -> Void) async throws -> String
}

@MainActor
final class NoteAIExchange: ObservableObject, Identifiable {
    let id = UUID()
    let action: NoteAIAction
    let instruction: String
    let context: NoteAIContext
    let taskRequest: AITaskRequest?
    let rewriteRequest: NoteRewriteRequest?
    let taskSession: AITaskDraftSession?
    let rewriteSession: NoteRewriteSession?

    /// 创建结果：成功后侧栏留在原地，既显示「已创建」也提供撤销/查看。
    @Published private(set) var appliedIDs: [UUID] = []
    @Published var applyError: String?
    /// 另存结果（不把当前笔记切走）。
    @Published private(set) var savedNoteID: UUID?
    @Published private(set) var didReplaceBody = false
    @Published var saveError: String?

    private let generators: NoteAIGenerators
    private var onFinish: (() -> Void)?
    private var started = false

    init(action: NoteAIAction, instruction: String, context: NoteAIContext, conversationID: UUID? = nil,
         generators: NoteAIGenerators) {
        self.action = action
        self.instruction = instruction
        self.context = context
        self.generators = generators
        switch action {
        case .extract:
            taskRequest = AITaskRequest(source: .note(context.noteID), title: context.title,
                                        content: context.content, referenceDate: context.referenceDate,
                                        existingTitles: context.existingTitles,
                                        instruction: instruction)
            rewriteRequest = nil
            taskSession = AITaskDraftSession()
            rewriteSession = nil
        case .organize, .polish:
            taskRequest = nil
            rewriteRequest = NoteRewriteRequest(noteID: context.noteID,
                                                title: context.title.isEmpty ? "未命名笔记" : context.title,
                                                content: context.content,
                                                action: action.rewriteAction ?? .organize,
                                                instruction: instruction,
                                                conversationID: conversationID)
            taskSession = nil
            rewriteSession = NoteRewriteSession()
        }
    }

    var isApplied: Bool { !appliedIDs.isEmpty }
    var selectedCount: Int { taskSession?.selectedCount ?? 0 }

    func start(onFinish: @escaping () -> Void) {
        guard !started else { return }
        started = true
        self.onFinish = onFinish
        runGeneration()
    }

    func retry(onFinish: @escaping () -> Void) {
        self.onFinish = onFinish
        runGeneration()
    }

    private func runGeneration() {
        _Concurrency.Task { [weak self] in
            guard let self else { return }
            switch action {
            case .extract:
                guard let taskRequest, let taskSession else { return }
                await taskSession.generate(request: taskRequest, using: generators.tasks)
            case .organize, .polish:
                guard let rewriteRequest, let rewriteSession else { return }
                await rewriteSession.generate(request: rewriteRequest, using: generators.rewrite)
            }
            onFinish?()
        }
    }

    func markApplied(_ ids: [UUID]) {
        appliedIDs = ids
        applyError = nil
    }

    func markUnapplied() {
        appliedIDs = []
    }

    func markSaved(noteID: UUID) {
        savedNoteID = noteID
        saveError = nil
    }

    func markReplaced() {
        didReplaceBody = true
        saveError = nil
    }
}

/// 同一篇笔记的会话在切换笔记后仍保留：每个 noteID 各自一份消息列表。
@MainActor
final class NoteAIConversationStore: ObservableObject {
    private var models: [UUID: NoteAIConversationModel] = [:]

    func model(for noteID: UUID) -> NoteAIConversationModel {
        if let model = models[noteID] { return model }
        let model = NoteAIConversationModel()
        models[noteID] = model
        return model
    }
}

@MainActor
final class NoteAIConversationModel: ObservableObject {
    @Published private(set) var exchanges: [NoteAIExchange] = []
    @Published private(set) var runningExchangeID: UUID?
    @Published var input = ""
    private var conversationID = UUID()

    var isRunning: Bool { runningExchangeID != nil }
    var lastAction: NoteAIAction? { exchanges.last?.action }
    var canSendInstruction: Bool {
        !isRunning && lastAction != nil
            && !input.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    @discardableResult
    func run(action: NoteAIAction, context: NoteAIContext, instruction: String,
             generators: NoteAIGenerators) -> NoteAIExchange? {
        guard runningExchangeID == nil else { return nil }
        let exchange = NoteAIExchange(action: action, instruction: instruction,
                                      context: context, conversationID: conversationID, generators: generators)
        exchanges.append(exchange)
        input = ""
        runningExchangeID = exchange.id
        exchange.start { [weak self, weak exchange] in
            guard let self, let exchange, self.runningExchangeID == exchange.id else { return }
            self.runningExchangeID = nil
        }
        return exchange
    }

    /// v1 的输入框只做「补充要求」：沿用最近一次动作，带 instruction 重新生成一条消息。
    @discardableResult
    func rerunLast(context: NoteAIContext, generators: NoteAIGenerators) -> NoteAIExchange? {
        guard let action = lastAction else { return nil }
        let instruction = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !instruction.isEmpty else { return nil }
        return run(action: action, context: context, instruction: instruction,
                   generators: generators)
    }

    func retry(_ exchange: NoteAIExchange) {
        guard runningExchangeID == nil else { return }
        runningExchangeID = exchange.id
        exchange.retry { [weak self, weak exchange] in
            guard let self, let exchange, self.runningExchangeID == exchange.id else { return }
            self.runningExchangeID = nil
        }
    }

    func reset() {
        guard runningExchangeID == nil else { return }
        exchanges = []
        input = ""
        conversationID = UUID()
    }

    func exchange(id: UUID) -> NoteAIExchange? {
        exchanges.first { $0.id == id }
    }
}
