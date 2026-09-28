import XCTest
@testable import WorkFollow

/// 全局快速添加的"解析 → 建任务"管线测试：只测 GlobalQuickAddComposer，
/// 不触碰真实热键注册与面板。
final class GlobalQuickAddTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)
    private var calendar: Calendar {
        var value = Calendar(identifier: .gregorian)
        value.timeZone = TimeZone(secondsFromGMT: 0)!
        return value
    }

    func testPlainTextCreatesInboxTask() async {
        await MainActor.run {
            let workspace = TaskWorkspaceModel(clock: { self.now }, calendar: self.calendar,
                                               seedDemoData: false)
            let composer = GlobalQuickAddComposer(workspace: workspace)
            let id = composer.submit(text: "买牛奶")
            XCTAssertNotNil(id)
            let task = workspace.task(for: id!)
            XCTAssertEqual(task?.title, "买牛奶")
            XCTAssertEqual(task?.list, .inbox)
            XCTAssertEqual(task?.priority, TaskPriority.none)
            XCTAssertNil(task?.schedule.dueAt)
            XCTAssertEqual(task?.schedule.hasTime, false)
        }
    }

    func testParsedDateSchedulesTask() async {
        await MainActor.run {
            let workspace = TaskWorkspaceModel(clock: { self.now }, calendar: self.calendar,
                                               seedDemoData: false)
            let composer = GlobalQuickAddComposer(workspace: workspace)
            let id = composer.submit(text: "明天 交周报")
            XCTAssertNotNil(id)
            let expected = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: now))
            XCTAssertEqual(workspace.task(for: id!)?.schedule.dueAt, expected)
            XCTAssertEqual(workspace.task(for: id!)?.schedule.hasTime, false)
        }
    }

    func testParsedPriorityAppliesToTask() async {
        await MainActor.run {
            let workspace = TaskWorkspaceModel(clock: { self.now }, calendar: self.calendar,
                                               seedDemoData: false)
            let composer = GlobalQuickAddComposer(workspace: workspace)
            let id = composer.submit(text: "准备评审材料 !!")
            XCTAssertNotNil(id)
            XCTAssertEqual(workspace.task(for: id!)?.priority, .medium)
            XCTAssertEqual(workspace.task(for: id!)?.title, "准备评审材料")
        }
    }

    func testEmptyOrTokenOnlyTextReturnsNilWithoutCreatingTasks() async {
        await MainActor.run {
            let workspace = TaskWorkspaceModel(clock: { self.now }, calendar: self.calendar,
                                               seedDemoData: false)
            let composer = GlobalQuickAddComposer(workspace: workspace)
            XCTAssertNil(composer.submit(text: ""))
            XCTAssertNil(composer.submit(text: "   "))
            // 只有解析 token（明天）而无标题文本：不建任务。
            XCTAssertNil(composer.submit(text: "明天"))
            XCTAssertTrue(workspace.allTasks.isEmpty)
        }
    }

    func testKnownListRoutingAndInboxFallback() async {
        await MainActor.run {
            let workspace = TaskWorkspaceModel(clock: { self.now }, calendar: self.calendar,
                                               seedDemoData: false, initialLists: ["工作"])
            let composer = GlobalQuickAddComposer(workspace: workspace)
            let routed = composer.submit(text: "@工作 写季度总结")
            XCTAssertNotNil(routed)
            XCTAssertEqual(workspace.task(for: routed!)?.list, TaskList(name: "工作"))
            // 解析不到清单时进收集箱。
            let fallback = composer.submit(text: "随手记一条")
            XCTAssertNotNil(fallback)
            XCTAssertEqual(workspace.task(for: fallback!)?.list, .inbox)
        }
    }

    // MARK: - 接入：换行批量添加 / Tab 描述（与列表快速添加条共用 QuickAddComposition）

    func testNewlineBatchCreatesOneTaskPerLineWithPerLineParsing() async {
        await MainActor.run {
            let workspace = TaskWorkspaceModel(clock: { self.now }, calendar: self.calendar,
                                               seedDemoData: false)
            let composer = GlobalQuickAddComposer(workspace: workspace)
            let first = composer.submit(text: "买牛奶\n写周报 !!\n\n  明天 交材料  ")

            XCTAssertNotNil(first)
            XCTAssertEqual(workspace.allTasks.count, 3, "空行必须被丢掉，而不是建成空任务")
            // 返回首条 ID：调用方只需要知道「有没有建成」。
            XCTAssertEqual(workspace.task(for: first!)?.title, "买牛奶")
            XCTAssertEqual(Set(workspace.allTasks.map(\.title)), ["买牛奶", "写周报", "交材料"])

            // 行内仍然走智能识别，且行与行之间互不污染。
            XCTAssertEqual(workspace.allTasks.first { $0.title == "写周报" }?.priority, .medium)
            XCTAssertNil(workspace.allTasks.first { $0.title == "买牛奶" }?.schedule.dueAt)
            let expected = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: now))
            XCTAssertEqual(workspace.allTasks.first { $0.title == "交材料" }?.schedule.dueAt, expected)
        }
    }

    func testBatchSkipsLinesThatCarryTokensButNoTitle() async {
        await MainActor.run {
            let workspace = TaskWorkspaceModel(clock: { self.now }, calendar: self.calendar,
                                               seedDemoData: false)
            let composer = GlobalQuickAddComposer(workspace: workspace)
            // 首行只有 token（明天）没有标题：该行不建任务，同批次的其它行照常创建。
            let first = composer.submit(text: "明天\n买牛奶")

            XCTAssertNotNil(first)
            XCTAssertEqual(workspace.allTasks.count, 1)
            XCTAssertEqual(workspace.task(for: first!)?.title, "买牛奶")
        }
    }

    func testDescriptionFollowsSingleTaskAndIsIgnoredForBatch() async {
        await MainActor.run {
            let workspace = TaskWorkspaceModel(clock: { self.now }, calendar: self.calendar,
                                               seedDemoData: false)
            let composer = GlobalQuickAddComposer(workspace: workspace)

            let single = composer.submit(text: "写周报", description: "季度总结")
            XCTAssertEqual(workspace.task(for: single!)?.document.plainText, "季度总结")

            // 批量时每一行各自成任务，共享同一段描述没有意义——描述只跟随单条创建。
            let batchFirst = composer.submit(text: "甲\n乙", description: "不该挂上")
            XCTAssertNotNil(batchFirst)
            XCTAssertEqual(workspace.task(for: batchFirst!)?.title, "甲")
            for title in ["甲", "乙"] {
                XCTAssertEqual(workspace.allTasks.first { $0.title == title }?.document.isEmpty, true)
            }
        }
    }

    func testBlankDescriptionLeavesDocumentEmpty() async {
        await MainActor.run {
            let workspace = TaskWorkspaceModel(clock: { self.now }, calendar: self.calendar,
                                               seedDemoData: false)
            let composer = GlobalQuickAddComposer(workspace: workspace)
            let id = composer.submit(text: "写周报", description: "   \n  ")
            XCTAssertEqual(workspace.task(for: id!)?.document.isEmpty, true)
        }
    }

    // MARK: - 与列表快速添加条对齐：落点由「当前清单 / 当前标签」决定（审计 §三）

    /// 面板是个全局浮层，用户看不出它「属于」哪个视图，所以落点必须读当前清单。
    /// 改动前这里是 `parsed.listName ?? 收集箱`，面板建的任务**永远进不了当前清单**——
    /// 这是会丢数据的差异（任务建到了用户没在看的地方）。
    func testActiveListIsRespectedAndExplicitListTokenStillWins() async {
        await MainActor.run {
            let workspace = TaskWorkspaceModel(clock: { self.now }, calendar: self.calendar,
                                               seedDemoData: false, initialLists: ["工作", "个人"])
            let composer = GlobalQuickAddComposer(workspace: workspace)

            workspace.activeList = "工作"
            let inherited = composer.submit(text: "写周报")
            XCTAssertEqual(workspace.task(for: inherited!)?.list, TaskList(name: "工作"),
                           "没有 @清单 时应落到当前清单，而不是收集箱")

            // 显式 @清单 优先级更高，与列表条 `parsed.listName ?? activeList ?? 收集箱` 同序。
            let explicit = composer.submit(text: "@个人 写周报")
            XCTAssertEqual(workspace.task(for: explicit!)?.list, TaskList(name: "个人"),
                           "显式 @清单 必须压过当前清单")
        }
    }

    /// 当前标签要注入到新建任务上，否则用户在某个标签的筛选视图里新建的任务
    /// 会当场从眼前消失（任务建出来了，但不在当前筛选里）。
    func testActiveTagIsInheritedAndDeduplicatedAgainstTypedTags() async {
        await MainActor.run {
            let workspace = TaskWorkspaceModel(clock: { self.now }, calendar: self.calendar,
                                               seedDemoData: false)
            let composer = GlobalQuickAddComposer(workspace: workspace)

            workspace.activeTag = "日期"
            let id = composer.submit(text: "写周报 #日期 #验收")
            let tags = workspace.task(for: id!)?.tags ?? []
            XCTAssertEqual(tags, ["日期", "验收"], "当前标签在最前，且与手打的同名标签不重复")
        }
    }

    /// 面板里把识别错的 chip 点掉之后，重解析必须真的忽略那一段——
    /// 否则「点掉」只是视觉上消失，任务上仍然带着它。
    func testDismissedTokenIsIgnoredWhenSubmitting() async {
        await MainActor.run {
            let workspace = TaskWorkspaceModel(clock: { self.now }, calendar: self.calendar,
                                               seedDemoData: false)
            let composer = GlobalQuickAddComposer(workspace: workspace)

            let parsed = composer.parse("明天 交材料")
            guard let dateToken = parsed.tokens.first(where: { $0.kind == .date }) else {
                return XCTFail("「明天」应被识别为日期 token")
            }
            XCTAssertNotNil(parsed.dueAt)

            let id = composer.submit(text: "明天 交材料", dismissedTokenIDs: [dateToken.id])
            let task = workspace.task(for: id!)
            XCTAssertNil(task?.schedule.dueAt, "点掉的日期 chip 不能再落到任务上")
            XCTAssertEqual(task?.title, "明天 交材料",
                           "退化为普通标题文字（对齐 Flutter 遮罩重解析的最终效果），而不是从文本里消失")
        }
    }
}
