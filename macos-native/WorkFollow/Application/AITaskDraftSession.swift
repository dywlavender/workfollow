import Combine
import Foundation

@MainActor
final class AITaskDraftSession: ObservableObject {
    enum Phase { case loading, ready, failed(String) }
    @Published var drafts: [AITaskDraft] = []
    @Published private(set) var phase: Phase = .loading
    var selectedCount: Int { drafts.filter { $0.selected && !$0.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }.count }

    func generate(request: AITaskRequest, using generate: (AITaskRequest) async throws -> String) async {
        phase = .loading
        do {
            let text = try await generate(request)
            try _Concurrency.Task.checkCancellation()
            drafts = try AITaskDraft.decode(text, request: request)
            phase = .ready
        } catch is CancellationError { }
        catch is DecodingError { phase = .failed("未能整理出有效结果，请重新生成。") }
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
