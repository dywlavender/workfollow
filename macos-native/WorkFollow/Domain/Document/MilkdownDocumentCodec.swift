import Foundation

/// The editor wire format is independent from NativeDocument's persisted Delta.
/// Large attachment/drawing payloads stay in the native asset registry.
struct MilkdownDocument: Codable, Equatable {
    var blocks: [Block]
    struct Block: Codable, Equatable {
        var id: UUID
        var kind: String
        var level: Int?
        var checked: Bool?
        var runs: [Run]
        var indentLevel: Int
        var listStart: Int?
        var align: DocumentAlignment?
        var bodySize: DocumentBodySize?
        var checklist: ChecklistItemMeta?
    }
    struct Run: Codable, Equatable {
        var text: String
        var marks: [Mark]
        var embed: Embed?
    }
    struct Mark: Codable, Equatable {
        var type: String
        var value: String?
    }
    struct Embed: Codable, Equatable {
        var type: String
        var id: UUID
        var name: String?
        var src: String?
        var assetKey: UUID?
        var image: Bool?
        var width: Double?
        var height: Double?
        var rows: [[String]]?
        var latex: String?
    }
}

struct MilkdownDocumentCodec {
    private(set) var assets: [UUID: DocumentRun] = [:]
    private var payloads: [UUID: DocumentRun] = [:]
    private var latestKeys: [UUID: UUID] = [:]
    var assetURL: (UUID) -> String = { "workfollow-milkdown://editor/asset/\($0.uuidString)" }

    func asset(_ id: UUID) -> DocumentRun? { payloads[id] ?? assets[id] }
    private mutating func assetKey(_ id: UUID, run: DocumentRun) -> UUID {
        if let key = latestKeys[id], payloads[key] == run { return key }
        let key = UUID()
        payloads[key] = run; assets[id] = run; latestKeys[id] = key
        return key
    }

    mutating func encode(_ source: NativeDocument) throws -> MilkdownDocument {
        let source = try source.materialized()
        return MilkdownDocument(blocks: source.blocks.map { block in
            let kind: String, level: Int?, checked: Bool?
            switch block.kind {
            case .paragraph: (kind, level, checked) = ("paragraph", nil, nil)
            case .heading(let value): (kind, level, checked) = ("heading", value, nil)
            case .bullet: (kind, level, checked) = ("bullet", nil, nil)
            case .ordered: (kind, level, checked) = ("ordered", nil, nil)
            case .checklist(let value): (kind, level, checked) = ("checklist", nil, value)
            case .quote: (kind, level, checked) = ("quote", nil, nil)
            case .code: (kind, level, checked) = ("code", nil, nil)
            case .divider: (kind, level, checked) = ("divider", nil, nil)
            }
            return MilkdownDocument.Block(id: block.id, kind: kind, level: level, checked: checked,
                runs: block.runs.map { run in
                    var embed: MilkdownDocument.Embed?
                    if let file = run.attachment {
                        let key = assetKey(file.id, run: run)
                        embed = .init(type: "attachment", id: file.id, name: file.name, src: assetURL(key), assetKey: key, image: file.isInlineImage,
                            width: file.displayWidth, height: file.displayHeight)
                    } else if let drawing = run.diagram {
                        let key = assetKey(drawing.id, run: run)
                        embed = .init(type: "diagram", id: drawing.id, name: drawing.title, src: assetURL(key), assetKey: key)
                    } else if let table = run.table {
                        assets[table.id] = run
                        embed = .init(type: "table", id: table.id, rows: table.rows)
                    } else if let formula = run.formula {
                        assets[formula.id] = run
                        embed = .init(type: "formula", id: formula.id, latex: formula.latex)
                    }
                    return .init(text: run.text, marks: run.marks.map(Self.encodeMark).sorted {
                        ($0.type + ($0.value ?? "")) < ($1.type + ($1.value ?? ""))
                    }, embed: embed)
                }, indentLevel: block.indentLevel, listStart: block.listStart, align: block.align,
                bodySize: block.bodySize, checklist: block.checklist)
        })
    }

    func decode(_ wire: MilkdownDocument) throws -> NativeDocument {
        NativeDocument(blocks: try wire.blocks.map { try decodeBlock($0) })
    }

    /// 块级解码：增量提交只过桥变化块，按块解码后由视图层按 order 重组。
    func decodeBlock(_ block: MilkdownDocument.Block) throws -> DocumentBlock {
        let kind: DocumentBlockKind
        switch block.kind {
        case "paragraph": kind = .paragraph
        case "heading": kind = .heading(min(6, max(1, block.level ?? 1)))
        case "bullet": kind = .bullet
        case "ordered": kind = .ordered
        case "checklist": kind = .checklist(block.checked ?? false)
        case "quote": kind = .quote
        case "code": kind = .code
        case "divider": kind = .divider
        default: throw Failure.unsupportedBlock
        }
        return DocumentBlock(id: block.id, kind: kind, runs: try block.runs.map { run in
            var result = DocumentRun(text: run.text, marks: Set(try run.marks.map(Self.decodeMark)))
            if let embed = run.embed {
                switch embed.type {
                case "attachment":
                    guard var file = asset(embed.assetKey ?? embed.id)?.attachment else { throw Failure.missingAsset }
                    file.displayWidth = embed.width; file.displayHeight = embed.height
                    result.attachment = file
                case "diagram":
                    guard var drawing = asset(embed.assetKey ?? embed.id)?.diagram else { throw Failure.missingAsset }
                    if let name = embed.name { drawing.title = name }
                    result.diagram = drawing
                case "table": result.table = NativeTable(id: embed.id, rows: embed.rows ?? [])
                case "formula": result.formula = NativeFormula(id: embed.id, latex: embed.latex ?? "")
                default: throw Failure.missingAsset
                }
            }
            return result
        }, indentLevel: block.indentLevel, listStart: block.listStart, align: block.align,
            bodySize: block.bodySize, checklist: block.checklist)
    }

    static func encodeMark(_ mark: DocumentMark) -> MilkdownDocument.Mark {
        switch mark {
        case .bold: .init(type: "bold")
        case .italic: .init(type: "italic")
        case .underline: .init(type: "underline")
        case .highlight: .init(type: "highlight")
        case .strikethrough: .init(type: "strikethrough")
        case .code: .init(type: "code")
        case .link(let url): .init(type: "link", value: url)
        case .muted: .init(type: "muted")
        case .caption: .init(type: "caption")
        case .symbol(let symbol): .init(type: "symbol", value: symbol.rawValue)
        case .ink(let ink): .init(type: "ink", value: ink.token)
        case .textColor(let value): .init(type: "textColor", value: value)
        case .highlightColor(let value): .init(type: "highlightColor", value: value)
        }
    }
    static func decodeMark(_ mark: MilkdownDocument.Mark) throws -> DocumentMark {
        switch mark.type {
        case "bold": return .bold
        case "italic": return .italic
        case "underline": return .underline
        case "highlight": return .highlight
        case "strikethrough": return .strikethrough
        case "code": return .code
        case "link": return .link(mark.value ?? "")
        case "muted": return .muted
        case "caption": return .caption
        case "symbol":
            guard let value = mark.value.flatMap(DocumentInlineSymbol.init(rawValue:)) else { throw Failure.unsupportedMark }
            return .symbol(value)
        case "ink":
            guard let value = mark.value.flatMap(DocumentInk.init(token:)) else { throw Failure.unsupportedMark }
            return .ink(value)
        case "textColor": return .textColor(mark.value ?? "")
        case "highlightColor": return .highlightColor(mark.value ?? "")
        default: throw Failure.unsupportedMark
        }
    }
    enum Failure: LocalizedError {
        case unsupportedBlock, unsupportedMark, missingAsset, missingBlock
        var errorDescription: String? { "编辑器内容无法完整读取，已保留原文。" }
    }
}
