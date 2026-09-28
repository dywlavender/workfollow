import AppKit
import XCTest
@testable import WorkFollow

@MainActor
final class SlashSessionTests: XCTestCase {
    func testTaskSlashTriggersAfterTextAndClosesWhenTypingContinues() {
        let editor = NativeTextView(frame: .zero, textContainer: nil)
        editor.profile = DocumentProfile(taskSlash: true)
        editor.insertText("正文", replacementRange: NSRange(location: 0, length: 0))
        editor.insertText("/", replacementRange: NSRange(location: 2, length: 0))
        XCTAssertNotNil(editor.slashSession)
        XCTAssertEqual(editor.profile.slashCommands.map(\.title), ["一级标题", "二级标题", "三级标题", "无序列表", "有序列表", "检查项", "引用", "水平分割线", "附件"])
        editor.insertText("a", replacementRange: NSRange(location: 3, length: 0))
        XCTAssertNil(editor.slashSession)
        XCTAssertEqual(editor.string, "正文/a")
    }

    func testUTF16RangeSearchAndKeyboardWrap() {
        var session = SlashSession(start: 3)
        XCTAssertTrue(session.update(text: "😀 /标题", selection: NSRange(location: 6, length: 0)))
        XCTAssertEqual(session.range, NSRange(location: 3, length: 3))
        XCTAssertEqual(session.results(in: DocumentProfile().slashCommands).count, 3)
        session.move(-1, count: 2)
        XCTAssertEqual(session.selectedIndex, 1)
        session.move(1, count: 2)
        XCTAssertEqual(session.selectedIndex, 0)
    }

    func testDeletingSlashOrMovingOutsideCancelsSession() {
        var session = SlashSession(start: 0)
        XCTAssertFalse(session.update(text: "abc", selection: NSRange(location: 3, length: 0)))
        XCTAssertFalse(session.update(text: "/abc", selection: NSRange(location: 0, length: 0)))
        XCTAssertFalse(session.update(text: "/abc\n", selection: NSRange(location: 5, length: 0)))
    }

    func testInjectedCommandOnlyExistsInItsProfile() {
        let custom = DocumentCommand(id: "host.action", title: "业务操作", group: "宿主", keywords: "custom") { _ in }
        let profile = DocumentProfile(commands: [custom])
        var session = SlashSession(start: 0)
        XCTAssertTrue(session.update(text: "/custom", selection: NSRange(location: 7, length: 0)))
        XCTAssertEqual(session.results(in: profile.slashCommands).map(\.id), ["host.action"])
        XCTAssertTrue(session.results(in: DocumentProfile().slashCommands).isEmpty)
    }

    func testExecutionConsumesQueryAndCallsInjectedAction() {
        let editor = NativeTextView(frame: .zero, textContainer: nil)
        var invoked = false
        editor.profile = DocumentProfile(commands: [DocumentCommand(id: "custom", title: "custom", group: "测试") { view in
            invoked = true
            XCTAssertEqual(view.string, "")
        }])
        editor.insertText("/", replacementRange: NSRange(location: 0, length: 0))
        editor.insertText("custom", replacementRange: NSRange(location: 1, length: 0))
        editor.doCommand(by: #selector(NSTextView.insertNewline(_:)))
        XCTAssertTrue(invoked)
        XCTAssertNil(editor.slashSession)
        XCTAssertEqual(editor.string, "")
    }

    func testSlashBlockFormatsMatchFlutterLineScopeAndKeepCaret() {
        let cases: [(Int, DocumentBlockKind)] = [
            (0, .heading(1)), (1, .heading(2)), (2, .heading(3)),
            (3, .bullet), (4, .ordered), (5, .checklist(false)), (6, .quote)
        ]

        for (commandIndex, expectedKind) in cases {
            let editor = NativeTextView(frame: .zero, textContainer: nil)
            editor.profile = DocumentProfile(taskSlash: true)
            let original = "前置\n目标内容\n后置"
            editor.textStorage?.setAttributedString(DocumentTextCodec.render(NativeDocument(plainText: original)))
            editor.setSelectedRange(NSRange(location: 5, length: 0))
            editor.insertText("/", replacementRange: editor.selectedRange())

            editor.executeSlash(at: commandIndex)

            XCTAssertEqual(editor.string, original, "command \(commandIndex) must only remove its slash trigger")
            XCTAssertEqual(editor.selectedRange(), NSRange(location: 5, length: 0), "command \(commandIndex) must preserve the caret")
            let document = DocumentTextCodec.decode(
                editor.attributedString(), preserving: NativeDocument(plainText: editor.string))
            XCTAssertEqual(document.blocks.map(\.kind), [.paragraph, expectedKind, .paragraph],
                           "command \(commandIndex) must format only the invoking line")

            editor.insertText("续", replacementRange: editor.selectedRange())
            let continued = DocumentTextCodec.decode(
                editor.attributedString(), preserving: NativeDocument(plainText: editor.string))
            XCTAssertEqual(editor.string, "前置\n目标续内容\n后置")
            XCTAssertEqual(continued.blocks.map(\.kind), [.paragraph, expectedKind, .paragraph],
                           "typing after command \(commandIndex) must retain the line format")

            if expectedKind == .bullet || expectedKind == .ordered || expectedKind == .checklist(false) {
                let style = editor.attributedString().attribute(.paragraphStyle, at: 3, effectiveRange: nil) as? NSParagraphStyle
                XCTAssertEqual(style?.textLists.count, 1, "list command \(commandIndex) must render a native list marker")
            }
        }
    }

    func testSlashChecklistFormatsOneEmptyLineWithoutMarkingTheNextLine() {
        let editor = NativeTextView(frame: .zero, textContainer: nil)
        editor.profile = DocumentProfile(taskSlash: true)
        let original = "前置\n\n后置"
        editor.textStorage?.setAttributedString(DocumentTextCodec.render(NativeDocument(plainText: original)))
        editor.setSelectedRange(NSRange(location: 3, length: 0))
        editor.insertText("/", replacementRange: editor.selectedRange())

        editor.executeSlash(at: 5)

        XCTAssertEqual(editor.string, original)
        let document = DocumentTextCodec.decode(
            editor.attributedString(), preserving: NativeDocument(plainText: editor.string))
        XCTAssertEqual(document.blocks.map(\.kind), [.paragraph, .checklist(false), .paragraph])
    }

    func testSlashOrderedFormatJoinsAdjacentOrderedItems() throws {
        let editor = NativeTextView(frame: .zero, textContainer: nil)
        editor.profile = DocumentProfile(taskSlash: true)
        let document = NativeDocument(blocks: [
            DocumentBlock(kind: .paragraph, runs: [DocumentRun(text: "前置")]),
            DocumentBlock(kind: .ordered, runs: [DocumentRun(text: "第一项")]),
            DocumentBlock(kind: .paragraph, runs: [DocumentRun(text: "目标项")]),
            DocumentBlock(kind: .ordered, runs: [DocumentRun(text: "第三项")]),
            DocumentBlock(kind: .paragraph, runs: [DocumentRun(text: "后置")])
        ])
        editor.textStorage?.setAttributedString(DocumentTextCodec.render(document))
        editor.setSelectedRange(NSRange(location: 9, length: 0))
        editor.insertText("/", replacementRange: editor.selectedRange())

        editor.executeSlash(at: 4)

        let rendered = editor.attributedString()
        let first = try XCTUnwrap((rendered.attribute(.paragraphStyle, at: 3, effectiveRange: nil) as? NSParagraphStyle)?.textLists.first)
        let second = (rendered.attribute(.paragraphStyle, at: 7, effectiveRange: nil) as? NSParagraphStyle)?.textLists.first
        let third = (rendered.attribute(.paragraphStyle, at: 11, effectiveRange: nil) as? NSParagraphStyle)?.textLists.first
        XCTAssertTrue(first === second)
        XCTAssertTrue(second === third)
        XCTAssertEqual(rendered.itemNumber(in: first, at: 3), 1)
        XCTAssertEqual(rendered.itemNumber(in: first, at: 7), 2)
        XCTAssertEqual(rendered.itemNumber(in: first, at: 11), 3)
    }

    func testSlashInlineFormatAppliesToNextTypedText() {
        let editor = NativeTextView(frame: .zero, textContainer: nil)
        editor.textStorage?.setAttributedString(DocumentTextCodec.render(NativeDocument(plainText: "正文")))
        editor.setSelectedRange(NSRange(location: 0, length: 0))
        editor.insertText("/", replacementRange: editor.selectedRange())
        let boldIndex = editor.profile.slashCommands.firstIndex { $0.id == "format.9" }!
        editor.executeSlash(at: boldIndex)
        editor.insertText("加粗", replacementRange: editor.selectedRange())
        let boldDocument = DocumentTextCodec.decode(
            editor.attributedString(), preserving: NativeDocument(plainText: editor.string))
        XCTAssertTrue(boldDocument.blocks[0].runs.contains { $0.text == "加粗" && $0.marks.contains(.bold) })
    }

    func testSlashDividerKeepsSurroundingText() {
        let divider = NativeTextView(frame: .zero, textContainer: nil)
        divider.profile = DocumentProfile(taskSlash: true)
        divider.textStorage?.setAttributedString(DocumentTextCodec.render(NativeDocument(plainText: "前置内容")))
        divider.setSelectedRange(NSRange(location: 2, length: 0))
        divider.insertText("/", replacementRange: divider.selectedRange())
        divider.executeSlash(at: 7)
        XCTAssertEqual(divider.string, "前置\n\u{FFFC}\n内容")
        let dividerDocument = DocumentTextCodec.decode(
            divider.attributedString(), preserving: NativeDocument(plainText: divider.string))
        XCTAssertTrue(dividerDocument.blocks.contains { $0.kind == .divider })
    }

    func testEscapeKeepsQueryAndDoesNotEscapeHost() {
        let editor = NativeTextView(frame: .zero, textContainer: nil)
        var escaped = false
        editor.onEscape = { escaped = true; return .keepInspector }
        editor.insertText("/", replacementRange: NSRange(location: 0, length: 0))
        editor.cancelOperation(nil)
        XCTAssertEqual(editor.string, "/")
        XCTAssertNil(editor.slashSession)
        XCTAssertFalse(escaped)
    }

    /// 用 `/` 覆盖一段选中文本是普通编辑：原版按前后文本差异判断"这是插入了一个
    /// `/`"，选中内容被替换掉不算，因此不该开面板（`slash_command_session.dart:21-31`）。
    func testTypingSlashOverASelectionIsOrdinaryText() {
        let editor = NativeTextView(frame: .zero, textContainer: nil)
        editor.profile = DocumentProfile(taskSlash: true)
        editor.insertText("选中的文字", replacementRange: NSRange(location: 0, length: 0))
        editor.setSelectedRange(NSRange(location: 0, length: 3))
        editor.insertText("/", replacementRange: editor.selectedRange())

        XCTAssertEqual(editor.string, "/文字")
        XCTAssertNil(editor.slashSession, "替换选中文本不该开斜杠面板")
    }

    /// 对照面：光标处插入 `/` 仍然要开面板。
    func testTypingSlashAtTheCaretStillOpensThePalette() {
        let editor = NativeTextView(frame: .zero, textContainer: nil)
        editor.profile = DocumentProfile(taskSlash: true)
        editor.insertText("正文", replacementRange: NSRange(location: 0, length: 0))
        editor.setSelectedRange(NSRange(location: 2, length: 0))
        editor.insertText("/", replacementRange: editor.selectedRange())

        XCTAssertEqual(editor.string, "正文/")
        XCTAssertNotNil(editor.slashSession)
    }

    func testURLDoesNotOpenSession() {
        let editor = NativeTextView(frame: .zero, textContainer: nil)
        editor.insertText("https:", replacementRange: NSRange(location: 0, length: 0))
        editor.insertText("/", replacementRange: NSRange(location: 6, length: 0))
        XCTAssertNil(editor.slashSession)
    }

    func testDocumentRebindClearsUndoAndSlash() {
        let editor = NativeTextView(frame: .zero, textContainer: nil)
        let coordinator = DocumentEditorCoordinator(documentID: UUID(), document: .empty,
            onDocumentChange: { _ in }, onEscape: { .keepInspector }, onEditingChanged: { _ in })
        editor.delegate = coordinator
        editor.insertText("/", replacementRange: NSRange(location: 0, length: 0))
        coordinator.update(editor, documentID: UUID(), document: NativeDocument(plainText: "second"),
                           onDocumentChange: { _ in }, onEscape: { .keepInspector }, onEditingChanged: { _ in })
        XCTAssertEqual(editor.string, "second")
        XCTAssertFalse(editor.undoManager!.canUndo)
        XCTAssertNil(editor.slashSession)
    }
}
