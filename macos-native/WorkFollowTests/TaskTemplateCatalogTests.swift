import XCTest
@testable import WorkFollow

final class TaskTemplateCatalogTests: XCTestCase {
    func testBuiltInIDsAndCreationDatesAreStable() {
        let templates = BuiltInTaskTemplates.all

        XCTAssertEqual(templates.map(\.id), [
            UUID(uuidString: "10000000-0000-4000-8000-000000000001")!,
            UUID(uuidString: "10000000-0000-4000-8000-000000000002")!,
            UUID(uuidString: "10000000-0000-4000-8000-000000000003")!
        ])
        XCTAssertEqual(Set(templates.map(\.id)).count, templates.count)
        XCTAssertEqual(templates.map(\.createdAt), Array(
            repeating: Date(timeIntervalSince1970: 1_704_067_200), count: 3))
    }

    func testWorkPreparationUsesChecklistBlocksInsteadOfChildTasks() throws {
        let template = try XCTUnwrap(BuiltInTaskTemplates.all.first {
            $0.name == "每天工作前要做的几件事"
        })

        XCTAssertEqual(template.title, "每天工作前要做的几件事")
        XCTAssertEqual(template.document.blocks.map(\.kind), Array(repeating: .checklist(false), count: 7))
        XCTAssertEqual(template.document.blocks.map(\.plainText), [
            "简单回顾昨天的情况",
            "花点时间处理邮件和未读消息",
            "查看智能清单“今天”中的任务",
            "确定今天最重要的1~3件事，排好优先级",
            "Break the most difficult one into small check items",
            "给自己倒一杯水（或咖啡）",
            "休息5分钟，将状态调整到最佳"
        ])
        XCTAssertEqual(template.childTitles, [])
        XCTAssertEqual(template.schedule, .today)
        XCTAssertNil(template.listName)
    }

    func testDailyLogUsesParagraphBlocks() throws {
        let template = try XCTUnwrap(BuiltInTaskTemplates.all.first { $0.name == "每日记录" })

        XCTAssertEqual(template.document.blocks.map(\.kind), Array(repeating: .paragraph, count: 5))
        XCTAssertEqual(template.document.blocks.map(\.plainText), [
            "今天完成了什么？",
            "今天发生了哪些美好或值得关注的事？",
            "今天遇到了哪些突发问题？",
            "今天心情如何？",
            "今天有哪些感想或总结？"
        ])
    }

    func testTravelChecklistUsesChecklistBlocks() throws {
        let template = try XCTUnwrap(BuiltInTaskTemplates.all.first { $0.name == "旅行必备物品" })

        XCTAssertEqual(template.document.blocks.map(\.kind), Array(repeating: .checklist(false), count: 7))
        XCTAssertEqual(template.document.blocks.map(\.plainText), [
            "身份证 / 护照 / 学生证",
            "充电器 / 数据线",
            "晴雨伞",
            "易于携带的小背包",
            "衣物：上衣 / 下装",
            "衣物：换洗内衣裤",
            "鞋袜"
        ])
        XCTAssertEqual(template.childTitles, [])
    }

    func testCatalogComposesBuiltInsAndUserTemplatesAndSearchesAllFieldsCaseInsensitively() {
        let userTemplate = TaskTemplate(
            id: UUID(uuidString: "20000000-0000-4000-8000-000000000001")!,
            name: "user Template",
            title: "Quarterly REVIEW",
            document: NativeDocument(plainText: "SHIP report"),
            createdAt: Date(timeIntervalSince1970: 1_800_000_000))
        let allItems = TaskTemplateCatalog.items(userTemplates: [userTemplate])

        XCTAssertEqual(allItems.map(\.source), [.builtIn, .builtIn, .builtIn, .user])
        XCTAssertEqual(allItems.last?.id, userTemplate.id)
        XCTAssertEqual(TaskTemplateCatalog.items(userTemplates: [userTemplate], query: "USER TEMPLATE").map(\.id),
                       [userTemplate.id])
        XCTAssertEqual(TaskTemplateCatalog.items(userTemplates: [userTemplate], query: "quarterly review").map(\.id),
                       [userTemplate.id])
        XCTAssertEqual(TaskTemplateCatalog.items(userTemplates: [userTemplate], query: "ship REPORT").map(\.id),
                       [userTemplate.id])
    }

    func testCatalogDoesNotWriteBuiltInsToTemplateArchive() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("TaskTemplateCatalogTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        await MainActor.run {
            let store = TemplateStore(directory: directory)
            XCTAssertTrue(store.templates.isEmpty)

            let items = TaskTemplateCatalog.items(userTemplates: store.templates)
            XCTAssertEqual(items.map(\.source), Array(repeating: .builtIn, count: 3))
            XCTAssertFalse(FileManager.default.fileExists(
                atPath: directory.appendingPathComponent("templates.json").path))
        }
    }
}
