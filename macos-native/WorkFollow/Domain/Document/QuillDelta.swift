import Foundation

/// 与 JSON 一一对应的宽容值类型（Delta 的 insert/attributes 直接用它承载）。
/// 编码产出标准 JSON；解码接受任意 JSON——内核或迁移数据里的未知属性
/// 原样保留在树里，不丢信息。
enum JSONValue: Equatable, Hashable, Codable {
    case null
    case bool(Bool)
    case number(Double)
    case string(String)
    case array([JSONValue])
    case object([String: JSONValue])

    var stringValue: String? {
        if case .string(let value) = self { return value }
        return nil
    }

    var boolValue: Bool? {
        if case .bool(let value) = self { return value }
        return nil
    }

    var doubleValue: Double? {
        if case .number(let value) = self { return value }
        return nil
    }

    var intValue: Int? {
        doubleValue.flatMap(Int.init(exactly:))
    }

    var objectValue: [String: JSONValue]? {
        if case .object(let value) = self { return value }
        return nil
    }

    var arrayValue: [JSONValue]? {
        if case .array(let value) = self { return value }
        return nil
    }

    var isNull: Bool {
        if case .null = self { return true }
        return false
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() { self = .null }
        else if let value = try? container.decode(Bool.self) { self = .bool(value) }
        else if let value = try? container.decode(Double.self) { self = .number(value) }
        else if let value = try? container.decode(String.self) { self = .string(value) }
        else if let value = try? container.decode([JSONValue].self) { self = .array(value) }
        else if let value = try? container.decode([String: JSONValue].self) { self = .object(value) }
        else {
            throw DecodingError.dataCorruptedError(in: container,
                debugDescription: "不支持的 JSON 值")
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .null: try container.encodeNil()
        case .bool(let value): try container.encode(value)
        case .number(let value): try container.encode(value)
        case .string(let value): try container.encode(value)
        case .array(let value): try container.encode(value)
        case .object(let value): try container.encode(value)
        }
    }
}

/// Quill Delta 操作（编辑器内核的文档真源；2026-10-24 用户决策：持久化改存 Delta JSON）。
///
/// `insert` 为 `.string(文本)` 或 `.object(embed)`（`workfollow-block` /
/// `image` 等）；`attributes` 是行内标记（bold/italic/…/link）——
/// **块级格式挂在换行符那条 op 上**（Quill 语义：header/list/blockquote/
/// code-block），`wf-block-id` 用来在往返中保住块身份。
struct QuillDeltaOp: Equatable, Codable {
    var insert: JSONValue
    var attributes: [String: JSONValue]?

    init(insert: JSONValue, attributes: [String: JSONValue]? = nil) {
        self.insert = insert
        self.attributes = attributes
    }
}
