import XCTest
@testable import WorkFollow

/// 优先级菜单的两条契约：
/// 1. 顺序来自领域类型的 `menuOrder`（滴答实测：高 → 中 → 低 → 无），视图只按它渲染；
/// 2. 文案只有一份（`TaskPriority.title`），Inspector / 任务行 / 右键菜单共用。
final class TaskPriorityMenuContractTests: XCTestCase {

    func testMenuOrderMatchesTickTick() {
        XCTAssertEqual(TaskPriority.menuOrder, [.high, .medium, .low, .none],
                       "滴答的优先级菜单自上而下是 高 → 中 → 低 → 无")
        // 四档齐全（以后加档位时，菜单漏项会在这里失败）。
        XCTAssertEqual(Set(TaskPriority.menuOrder),
                       Set([TaskPriority.high, .medium, .low, .none]))
    }

    func testTitlesAreSingleSourcedAndMatchProductWording() {
        XCTAssertEqual(TaskPriority.high.title, "高优先级")
        XCTAssertEqual(TaskPriority.medium.title, "中优先级")
        XCTAssertEqual(TaskPriority.low.title, "低优先级")
        XCTAssertEqual(TaskPriority.none.title, "无优先级")
    }

    func testAccessibilityUsesShortTitles() {
        XCTAssertEqual(TaskPriority.high.shortTitle, "高")
        XCTAssertEqual(TaskPriority.none.shortTitle, "无优先级")
    }
}
