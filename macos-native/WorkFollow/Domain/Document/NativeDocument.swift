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

    /// 清单进度/提醒的快路径：延迟文档只读摘要；内存文档才从块计算。
    /// 不得为了拿摘要而调用 `materialized()`，否则列表会逐条水合正文。
    var checklistSummary: ChecklistSummary? {
        if let deferred { return deferred.summary.checklist }
        let summary = ChecklistSummary(blocks: storedBlocks)
        return summary.total > 0 ? summary : nil
    }

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

        let metadataByID = Dictionary(blocks.compactMap { block in
            block.checklist.map { (block.id, $0) }
        }, uniquingKeysWith: { first, _ in first })
        let newBlocks = newLines.enumerated().map { index, line in
            let id = ids[index] ?? UUID()
            return DocumentBlock(id: id, kind: .paragraph,
                                 runs: [DocumentRun(text: line)],
                                 checklist: metadataByID[id])
        }
        return NativeDocument(blocks: newBlocks)
    }
}

/// 检查事项的业务元数据。正文仍由 `DocumentBlock` 持有，这里只存完成时间
/// 与项级提醒；随 Delta 行属性 `wf-checklist-*` 往返，旧档缺键即 nil。
struct ChecklistItemMeta: Equatable, Codable {
    var completedAt: Date?
    var reminderAt: Date?
    var allDay: Bool

    init(completedAt: Date? = nil, reminderAt: Date? = nil, allDay: Bool = false) {
        self.completedAt = completedAt
        self.reminderAt = reminderAt
        self.allDay = allDay
    }

    var isEmpty: Bool { completedAt == nil && reminderAt == nil }

    private enum CodingKeys: String, CodingKey { case completedAt, reminderAt, allDay }
    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        completedAt = try values.decodeIfPresent(Date.self, forKey: .completedAt)
        reminderAt = try values.decodeIfPresent(Date.self, forKey: .reminderAt)
        allDay = try values.decodeIfPresent(Bool.self, forKey: .allDay) ?? false
    }
}

struct DocumentBlock: Identifiable, Equatable, Codable {
    let id: UUID
    var kind: DocumentBlockKind {
        didSet {
            if !kind.isList { indentLevel = 0 }
            if kind != .ordered { listStart = nil }
        }
    }
    var runs: [DocumentRun]
    var indentLevel: Int
    var listStart: Int?
    /// 检查项元数据。块换成普通段落/标题时保留，供切回清单时恢复。
    var checklist: ChecklistItemMeta?

    init(id: UUID = UUID(), kind: DocumentBlockKind, runs: [DocumentRun] = [],
         indentLevel: Int = 0, listStart: Int? = nil,
         checklist: ChecklistItemMeta? = nil) {
        self.id = id
        self.kind = kind
        self.runs = runs
        self.indentLevel = kind.isList ? min(8, max(0, indentLevel)) : 0
        self.listStart = kind == .ordered ? listStart.map { max(1, $0) } : nil
        self.checklist = checklist?.isEmpty == true ? nil : checklist
    }

    private enum CodingKeys: String, CodingKey { case id, kind, runs, indentLevel, listStart, checklist }
    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        self.init(id: try values.decode(UUID.self, forKey: .id),
                  kind: try values.decode(DocumentBlockKind.self, forKey: .kind),
                  runs: try values.decode([DocumentRun].self, forKey: .runs),
                  indentLevel: try values.decodeIfPresent(Int.self, forKey: .indentLevel) ?? 0,
                  listStart: try values.decodeIfPresent(Int.self, forKey: .listStart),
                  checklist: try values.decodeIfPresent(ChecklistItemMeta.self, forKey: .checklist))
    }
    func encode(to encoder: Encoder) throws {
        var values = encoder.container(keyedBy: CodingKeys.self)
        try values.encode(id, forKey: .id)
        try values.encode(kind, forKey: .kind)
        try values.encode(runs, forKey: .runs)
        if indentLevel > 0 { try values.encode(indentLevel, forKey: .indentLevel) }
        try values.encodeIfPresent(listStart, forKey: .listStart)
        try values.encodeIfPresent(checklist, forKey: .checklist)
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

    var isList: Bool {
        switch self {
        case .bullet, .ordered, .checklist: true
        default: false
        }
    }

    var isChecklist: Bool {
        if case .checklist = self { return true }
        return false
    }
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
