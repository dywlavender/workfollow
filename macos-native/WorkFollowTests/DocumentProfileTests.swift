import XCTest
@testable import WorkFollow

@MainActor
final class DocumentProfileTests: XCTestCase {
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
