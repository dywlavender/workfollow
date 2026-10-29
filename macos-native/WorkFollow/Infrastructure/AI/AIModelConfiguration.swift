import Foundation

enum AIModelProtocol: String, Codable, CaseIterable, Identifiable, Sendable {
    case openAIChat = "openai_chat", openAIResponses = "openai_responses", anthropic, gemini
    // Keep old values readable without exposing unsupported protocols for new calls.
    static let allCases: [Self] = [.openAIChat, .openAIResponses]
    var supported: Bool { Self.allCases.contains(self) }
    var id: String { rawValue }
    var title: String {
        switch self {
        case .openAIChat: "OpenAI 兼容"
        case .openAIResponses: "OpenAI Responses"
        case .anthropic: "Anthropic（暂不支持）"
        case .gemini: "Google Gemini（暂不支持）"
        }
    }
    var defaultURL: String {
        switch self {
        case .openAIChat, .openAIResponses: "https://api.openai.com/v1"
        case .anthropic: "https://api.anthropic.com"
        case .gemini: "https://generativelanguage.googleapis.com"
        }
    }
}

enum AITextEngine: String, Codable, Sendable { case pi, langchain }

struct AIModelProfile: Identifiable, Codable, Equatable, Sendable {
    var id = UUID()
    var protocolKind: AIModelProtocol = .openAIChat
    var model = ""
    var baseURL = AIModelProtocol.openAIChat.defaultURL
    var contextWindow = 32768
    var maxOutputTokens = 2048
    var anthropicWorkspaceID: String?
    var title: String { model.isEmpty ? "新模型" : model }
    var menuTitle: String {
        title + " · " + protocolKind.title + " · " + (URL(string: baseURL)?.host ?? "自定义服务")
    }
    var requiresKey: Bool {
        let host = URLComponents(string: baseURL)?.host?.trimmingCharacters(in: CharacterSet(charactersIn: "[]"))
        return !([AIModelProtocol.openAIChat, .openAIResponses].contains(protocolKind) &&
                 ["localhost", "127.0.0.1", "::1"].contains(host ?? ""))
    }

    func validated(key: String) throws -> Self {
        guard protocolKind.supported else {
            throw AIModelConfigurationError.invalid("目前支持 OpenAI 兼容和 OpenAI Responses，请选择其中一种协议。")
        }
        var value = self
        value.model = model.trimmingCharacters(in: .whitespacesAndNewlines)
        value.baseURL = baseURL.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.model.isEmpty, !value.model.contains(where: \.isNewline) else {
            throw AIModelConfigurationError.invalid("请填写一个完整的模型名称（模型 ID）。")
        }
        guard let url = URLComponents(string: value.baseURL), ["http", "https"].contains(url.scheme?.lowercased() ?? ""),
              url.host?.isEmpty == false, url.user == nil, url.password == nil, url.query == nil, url.fragment == nil else {
            throw AIModelConfigurationError.invalid("请填写有效的 API URL，不包含账号或查询参数。")
        }
        guard !value.requiresKey || !key.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw AIModelConfigurationError.invalid("请填写这个模型的 API Key。")
        }
        guard value.contextWindow >= 2048, value.maxOutputTokens >= 128,
              value.contextWindow - value.maxOutputTokens - 1024 >= 1024 else {
            throw AIModelConfigurationError.invalid("上下文窗口需要容纳最大输出，并至少留出 2048 个 token。")
        }
        return value
    }
}

enum AIModelConfigurationError: LocalizedError {
    case invalid(String), keychain(Int32), missingModel
    var errorDescription: String? {
        switch self {
        case .invalid(let message): message
        case .keychain(let status): "无法访问 API Key 的钥匙串记录（\(status)），请检查钥匙串访问权限。"
        case .missingModel: "请先在设置的“AI 模型”中保存并选择文字模型。"
        }
    }
}

struct AITextModelRequest: Sendable {
    let profile: AIModelProfile
    let key: String
    var configuration: [String: Any] {
        ["ai_enabled": true, "ai_protocol": profile.protocolKind.rawValue,
         "ai_model": profile.model, "ai_base_url": profile.baseURL, "ai_api_key": key,
         "ai_context_window": profile.contextWindow, "ai_max_output_tokens": profile.maxOutputTokens]
    }
    var parameters: [String: Any] { ["engine": "langchain", "profileID": profile.id.uuidString, "configuration": configuration] }
}
