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
        case .invalidResponse: "Pi 未返回模型列表，请确认 Pi 已配置模型并完成登录后刷新。"
        }
    }
}

struct PiModelCatalogClient {
    var timeout: TimeInterval = 15

    func fetch(executable: String) async throws -> [PiModelChoice] {
        let control = PiProcessControl()
        return try await withTaskCancellationHandler {
            try _Concurrency.Task.checkCancellation()
            return try await _Concurrency.Task.detached(priority: .utility) {
                try run(executable: executable, control: control)
            }.value
        } onCancel: { control.cancel() }
    }

    private func run(executable: String, control: PiProcessControl) throws -> [PiModelChoice] {
        guard FileManager.default.isExecutableFile(atPath: executable) else { throw PiModelCatalogError.unavailable }
        let process = Process(), input = Pipe(), output = Pipe()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = ["--mode", "rpc", "--no-session", "--no-tools", "--no-extensions",
            "--no-skills", "--no-prompt-templates", "--no-context-files", "--offline"]
        var environment = ProcessInfo.processInfo.environment
        environment["PATH"] = "/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:" + (environment["PATH"] ?? "")
        process.environment = environment
        process.currentDirectoryURL = FileManager.default.temporaryDirectory
        process.standardInput = input; process.standardOutput = output; process.standardError = FileHandle.nullDevice
        try control.start(process)
        let deadline = Date().addingTimeInterval(timeout)
        let timer = DispatchWorkItem { control.cancel() }
        DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + timeout, execute: timer)
        defer {
            timer.cancel()
            try? input.fileHandleForWriting.close()
            if process.isRunning { process.terminate() }
            process.waitUntilExit()
            try? output.fileHandleForReading.close()
        }
        let command = Data(#"{"id":"workfollow-models","type":"get_available_models"}"#.utf8) + Data([10])
        try input.fileHandleForWriting.write(contentsOf: command)
        var buffer = Data()
        while true {
            let bytes = output.fileHandleForReading.availableData
            if bytes.isEmpty { break }
            buffer.append(bytes)
            while let newline = buffer.firstIndex(of: 10) {
                let line = Data(buffer[..<newline]); buffer.removeSubrange(...newline)
                if let models = try Self.models(from: line) { return models }
            }
        }
        if Date() >= deadline { throw PiModelCatalogError.timedOut }
        if control.isCancelled { throw CancellationError() }
        throw PiModelCatalogError.invalidResponse
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
