import AppKit

/// TextKit attributes are an editing projection, never the stored document.
enum DocumentTextCodec {
    static let blockKey = NSAttributedString.Key("WorkFollow.block")
    static let attachmentKey = NSAttributedString.Key("WorkFollow.attachment")
    static let diagramKey = NSAttributedString.Key("WorkFollow.diagram")
    static let tableKey = NSAttributedString.Key("WorkFollow.table")
    static let formulaKey = NSAttributedString.Key("WorkFollow.formula")
    static let inlineCodeKey = NSAttributedString.Key("WorkFollow.inlineCode")
    static let mutedKey = NSAttributedString.Key("WorkFollow.muted")
    static let captionKey = NSAttributedString.Key("WorkFollow.caption")
    static let symbolKey = NSAttributedString.Key("WorkFollow.inlineSymbol")
    static let inkKey = NSAttributedString.Key("WorkFollow.ink")
    static let explicitBoldKey = NSAttributedString.Key("WorkFollow.explicitBold")
    static let completedChecklistPresentationKey = NSAttributedString.Key("WorkFollow.completedChecklistPresentation")
    static let indentKey = NSAttributedString.Key("WorkFollow.listIndent")
    static let listStartKey = NSAttributedString.Key("WorkFollow.listStart")
    static let alignKey = NSAttributedString.Key("WorkFollow.alignment")
    static let bodySizeKey = NSAttributedString.Key("WorkFollow.bodySize")
    static let textColorKey = NSAttributedString.Key("WorkFollow.textColor")
    static let highlightColorKey = NSAttributedString.Key("WorkFollow.highlightColor")
    static func blockToken(_ kind: DocumentBlockKind) -> String {
        switch kind {
        case .paragraph: "paragraph"
        case .heading(let level): "h\(level)"
        case .bullet: "bullet"
        case .ordered: "ordered"
        case .checklist(let checked): checked ? "checked" : "checklist"
        case .quote: "quote"
        case .code: "code"
        case .divider: "divider"
        }
    }
    static func kind(_ token: String) -> DocumentBlockKind {
        if token.hasPrefix("h"), let level = Int(token.dropFirst()) { return .heading(level) }
        switch token {
        case "bullet": return .bullet
        case "ordered": return .ordered
        case "checklist": return .checklist(false)
        case "checked": return .checklist(true)
        case "quote": return .quote
        case "code": return .code
        case "divider": return .divider
        default: return .paragraph
        }
    }
    /// 读一段富文本的"段落类型 + 每个 run 都带的标记"，供工具条显示激活态。
    ///
    /// 与 `applyFormat` 走同一套解码口径，所以"工具条显示激活"与"再点一次会取消"
    /// 判断的是同一件事，不会出现按钮亮着却取消不掉的错位。
    static func style(of attributed: NSAttributedString) -> DocumentSelectionStyle {
        let document = decode(attributed, preserving: NativeDocument(plainText: attributed.string))
        let token = document.blocks.first.map { blockToken($0.kind) } ?? blockToken(.paragraph)
        var intersection: Set<DocumentMark>?
        for block in document.blocks {
            for run in block.runs {
                intersection = intersection.map { $0.intersection(run.marks) } ?? run.marks
            }
        }
        return DocumentSelectionStyle(blockToken: token, marks: intersection ?? [],
                                      indentLevel: document.blocks.first?.indentLevel ?? 0,
                                      align: document.blocks.first?.align,
                                      bodySize: document.blocks.first?.bodySize)
    }

    /// 有"行首标记"的段落类型（点列/编号/检查项）：缩进与标记都由视图层绘制。
    static func isListKind(_ kind: DocumentBlockKind) -> Bool {
        switch kind {
        case .bullet, .ordered, .checklist: return true
        default: return false
        }
    }

    /// 有序列表项的序号：向前数连续的 ordered 段（与原版 Quill 的编号口径一致，
    /// 中间断开就重新从 1 计）。
    static func ordinal(forOrderedParagraphAt location: Int, in source: NSAttributedString,
                        indentLevel: Int? = nil, listStart: Int? = nil) -> Int {
        let ns = source.string as NSString
        guard location >= 0, location <= ns.length else { return 1 }
        let currentAttributes = location < source.length
            ? source.attributes(at: max(0, location), effectiveRange: nil) : [:]
        let level = indentLevel ?? (currentAttributes[indentKey] as? Int ?? 0)
        if let start = listStart ?? (currentAttributes[listStartKey] as? Int) { return start }
        guard location > 0, location <= ns.length else { return 1 }
        var ordinal = 1
        var offset = location
        while offset > 0 {
            let paragraph = ns.paragraphRange(for: NSRange(location: offset - 1, length: 0))
            let attributes = source.attributes(at: paragraph.location, effectiveRange: nil)
            let kind = Self.kind(attributes[blockKey] as? String ?? "paragraph")
            let previousLevel = attributes[indentKey] as? Int ?? 0
            guard kind.isList, previousLevel >= level else { break }
            if previousLevel > level { offset = paragraph.location; continue }
            guard kind == .ordered else { break }
            if let start = attributes[listStartKey] as? Int { return start + ordinal }
            ordinal += 1
            offset = paragraph.location
        }
        return ordinal
    }

    static func attributes(kind: DocumentBlockKind, marks: Set<DocumentMark>,
                           indentLevel: Int = 0, listStart: Int? = nil,
                           align: DocumentAlignment? = nil,
                           bodySize: DocumentBodySize? = nil) -> [NSAttributedString.Key: Any] {
        let style = NSMutableParagraphStyle()
        let structured = kind == .quote || isListKind(kind)
        let isHeading: Bool = { if case .heading = kind { return true }; return false }()
        let isCode = kind == .code
        // 清单行的文字与滴答一样留出更松的上下间距；行距由 paragraphSpacing
        // 承担，不拉高单行字体行盒，避免光标与文字基线偏移。
        // 正文段后 10pt：Enter 换段与自动折行刻意拉开（ima 实测段距 5+5）；
        // 自动折行和软换行仍在同一段里，只走 21pt 行盒。标题保留 8pt 才能
        // 维持 35 / 32 / 30 的标题节距；列表/引用 2pt、清单 19pt 不变。
        // 代码块连续行之间不留段距，整块由背景绘制成一体。
        style.paragraphSpacing = kind.isChecklist ? DocumentEditorGeometry.checklistRowSpacing
            : (structured ? DocumentEditorGeometry.structuredParagraphSpacing
                : (isHeading ? 8 : (isCode ? 0 : 10)))
        // 字阶按滴答实测（2026-10-16，截图 1px = 1pt）：标题三级 18 / 16 / 14，正文 14。
        // 滴答的标题 3 到 6 是**同一个字号**（实测三级到六级墨水质量完全相同），
        // 只靠字重与段间距和正文区分，所以这里不再按级别继续收窄。
        // 正文 1/2/3 是用户显式选择的字号档位（12 / 16 / 18）。
        var size: CGFloat = DocumentEditorPresentationMetrics.bodyFontSize
        if marks.contains(.caption) { size = 12 }
        if case .heading(let level) = kind { size = level == 1 ? 18 : level == 2 ? 16 : 14 }
        if kind == .paragraph, let bodySize { size = bodySize.pointSize }
        if isCode { size = 13 }
        let checklistCompleted: Bool = { if case .checklist(true) = kind { return true }; return false }()
        var font: NSFont
        if isCode || marks.contains(.code) {
            font = NSFont.monospacedSystemFont(ofSize: size, weight: .regular)
        } else if isHeading {
            // 标题是**粗体**：滴答实测标题笔画宽/字高比 0.20（Bold 0.20、Medium 0.158），
            // 整行墨水质量也对上 Bold（18pt「H1」预测 102、实测 105）。
            font = NSFont.systemFont(ofSize: size, weight: .bold)
        } else {
            font = NSFont.systemFont(ofSize: size)
        }
        if marks.contains(.bold) { font = NSFontManager.shared.convert(font, toHaveTrait: .boldFontMask) }
        if marks.contains(.italic) { font = NSFontManager.shared.convert(font, toHaveTrait: .italicFontMask) }
        // 行盒按滴答实测：标题 1.6 倍字号（H1 28.8 / H2 25.6 / H3–H6 22.4，配 8pt 段间距
        // 得到段落基线间距 35 / 32 / 30）；列表与引用 18（配 2pt 段间距得 20）；正文 21
        // （1.5 倍字号，与原版 `lineBody` 一致）。系统字体的默认行高只有约 1.18 倍字号，
        // 缺口用 lineSpacing 补，避免把默认行高写死成某个系统版本的具体数字。
        // 代码块 22pt 行盒让等宽行更舒展，也给卡片底边留出内边距；正文档位按 1.5 倍字号缩放。
        let lineBox: CGFloat = isHeading ? 1.6 * size
            : (isCode ? 22 : (structured ? 18 : 1.5 * size))
        style.lineSpacing = max(0, lineBox - (font.ascender - font.descender + font.leading))
        // 所有段落统一留 20pt 行首沟槽：H 角标 / 空行"+"画在文字左侧的这段
        // 空白里（滴答同款视觉）。沟槽必须在文本容器**内**——NSTextView 把
        // 绘制裁剪到容器区域，靠 textContainerInset 留白会让装饰不可见。
        let gutter = DocumentEditorGeometry.decorationLane
        let levelIndent = CGFloat(max(0, indentLevel)) * DocumentEditorGeometry.listIndentStep
        if isCode {
            // 代码块左右各留 12pt：左侧行首沟槽之外再让出一块内边距，右侧用
            // 负 tailIndent 收窄折行宽度；背景由视图层按同一几何绘制。
            let inset = DocumentEditorGeometry.codeBlockTextInset
            style.firstLineHeadIndent = gutter + inset + levelIndent
            style.headIndent = style.firstLineHeadIndent
            style.tailIndent = -inset
        } else if kind == .quote {
            // 引用是"行首缩进 + 3pt 左竖线"的结构表达（竖线由视图层绘制，
            // 画在正文起点处）。文字转灰是对齐滴答截图的有意选择。
            style.headIndent = gutter + DocumentEditorGeometry.quoteTextIndent + levelIndent
            style.firstLineHeadIndent = style.headIndent
        } else if isListKind(kind) {
            // 列表缩进与标记**全部由视图层负责**：段落绝不挂 `textLists`——
            // macOS 14+ 的 TextKit 2 会自绘 NSTextList 标记并占用行首空间，
            // 与视图层画的强调色标记叠成"双点/1.1"（用户实测）。标记与段落
            // 文字左缘对齐（滴答实测，装饰层按 `lineRect.minX` 反推）。
            // 检查项的勾选框更宽，文字再多让 8pt。
            let listIndent = kind.isChecklist
                ? DocumentEditorGeometry.checklistTextIndent
                : DocumentEditorGeometry.listTextIndent
            style.firstLineHeadIndent = gutter + listIndent + levelIndent
            style.headIndent = style.firstLineHeadIndent
        } else {
            style.firstLineHeadIndent = gutter + levelIndent
            style.headIndent = style.firstLineHeadIndent
        }
        if marks.contains(.caption) {
            style.firstLineHeadIndent = gutter + DocumentEditorGeometry.listTextIndent + levelIndent
            style.headIndent = style.firstLineHeadIndent
            style.paragraphSpacing = 10
            style.lineSpacing = 3
        }
        if let align { style.alignment = align.nsAlignment }
        let baseForeground: NSColor = kind == .quote ? NSColor.secondaryLabelColor
            : checklistCompleted ? NSColor(WFColors.taskCompletedTitle)
            : NSColor.labelColor
        var attrs: [NSAttributedString.Key: Any] = [
            blockKey: blockToken(kind), explicitBoldKey: marks.contains(.bold), .font: font, .paragraphStyle: style,
            // 引用与已勾选检查项转灰：勾选后只变灰（与已完成任务同一档灰），
            // 不再加删除线——删除线由切回文本时的转换负责。
            .foregroundColor: baseForeground
        ]
        if indentLevel > 0 { attrs[indentKey] = max(0, min(8, indentLevel)) }
        if let align, align != .left { attrs[alignKey] = align.rawValue }
        if kind == .paragraph, let bodySize { attrs[bodySizeKey] = bodySize.rawValue }
        if kind == .ordered, let listStart { attrs[listStartKey] = max(1, listStart) }
        if marks.contains(.code) { attrs[inlineCodeKey] = true }
        if marks.contains(.underline) { attrs[.underlineStyle] = NSUnderlineStyle.single.rawValue }
        if marks.contains(.strikethrough) { attrs[.strikethroughStyle] = NSUnderlineStyle.single.rawValue }
        if marks.contains(.highlight) { attrs[.backgroundColor] = NSColor.systemYellow.withAlphaComponent(0.45) }
        for mark in marks { if case .link(let target) = mark { attrs[.link] = target } }
        if marks.contains(.muted) {
            attrs[mutedKey] = true
            if attrs[.link] == nil { attrs[.foregroundColor] = NSColor.secondaryLabelColor }
        }
        if marks.contains(.caption) { attrs[captionKey] = true }
        if let ink = marks.documentInk {
            attrs[inkKey] = ink.token
            attrs[.foregroundColor] = ink.nativeColor
        }
        // 用户颜色最后落，优先于引用灰、muted 与 ink 等展示色。
        if let hex = marks.textColorHex, let color = NSColor(documentHex: hex) {
            attrs[.foregroundColor] = color
            attrs[textColorKey] = hex
        }
        if let hex = marks.highlightHex, !marks.contains(.highlight),
           let color = NSColor(documentHex: hex) {
            attrs[.backgroundColor] = color
            attrs[highlightColorKey] = hex
        }
        for mark in marks {
            if case .symbol(let symbol) = mark { attrs[symbolKey] = symbol.rawValue }
        }
        return attrs
    }
    static func render(_ document: NativeDocument) -> NSAttributedString {
        let result = NSMutableAttributedString(string: "")
        for (index, block) in document.blocks.enumerated() {
            for run in block.runs {
                var attrs = attributes(kind: block.kind, marks: run.marks,
                                       indentLevel: block.indentLevel, listStart: block.listStart,
                                       align: block.align, bodySize: block.bodySize)
                if let name = attrs[symbolKey] as? String, let symbol = DocumentInlineSymbol(rawValue: name),
                   run.text == symbol.textFallback {
                    let attachment = NSTextAttachment()
                    attachment.attachmentCell = DocumentInlineSymbolCell(symbol: symbol,
                        tint: attrs[.foregroundColor] as? NSColor ?? .secondaryLabelColor)
                    attrs[.attachment] = attachment
                    result.append(NSAttributedString(string: "\u{FFFC}", attributes: attrs))
                    continue
                }
                if block.kind == .divider {
                    let attachment = NSTextAttachment()
                    attachment.attachmentCell = DocumentDividerCell()
                    attrs[.attachment] = attachment
                }
                if let file = run.attachment, let data = try? JSONEncoder().encode(file) {
                    attrs[attachmentKey] = data
                    attrs[.toolTip] = file.name
                    let attachment = NSTextAttachment()
                    if let image = Self.pastedImage(from: file) {
                        // 粘贴图片以 data URL 存在附件里（NativeDocument 暂无图片块类型），
                        // 渲染成真实图片；其余附件保持 📎 文本单元。
                        attachment.image = image
                        attachment.bounds = Self.imageBounds(for: image)
                    } else {
                        let cell = NSTextAttachmentCell(textCell: "📎 " + file.name)
                        attachment.attachmentCell = cell
                    }
                    attrs[.attachment] = attachment
                }
                if let diagram = run.diagram, let data = try? JSONEncoder().encode(diagram) {
                    attrs[diagramKey] = data
                    attrs[.toolTip] = diagram.title + " · 双击编辑"
                    let attachment = NSTextAttachment()
                    attachment.attachmentCell = DocumentDiagramCell(diagram: diagram)
                    attrs[.attachment] = attachment
                }
                if let table = run.table, let data = try? JSONEncoder().encode(table) {
                    attrs[tableKey] = data
                    attrs[.toolTip] = "表格 · 双击编辑"
                    let attachment = NSTextAttachment()
                    attachment.attachmentCell = DocumentTableCell(table: table)
                    attrs[.attachment] = attachment
                }
                if let formula = run.formula, let data = try? JSONEncoder().encode(formula) {
                    attrs[formulaKey] = data
                    attrs[.toolTip] = "公式 · 双击编辑"
                    let attachment = NSTextAttachment()
                    attachment.attachmentCell = DocumentFormulaCell(formula: formula)
                    attrs[.attachment] = attachment
                }
                result.append(NSAttributedString(string: run.text, attributes: attrs))
            }
            if index < document.blocks.count - 1 {
                let separatorKind = block.kind == .divider ? DocumentBlockKind.paragraph : block.kind
                let caption = !block.runs.isEmpty && block.runs.allSatisfy { $0.marks.contains(.caption) }
                result.append(NSAttributedString(string: "\n", attributes: attributes(
                    kind: separatorKind, marks: caption ? [.caption] : [], indentLevel: block.indentLevel,
                    listStart: block.listStart, align: block.align,
                    bodySize: separatorKind == .paragraph ? block.bodySize : nil)))
            }
        }
        applyCodeHighlighting(to: result, document: document)
        return result
    }

    /// 富文本粘贴：把剪贴板里的 RTF/HTML 压回**基础标记**（粗/斜/下划线/删除线/
    /// 行内代码），其余排版（字号、颜色、背景、缩进、字体族）一律丢弃。
    ///
    /// 返回 nil 表示"没有任何可保留的标记"——调用方应退回纯文本粘贴，避免
    /// 把一整段普通文字也换成带属性的串（那会让撤销/提交路径多一轮无谓差异）。
    /// 段落类型用 `baseKind`（粘贴处所在段的类型），多行也保持同一类型：
    /// 富文本粘贴是"把内容放进来"，不该顺手把当前段落改成标题或列表。
    static func richText(_ attributed: NSAttributedString,
                         baseKind: DocumentBlockKind) -> NSAttributedString? {
        guard attributed.length > 0 else { return nil }
        let plain = attributed.string as NSString

        /// 一段文字的标记（段落内相对范围）。
        func marks(in attrs: [NSAttributedString.Key: Any]) -> Set<DocumentMark> {
            var result: Set<DocumentMark> = []
            if let font = attrs[.font] as? NSFont {
                let traits = NSFontManager.shared.traits(of: font)
                if traits.contains(.boldFontMask) { result.insert(.bold) }
                if traits.contains(.italicFontMask) { result.insert(.italic) }
                if font.isFixedPitch { result.insert(.code) }
            }
            if let value = attrs[.underlineStyle] as? Int, value != 0 { result.insert(.underline) }
            if let value = attrs[.strikethroughStyle] as? Int, value != 0 { result.insert(.strikethrough) }
            if let link = attrs[.link] { result.insert(.link(linkTarget(link))) }
            return result
        }

        // 按换行切段（段落 = 一行，与文档模型一致）。
        var paragraphRanges: [NSRange] = []
        var cursor = 0
        while cursor < plain.length {
            let range = plain.paragraphRange(for: NSRange(location: cursor, length: 0))
            paragraphRanges.append(range)
            cursor = NSMaxRange(range)
        }
        guard !paragraphRanges.isEmpty else { return nil }

        var hasMarks = false
        var lines: [(text: String, segments: [(NSRange, Set<DocumentMark>)])] = []
        for paragraph in paragraphRanges {
            let line = attributed.attributedSubstring(from: paragraph)
            let text = line.string
            var segments: [(NSRange, Set<DocumentMark>)] = []
            line.enumerateAttributes(in: NSRange(location: 0, length: line.length)) { attrs, range, _ in
                let resolved = marks(in: attrs)
                if !resolved.isEmpty { hasMarks = true }
                if let last = segments.last, NSMaxRange(last.0) == range.location, last.1 == resolved {
                    segments[segments.count - 1].0.length += range.length
                } else {
                    segments.append((range, resolved))
                }
            }
            lines.append((text, segments))
        }
        guard hasMarks else { return nil }

        let result = NSMutableAttributedString(string: "")
        for (index, line) in lines.enumerated() {
            // 段落尾的换行不进入内容（它由下面的分隔符承担）。
            let text = line.text.hasSuffix("\n") ? String(line.text.dropLast()) : line.text
            let ns = text as NSString
            var emitted = 0
            for (range, marks) in line.segments {
                let start = max(0, min(range.location, ns.length))
                let end = max(start, min(NSMaxRange(range), ns.length))
                guard end > start else { continue }
                if start > emitted {
                    result.append(NSAttributedString(string: ns.substring(with: NSRange(location: emitted,
                                                                                        length: start - emitted)),
                                                     attributes: attributes(kind: baseKind, marks: [])))
                }
                result.append(NSAttributedString(string: ns.substring(with: NSRange(location: start,
                                                                                     length: end - start)),
                                                 attributes: attributes(kind: baseKind, marks: marks)))
                emitted = end
            }
            if emitted < ns.length {
                result.append(NSAttributedString(string: ns.substring(from: emitted),
                                                 attributes: attributes(kind: baseKind, marks: [])))
            }
            if index < lines.count - 1 {
                result.append(NSAttributedString(string: "\n", attributes: attributes(kind: baseKind, marks: [])))
            }
        }
        return result
    }

    private static func linkTarget(_ value: Any) -> String {
        if let url = value as? URL { return url.absoluteString }
        return String(describing: value)
    }

    /// 代码块着色在**渲染期**做一次（加载 / 切换文档），编辑期由
    /// `NativeTextView.restyleCodeBlocks` 只重排光标所在段。
    private static func applyCodeHighlighting(to result: NSMutableAttributedString,
                                              document: NativeDocument) {
        guard result.length > 0 else { return }
        // `NSApp` 在单元测试里可能没有，回落到 aqua（着色差异只在颜色，不影响断言）。
        let appearance: NSAppearance = NSApp?.effectiveAppearance
            ?? NSAppearance(named: .aqua) ?? NSAppearance.currentDrawing()
        let base = attributes(kind: .code, marks: [])[.foregroundColor] as? NSColor ?? .labelColor
        let source = result.string as NSString
        var offset = 0
        for (index, block) in document.blocks.enumerated() {
            let length = (block.plainText as NSString).length
            if block.kind == .code, length > 0 {
                let range = NSRange(location: offset, length: min(length, result.length - offset))
                let language = CodeSyntaxHighlighter.Language.detect(in: source.substring(with: range))
                CodeSyntaxHighlighter.apply(to: result, range: range, language: language,
                                            baseColor: base, appearance: appearance)
            }
            offset += length
            if index < document.blocks.count - 1 { offset += 1 }
        }
    }

    static func decode(_ text: NSAttributedString, preserving previous: NativeDocument,
                       trailing: DocumentBlockKind? = nil,
                       trailingIndentLevel: Int = 0, trailingListStart: Int? = nil,
                       trailingAlign: DocumentAlignment? = nil) -> NativeDocument {
        let plain = text.string as NSString
        let skeleton = previous.replacingPlainText(text.string)
        var offset = 0
        let blocks = skeleton.blocks.enumerated().map { index, block -> DocumentBlock in
            let length = (block.plainText as NSString).length
            var runs: [DocumentRun] = []
            var kind: DocumentBlockKind = .paragraph
            var indentLevel = 0
            var listStart: Int?
            var align: DocumentAlignment?
            var bodySize: DocumentBodySize?
            if offset < text.length, let token = text.attribute(blockKey, at: offset, effectiveRange: nil) as? String {
                kind = Self.kind(token)
                indentLevel = text.attribute(indentKey, at: offset, effectiveRange: nil) as? Int ?? 0
                listStart = text.attribute(listStartKey, at: offset, effectiveRange: nil) as? Int
                align = (text.attribute(alignKey, at: offset, effectiveRange: nil) as? String)
                    .flatMap(DocumentAlignment.init(rawValue:))
                bodySize = (text.attribute(bodySizeKey, at: offset, effectiveRange: nil) as? String)
                    .flatMap(DocumentBodySize.init(rawValue:))
            }
            // 文末那个"一个字符都没有"的空段落：TextKit 把段落样式挂在字符上，而它
            // 没有字符，级别只活在输入属性里，所以由视图把待定级别报进来。原版把行
            // 属性存在 Delta 里，没有这个边界。
            if length == 0, index == skeleton.blocks.count - 1, let trailing {
                kind = trailing
                indentLevel = trailingIndentLevel
                listStart = trailingListStart
                align = trailingAlign
            }
            text.enumerateAttributes(in: NSRange(location: min(offset, text.length), length: length)) { attrs, range, _ in
                var marks = Set<DocumentMark>()
                if attrs[inlineCodeKey] as? Bool == true { marks.insert(.code) }
                if let font = attrs[.font] as? NSFont {
                    let traits = NSFontManager.shared.traits(of: font)
                    // Heading weight is presentation, not a user-applied mark.
                    // Preserve explicit bold on headings, while plain/rich-text
                    // paragraphs still accept font traits from native editing.
                    let isHeading: Bool = { if case .heading = kind { return true }; return false }()
                    if traits.contains(.boldFontMask), !isHeading || attrs[explicitBoldKey] as? Bool == true {
                        marks.insert(.bold)
                    }
                    if traits.contains(.italicFontMask) { marks.insert(.italic) }
                    if font.isFixedPitch && kind != .code { marks.insert(.code) }
                }
                if let value = attrs[.underlineStyle] as? Int, value != 0 { marks.insert(.underline) }
                // 已勾选检查项的删除线是展示层（原版 `completedChecklistText`），
                // 不是用户标记：decode 时忽略，否则会写进 Delta 且勾选状态无法切换。
                if let value = attrs[.strikethroughStyle] as? Int, value != 0,
                   kind != .checklist(true),
                   attrs[completedChecklistPresentationKey] as? Bool != true { marks.insert(.strikethrough) }
                if attrs[.backgroundColor] != nil { marks.insert(.highlight) }
                if let hex = (attrs[highlightColorKey] as? String).flatMap(QuillDeltaCodec.normalizedColor) {
                    marks.remove(.highlight)
                    marks.insert(.highlightColor(hex))
                }
                if let hex = (attrs[textColorKey] as? String).flatMap(QuillDeltaCodec.normalizedColor) {
                    marks.insert(.textColor(hex))
                }
                if attrs[mutedKey] as? Bool == true { marks.insert(.muted) }
                if attrs[captionKey] as? Bool == true { marks.insert(.caption) }
                if let token = attrs[inkKey] as? String, let ink = DocumentInk(token: token) { marks.insert(.ink(ink)) }
                let symbol = (attrs[symbolKey] as? String).flatMap(DocumentInlineSymbol.init(rawValue:))
                if let link = attrs[.link] { marks.insert(.link(String(describing: link))) }
                let attachment = (attrs[attachmentKey] as? Data).flatMap { try? JSONDecoder().decode(NativeAttachment.self, from: $0) }
                let diagram = (attrs[diagramKey] as? Data).flatMap { try? JSONDecoder().decode(NativeDiagram.self, from: $0) }
                let table = (attrs[tableKey] as? Data).flatMap { try? JSONDecoder().decode(NativeTable.self, from: $0) }
                let formula = (attrs[formulaKey] as? Data).flatMap { try? JSONDecoder().decode(NativeFormula.self, from: $0) }
                let fragment = plain.substring(with: range)
                if let symbol, fragment.contains("\u{FFFC}") {
                    // Newly typed text next to an icon must stay ordinary text.
                    for (index, part) in fragment.components(separatedBy: "\u{FFFC}").enumerated() {
                        if index > 0 { runs.append(DocumentRun(text: symbol.textFallback, marks: marks.union([.symbol(symbol)]))) }
                        if !part.isEmpty { runs.append(DocumentRun(text: part, marks: marks)) }
                    }
                } else {
                    runs.append(DocumentRun(text: fragment, marks: marks, attachment: attachment,
                                            diagram: diagram, table: table, formula: formula))
                }
            }
            offset += length + 1
            return DocumentBlock(id: block.id, kind: kind, runs: runs,
                                 indentLevel: indentLevel, listStart: listStart,
                                 align: align, bodySize: bodySize, checklist: block.checklist)
        }
        return NativeDocument(blocks: blocks)
    }
}

final class DocumentDividerCell: NSTextAttachmentCell {
    var lineWidth: CGFloat = 240
    override func cellSize() -> NSSize { NSSize(width: lineWidth, height: 20) }
    override func draw(withFrame cellFrame: NSRect, in controlView: NSView?) {
        NSColor.separatorColor.setFill()
        NSRect(x: cellFrame.minX, y: cellFrame.midY, width: cellFrame.width, height: 1).fill()
    }
}

extension DocumentTextCodec {
    /// 识别以 data URL 承载的粘贴图片附件（NativeTextView.paste 写入）。
    static func pastedImage(from file: NativeAttachment) -> NSImage? {
        guard file.storedName.hasPrefix("data:image/"),
              let comma = file.storedName.firstIndex(of: ","),
              let data = Data(base64Encoded: String(file.storedName[file.storedName.index(after: comma)...])) else { return nil }
        return NSImage(data: data)
    }

    /// 等比放入正文宽度内：上限 480×320，小图保持原尺寸不放大。
    static func imageBounds(for image: NSImage) -> NSRect {
        var size = image.size
        guard size.width > 0, size.height > 0 else { return NSRect(x: 0, y: 0, width: 1, height: 1) }
        let maximum = NSSize(width: 480, height: 320)
        if size.height > maximum.height {
            size.width *= maximum.height / size.height
            size.height = maximum.height
        }
        if size.width > maximum.width {
            size.height *= maximum.width / size.width
            size.width = maximum.width
        }
        return NSRect(x: 0, y: 0, width: max(1, ceil(size.width)), height: max(1, ceil(size.height)))
    }
}
