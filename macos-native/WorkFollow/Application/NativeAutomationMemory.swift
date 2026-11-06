import Foundation

extension NativeAutomationService {
    func executeMemory(_ request: AutomationRequest) throws -> AutomationValue? {
        guard request.operation.hasPrefix("memory.") else { return nil }
        let args = request.arguments
        func value(_ entry: AssistantMemory) -> AutomationValue {
            .object(["id": .string(entry.id.uuidString), "content": .string(entry.content),
                     "title": .string(entry.content), "version": .string(String(entry.version))])
        }
        if request.operation == "memory.list" {
            if let error = memories.storageError { throw AutomationFailure(code: "storage_unavailable", message: error) }
            return .array(memories.entries.map(value))
        }
        if request.operation == "memory.add" { return value(try memories.add(args["content"] ?? "")) }
        guard let raw = args["id"], let id = UUID(uuidString: raw),
              let revision = args["version"].flatMap(Int.init) else {
            throw AutomationFailure.argument("请先 memory list，再提供有效的 id 和 version。")
        }
        switch request.operation {
        case "memory.update": return value(try memories.update(id, version: revision, content: args["content"] ?? ""))
        case "memory.delete": return value(try memories.forget(id, version: revision))
        default: throw AutomationFailure.argument("未知助手记忆操作。")
        }
    }
}
