import Combine
import Foundation

@MainActor
final class AIModelStore: ObservableObject {
    private struct Snapshot: Codable {
        var engine: AITextEngine = .pi
        var profiles: [AIModelProfile] = []
        var selectedID: UUID?
    }
    @Published private var snapshot = Snapshot()
    @Published private(set) var loadError: String?
    var engine: AITextEngine { snapshot.engine }
    var profiles: [AIModelProfile] { snapshot.profiles }
    var selectedID: UUID? { snapshot.selectedID }
    private let file: URL
    private let credentials: any AIModelCredentials
    private let writeFile: (Data, URL) throws -> Void

    init(directory: URL = JSONFileStore<AIModelProfile>.moduleDirectory,
         credentials: (any AIModelCredentials)? = nil,
         writeFile: @escaping (Data, URL) throws -> Void = { try $0.write(to: $1, options: .atomic) }) {
        file = directory.appendingPathComponent("ai-models.json")
        self.credentials = credentials ?? KeychainAIModelCredentials()
        self.writeFile = writeFile
        if FileManager.default.fileExists(atPath: file.path) {
            do { snapshot = try JSONDecoder().decode(Snapshot.self, from: Data(contentsOf: file)) }
            catch { loadError = "模型配置读取失败，已有配置未覆盖：" + error.localizedDescription }
        }
    }

    func key(for id: UUID) throws -> String { try credentials.read(id) ?? "" }

    @discardableResult
    func save(_ profile: AIModelProfile, key: String) throws -> AIModelProfile {
        let key = key.trimmingCharacters(in: .whitespacesAndNewlines)
        let profile = try profile.validated(key: key)
        let oldKey = try credentials.read(profile.id)
        try credentials.write(key, for: profile.id)
        var value = snapshot
        if let index = value.profiles.firstIndex(where: { $0.id == profile.id }) { value.profiles[index] = profile }
        else { value.profiles.append(profile) }
        value.engine = .langchain; value.selectedID = profile.id
        do { try persist(value) }
        catch { try? credentials.write(oldKey, for: profile.id); throw error }
        return profile
    }

    func usePi() throws {
        var value = snapshot; value.engine = .pi; try persist(value)
    }

    func useLangchain() throws {
        var value = snapshot; value.engine = .langchain; try persist(value)
    }

    func select(_ id: UUID) throws {
        guard let profile = profiles.first(where: { $0.id == id }) else { throw AIModelConfigurationError.missingModel }
        _ = try profile.validated(key: key(for: id))
        var value = snapshot; value.engine = .langchain; value.selectedID = id; try persist(value)
    }

    func delete(_ id: UUID) throws {
        var value = snapshot; value.profiles.removeAll { $0.id == id }
        if value.selectedID == id {
            value.selectedID = value.profiles.first?.id
        }
        // Remove the credential before publishing the successful deletion. If
        // metadata cannot be saved, restore it so the previous model still works.
        let oldKey = try credentials.read(id)
        try credentials.write(nil, for: id)
        do { try persist(value) }
        catch { try? credentials.write(oldKey, for: id); throw error }
    }

    func request() throws -> AITextModelRequest? {
        guard engine == .langchain else { return nil }
        guard let profile = profiles.first(where: { $0.id == selectedID }) else { throw AIModelConfigurationError.missingModel }
        return try Self.request(profile: profile, key: key(for: profile.id))
    }

    static func request(profile: AIModelProfile, key: String) throws -> AITextModelRequest {
        AITextModelRequest(profile: try profile.validated(key: key), key: key.trimmingCharacters(in: .whitespacesAndNewlines))
    }

    func test(_ profile: AIModelProfile, key: String, backend: AIBackendBridge = .shared) async throws {
        struct Result: Decodable { let success: Bool }
        let request = try Self.request(profile: profile, key: key)
        var config = request.configuration
        config["ai_timeout_seconds"] = 25
        config["ai_max_output_tokens"] = min(profile.maxOutputTokens, 512)
        let params: [String: Any] = ["engine": "langchain", "configuration": config]
        let value: Result = try await backend.call("model.test", params: params, timeout: 30)
        guard value.success else { throw AIBackendError.invalidResponse }
    }

    private func persist(_ value: Snapshot) throws {
        if let loadError { throw AIModelConfigurationError.invalid(loadError) }
        try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        try writeFile(JSONEncoder().encode(value), file)
        snapshot = value
    }
}
