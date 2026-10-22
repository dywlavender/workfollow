import XCTest
@testable import WorkFollow

/// 摘要筛选/显示条件：默认值、显示内容计数、以及旧档案缺字段时的解码兼容。
/// 这几个字段是后加的（`tagName` / `showsDate` / `showsList` / `showsTags`），
/// 旧 JSON 里没有它们时必须回落到默认，不能 keyNotFound。
final class SummaryFilterTests: XCTestCase {
    func testDefaultKeepsDateAndHidesListAndTags() {
        let filter = SummaryFilter.all
        XCTAssertNil(filter.listName)
        XCTAssertNil(filter.tagName)
        XCTAssertEqual(filter.status, .all)
        XCTAssertTrue(filter.showsDate)
        XCTAssertFalse(filter.showsList)
        XCTAssertFalse(filter.showsTags)
    }

    func testContentOptionCountCountsEnabledFields() {
        var filter = SummaryFilter.all
        XCTAssertEqual(filter.contentOptionCount, 1)
        filter.showsList = true
        XCTAssertEqual(filter.contentOptionCount, 2)
        filter.showsTags = true
        XCTAssertEqual(filter.contentOptionCount, 3)
        filter.showsDate = false
        XCTAssertEqual(filter.contentOptionCount, 2)
    }

    func testDecodingLegacyPayloadFillsNewFieldsWithDefaults() throws {
        // 旧档案只有 listName + status。
        let legacy = #"{"listName":"工作","status":"已完成"}"#
        let filter = try JSONDecoder().decode(SummaryFilter.self,
                                              from: Data(legacy.utf8))
        XCTAssertEqual(filter.listName, "工作")
        XCTAssertEqual(filter.status, .completed)
        XCTAssertNil(filter.tagName)
        XCTAssertTrue(filter.showsDate)
        XCTAssertFalse(filter.showsList)
        XCTAssertFalse(filter.showsTags)
    }

    func testCodableRoundTripPreservesEveryField() throws {
        var filter = SummaryFilter.all
        filter.listName = "学习"
        filter.tagName = "紧急"
        filter.status = .uncompleted
        filter.showsDate = false
        filter.showsList = true
        filter.showsTags = true

        let data = try JSONEncoder().encode(filter)
        let decoded = try JSONDecoder().decode(SummaryFilter.self, from: data)
        XCTAssertEqual(decoded, filter)
    }
}
