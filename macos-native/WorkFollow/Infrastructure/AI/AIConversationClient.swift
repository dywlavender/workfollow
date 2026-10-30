import Foundation

/// The UI never rebuilds Pi history. The session file belongs to the App's data directory.
struct AIConversationClient {
    var backend: AIBackendBridge = .shared
    var executable = ""
    var model = ""
    var directory: URL
    var appURL: URL = Bundle.main.bundleURL

    func checkConfiguration() async throws -> [AIConfigurationCheck] {
        struct Response: Decodable { let checks: [AIConfigurationCheck] }
        let result: Response = try await backend.call("configuration.check", params: [
            "piExecutable": executable, "model": model,
            "workfollowCLI": appURL.appendingPathComponent("Contents/MacOS/workfollowctl").path,
            "workfollowSkill": appURL.appendingPathComponent("Contents/Resources/Skills/workfollow-cli/SKILL.md").path,
            "workfollowApp": appURL.path
        ], timeout: 65)
        return result.checks
    }

    func delete(id: UUID) async throws {
        struct Response: Decodable { let deleted: Bool }
        let _: Response = try await backend.call("conversation.delete", params: [
            "conversationID": id.uuidString, "sessionDirectory": directory.path
        ], timeout: 30)
    }

    func send(id: UUID, scene: AIConversationModel.Scene, context: String, message: String,
              attachments: [AIConversationAttachment] = [],
              preset: AIConversationPreset? = nil, source: AIConversationSource? = nil,
              updates: @escaping @Sendable (AITextUpdate) -> Void) async throws -> String {
        struct Response: Decodable { let text: String }
        var params: [String: Any] = [
            "conversationID": id.uuidString, "sessionDirectory": directory.path,
            "scene": scene.rawValue, "context": context, "message": message,
            "piExecutable": executable, "model": model, "engine": "pi", "timeoutSeconds": 120
        ]
        if !attachments.isEmpty { params["attachments"] = attachments.map(\.parameters) }
        if let preset { params["preset"] = preset.rawValue }
        if let source { params["source"] = source.parameters }
        do {
            params["workfollowCLI"] = appURL.appendingPathComponent("Contents/MacOS/workfollowctl").path
            params["workfollowSkill"] = appURL.appendingPathComponent("Contents/Resources/Skills/workfollow-cli/SKILL.md").path
            params["workfollowApp"] = appURL.path
            let day = DateFormatter(); day.calendar = Calendar(identifier: .gregorian)
            day.locale = Locale(identifier: "en_US_POSIX"); day.dateFormat = "yyyy-MM-dd HH:mm"
            params["localTime"] = day.string(from: Date()); params["timeZone"] = TimeZone.current.identifier
        }
        let response: Response = try await AITextStreamRequest.call(backend: backend, method: "conversation.send", params: params, updates: updates)
        return response.text
    }

    @MainActor
    func generator(for model: AIConversationModel) -> AIConversationModel.Generate {
        { id, scene, context, message, updates in
            try await send(id: id, scene: scene, context: context, message: message,
                attachments: model.submittedAttachments, preset: model.submittedPreset,
                source: model.submittedSource, updates: updates)
        }
    }
}

struct AIConfigurationCheck: Decodable, Identifiable {
    let name: String
    let ok: Bool
    let message: String
    var id: String { name }
}

enum AITextStreamRequest {
    static func call<T: Decodable>(backend: AIBackendBridge, method: String, params: [String: Any],
                                   updates: @escaping @Sendable (AITextUpdate) -> Void) async throws -> T {
        let channel = UUID().uuidString
        backend.subscribe(channel) { data in
            if let value = try? JSONDecoder().decode(AITextUpdate.self, from: data) { updates(value) }
        }
        defer { backend.unsubscribe(channel) }
        return try await backend.call(method, params: params.merging(["progressChannel": channel]) { _, new in new }, timeout: 605)
    }
}
