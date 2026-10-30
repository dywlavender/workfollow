import Combine
import Foundation

struct NoteRewriteRequest: Identifiable {
    enum Action: String { case organize, polish
        var title: String { self == .organize ? "整理要点" : "润色笔记" }
        var suffix: String { self == .organize ? "要点" : "润色" }
    }
    let id = UUID()
    let noteID: UUID
    let title: String
    let content: String
    let action: Action
    /// 对话栏里对本次结果的补充要求；空字符串表示沿用原提示词。
    var instruction: String = ""
    var conversationID: UUID?
    var attachments: [AIConversationAttachment] = []
}

@MainActor
final class NoteRewriteSession: ObservableObject {
    enum Phase: Equatable { case loading, ready, failed(String) }
    @Published private(set) var phase = Phase.loading
    @Published var draft = ""
    @Published private(set) var preview = ""
    @Published private(set) var status = "正在生成…"
    @Published private(set) var retryAt: Date?
    private var generation = UUID()
    private var running = false

    func load(_ text: String) { draft = text; phase = .ready }

    func generate(request: NoteRewriteRequest, using generate: (NoteRewriteRequest, @escaping @Sendable (AITextUpdate) -> Void) async throws -> String) async {
        guard !running, retryAt.map({ $0 <= Date() }) ?? true else { return }
        running = true
        let token = UUID(); generation = token
        phase = .loading; preview = ""; status = "正在生成…"; retryAt = nil
        defer { running = false; generation = UUID() }
        do {
            let text = try await generate(request) { [weak self] value in
                _Concurrency.Task { @MainActor in
                    guard let self, self.generation == token, self.phase == .loading else { return }
                    if value.kind == "text" { self.preview = value.text ?? "" }
                    if value.kind == "status" { self.status = value.message ?? "正在生成…" }
                }
            }
            try _Concurrency.Task.checkCancellation()
            guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { throw SummaryPiError.emptyResult }
            draft = text; phase = .ready
        } catch is CancellationError { }
        catch {
            if !_Concurrency.Task.isCancelled {
                if let seconds = (error as? AIBackendError)?.retryAfterSeconds { retryAt = Date().addingTimeInterval(seconds) }
                phase = .failed(error.localizedDescription)
            }
        }
    }
}
