import Foundation

enum AutomationValue: Codable, Equatable, Sendable {
    case object([String: AutomationValue]), array([AutomationValue]), string(String), number(Double), bool(Bool), null
    init(from decoder: Decoder) throws {
        let value = try decoder.singleValueContainer()
        if value.decodeNil() { self = .null }
        else if let item = try? value.decode(Bool.self) { self = .bool(item) }
        else if let item = try? value.decode(String.self) { self = .string(item) }
        else if let item = try? value.decode(Double.self) { self = .number(item) }
        else if let item = try? value.decode([AutomationValue].self) { self = .array(item) }
        else { self = .object(try value.decode([String: AutomationValue].self)) }
    }
    func encode(to encoder: Encoder) throws {
        var value = encoder.singleValueContainer()
        switch self {
        case let .object(item): try value.encode(item)
        case let .array(item): try value.encode(item)
        case let .string(item): try value.encode(item)
        case let .number(item): try value.encode(item)
        case let .bool(item): try value.encode(item)
        case .null: try value.encodeNil()
        }
    }
    subscript(_ key: String) -> AutomationValue? { if case let .object(items) = self { return items[key] }; return nil }
    var string: String? { if case let .string(value) = self { return value }; return nil }
}

struct AutomationFailure: Error, LocalizedError, Codable, Equatable, Sendable {
    let code: String
    let message: String
    var errorDescription: String? { message }
    static func argument(_ message: String) -> Self { Self(code: "invalid_argument", message: message) }
}

struct AutomationRequest: Codable, Sendable {
    var version = 1
    var id = UUID()
    let operation: String
    let arguments: [String: String]
    var conversationID: UUID? = nil
    var requestedAt = Date()
    var expiresAt = Date().addingTimeInterval(20)
}

struct AutomationResponse: Codable, Sendable {
    let requestID: UUID
    let ok: Bool
    var data: AutomationValue?
    var error: AutomationFailure?
    static func success(_ request: AutomationRequest, _ data: AutomationValue) -> Self {
        Self(requestID: request.id, ok: true, data: data)
    }
    static func failure(_ request: AutomationRequest, _ error: AutomationFailure) -> Self {
        Self(requestID: request.id, ok: false, error: error)
    }
}
