import Combine
import Foundation

struct AssistantMemory: Identifiable, Codable, Equatable, Sendable {
    var id = UUID()
    var content: String
    var version = 1

    var parameters: [String: String] { ["id": id.uuidString, "content": content] }
}

/// Personal preferences belong to the workspace, independently of Pi sessions.
/// Writes are small, explicit actions; publish only after the atomic save succeeds.
@MainActor
final class AssistantMemoryStore: ObservableObject {
    @Published private(set) var entries: [AssistantMemory] = []
    @Published private(set) var storageError: String?
    private let file: URL
    private let write: (Data, URL) throws -> Void

    init(directory: URL, write: @escaping (Data, URL) throws -> Void = { try $0.write(to: $1, options: .atomic) }) {
        file = directory.appendingPathComponent("assistant-memory.json")
        self.write = write
        if FileManager.default.fileExists(atPath: file.path) {
            do { entries = try JSONDecoder().decode([AssistantMemory].self, from: Data(contentsOf: file)) }
            catch { storageError = "助手记忆读取失败：" + error.localizedDescription }
        }
    }

    @discardableResult
    func add(_ content: String) throws -> AssistantMemory {
        let text = try normalized(content)
        if let existing = entries.first(where: { $0.content == text }) { return existing }
        let memory = AssistantMemory(content: text)
        try persist(entries + [memory])
        return memory
    }

    @discardableResult
    func update(_ id: UUID, version: Int, content: String) throws -> AssistantMemory {
        let index = try index(id, version: version)
        let text = try normalized(content)
        if entries[index].content == text { return entries[index] }
        var next = entries
        next[index].content = text; next[index].version += 1
        try persist(next)
        return next[index]
    }

    @discardableResult
    func forget(_ id: UUID, version: Int) throws -> AssistantMemory {
        let index = try index(id, version: version)
        let removed = entries[index]
        var next = entries; next.remove(at: index)
        try persist(next)
        return removed
    }

    private func index(_ id: UUID, version: Int) throws -> Int {
        guard let index = entries.firstIndex(where: { $0.id == id }) else {
            throw AutomationFailure(code: "not_found", message: "这条助手记忆已不存在。")
        }
        guard entries[index].version == version else {
            throw AutomationFailure(code: "version_conflict", message: "助手记忆已更新，请重新读取后再修改。")
        }
        return index
    }

    private func normalized(_ value: String) throws -> String {
        let text = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { throw AutomationFailure.argument("记忆内容不能为空。") }
        return text
    }

    private func persist(_ next: [AssistantMemory]) throws {
        // A load error must remain visible rather than replace an unreadable file.
        guard storageError == nil else { throw AutomationFailure(code: "storage_unavailable", message: storageError!) }
        try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        try write(JSONEncoder().encode(next), file)
        entries = next
    }
}
