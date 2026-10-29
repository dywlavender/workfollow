import Combine
import Foundation

struct PiModelChoice: Decodable, Equatable, Identifiable, Sendable {
    let modelID: String
    let provider: String
    let name: String
    let input: [String]
    var id: String { provider + "/" + modelID }
    var title: String { name.isEmpty ? modelID : name }
    var menuTitle: String { title + " · " + provider }

    init(modelID: String, provider: String, name: String = "", input: [String] = ["text"]) {
        self.modelID = modelID; self.provider = provider; self.name = name; self.input = input
    }
    private enum CodingKeys: String, CodingKey { case modelID = "id", provider, name, input }
    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        modelID = try values.decode(String.self, forKey: .modelID)
        provider = try values.decode(String.self, forKey: .provider)
        name = try values.decodeIfPresent(String.self, forKey: .name) ?? modelID
        input = try values.decodeIfPresent([String].self, forKey: .input) ?? ["text"]
    }

    var supportsText: Bool {
        let value = modelID.lowercased()
        return input.contains("text") && !value.contains("-asr-") && !value.hasPrefix("fun-asr")
            && !value.hasPrefix("paraformer") && !value.contains("realtime") && !value.hasSuffix("-live")
    }
    /// These are transport capabilities of the bundled audio adapter, not a model catalog.
    var supportsTranscription: Bool {
        modelID == "qwen-audio-3.1-asr-flash" ||
            modelID.range(of: #"^qwen-audio-3\.[01]-asr-flash-streaming$"#, options: .regularExpression) != nil ||
            (modelID.contains("-omni-") && modelID.hasSuffix("-realtime"))
    }
}

enum PiModelCatalogError: LocalizedError {
    case unavailable, timedOut, invalidResponse
    var errorDescription: String? {
        switch self {
        case .unavailable: "找不到 Pi，请在高级选项中检查程序路径。"
        case .timedOut: "读取 Pi 模型列表超时，请稍后刷新。"
        case .invalidResponse: "本机 Pi 未返回模型列表，请按新手引导配置 models.json 或完成登录后刷新。"
        }
    }
}

struct PiModelCatalogClient {
    var timeout: TimeInterval = 15

    var backend: AIBackendBridge = .shared
    func fetch(executable: String) async throws -> [PiModelChoice] {
        struct Response: Decodable { let models: [PiModelChoice] }
        let value: Response = try await backend.call("models", params: ["piExecutable": executable], timeout: timeout)
        return value.models
    }

    static func models(from line: Data) throws -> [PiModelChoice]? {
        struct Header: Decodable { var id: String?; var command: String?; var success: Bool? }
        struct Response: Decodable { struct Payload: Decodable { var models: [PiModelChoice] }; var data: Payload }
        guard let header = try? JSONDecoder().decode(Header.self, from: line), header.id == "workfollow-models",
              header.command == "get_available_models" else { return nil }
        guard header.success == true else { throw PiModelCatalogError.invalidResponse }
        let models = try JSONDecoder().decode(Response.self, from: line).data.models
        var seen = Set<String>()
        return models.filter { !$0.modelID.isEmpty && !$0.provider.isEmpty && seen.insert($0.id).inserted }
            .sorted { ($0.provider, $0.modelID) < ($1.provider, $1.modelID) }
    }
}

@MainActor
final class PiModelCatalog: ObservableObject {
    @Published private(set) var models: [PiModelChoice] = []
    @Published private(set) var loading = false
    @Published private(set) var error: String?
    private var executable: String?
    private var generation = UUID()
    private let load: (String) async throws -> [PiModelChoice]

    init(load: @escaping (String) async throws -> [PiModelChoice] = { try await PiModelCatalogClient().fetch(executable: $0) }) {
        self.load = load
    }

    func refresh(executable: String) async {
        let token = UUID(); generation = token
        if self.executable != executable { models = []; self.executable = executable }
        loading = true; error = nil
        defer { if generation == token { loading = false } }
        do {
            let result = try await load(executable)
            try _Concurrency.Task.checkCancellation()
            guard generation == token else { return }
            models = result
        } catch is CancellationError { }
        catch { if generation == token { self.error = error.localizedDescription } }
    }

    func model(for saved: String) -> PiModelChoice? {
        if let exact = models.first(where: { $0.id == saved }) { return exact }
        let matches = models.filter { $0.modelID == saved }
        return matches.count == 1 ? matches.first : nil
    }
}
