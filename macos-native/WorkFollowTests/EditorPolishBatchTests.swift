import AppKit
import SwiftUI
import XCTest
@testable import WorkFollow

/// 编辑栏第一批收尾：块菜单标题级别、智能替换、折叠计数、更多菜单高度。
@MainActor
final class EditorPolishBatchTests: XCTestCase {

    // MARK: - 块菜单（TI2-21 收尾）

    func testBlockMenuOffersAllSixHeadingLevels() {
        let commands = DocumentProfile.standardBlockMenuCommands
        let headings = commands.compactMap { command -> Int? in
            guard case .heading(let level)? = EditorCommandCatalog.format(command.id)?.block else { return nil }
            return level
        }
        XCTAssertEqual(headings, [1, 2, 3, 4, 5, 6], "滴答 md_vertical_header1..6：块菜单要有六级标题")
        XCTAssertEqual(commands.first?.id, "format.paragraph", "第一项是正文")
        XCTAssertTrue(commands.contains { $0.id == "shared.divider" })
        XCTAssertTrue(commands.contains { $0.id == "shared.attachment" })
    }

    func testBlockMenuKeepsFourSections() {
        let commands = DocumentProfile.standardBlockMenuCommands
        let groups = commands.map(\.group)
        let sections = groups.reduce(into: [String]()) { if $0.last != $1 { $0.append($1) } }
        XCTAssertEqual(sections, ["标题", "列表", "格式", "插入"])
        // 细线数 = 相邻分组变化次数 = 3，菜单高度按它算。
        let dividers = zip(groups.dropFirst(), groups).filter { $0 != $1 }.count
        XCTAssertEqual(dividers, 3)
        XCTAssertEqual(SlashMenuMetrics.height(for: commands),
                       CGFloat(commands.count) * SlashMenuMetrics.rowHeight
                        + CGFloat(dividers) * SlashMenuMetrics.dividerBlock
                        + SlashMenuMetrics.padding * 2)
    }

    func testBlockMenuIsIndependentFromSlashMenu() throws {
        let workspace = TaskWorkspaceModel(seedDemoData: false)
        let id = try XCTUnwrap(workspace.createTask(title: "菜单来源", in: .inbox).taskID)
        let profile = TaskDocumentProfile.make(
            task: try XCTUnwrap(workspace.task(for: id)),
            host: TaskEditorHostActions(createChild: {}, openTags: {}, openRelation: {},
                                        openLink: { _ in true }))
        // Slash 菜单保持实测的 12 项（标题只到 H3），块菜单另有六级。
        XCTAssertEqual(profile.slashCommands.count, 13)
        XCTAssertFalse(profile.slashCommands.contains { $0.id == "format.heading4" })
        XCTAssertEqual(profile.blockMenuCommands?.count, 13)
        XCTAssertTrue(profile.blockMenuCommands?.contains { $0.id == "format.heading6" } == true)
    }

    func testGutterClickOpensBlockScope() throws {
        let view = NativeTextView(frame: NSRect(x: 0, y: 0, width: 600, height: 200), textContainer: nil)
        view.isEditable = true
        let window = NSWindow(contentRect: view.frame, styleMask: [.borderless],
                              backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.appearance = NSAppearance(named: .aqua)
        window.contentView = view
        window.orderFront(nil)
        addTeardownBlock { view.dismissSlash() }
        view.textStorage?.setAttributedString(DocumentTextCodec.render(NativeDocument(blocks: [
            DocumentBlock(kind: .paragraph, runs: [DocumentRun(text: "正文")])
        ])))
        window.makeFirstResponder(view)
        let line = try XCTUnwrap(view.viewRect(forCharacterAt: 0))
        let point = NSPoint(x: DocumentEditorGeometry.decorationMarkerX(visibleMinX: view.decorationVisibleMinX) + 2,
                            y: line.midY)
        XCTAssertTrue(view.openBlockMenu(at: point))
        XCTAssertEqual(view.slashSession?.scope, .block)
        XCTAssertEqual(view.commands(for: try XCTUnwrap(view.slashSession)).count, 13,
                       "块菜单走自己的命令集，不是 Slash 的")
        view.dismissSlash()
    }

    // MARK: - 智能替换

    func testSmartSubstitutionsAreDisabled() {
        let view = NativeTextView(frame: NSRect(x: 0, y: 0, width: 400, height: 200), textContainer: nil)
        XCTAssertFalse(view.isAutomaticQuoteSubstitutionEnabled, "智能引号会破坏代码块与 Markdown")
        XCTAssertFalse(view.isAutomaticDashSubstitutionEnabled)
        XCTAssertFalse(view.isAutomaticTextReplacementEnabled)
        XCTAssertFalse(view.isAutomaticSpellingCorrectionEnabled)
        XCTAssertFalse(view.isGrammarCheckingEnabled)
    }

    func testTypingMarkdownSyntaxSurvivesWithoutSubstitution() {
        let view = NativeTextView(frame: NSRect(x: 0, y: 0, width: 500, height: 200), textContainer: nil)
        let window = NSWindow(contentRect: view.frame, styleMask: [.borderless],
                              backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = view
        window.orderFrontRegardless()
        window.makeFirstResponder(view)
        view.setSelectedRange(NSRange(location: 0, length: 0))
        view.insertText("\"quoted\" -- dash", replacementRange: view.selectedRange())
        XCTAssertEqual(view.string, "\"quoted\" -- dash", "直引号与双连字符必须原样保留")
    }

    func testSpellCheckingFollowsPreference() {
        let previous = EditorPreferences.spellCheckingEnabled
        defer { EditorPreferences.setSpellCheckingEnabled(previous) }
        let view = NativeTextView(frame: NSRect(x: 0, y: 0, width: 400, height: 200), textContainer: nil)
        EditorPreferences.setSpellCheckingEnabled(true)
        RunLoop.current.run(until: Date().addingTimeInterval(0.05))
        XCTAssertTrue(view.isContinuousSpellCheckingEnabled)
        EditorPreferences.setSpellCheckingEnabled(false)
        RunLoop.current.run(until: Date().addingTimeInterval(0.05))
        XCTAssertFalse(view.isContinuousSpellCheckingEnabled)
    }

    // MARK: - 折叠计数

    func testHiddenCountCoversNestedCollapse() {
        let a = UUID(), b = UUID(), c = UUID(), d = UUID()
        let tree: [UUID: [UUID]] = [a: [b, c], b: [d]]
        func children(_ id: UUID) -> [UUID] { tree[id] ?? [] }

        XCTAssertEqual(SubtaskFoldSummary.hiddenCount(under: a, children: children, collapsed: []), 0)
        XCTAssertEqual(SubtaskFoldSummary.hiddenCount(under: a, children: children, collapsed: [b]), 1,
                       "折叠 b 只藏住 d")
        XCTAssertEqual(SubtaskFoldSummary.hiddenCount(under: a, children: children, collapsed: [b, c]), 1,
                       "c 是叶子，折叠它不藏行；b 藏住 d")
        XCTAssertEqual(SubtaskFoldSummary.hiddenCount(under: a, children: children, collapsed: [d]), 0,
                       "折叠叶子节点不藏任何行")
        XCTAssertEqual(SubtaskFoldSummary.hiddenCount(under: b, children: children, collapsed: [d]), 0)
    }

    // MARK: - 更多菜单高度

    func testMoreMenuHeightFollowsRowCount() {
        let tall = TaskInspectorMetrics.moreMenuHeight(rowCount: 16, dividerCount: 1, screenHeight: 900)
        let short = TaskInspectorMetrics.moreMenuHeight(rowCount: 6, dividerCount: 1, screenHeight: 900)
        XCTAssertLessThan(short, tall, "行少的菜单不能再留一大片空白")
        XCTAssertEqual(tall, 16 * 32 + 15 * 2 + 9 + 16)
        // 屏幕不够高时夹到可用高度，不会把菜单推出屏幕。
        XCTAssertLessThanOrEqual(TaskInspectorMetrics.moreMenuHeight(rowCount: 40, dividerCount: 3,
                                                                     screenHeight: 400), 400)
    }

    func testMoreMenuHasNoHardCodedHeight() throws {
        let source = try String(contentsOfFile: Self.inspectorSourcePath, encoding: .utf8)
        XCTAssertFalse(source.contains("height: 490"), "「更多」菜单高度必须按行数算")
        XCTAssertTrue(source.contains("height: moreMenuHeight"))
    }

    private static var inspectorSourcePath: String {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("WorkFollow/Features/Tasks/TaskInspector/TaskInspectorShell.swift")
            .path
    }
}
