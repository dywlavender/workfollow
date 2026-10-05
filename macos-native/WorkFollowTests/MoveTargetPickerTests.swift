import XCTest
@testable import WorkFollow

/// 「移动到」选择器的纯逻辑：滴答那版带搜索框，自绘时最容易错的就是
/// "过滤之后高亮指向谁"。
final class MoveTargetPickerTests: XCTestCase {
    private let targets = [MoveTarget(name: "收集箱", isCurrent: false),
                           MoveTarget(name: "工作", isCurrent: false),
                           MoveTarget(name: "欢迎", isCurrent: true)]

    func testEmptyQueryShowsAllInOrderAndMarksCurrent() {
        let picker = MoveTargetPicker(allTargets: targets)
        XCTAssertEqual(picker.rows.map(\.name), ["收集箱", "工作", "欢迎"], "保持侧栏顺序")
        XCTAssertEqual(picker.rows.map(\.isCurrent), [false, false, true], "当前清单要能打勾")
        XCTAssertEqual(picker.selected?.name, "收集箱", "默认高亮第一行")
    }

    func testFilterIsSubstringAndCaseInsensitive() {
        var picker = MoveTargetPicker(allTargets: targets)
        picker.setQuery("工")
        XCTAssertEqual(picker.rows.map(\.name), ["工作"])
        picker.setQuery("箱")
        XCTAssertEqual(picker.rows.map(\.name), ["收集箱"], "中间匹配也算")
        picker.setQuery("zz")
        XCTAssertTrue(picker.rows.isEmpty)
        XCTAssertNil(picker.selected, "没有可选项时不该有选中项（界面据此禁用回车）")
    }

    func testQueryChangeResetsHighlight() {
        var picker = MoveTargetPicker(allTargets: targets)
        picker.moveHighlight(by: 2)
        XCTAssertEqual(picker.selected?.name, "欢迎")
        picker.setQuery("工")
        XCTAssertEqual(picker.highlighted, 0, "过滤后高亮必须回到第一行")
        XCTAssertEqual(picker.selected?.name, "工作")
    }

    func testHighlightClampsAtBothEnds() {
        var picker = MoveTargetPicker(allTargets: targets)
        picker.moveHighlight(by: -1)
        XCTAssertEqual(picker.highlighted, 0, "顶部不越界")
        picker.moveHighlight(by: 99)
        XCTAssertEqual(picker.highlighted, targets.count - 1, "底部不越界（不环绕）")
        picker.setQuery("zz")
        picker.moveHighlight(by: 1)
        XCTAssertEqual(picker.highlighted, 0, "空结果时高亮归零")
    }
}
