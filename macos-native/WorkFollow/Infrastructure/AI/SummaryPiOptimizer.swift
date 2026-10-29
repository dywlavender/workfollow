import Foundation

/// 摘要 AI 优化的参数（对齐滴答「内容优化」：长度 / 语言风格 / 职业 + 自定义要求）。
struct SummaryAIOptions: Equatable, Codable {
    enum Length: String, CaseIterable, Codable {
        case brief = "简短"
        case normal = "默认"
        case detailed = "详细"
    }

    enum Style: String, CaseIterable, Codable {
        case plain = "平实"
        case warm = "温暖"
        case formal = "正式"
    }

    var length: Length = .normal
    var style: Style = .plain
    var profession: String = ""
    /// 滴答的 `ai_improve_hint`：一句话补充要求。
    var hint: String = ""
    var weeklyStructure = false
    var isWeeklyPeriod = true

    static var weeklyReview: SummaryAIOptions {
        var value = SummaryAIOptions()
        value.length = .brief
        value.weeklyStructure = true
        return value
    }
}

enum SummaryPiError: LocalizedError {
    case unavailable
    case timedOut
    case failed(String)
    case emptyResult

    var errorDescription: String? {
        switch self {
        case .unavailable: "内置 AI 引擎不可用，请重新安装完整应用。"
        case .timedOut: "AI 优化超时，请稍后重试"
        case .failed(let message): message
        case .emptyResult: "AI 没有返回内容"
        }
    }
}

/// Compatibility name retained for callers; all work goes through the App AI backend.
struct SummaryPiOptimizer {
    var executable: String = ""
    var timeout: TimeInterval = 90
    var model: String = ""
    var backend: AIBackendBridge = .shared
    var textModel: AITextModelRequest?

    func optimize(text: String, options: SummaryAIOptions) async throws -> String {
        let encoded = try JSONEncoder().encode(options)
        let value = try JSONSerialization.jsonObject(with: encoded)
        return try await request("text.summary", params: ["content": text, "options": value])
    }

    func generateTasks(_ request: AITaskRequest) async throws -> String {
        try await self.request("text.tasks", params: request.backendParameters)
    }

    func generate(prompt: String) async throws -> String {
        try await request("text.generate", params: ["prompt": prompt])
    }

    private func request(_ method: String, params: [String: Any]) async throws -> String {
        struct Response: Decodable { let text: String }
        var params = params
        params["model"] = model; params["piExecutable"] = executable
        params["timeoutSeconds"] = timeout
        if let textModel { params.merge(textModel.parameters) { _, new in new } }
        let response: Response = try await backend.call(method, params: params, timeout: timeout + 5)
        guard !response.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { throw SummaryPiError.emptyResult }
        return response.text
    }

}
