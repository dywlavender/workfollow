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
