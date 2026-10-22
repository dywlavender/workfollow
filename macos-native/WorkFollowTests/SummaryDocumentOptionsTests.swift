import XCTest
@testable import WorkFollow

/// 摘要的「生成配方」：filter / grouping / 下一周期 / 显示字段。
/// 重点是旧档案兼容——早期只存了 `filter.showsDate/showsList/showsTags`，
/// 后来换成 `content: Set<SummaryContentField>`，解码时要能翻译过来。
final class SummaryDocumentOptionsTests: XCTestCase {
    func testStandardKeepsDefaultRecipe() {
        let options = SummaryDocumentOptions.standard
        XCTAssertEqual(options.grouping, .completion)
        XCTAssertFalse(options.includesNextWeek)
        XCTAssertEqual(options.content, SummaryContentField.standard)
        XCTAssertTrue(options.filter.showsDate)
        XCTAssertTrue(options.filter.showsList)
        XCTAssertTrue(options.filter.showsTags)
    }

    func testDecodingLegacyFilterOnlyPayloadMigratesContent() throws {
        // 早期档案：只有 filter，没有 content。
        let legacy = """
        {"filter":{"listName":null,"status":"所有状态",
        "showsDate":true,"showsList":true,"showsTags":false}}
        """
        let options = try JSONDecoder().decode(SummaryDocumentOptions.self,
                                               from: Data(legacy.utf8))
        // showsDate → 完成时间 + 任务时间；showsList → 所属清单；showsTags 关 → 不含标签。
        XCTAssertTrue(options.content.contains(.taskName))
        XCTAssertTrue(options.content.contains(.progress))
        XCTAssertTrue(options.content.contains(.completedTime))
        XCTAssertTrue(options.content.contains(.taskTime))
        XCTAssertTrue(options.content.contains(.list))
        XCTAssertFalse(options.content.contains(.tags))
    }

    func testDecodingEmptyPayloadFallsBackToNeutralDefaults() throws {
        let options = try JSONDecoder().decode(SummaryDocumentOptions.self,
                                               from: Data("{}".utf8))
        XCTAssertEqual(options.grouping, .completion)
        XCTAssertFalse(options.includesNextWeek)
        // 缺 filter 时回落 .all：默认只显示日期，不含清单/标签。
        XCTAssertTrue(options.filter.showsDate)
        XCTAssertFalse(options.filter.showsList)
        XCTAssertFalse(options.filter.showsTags)
        XCTAssertTrue(options.content.contains(.taskName))
        XCTAssertFalse(options.content.contains(.list))
        XCTAssertFalse(options.content.contains(.tags))
    }

    func testCodableRoundTripPreservesRecipe() throws {
        var options = SummaryDocumentOptions()
        options.grouping = .list
        options.includesNextWeek = true
        options.content = [.status, .taskName, .list]
        options.filter.listName = "工作"

        let data = try JSONEncoder().encode(options)
        let decoded = try JSONDecoder().decode(SummaryDocumentOptions.self, from: data)
        XCTAssertEqual(decoded.grouping, .list)
        XCTAssertTrue(decoded.includesNextWeek)
        XCTAssertEqual(decoded.content, [.status, .taskName, .list])
        XCTAssertEqual(decoded.filter.listName, "工作")
    }
}
