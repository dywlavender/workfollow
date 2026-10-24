import Foundation

struct NativeDocument: Equatable, Codable {
    private var storedBlocks: [DocumentBlock]
    private var deferred: DeferredDocument?
    var blocks: [DocumentBlock] {
        get { deferred?.displayBlocks() ?? storedBlocks }
        set {
            if let deferred, (try? deferred.resolve()) == nil { return }
            storedBlocks = newValue; deferred = nil
        }
    }
    var isLoaded: Bool { deferred?.isLoaded ?? true }
    var loadError: Error? { deferred?.loadError }
    var firstLinePreview: String? { deferred?.summary.firstLine }
    var previewText: String { deferred?.summary.head ?? String(plainText.prefix(160)) }

    /// 未水合时的正文摘要（head / tail / firstLine）。
    /// 读它**不会**触发正文加载，适合搜索、列表这类高频路径。
    /// 已水合或本来就是内存文档时为 nil。
    var deferredSummary: DocumentSummary? { deferred?.summary }

    init(deferred: DeferredDocument) { storedBlocks = []; self.deferred = deferred }
    func materialized() throws -> NativeDocument { try deferred?.resolve() ?? self }
    /// 持久化形态（2026-10-24 内核切换决策）：`{ops, plainText}`——Delta 是真源，
    /// 块模型只是内存投影。**旧档 `{blocks}` 仍可读**（读入即转换，下次保存落新形态）。
    private enum CodingKeys: String, CodingKey { case blocks, ops, plainText }
    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        if let ops = try? values.decode([QuillDeltaOp].self, forKey: .ops) {
            storedBlocks = QuillDeltaCodec.document(from: ops).blocks
        } else {
            storedBlocks = try values.decode([DocumentBlock].self, forKey: .blocks)
        }
    }
    func encode(to encoder: Encoder) throws {
        let document = try materialized()
        var values = encoder.container(keyedBy: CodingKeys.self)
        try values.encode(QuillDeltaCodec.delta(from: document), forKey: .ops)
        try values.encode(document.plainText, forKey: .plainText)
    }
    static func == (lhs: NativeDocument, rhs: NativeDocument) -> Bool {
        if let left = lhs.deferred, left === rhs.deferred { return true }
        guard let left = try? lhs.materialized(), let right = try? rhs.materialized() else { return false }
        return left.storedBlocks == right.storedBlocks
    }
    func matches(_ query: String, prefix: String = "", suffix: String = "", lowercase: Bool = false) -> Bool {
        func contains(_ text: String) -> Bool {
            lowercase ? text.localizedLowercase.contains(query) : text.localizedCaseInsensitiveContains(query)
        }
        guard let deferred, !deferred.isLoaded, query.count <= 160 else {
            return contains(prefix + plainText + suffix)
        }
        let summary = deferred.summary
        if summary.length <= 160 { return contains(prefix + summary.head + suffix) }
        return contains(prefix + summary.head) || contains(summary.tail + suffix) || deferred.matches(query, lowercase: lowercase)
    }

    static var empty: NativeDocument { NativeDocument(plainText: "") }

    init(blocks: [DocumentBlock]) {
        self.storedBlocks = blocks.isEmpty ? [DocumentBlock(kind: .paragraph)] : blocks
    }

    init(plainText: String) {
        let normalized = plainText
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
        self.storedBlocks = normalized.components(separatedBy: "\n").map {
            DocumentBlock(kind: .paragraph, runs: [DocumentRun(text: $0)])
        }
    }

    var plainText: String { blocks.map(\.plainText).joined(separator: "\n") }
    var isEmpty: Bool { deferred?.summary.isEmpty ?? (blocks.count == 1 && blocks[0].plainText.isEmpty) }

    /// Rebuilds the first-version paragraph model while retaining IDs for lines
    /// that stayed in place or moved outside the edited span.
    func replacingPlainText(_ text: String) -> NativeDocument {
        let normalized = text
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
        let newLines = normalized.components(separatedBy: "\n")
        let oldLines = blocks.map(\.plainText)
        var ids = Array<UUID?>(repeating: nil, count: newLines.count)

        var prefix = 0
        while prefix < min(oldLines.count, newLines.count),
              oldLines[prefix] == newLines[prefix] {
            ids[prefix] = blocks[prefix].id
            prefix += 1
        }

        var oldSuffix = oldLines.count
        var newSuffix = newLines.count
        while oldSuffix > prefix, newSuffix > prefix,
              oldLines[oldSuffix - 1] == newLines[newSuffix - 1] {
            oldSuffix -= 1
            newSuffix -= 1
            ids[newSuffix] = blocks[oldSuffix].id
        }

        let oldEditedCount = oldSuffix - prefix
        let newEditedCount = newSuffix - prefix
        for offset in 0..<min(oldEditedCount, newEditedCount) {
            ids[prefix + offset] = blocks[prefix + offset].id
        }

        let newBlocks = newLines.enumerated().map { index, line in
            DocumentBlock(id: ids[index] ?? UUID(), kind: .paragraph,
                          runs: [DocumentRun(text: line)])
        }
        return NativeDocument(blocks: newBlocks)
    }
}

struct DocumentBlock: Identifiable, Equatable, Codable {
    let id: UUID
    var kind: DocumentBlockKind
    var runs: [DocumentRun]

    init(id: UUID = UUID(), kind: DocumentBlockKind, runs: [DocumentRun] = []) {
        self.id = id
        self.kind = kind
        self.runs = runs
    }

    var plainText: String { runs.map(\.text).joined() }
}

enum DocumentBlockKind: Equatable, Codable {
    case paragraph
    case heading(Int)
    case bullet
    case ordered
    case checklist(Bool)
    case quote
    case code
    case divider
}

struct DocumentRun: Equatable, Codable {
    var text: String
    var marks: Set<DocumentMark>
    var attachment: NativeAttachment?
    var diagram: NativeDiagram?

    init(text: String, marks: Set<DocumentMark> = [], attachment: NativeAttachment? = nil,
         diagram: NativeDiagram? = nil) {
        self.text = text
        self.marks = marks
        self.attachment = attachment
        self.diagram = diagram
    }
}

enum DocumentMark: Hashable, Codable {
    case bold
    case italic
    case underline
    case highlight
    case strikethrough
    case code
    case link(String)
}
