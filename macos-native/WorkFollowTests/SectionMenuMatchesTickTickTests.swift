import XCTest

/// 分组标题菜单必须与滴答一致（以用户提供的三张截图为准）：
/// 重命名 / 在上方添加分组 / 在下方添加分组 / 移动到 ▸ 清单 / 删除；
/// 标题上还有可见的 `+` 与 `⋯`。
///
/// 菜单是 SwiftUI `@ViewBuilder`，运行时**不可枚举**（这也是我无法靠截图确认菜单项的原因），
/// 所以沿用仓库既有做法（`TaskMoreMenuRoundTwoTests` 的源码扫描）在源码层钉住条目与顺序。
/// 这条测试证明的是"条目齐全且顺序对"，**不能**证明"点了会怎样"——后者由动作层测试覆盖。
final class SectionMenuMatchesTickTickTests: XCTestCase {
    private func listViewSource() throws -> String {
        var url = URL(fileURLWithPath: #filePath)
        url.deleteLastPathComponent()   // WorkFollowTests
        url.deleteLastPathComponent()   // macos-native
        url.appendPathComponent("WorkFollow/Features/Tasks/TaskList/TaskListView.swift")
        return try String(contentsOf: url, encoding: .utf8)
    }

    func testSectionMenuHasTickTickEntriesInOrder() throws {
        let src = try listViewSource()
        guard let start = src.range(of: "private func sectionMenu(_ group: TaskListGroup)") else {
            return XCTFail("sectionMenu 不存在")
        }
        let tail = src[start.lowerBound...]
        guard let end = tail.range(of: "\n    private func headerContent") else {
            return XCTFail("sectionMenu 的边界找不到")
        }
        let menu = String(tail[..<end.lowerBound])
        var cursor = menu.startIndex
        for entry in ["重命名", "在上方添加分组", "在下方添加分组", "移动到", "删除"] {
            guard let range = menu.range(of: entry, range: cursor..<menu.endIndex) else {
                return XCTFail("分组菜单缺少条目或顺序不对: \(entry)")
            }
            cursor = range.upperBound
        }
    }

    func testSectionHeaderHasVisiblePlusAndEllipsis() throws {
        let src = try listViewSource()
        XCTAssertTrue(src.contains(#"systemName: "plus""#), "分组标题上的 + 不见了")
        XCTAssertTrue(src.contains(#"systemName: "ellipsis""#), "分组标题上的 ⋯ 不见了")
    }
}
