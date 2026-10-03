import Foundation
import XCTest

final class TaskMoreMenuRoundTwoTests: XCTestCase {
    func testMoreMenuKeepsSupportedRowsInOrderAndOmitsRemovedEntrypoints() throws {
        let source = try inspectorSource()
        let menu = try sourceRegion(
            source,
            startingAt: "    private func moreActionsPopover(_ task: Task) -> some View {",
            endingAt: "\n    private func focusSubmenuRow("
        )

        let orderedRows = [
            #"if task.parentID == nil {"#,
            #"moreAction("添加子任务", symbol: "list.bullet.indent")"#,
            #"moreAction("关联主任务", symbol: "rectangle.3.group")"#,
            #"moreAction(task.isPinned ? "取消置顶" : "置顶", symbol: "pin")"#,
            #"moreAction(task.isAbandoned ? "恢复" : "放弃", symbol: "xmark.square")"#,
            #"moreAction("标签", symbol: "tag")"#,
            #"moreAction("上传附件", symbol: "paperclip")"#,
            "focusSubmenuRow(task)",
            "Divider()",
            #"moreAction("任务动态", symbol: "list.bullet.rectangle")"#,
            #"moreAction("保存为模板", symbol: "doc.badge.plus")"#,
            #"moreAction("创建副本", symbol: "square.on.square")"#,
            #"moreAction("复制链接", symbol: "link")"#,
            #"moreAction("转换为笔记", symbol: "doc.text")"#,
            #"moreAction("删除", symbol: "trash")"#
        ]

        var cursor = menu.startIndex
        for row in orderedRows {
            guard let range = menu.range(of: row, range: cursor..<menu.endIndex) else {
                XCTFail("moreActionsPopover is missing or misorders row: \(row)")
                return
            }
            cursor = range.upperBound
        }

        for removedEntry in ["其他操作", "更多属性", "截止日期", "跳过本周期",
                             "便签", "打印"] {
            XCTAssertFalse(menu.contains(removedEntry), "Unexpected more menu entry: \(removedEntry)")
        }
    }

    func testAbandonRestoreAndDeleteRemainPlainTextActions() throws {
        let source = try inspectorSource()
        let menu = try sourceRegion(
            source,
            startingAt: "    private func moreActionsPopover(_ task: Task) -> some View {",
            endingAt: "\n    private func focusSubmenuRow("
        )
        let actionRenderer = try sourceRegion(
            source,
            startingAt: "    private func moreAction(",
            endingAt: "\n    private func inspectorContent("
        )

        XCTAssertTrue(menu.contains(#"moreAction(task.isAbandoned ? "恢复" : "放弃", symbol: "xmark.square")"#))
        XCTAssertTrue(menu.contains(#"moreAction("删除", symbol: "trash")"#))
        for redStyle in ["destructive", "WFColors.danger", "Color.red", "NSColor.systemRed", ".red"] {
            XCTAssertFalse(menu.contains(redStyle), "More menu action uses destructive styling: \(redStyle)")
            XCTAssertFalse(actionRenderer.contains(redStyle), "Action renderer uses destructive styling: \(redStyle)")
        }
        XCTAssertTrue(actionRenderer.contains(".foregroundStyle(WFColors.text)"),
                      "More menu actions should use the regular text color")
    }

    private func inspectorSource() throws -> String {
        let sourceRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("WorkFollow", isDirectory: true)
        return try String(
            contentsOf: sourceRoot.appendingPathComponent(
                "Features/Tasks/TaskInspector/TaskInspectorShell.swift"
            ),
            encoding: .utf8
        )
    }

    private func sourceRegion(_ source: String, startingAt startMarker: String,
                             endingAt endMarker: String) throws -> String {
        let start = try XCTUnwrap(source.range(of: startMarker), "Source marker not found: \(startMarker)")
        let end = try XCTUnwrap(
            source.range(of: endMarker, range: start.upperBound..<source.endIndex),
            "Source marker not found after \(startMarker): \(endMarker)"
        )
        return String(source[start.lowerBound..<end.lowerBound])
    }
}
