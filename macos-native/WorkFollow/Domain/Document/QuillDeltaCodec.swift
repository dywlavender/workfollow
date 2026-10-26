import Foundation

/// `NativeDocument`（块/行/标记模型）↔ Quill Delta 的双向转换器。
///
/// 映射口径（与内核桥、Flutter `workfollow-block` embed 对齐）：
/// - 块级格式挂换行 op：header:N / list:bullet|ordered|unchecked|checked /
///   blockquote:true / code-block:true；`wf-block-id` 保有块 UUID（往返稳定）。
/// - 行内标记：bold/italic/underline/strike/code/`background`(高亮)/link(url)。
/// - 块 embed：`{workfollow-block: {type: divider|attachment|diagram, …}}`；
///   附件带 id/name/storedName，流程图带 id/title/xml/png(base64)。
/// - 相邻同属性文本在内核里自然合并（Quill 规范式），解码按 op 逐条还原 run。
///
/// 解码宽容：未知属性忽略、未知 embed 降级为占位文本，内核升级不炸旧档。
enum QuillDeltaCodec {
    static let highlightBackground = "#ffe98a"
    static let embedKey = "workfollow-block"

    // MARK: - NativeDocument → Delta

    static func delta(from document: NativeDocument) -> [QuillDeltaOp] {
        document.blocks.flatMap(blockOps)
    }

    /// 与 `NativeDocument.plainText` 同口径的投影：embed 计入 U+FFFC，
    /// 换行按 op 原样——列表预览/搜索/小组件读这份，不经过块模型。
    static func plainText(of ops: [QuillDeltaOp]) -> String {
        var joined = ops.map { op -> String in
            if let text = op.insert.stringValue { return text }
            return "\u{FFFC}"
        }.joined()
        // Quill 的换行 op 恒带一个结尾 \n；块模型的 plainText 无尾换行。
        // 投影对齐块模型口径（桥在持久化时同样按此 trim）。
        if joined.hasSuffix("\n") { joined.removeLast() }
        return joined
    }

    private static func blockOps(block: DocumentBlock) -> [QuillDeltaOp] {
        var ops: [QuillDeltaOp] = []
        if case .divider = block.kind {
            ops.append(QuillDeltaOp(insert: .object([embedKey: .object(["type": .string("divider")])])))
        } else {
            for run in block.runs {
                ops.append(contentsOf: runOps(run, blockKind: block.kind))
            }
        }
        // 换行 op 承载块格式；空块（无 run）也由它落位。
        ops.append(QuillDeltaOp(insert: .string("\n"), attributes: lineAttributes(of: block)))
        return ops
    }

    private static func lineAttributes(of block: DocumentBlock) -> [String: JSONValue] {
        var attributes: [String: JSONValue] = ["wf-block-id": .string(block.id.uuidString)]
        if block.indentLevel > 0 { attributes["indent"] = .number(Double(block.indentLevel)) }
        if let start = block.listStart { attributes["wf-list-start"] = .number(Double(start)) }
        if let checklist = block.checklist {
            if let completedAt = checklist.completedAt {
                attributes["wf-checklist-completed-at"] = .number(Self.milliseconds(completedAt))
            }
            if let reminderAt = checklist.reminderAt {
                attributes["wf-checklist-reminder-at"] = .number(Self.milliseconds(reminderAt))
            }
            if checklist.allDay { attributes["wf-checklist-all-day"] = .bool(true) }
        }
        switch block.kind {
        case .paragraph, .divider: break
        case .heading(let level): attributes["header"] = .number(Double(level))
        case .bullet: attributes["list"] = .string("bullet")
        case .ordered: attributes["list"] = .string("ordered")
        case .checklist(let checked): attributes["list"] = .string(checked ? "checked" : "unchecked")
        case .quote: attributes["blockquote"] = .bool(true)
        case .code: attributes["code-block"] = .bool(true)
        }
        return attributes
    }

    private static func runOps(_ run: DocumentRun, blockKind: DocumentBlockKind) -> [QuillDeltaOp] {
        var ops: [QuillDeltaOp] = []
        if let attachment = run.attachment {
            ops.append(QuillDeltaOp(insert: .object([embedKey: .object([
                "type": .string("attachment"),
                "id": .string(attachment.id.uuidString),
                "name": .string(attachment.name),
                "storedName": .string(attachment.storedName)
            ])])))
        }
        if let diagram = run.diagram {
            ops.append(QuillDeltaOp(insert: .object([embedKey: .object([
                "type": .string("diagram"),
                "id": .string(diagram.id.uuidString),
                "title": .string(diagram.title),
                "xml": .string(diagram.xml),
                "png": .string(diagram.previewPNG.base64EncodedString())
            ])])))
        }
        guard !run.text.isEmpty, run.text != "\u{FFFC}" || (run.attachment == nil && run.diagram == nil) else {
            return ops
        }
        var attributes: [String: JSONValue] = [:]
        for mark in run.marks {
            switch mark {
            case .bold: attributes["bold"] = .bool(true)
            case .italic: attributes["italic"] = .bool(true)
            case .underline: attributes["underline"] = .bool(true)
            case .strikethrough: attributes["strike"] = .bool(true)
            case .highlight: attributes["background"] = .string(highlightBackground)
            case .code: attributes["code"] = .bool(true)
            case .link(let url): attributes["link"] = .string(url)
            }
        }
        // 代码块里的行内标记按 Quill 语义保持纯文本。
        if case .code = blockKind { attributes.removeAll() }
        ops.append(QuillDeltaOp(insert: .string(run.text),
                                 attributes: attributes.isEmpty ? nil : attributes))
        return ops
    }

    // MARK: - Delta → NativeDocument

    static func document(from ops: [QuillDeltaOp]) -> NativeDocument {
        var blocks: [DocumentBlock] = []
        var currentRuns: [DocumentRun] = []
        /// divider 的 embed 已见、等它的换行 op 一起成块（id 取换行携带的 wf-block-id）。
        var pendingDivider = false

        func closeBlock(newlineAttributes: [String: JSONValue]?) {
            let attributes = newlineAttributes ?? [:]
            if pendingDivider {
                pendingDivider = false
                blocks.append(DocumentBlock(id: blockID(from: attributes), kind: .divider,
                                            runs: [DocumentRun(text: "\u{FFFC}")]))
                currentRuns = []
                return
            }
            // 空行规范：与 `NativeDocument(plainText:)` 同口径——空段落持有一个
            // 空文本 run（而不是零个 run），往返比较才稳定。
            if currentRuns.isEmpty { currentRuns = [DocumentRun(text: "")] }
            blocks.append(DocumentBlock(id: blockID(from: attributes),
                                        kind: blockKind(from: attributes),
                                        runs: currentRuns,
                                        indentLevel: attributes["indent"]?.intValue ?? 0,
                                        listStart: attributes["wf-list-start"]?.intValue,
                                        checklist: checklistMeta(from: attributes)))
            currentRuns = []
        }

        for op in ops {
            if let text = op.insert.stringValue {
                var remainder = text
                while let newline = remainder.firstIndex(of: "\n") {
                    let head = String(remainder[..<newline])
                    remainder = String(remainder[remainder.index(after: newline)...])
                    if !head.isEmpty {
                        currentRuns.append(run(text: head, attributes: op.attributes))
                    }
                    closeBlock(newlineAttributes: op.attributes)
                }
                if !remainder.isEmpty {
                    currentRuns.append(run(text: remainder, attributes: op.attributes))
                }
            } else if let embed = op.insert.objectValue {
                if let blockEmbed = embed[embedKey]?.objectValue,
                   let type = blockEmbed["type"]?.stringValue {
                    switch type {
                    case "divider":
                        pendingDivider = true
                    case "attachment":
                        currentRuns.append(attachmentRun(from: blockEmbed))
                    case "diagram":
                        currentRuns.append(diagramRun(from: blockEmbed))
                    default:
                        currentRuns.append(DocumentRun(text: "[\(type)]"))
                    }
                } else if let source = embed["image"]?.stringValue,
                          source.hasPrefix("data:image/") {
                    // Quill's standard image embed predates our custom block
                    // embed. Preserve its inline bytes when opening old notes.
                    let attachment = NativeAttachment(id: UUID(), name: "图片",
                                                      storedName: source)
                    currentRuns.append(DocumentRun(text: "\u{FFFC}", attachment: attachment))
                } else if let source = embed["image"]?.stringValue {
                    currentRuns.append(DocumentRun(text: "图片", marks: [.link(source)]))
                } else {
                    currentRuns.append(DocumentRun(text: "[块]"))
                }
            }
        }
        if pendingDivider || !currentRuns.isEmpty {
            closeBlock(newlineAttributes: nil)
        }
        if blocks.isEmpty { blocks = [DocumentBlock(kind: .paragraph)] }
        return NativeDocument(blocks: blocks)
    }

    // MARK: - run / 块的还原

    private static func run(text: String, attributes: [String: JSONValue]?) -> DocumentRun {
        var marks = Set<DocumentMark>()
        if let attributes {
            for (key, value) in attributes {
                switch key {
                case "bold" where value.boolValue == true: marks.insert(.bold)
                case "italic" where value.boolValue == true: marks.insert(.italic)
                case "underline" where value.boolValue == true: marks.insert(.underline)
                case "strike" where value.boolValue == true: marks.insert(.strikethrough)
                case "code" where value.boolValue == true: marks.insert(.code)
                case "background": marks.insert(.highlight)
                case "link": if let url = value.stringValue { marks.insert(.link(url)) }
                default: break
                }
            }
        }
        return DocumentRun(text: text, marks: marks)
    }

    private static func attachmentRun(from embed: [String: JSONValue]) -> DocumentRun {
        let id = embed["id"]?.stringValue.flatMap(UUID.init(uuidString:)) ?? UUID()
        return DocumentRun(text: "\u{FFFC}", attachment: NativeAttachment(
            id: id,
            name: embed["name"]?.stringValue ?? "附件",
            storedName: embed["storedName"]?.stringValue ?? ""))
    }

    private static func diagramRun(from embed: [String: JSONValue]) -> DocumentRun {
        let id = embed["id"]?.stringValue.flatMap(UUID.init(uuidString:)) ?? UUID()
        let png = embed["png"]?.stringValue.flatMap { Data(base64Encoded: $0) } ?? Data()
        return DocumentRun(text: "\u{FFFC}", diagram: NativeDiagram(
            id: id,
            title: embed["title"]?.stringValue ?? "未命名流程图",
            xml: embed["xml"]?.stringValue ?? "",
            previewPNG: png))
    }

    private static func blockKind(from attributes: [String: JSONValue]) -> DocumentBlockKind {
        if let header = attributes["header"]?.intValue { return .heading(max(1, min(6, header))) }
        switch attributes["list"]?.stringValue {
        case "bullet": return .bullet
        case "ordered": return .ordered
        case "unchecked": return .checklist(false)
        case "checked": return .checklist(true)
        default: break
        }
        if attributes["blockquote"]?.boolValue == true { return .quote }
        if attributes["code-block"]?.boolValue == true { return .code }
        return .paragraph
    }

    private static func blockID(from attributes: [String: JSONValue]) -> UUID {
        attributes["wf-block-id"]?.stringValue.flatMap(UUID.init(uuidString:)) ?? UUID()
    }

    private static func milliseconds(_ date: Date) -> Double {
        (date.timeIntervalSince1970 * 1000).rounded()
    }

    private static func checklistMeta(from attributes: [String: JSONValue]) -> ChecklistItemMeta? {
        let completedAt = attributes["wf-checklist-completed-at"]?.doubleValue
            .map { Date(timeIntervalSince1970: $0 / 1000) }
        let reminderAt = attributes["wf-checklist-reminder-at"]?.doubleValue
            .map { Date(timeIntervalSince1970: $0 / 1000) }
        let allDay = attributes["wf-checklist-all-day"]?.boolValue == true
        guard completedAt != nil || reminderAt != nil else { return nil }
        return ChecklistItemMeta(completedAt: completedAt, reminderAt: reminderAt, allDay: allDay)
    }
}
