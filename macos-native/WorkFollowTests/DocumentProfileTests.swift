import XCTest
@testable import WorkFollow

@MainActor
final class DocumentProfileTests: XCTestCase {
    func testCatalogUsesUniqueSemanticIDsIndependentOfPresentationOrder() throws {
        let descriptors = EditorCommandCatalog.formats
        XCTAssertEqual(Set(descriptors.map(\.id)).count, 16)
        XCTAssertEqual(descriptors.count, 16)
        let reversed = Dictionary(uniqueKeysWithValues: descriptors.reversed().map { ($0.id, $0.glyph) })
        for id in EditorCommandCatalog.compactSlashFormatIDs {
            let format = try XCTUnwrap(EditorCommandCatalog.format(id))
            XCTAssertEqual(reversed[id], format.descriptor.glyph)
            XCTAssertEqual(SlashGlyphKind.forCommand(id), format.descriptor.glyph)
        }
        XCTAssertEqual(EditorCommandCatalog.format("format.bold")?.mark, .bold)
        XCTAssertEqual(EditorCommandCatalog.format("format.heading3")?.block, .heading(3))
        XCTAssertEqual(EditorCommandCatalog.format("format.checkedChecklist")?.block, .checklist(true))
    }

    func testTaskNoteAndGenericProfilesShareFormatIdentityWithoutChangingGlyphPolicy() {
        let task = DocumentProfile(taskSlash: true).slashCommands
        let note = DocumentProfile(noteSlash: true).slashCommands
        let generic = DocumentProfile().slashCommands
        XCTAssertEqual(task.map(\.id), note.map(\.id))
        XCTAssertEqual(Array(task.prefix(7)).map(\.id), EditorCommandCatalog.compactSlashFormatIDs)
        XCTAssertEqual(Array(generic.prefix(16)).map(\.id), DocumentFormatCommand.commands.map(\.id))
        XCTAssertEqual(Array(task.prefix(7)).map(\.resolvedGlyph),
                       [.heading(1), .heading(2), .heading(3), .bullet, .ordered, .checklist, .quote])
        XCTAssertTrue(generic.prefix(16).allSatisfy { $0.resolvedGlyph == .symbol("text.alignleft") },
                      "Generic Slash keeps its existing visual policy during this refactor")
        for command in task.prefix(7) {
            let format = EditorCommandCatalog.format(command.id)
            XCTAssertEqual(command.title, format?.title)
            XCTAssertEqual(command.keywords, "", "Compact Slash search behavior must not change")
        }
    }

    func testSlashAdapterKeepsExistingFormatExecutionResults() {
        for format in DocumentFormatCommand.commands {
            let direct = NativeTextView(frame: .zero, textContainer: nil)
            let adapted = NativeTextView(frame: .zero, textContainer: nil)
            for view in [direct, adapted] {
                view.textStorage?.setAttributedString(DocumentTextCodec.render(NativeDocument(plainText: "正文内容")))
                view.setSelectedRange(NSRange(location: 1, length: 2))
            }
            direct.applyFormat(format)
            format.slashCommand(group: "格式").perform(adapted)
            let expected = DocumentTextCodec.decode(direct.attributedString(), preserving: .empty)
            let actual = DocumentTextCodec.decode(adapted.attributedString(), preserving: .empty)
            XCTAssertEqual(actual.plainText, expected.plainText, format.id)
            XCTAssertEqual(actual.blocks.map(\.kind), expected.blocks.map(\.kind), format.id)
            XCTAssertEqual(actual.blocks.flatMap(\.runs).map(\.marks),
                           expected.blocks.flatMap(\.runs).map(\.marks), format.id)
            XCTAssertEqual(adapted.selectedRange(), direct.selectedRange(), format.id)
            XCTAssertEqual(DocumentTextCodec.style(of: adapted.attributedString()),
                           DocumentTextCodec.style(of: direct.attributedString()), format.id)
        }
    }

    func testTaskSlashCommandsMatchFlutterOrderAndLabels() {
        let parentCommands = taskActions(includeChild: true)
        let childCommands = taskActions(includeChild: false)

        let parentTitles = DocumentProfile(commands: parentCommands, taskSlash: true)
            .slashCommands.map(\.title)
        let childTitles = DocumentProfile(commands: childCommands, taskSlash: true)
            .slashCommands.map(\.title)

        XCTAssertEqual(parentTitles, [
            "一级标题", "二级标题", "三级标题", "无序列表", "有序列表", "检查项", "引用",
            "水平分割线", "附件", "子任务", "标签", "关联任务/笔记"
        ])
        XCTAssertEqual(childTitles, [
            "一级标题", "二级标题", "三级标题", "无序列表", "有序列表", "检查项", "引用",
            "水平分割线", "附件", "标签", "关联任务/笔记"
        ])
    }

    func testTaskSlashClosesWhenTypingAfterSlashInsteadOfSearching() {
        var session = SlashSession(start: 3)

        XCTAssertTrue(session.update(
            text: "abc/",
            selection: NSRange(location: 4, length: 0),
            allowsQuery: false
        ))
        XCTAssertFalse(session.update(
            text: "abc/q",
            selection: NSRange(location: 5, length: 0),
            allowsQuery: false
        ))
    }

    private func taskActions(includeChild: Bool) -> [DocumentCommand] {
        var commands: [DocumentCommand] = []
        if includeChild {
            commands.append(DocumentCommand(id: "task.child", title: "子任务", group: "插入") { _ in })
        }
        commands.append(DocumentCommand(id: "task.tags", title: "标签", group: "插入") { _ in })
        commands.append(DocumentCommand(id: "task.relation", title: "关联任务/笔记", group: "插入") { _ in })
        return commands
    }
}
