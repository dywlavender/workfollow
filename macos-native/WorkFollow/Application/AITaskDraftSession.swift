import Combine
import Foundation

@MainActor
final class AITaskDraftSession: ObservableObject {
    enum Phase { case loading, ready, failed(String) }
    @Published var drafts: [AITaskDraft] = []
    @Published private(set) var phase: Phase = .loading
    @Published private(set) var retryAt: Date?
    @Published private(set) var preview = ""
    @Published private(set) var status = "正在生成…"
    private var generation = UUID()
    private var running = false
    var selectedCount: Int { drafts.filter { $0.selected && !$0.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }.count }

    func load(_ text: String, request: AITaskRequest) {
        do { drafts = try AITaskDraft.decode(text, request: request); phase = .ready }
        catch { phase = .failed("未能整理出有效的待办结果，请重新生成。") }
    }

    func generate(request: AITaskRequest, using generate: (AITaskRequest, @escaping @Sendable (AITextUpdate) -> Void) async throws -> String) async {
        guard !running, retryAt.map({ $0 <= Date() }) ?? true else { return }
        running = true
        let token = UUID(); generation = token
        defer { running = false; generation = UUID() }
        phase = .loading; retryAt = nil; preview = ""; status = "正在生成…"
        do {
            let text = try await generate(request) { [weak self] value in
                _Concurrency.Task { @MainActor in
                    guard let self, self.generation == token else { return }
                    if value.kind == "text" { self.preview = value.text ?? "" }
                    if value.kind == "status" { self.status = value.message ?? "正在生成…" }
                }
            }
            try _Concurrency.Task.checkCancellation()
            drafts = try AITaskDraft.decode(text, request: request)
            phase = .ready
        } catch is CancellationError { }
        catch is DecodingError { phase = .failed("未能整理出有效结果，请重新生成。") }
        catch let error as AIBackendError {
            if let seconds = error.retryAfterSeconds { retryAt = Date().addingTimeInterval(seconds) }
            phase = .failed(error.localizedDescription)
        }
        catch {
            let message = error.localizedDescription
            if message.contains("503") || message.contains("无可用渠道") {
                phase = .failed("当前文字模型暂时不可用，请在设置的“AI 模型”中更换后重试。")
            } else if message.localizedCaseInsensitiveContains("timed out") || message.contains("超时") {
                phase = .failed("AI 响应超时，请稍后重试。")
            } else { phase = .failed(message) }
        }
    }
}
