import AppKit

/// Hosts supply business actions; the shared editor only executes descriptors.
struct DocumentCommand: Identifiable {
    let id: String
    let title: String
    let group: String
    var keywords: String = ""
    let perform: (NativeTextView) -> Void
    var performSlash: ((NativeTextView, SlashCommandInvocation) -> Void)?
    var glyph: SlashGlyphKind?
    var resolvedGlyph: SlashGlyphKind { glyph ?? SlashGlyphKind.forCommand(id) }

    init(id: String, title: String, group: String, keywords: String = "",
         perform: @escaping (NativeTextView) -> Void) {
        self.id = id
        self.title = title
        self.group = group
        self.keywords = keywords
        self.perform = perform
        self.performSlash = nil
    }

    init(id: String, title: String, group: String, keywords: String = "",
         glyph: SlashGlyphKind? = nil, perform: @escaping (NativeTextView) -> Void,
         slash: @escaping (NativeTextView, SlashCommandInvocation) -> Void) {
        self.id = id
        self.title = title
        self.group = group
        self.keywords = keywords
        self.perform = perform
        self.performSlash = slash
        self.glyph = glyph
    }
}

/// Offsets captured before the trigger/query is removed, in NSTextView's UTF-16
/// space. This mirrors Flutter's DocumentSlashInvocation and anchors block
/// commands to the line where the user opened the palette.
struct SlashCommandInvocation {
    let lineStart: Int
    let slashOffset: Int
}

struct DocumentSelectionAction: Identifiable {
    let id: String
    let title: String
    var toolbarTitle: String? = nil
    let perform: (String) -> Void
    var displayTitle: String { toolbarTitle ?? title }
}

struct DocumentProfile {
    var commands: [DocumentCommand] = []
    var selectionActions: [DocumentSelectionAction] = []
    var taskSlash = false
    var noteSlash = false
    var compactSlash: Bool { taskSlash || noteSlash }
    var onOpenLink: ((String) -> Bool)?
    /// `#` 标签补全（TI2-08）：宿主提供候选与"已插入"回调；默认空 = 不启用。
    var tagCandidates: () -> [String] = { [] }
    var onTagInserted: (String) -> Void = { _ in }
    /// `~` 清单补全：滴答 `shouldShowQuickList` + `TTListCandidatePopover`
    /// （`prefixSymbal` 立即数 `0x7e`）。默认空 = 不启用。
    var listCandidates: () -> [String] = { [] }
    var onListInserted: (String) -> Void = { _ in }
    /// 粘贴文件（TI2-03 剩余项）：宿主负责落盘成附件；默认不处理。
    var onPasteFiles: (([URL]) -> Void)?
    /// 检查项行内控件：行号按换行切分，与 `NativeDocument.blocks` 对齐。
    /// 返回 nil 表示该行不是检查项。
    var checklistItem: (Int) -> ChecklistItemMeta? = { _ in nil }
    var setChecklistReminder: (Int, Date?) -> Void = { _, _ in }
    /// 未授权通知时提醒面板底部的说明；nil 不显示。
    var checklistReminderNotice: () -> String? = { nil }
    /// 只有清单任务开启行尾铃铛；笔记/文本里的行内复选框保持原样。
    var checklistRemindersEnabled = false
    // Explicit host policy. Nil preserves profiles constructed by older callers.
    var selectionToolbarEnabled: Bool?
    /// Complete host-owned menu; nil keeps legacy/generic profile behavior.
    var slashCommandOverride: [DocumentCommand]?
    /// 块菜单（行首手柄 / 空行「+」）的命令集。
    ///
    /// 与 Slash 菜单**不是同一份**：滴答的竖排块菜单资源是 `md_vertical_header1..6`
    /// （六种标题都在），而 Slash 菜单实测只有 12 项、标题到 H3。共用一份会让块菜单
    /// 少掉 H4–H6，所以这里单独给。
    var blockMenuCommands: [DocumentCommand]?
    var supportsSelectionToolbar: Bool {
        selectionToolbarEnabled ?? (!taskSlash && !selectionActions.isEmpty)
    }
    var slashCommands: [DocumentCommand] {
        if let slashCommandOverride { return slashCommandOverride }
        if compactSlash {
            // Legacy compact profiles retain their menu; production hosts
            // supply slashCommandOverride with their own ordering policy.
            return Self.compactDocumentCommands(formatIDs: EditorCommandCatalog.compactSlashFormatIDs) + commands
        }
        return DocumentFormatCommand.commands.map { format in
            format.slashCommand(group: format.block == nil ? "文字格式" : "段落",
                                includeKeywords: true)
        } + [
            DocumentCommand(id: "shared.link", title: "编辑链接", group: "正文", keywords: "link url") { $0.editDocumentLink(nil) },
            DocumentCommand(id: "shared.attachment", title: "插入附件", group: "正文", keywords: "attachment file",
                            perform: { $0.insertDocumentAttachment(nil) },
                            slash: { view, invocation in
                                view.insertDocumentAttachment(at: invocation.slashOffset)
                            }),
            Self.diagramCommand
        ] + commands
    }

    /// Shared execution adapters, not a Task/Note product ordering policy.
    /// 分节对齐滴答实测（2026-10-16）：标题｜列表｜格式（引用/分割线）｜插入。
    static func compactDocumentCommands(formatIDs: [String]) -> [DocumentCommand] {
        let formats = formatIDs.compactMap(EditorCommandCatalog.format)
        return formats.map { format in
            format.slashCommand(group: slashSection(forFormatID: format.id), useFormatGlyph: true)
        } + [
            DocumentCommand(id: "shared.divider", title: "水平分割线", group: "格式",
                            perform: { $0.insertDocumentDivider() },
                            slash: { view, invocation in
                                view.insertDocumentDivider(at: invocation.slashOffset)
                            }),
            DocumentCommand(id: "shared.attachment", title: "附件", group: "插入",
                            perform: { $0.insertDocumentAttachment(nil) },
                            slash: { view, invocation in
                                view.insertDocumentAttachment(at: invocation.slashOffset)
                            }),
            diagramCommand
        ]
    }

    /// 块类型菜单（滴答 `md_vertical_*`）：正文 / H1–H6 / 无序 / 有序 / 检查项 / 引用 /
    /// 分割线 / 附件。分节决定细线位置：标题｜列表｜格式｜插入。
    static var standardBlockMenuCommands: [DocumentCommand] {
        let formatIDs = ["format.paragraph",
                         "format.heading1", "format.heading2", "format.heading3",
                         "format.heading4", "format.heading5", "format.heading6",
                         "format.bullet", "format.ordered", "format.checklist", "format.quote"]
        var commands = formatIDs.compactMap(EditorCommandCatalog.format).map { format in
            format.slashCommand(group: blockSection(forFormatID: format.id), useFormatGlyph: true)
        }
        commands.append(DocumentCommand(id: "shared.divider", title: "水平分割线", group: "格式",
                                        perform: { $0.insertDocumentDivider() },
                                        slash: { view, invocation in
                                            view.insertDocumentDivider(at: invocation.slashOffset)
                                        }))
        commands.append(DocumentCommand(id: "shared.attachment", title: "附件", group: "插入",
                                        perform: { $0.insertDocumentAttachment(nil) },
                                        slash: { view, invocation in
                                            view.insertDocumentAttachment(at: invocation.slashOffset)
                                        }))
        return commands
    }

    private static func blockSection(forFormatID id: String) -> String {
        switch id {
        case "format.paragraph", "format.heading1", "format.heading2", "format.heading3",
             "format.heading4", "format.heading5", "format.heading6":
            return "标题"
        case "format.bullet", "format.ordered", "format.checklist":
            return "列表"
        default:
            return "格式"
        }
    }

    static var diagramCommand: DocumentCommand {
        DocumentCommand(id: "shared.drawio", title: "流程图（draw.io）", group: "插入",
                        keywords: "drawio draw.io diagram 流程图 绘图 思维导图 架构图",
                        perform: { $0.insertDocumentDiagram(at: nil) },
                        slash: { view, invocation in
                            view.insertDocumentDiagram(at: invocation.slashOffset)
                        })
    }

    /// Slash 菜单分节名：只决定分隔线位置与非 compact 的组文本；
    /// 与滴答实测的四节（标题｜列表｜格式｜插入）对应（2026-10-16）。
    private static func slashSection(forFormatID id: String) -> String {
        switch id {
        case "format.heading1", "format.heading2", "format.heading3":
            return "标题"
        case "format.bullet", "format.ordered", "format.checklist":
            return "列表"
        default:
            return "格式"
        }
    }
}

/// 同一个浮层面板承载两种菜单：Slash 输入触发，或行首块手柄点开。
enum SlashMenuScope: Equatable {
    case slash
    case block
}

struct SlashSession {
    let start: Int
    let trigger: String
    var scope: SlashMenuScope = .slash
    private(set) var range: NSRange
    private(set) var query = ""
    private(set) var selectedIndex = 0

    init(start: Int, trigger: String = "/", scope: SlashMenuScope = .slash) {
        self.start = start
        self.trigger = trigger
        self.scope = scope
        range = NSRange(location: start, length: (trigger as NSString).length)
    }

    mutating func update(text: String, selection: NSRange, allowsQuery: Bool = true) -> Bool {
        let text = text as NSString
        let triggerLength = (trigger as NSString).length
        guard selection.length == 0, selection.location >= start + triggerLength,
              selection.location <= text.length, start >= 0,
              start + triggerLength <= text.length,
              text.substring(with: NSRange(location: start, length: triggerLength)) == trigger else { return false }
        let range = NSRange(location: start, length: selection.location - start)
        let query = text.substring(with: NSRange(location: start + triggerLength,
                                                 length: selection.location - start - triggerLength))
        guard allowsQuery || query.isEmpty else { return false }
        guard !query.contains("\n"), !query.contains("/"), !query.contains("、") else { return false }
        if self.query != query { selectedIndex = 0 }
        self.query = query
        self.range = range
        return true
    }

    func results(in commands: [DocumentCommand]) -> [DocumentCommand] {
        let needle = query.trimmingCharacters(in: .whitespaces)
        return commands.filter { needle.isEmpty || ($0.title + " " + $0.keywords).localizedCaseInsensitiveContains(needle) }
    }

    mutating func move(_ offset: Int, count: Int) {
        guard count > 0 else { selectedIndex = 0; return }
        selectedIndex = (selectedIndex + offset + count) % count
    }

    /// 指针移到某一行：原版 `MouseRegion.onEnter` 会把**键盘高亮也移到那一行**，
    /// 悬停与键盘共用同一根高亮条，而不是各画一根。
    mutating func select(_ index: Int) {
        guard index >= 0, index != selectedIndex else { return }
        selectedIndex = index
    }
}
