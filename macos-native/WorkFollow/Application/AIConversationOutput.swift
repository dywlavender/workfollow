import Foundation

enum AIConversationPreset: String, Codable {
    case extract, organize, polish
    var question: String {
        switch self {
        case .extract: "请从当前内容中提取明确的待办，先给出候选。"
        case .organize: "请把当前内容整理成清晰的要点。"
        case .polish: "请润色当前内容，保留原意和事实。"
        }
    }
}

struct AIConversationSource: Codable, Equatable {
    var id: UUID?
    var kind: String
    var title: String
    var content: String
    var parameters: [String: Any] {
        var values: [String: Any] = ["kind": kind, "title": title, "content": content]
        if let id { values["id"] = id.uuidString }
        return values
    }
}

struct AIConversationArtifact: Identifiable, Codable, Equatable {
    enum Kind: String, Codable { case tasks, writing }
    var id = UUID()
    var kind: Kind
    var content: String
    var adoption: String? = nil
}

/// Optional adoptable results accompany ordinary conversation; they never select the next turn's mode.
enum AIConversationOutput {
    struct Result { var text: String; var artifacts: [AIConversationArtifact] }
    static func preview(_ raw: String) -> String {
        // Do not expose a partial result payload while it is streaming.
        guard let start = raw.range(of: "```workfollow-") else { return raw }
        return String(raw[..<start.lowerBound]).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    static func decode(_ raw: String, preset: AIConversationPreset?) throws -> Result {
        let expression = try NSRegularExpression(pattern: #"(?ms)^```workfollow-(tasks|note)[ \t]*\r?\n(.*?)^```[ \t]*(?:\r?\n|$)"#)
        let source = raw as NSString
        let matches = expression.matches(in: raw, range: NSRange(location: 0, length: source.length))
        var artifacts: [AIConversationArtifact] = []
        for match in matches {
            let kind = source.substring(with: match.range(at: 1))
            let body = source.substring(with: match.range(at: 2)).trimmingCharacters(in: .whitespacesAndNewlines)
            if kind == "tasks" {
                guard let object = try? JSONSerialization.jsonObject(with: Data(body.utf8)) as? [String: Any],
                      object["tasks"] is [[String: Any]] else { throw SummaryPiError.failed("待办结果格式无效，请重试。") }
                artifacts.append(.init(kind: .tasks, content: body))
            } else {
                let object = try? JSONSerialization.jsonObject(with: Data(body.utf8)) as? [String: Any]
                let text = (object?["content"] as? String) ?? body
                guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { throw SummaryPiError.emptyResult }
                artifacts.append(.init(kind: .writing, content: text))
            }
        }
        let visible = NSMutableString(string: raw)
        for match in matches.reversed() { visible.deleteCharacters(in: match.range) }
        if !artifacts.isEmpty {
            return Result(text: (visible as String).trimmingCharacters(in: .whitespacesAndNewlines), artifacts: artifacts)
        }
        // Existing providers can still return a plain shortcut result. Free chat never takes this path.
        if preset == .extract {
            var json = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            if json.hasPrefix("```"), json.hasSuffix("```"), let line = json.firstIndex(of: "\n") {
                json = String(json[json.index(after: line)..<json.index(json.endIndex, offsetBy: -3)]).trimmingCharacters(in: .whitespacesAndNewlines)
            }
            guard let object = try? JSONSerialization.jsonObject(with: Data(json.utf8)) as? [String: Any],
                  object["tasks"] is [[String: Any]] else { throw SummaryPiError.failed("待办结果格式无效，请重试。") }
            return Result(text: "", artifacts: [.init(kind: .tasks, content: json)])
        }
        if preset == .organize || preset == .polish {
            return Result(text: "", artifacts: [.init(kind: .writing, content: raw)])
        }
        return Result(text: raw, artifacts: [])
    }
}

/// Transient surfaces receive the same native operation receipts as the persisted chat page.
@MainActor
final class AIConversationRegistry {
    static let shared = AIConversationRegistry()
    private final class Entry { weak var model: AIConversationModel?; init(_ model: AIConversationModel) { self.model = model } }
    private var models: [UUID: Entry] = [:]
    func register(_ model: AIConversationModel) {
        models = models.filter { $0.value.model != nil }
        models[model.record.id] = Entry(model)
    }
    func append(_ receipt: AIActionReceipt, id: UUID) -> Bool {
        guard let model = models[id]?.model else { return false }
        model.appendAction(receipt); return true
    }
    func markUndone(_ token: UUID) { for entry in models.values { entry.model?.markUndone(token) } }
}
