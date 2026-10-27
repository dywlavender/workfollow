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

    // MARK: - 顺序与样式（显示内容组）

    func testStandardKeepsDefaultOrderAndStyles() {
        let options = SummaryDocumentOptions.standard
        XCTAssertEqual(options.contentOrder, SummaryContentField.inlineOrder)
        XCTAssertEqual(options.contentOrder, [.taskName, .status, .progress, .taskTime,
                                              .parentTask, .tags, .focus, .list])
        XCTAssertEqual(options.contentStyles, .standard)
        XCTAssertEqual(options.contentStyles.completedTime, .date)
        XCTAssertEqual(options.contentStyles.taskTime, .dateTime)
        XCTAssertEqual(options.contentStyles.list, .list)
        XCTAssertEqual(options.contentStyles.detail, .formatted)
    }

    func testLegacyRecipeGetsDefaultOrderAndStyles() throws {
        let legacy = """
        {"filter":{"status":"所有状态","showsDate":true,"showsList":true,"showsTags":true},
        "content":["任务名称","进度","完成时间"]}
        """
        let options = try JSONDecoder().decode(SummaryDocumentOptions.self,
                                               from: Data(legacy.utf8))
        XCTAssertEqual(options.contentOrder, SummaryContentField.inlineOrder)
        XCTAssertEqual(options.contentStyles, .standard)
    }

    func testContentOrderNormalizationDropsFixedSlotsDuplicatesAndUnknownFields() throws {
        // 固定槽位（详细内容）不参与行内排序；重复项与未知字段直接丢弃；
        // 缺失字段按默认顺序补到末尾，保证弹层始终展示完整清单。
        let payload = """
        {"content":["任务名称"],
         "contentOrder":["所属清单","详细内容","任务名称","所属清单","状态","没有这个字段"]}
        """
        let options = try JSONDecoder().decode(SummaryDocumentOptions.self,
                                               from: Data(payload.utf8))
        XCTAssertEqual(options.contentOrder, [.list, .taskName, .status, .progress,
                                              .taskTime, .parentTask, .tags, .focus])
    }

    func testPartialStylesFallBackPerField() throws {
        let payload = """
        {"contentStyles":{"list":"清单-分组","detail":"纯文本"}}
        """
        let options = try JSONDecoder().decode(SummaryDocumentOptions.self,
                                               from: Data(payload.utf8))
        XCTAssertEqual(options.contentStyles.completedTime, .date)
        XCTAssertEqual(options.contentStyles.taskTime, .dateTime)
        XCTAssertEqual(options.contentStyles.list, .listGroup)
        XCTAssertEqual(options.contentStyles.detail, .plain)
    }

    func testMoveContentFieldMovesWithinBoundsAndKeepsEveryField() {
        var options = SummaryDocumentOptions.standard
        options.moveContentField(.taskName, by: 1)
        XCTAssertEqual(Array(options.contentOrder.prefix(2)), [.status, .taskName])
        options.moveContentField(.focus, by: 1)
        XCTAssertEqual(options.contentOrder.last, .focus)
        options.moveContentField(.taskName, by: -100)
        XCTAssertEqual(options.contentOrder.first, .taskName)
        options.moveContentField(.completedTime, by: 1)
        XCTAssertEqual(options.contentOrder, [.taskName, .status, .progress, .taskTime,
                                              .parentTask, .tags, .list, .focus])
        XCTAssertEqual(Set(options.contentOrder), Set(SummaryContentField.inlineOrder))
    }

    func testDisablingFieldKeepsItsOrderSlotAndStyle() {
        var options = SummaryDocumentOptions.standard
        options.contentStyles.list = .listGroup
        options.content.remove(.list)
        XCTAssertFalse(options.content.contains(.list))
        XCTAssertEqual(options.contentStyles.list, .listGroup)
        XCTAssertEqual(options.contentOrder.firstIndex(of: .list), 7)
        options.content.insert(.list)
        XCTAssertEqual(options.contentOrder.firstIndex(of: .list), 7)
        XCTAssertEqual(options.contentStyles.list, .listGroup)
    }

    func testCodableRoundTripPreservesOrderAndStyles() throws {
        var options = SummaryDocumentOptions()
        options.content = [.taskName, .list, .detail]
        options.contentOrder = [.list, .taskName, .status, .progress,
                                .taskTime, .parentTask, .tags, .focus]
        options.contentStyles.completedTime = .dateTime
        options.contentStyles.taskTime = .date
        options.contentStyles.list = .listGroup
        options.contentStyles.detail = .plain

        let decoded = try JSONDecoder().decode(SummaryDocumentOptions.self,
                                               from: JSONEncoder().encode(options))
        XCTAssertEqual(decoded, options)
        XCTAssertEqual(Array(decoded.contentOrder.prefix(2)), [.list, .taskName])
        XCTAssertEqual(decoded.contentStyles, options.contentStyles)
    }
}
