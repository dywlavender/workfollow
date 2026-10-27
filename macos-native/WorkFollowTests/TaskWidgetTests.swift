import AppKit
import Combine
import SwiftUI
import XCTest
@testable import WorkFollow

@MainActor
final class TaskWidgetTests: XCTestCase {
    private var calendar: Calendar {
        var value = Calendar(identifier: .gregorian)
        value.timeZone = TimeZone(secondsFromGMT: 8 * 3600)!
        return value
    }
    private var now: Date { calendar.date(from: DateComponents(year: 2026, month: 10, day: 23, hour: 10))! }
    private func day(_ offset: Int) -> Date { calendar.date(byAdding: .day, value: offset, to: calendar.startOfDay(for: now))! }
    private func task(_ title: String, due: Date? = nil, priority: TaskPriority = .none) throws -> Task {
        let workspace = TaskWorkspaceModel(clock: { self.now }, calendar: calendar, seedDemoData: false)
        let id = try XCTUnwrap(workspace.createTask(title: title, in: .inbox).taskID)
        var task = try XCTUnwrap(workspace.task(for: id))
        task.schedule = TaskSchedule(dueAt: due)
        task.priority = priority
        return task
    }
    private func directory() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("WorkFollowWidgetTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: url) }
        return url
    }

    func testTodayIncludesOverdueAndDeadlineTasksAndOmitsNestedDuplicates() throws {
        let overdue = try task("逾期", due: day(-1))
        let high = try task("重要", due: day(0), priority: .high)
        var child = try task("子任务", due: day(0)); child.parentID = high.id
        var deadline = try task("只有截止日期"); deadline.schedule.deadlineAt = now
        let tasks = [high, child, overdue, deadline, try task("明天", due: day(1)), try task("未安排")]
        let snapshot = TaskWidgetSnapshot(updatedAt: now, tasks: TaskWidgetBridge.items(tasks))
        let result = snapshot.today(at: now, calendar: calendar)
        XCTAssertEqual(result.remaining.map(\.title), ["逾期", "重要", "只有截止日期"])
        XCTAssertEqual(result.overdueCount, 1)
    }

    func testCompletionCountUsesCompletionDayAndSnapshotChangesAtMidnightWithoutTheApp() throws {
        var old = try task("以前完成", due: day(-4)); old.status = .completed; old.completedAt = day(-1)
        var done = try task("今日完成", due: day(0)); done.status = .completed; done.completedAt = now
        let tomorrow = try task("明天到期", due: day(1))
        let snapshot = TaskWidgetSnapshot(updatedAt: now, tasks: TaskWidgetBridge.items([old, done, tomorrow]))
        XCTAssertEqual(snapshot.today(at: now, calendar: calendar).completedCount, 1)
        XCTAssertTrue(snapshot.today(at: now, calendar: calendar).remaining.isEmpty)
        let next = snapshot.today(at: day(1), calendar: calendar)
        XCTAssertEqual(next.completedCount, 0)
        XCTAssertEqual(next.remaining.map(\.id), [tomorrow.id])
    }

    func testWeekCountIncludesUndatedWeeklyPlansAndExportOmitsUnavailableTasks() throws {
        var planned = try task("本周未定日期")
        planned.weeklyPlanning = TaskWeeklyPlanning(currentWeek: TaskWeeklyPlanning.key(for: now, calendar: calendar))
        var deleted = try task("已删除", due: day(0)); deleted.deletedAt = now
        var abandoned = try task("已放弃", due: day(0)); abandoned.abandonedAt = now
        var note = try task("已转笔记", due: day(0)); note.convertedNoteID = UUID()
        let snapshot = TaskWidgetSnapshot(updatedAt: now,
            tasks: TaskWidgetBridge.items([planned, deleted, abandoned, note, try task("下周", due: day(7))]))
        XCTAssertEqual(snapshot.tasks.count, 2)
        XCTAssertEqual(snapshot.today(at: now, calendar: calendar).weekRemainingCount, 1)
        XCTAssertTrue(snapshot.today(at: now, calendar: calendar).remaining.isEmpty)
    }

    func testWidgetCompletionPersistsThroughExistingActionsAndDuplicateRequestsDoNotAdvanceTheSeries() async throws {
        let root = try directory(), channel = TaskWidgetChannel(directory: root.appendingPathComponent("widget"))
        var recurring = try task("每天复盘", due: day(0)); recurring.recurrence = .daily
        let workspace = TaskWorkspaceModel(clock: { self.now }, calendar: calendar, initialTasks: [recurring])
        let current = try XCTUnwrap(workspace.task(for: recurring.id))
        let repository = NativePreviewRepository(directory: root.appendingPathComponent("workspace"))
        try repository.save(NativeWorkspaceSnapshot(tasks: workspace.allTasks, notes: []))
        let persistence = PersistenceCoordinator(repository: repository)
        let subscription = workspace.taskChanges.sink { persistence.schedule(changes: $0) }
        defer { subscription.cancel() }
        let command = TaskWidgetCompletion(taskID: current.id, expectedUpdatedAt: current.updatedAt)
        try channel.submit(command)
        var flushedBeforeAcknowledgement = false
        let bridge = TaskWidgetBridge(channel: channel, workspace: workspace, canProcess: { true }, flush: { completion in
            flushedBeforeAcknowledgement = (try? channel.receipt(for: command.id)) == nil
            persistence.flush(completion: completion)
        }, reload: {})
        await bridge.processPending()
        XCTAssertTrue(flushedBeforeAcknowledgement)
        XCTAssertEqual(workspace.task(for: current.id)?.status, .completed)
        XCTAssertNil(try XCTUnwrap(channel.receipt(for: command.id)).error)
        XCTAssertTrue(try channel.pending().isEmpty)
        XCTAssertEqual(try repository.load()?.tasks.first { $0.id == current.id }?.status, .completed)
        XCTAssertEqual(workspace.allTasks.filter { !$0.isClosed }.count, 1)
        let retry = TaskWidgetCompletion(taskID: current.id, expectedUpdatedAt: current.updatedAt)
        try channel.submit(retry)
        await bridge.processPending()
        XCTAssertEqual(workspace.allTasks.count, 2)
        XCTAssertEqual(workspace.allTasks.filter { !$0.isClosed }.count, 1)
        XCTAssertNil(try XCTUnwrap(channel.receipt(for: retry.id)).error)
        XCTAssertTrue(workspace.canUndo)
    }

    func testStaleWidgetRefreshesWithoutCompletingAnEditedTask() async throws {
        let channel = TaskWidgetChannel(directory: try directory())
        var value = try task("已改期", due: day(1))
        let stale = TaskWidgetCompletion(taskID: value.id, expectedUpdatedAt: value.updatedAt.addingTimeInterval(-5))
        value.updatedAt = now
        let workspace = TaskWorkspaceModel(clock: { self.now }, calendar: calendar, initialTasks: [value])
        try channel.submit(stale)
        let bridge = TaskWidgetBridge(channel: channel, workspace: workspace, canProcess: { true }, flush: { $0(nil) }, reload: {})
        await bridge.processPending()
        XCTAssertEqual(workspace.task(for: value.id)?.status, .active)
        XCTAssertNotNil(try XCTUnwrap(channel.receipt(for: stale.id)).error)
        XCTAssertEqual(try channel.readSnapshot()?.tasks.first?.dueAt, day(1))
    }

    func testLocalContainerWaitsForSystemInitializationThenSharesSnapshotsAndCompletionReceipts() async throws {
        let home = try directory(), identifier = "com.workfollow.widget-tests.widgets"
        let container = home.appendingPathComponent("Library/Containers/\(identifier)/Data", isDirectory: true)
        let support = container.appendingPathComponent("Library/Application Support", isDirectory: true)
        let host = TaskWidgetChannel.localContainer(extensionID: identifier, isExtension: false, home: home,
                                                   applicationSupport: home.appendingPathComponent("Library/Application Support"))
        let widget = TaskWidgetChannel.localContainer(extensionID: identifier, isExtension: true, home: container,
                                                     applicationSupport: support)
        XCTAssertEqual(host.directory, widget.directory)
        let snapshot = TaskWidgetSnapshot(updatedAt: now, tasks: TaskWidgetBridge.items([try task("本地组件", due: day(0))]))
        let value = try task("首次添加后重试", due: day(0))
        let workspace = TaskWorkspaceModel(clock: { self.now }, calendar: calendar, initialTasks: [value])
        let bridge = TaskWidgetBridge(channel: host, workspace: workspace, canProcess: { true }, flush: { $0(nil) }, reload: {})
        XCTAssertThrowsError(try host.publish(snapshot))
        XCTAssertFalse(FileManager.default.fileExists(atPath: container.path))
        try FileManager.default.createDirectory(at: support, withIntermediateDirectories: true)
        await bridge.processPending()
        let published = try XCTUnwrap(widget.readSnapshot())
        XCTAssertEqual(published.tasks, TaskWidgetBridge.items(workspace.allTasks))
        let item = try XCTUnwrap(published.tasks.first)
        let command = TaskWidgetCompletion(taskID: item.id, expectedUpdatedAt: item.updatedAt)
        try widget.submit(command)
        XCTAssertEqual(try host.pending(), [command])
        try host.acknowledge(command, error: nil)
        XCTAssertNil(try XCTUnwrap(widget.receipt(for: command.id)).error)
        XCTAssertTrue(try widget.pending().isEmpty)
    }

    func testWidgetLinksNavigateToCurrentWeekAndQuickAddWithoutChangingTaskData() throws {
        let root = try directory()
        try NativePreviewRepository(directory: root).save(NativeWorkspaceSnapshot(tasks: [], notes: []))
        let environment = AppEnvironment(clock: { self.now }, calendar: calendar, directory: root)
        defer { environment.widgetQuickAdd.dismiss() }
        environment.navigation.destination = .notes
        XCTAssertTrue(environment.openResourceLink(TaskWidgetLink.quickAdd))
        XCTAssertEqual(environment.navigation.destination, .notes)
        XCTAssertEqual(environment.quickAddRequest, 0)
        XCTAssertTrue(environment.widgetQuickAdd.panel?.isVisible == true)
        environment.weeklyPlanning.shift(-1)
        environment.weeklyPlanning.listName = "之前浏览的清单"
        XCTAssertTrue(environment.openResourceLink(TaskWidgetLink.weekPlan))
        XCTAssertEqual(environment.navigation.destination, .calendar)
        XCTAssertEqual(environment.navigation.calendarRevealRequest, SummaryReviewBuilder.weekStart(of: now, calendar: calendar))
        XCTAssertEqual(environment.weeklyPlanning.weekStart, SummaryReviewBuilder.weekStart(of: now, calendar: calendar))
        XCTAssertNil(environment.weeklyPlanning.listName)
        XCTAssertTrue(environment.openResourceLink(TaskWidgetLink.countdowns))
        XCTAssertEqual(environment.navigation.destination, .countdown)
        XCTAssertTrue(environment.taskWorkspace.allTasks.isEmpty)
    }

    func testCountdownSnapshotsFollowSmartListRulesAcrossPreparedDaysAndReadLegacyTasks() throws {
        let today = CountdownEvent(name: "周末", kind: .countdown, rule: .once(day(0)), smartListDisplay: .sameDay)
        let tomorrow = CountdownEvent(name: "发布日", kind: .countdown, rule: .once(day(1)), smartListDisplay: .sameDay)
        let hidden = CountdownEvent(name: "隐藏", rule: .once(day(0)), smartListDisplay: .never)
        let archived = CountdownEvent(name: "归档", rule: .once(day(0)), archivedAt: now)
        let items = TaskWidgetBridge.items([try task("今日任务", due: day(0))])
        let snapshot = TaskWidgetSnapshot(updatedAt: now, tasks: items,
            countdowns: TaskWidgetBridge.countdownItems([today, tomorrow, hidden, archived], now: now, calendar: calendar))
        XCTAssertEqual(snapshot.today(at: now, calendar: calendar).countdowns.map(\.id), [today.id])
        XCTAssertEqual(snapshot.today(at: now, calendar: calendar).entryCount, 2)
        XCTAssertEqual(snapshot.today(at: day(1), calendar: calendar).countdowns.map(\.id), [tomorrow.id])
        XCTAssertEqual(snapshot.today(at: day(1), calendar: calendar).countdowns.first?.relativeLabel, "今天")
        XCTAssertEqual(try JSONDecoder().decode(TaskWidgetSnapshot.self,
            from: JSONEncoder().encode(snapshot)), snapshot)
        var legacy = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(snapshot)) as? [String: Any])
        legacy.removeValue(forKey: "countdowns")
        let restored = try JSONDecoder().decode(TaskWidgetSnapshot.self,
            from: JSONSerialization.data(withJSONObject: legacy))
        XCTAssertNil(restored.countdowns)
        XCTAssertEqual(restored.tasks, items)
    }

    func testCountdownChangesRefreshWidgetWithoutEditingAnyTask() throws {
        let root = try directory(), channel = TaskWidgetChannel(directory: root.appendingPathComponent("widget"))
        let store = CountdownStore(clock: { self.now }, calendar: calendar, directory: root.appendingPathComponent("countdowns"))
        let workspace = TaskWorkspaceModel(clock: { self.now }, calendar: calendar, seedDemoData: false)
        let bridge = TaskWidgetBridge(channel: channel, workspace: workspace, countdowns: store,
            canProcess: { true }, flush: { $0(nil) }, reload: {})
        let event = store.add(name: "周末", kind: .countdown, rule: .once(day(0)), smartListDisplay: .sameDay)
        try InspectorPanelTestSupport.waitUntil("新增倒数日应主动刷新组件") {
            (try? channel.readSnapshot()?.today(at: self.now, calendar: self.calendar).countdowns.first?.id) == event.id
        }
        store.archive(event.id)
        try InspectorPanelTestSupport.waitUntil("归档倒数日应从组件移除") {
            (try? channel.readSnapshot()?.today(at: self.now, calendar: self.calendar).countdowns.isEmpty) == true
        }
        XCTAssertTrue(workspace.allTasks.isEmpty)
        XCTAssertTrue(try channel.pending().isEmpty)
        withExtendedLifetime(bridge) {}
    }

    func testMediumWidgetFitsAndRendersInLightAndDarkAppearance() throws {
        let directory = URL(fileURLWithPath: "/Users/dongyangwei/.codex/visualizations/2026/10/13/01a135b2-f44a-7673-88db-eb71f3dc8cc1/today-widget")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let values = try [task("准备项目评审", due: day(0), priority: .high),
                          task("整理本周的工作进展和下周需要跟进的事项", due: day(-1)),
                          task("核对设计稿", due: day(0), priority: .medium), task("阅读与学习", due: day(0))]
        var items = TaskWidgetBridge.items(values)
        items[0].dueAt = now
        items[0].hasTime = true
        let countdown = CountdownEvent(name: "周末", kind: .countdown, rule: .once(day(0)))
        let countdowns = TaskWidgetBridge.countdownItems([countdown], now: now, calendar: calendar)
        let mixed = TaskWidgetSnapshot(updatedAt: now, tasks: Array(items.prefix(3)), countdowns: countdowns)
        let tasksOnly = TaskWidgetSnapshot(updatedAt: now, tasks: items)
        let more = try (0..<15).map { try task("其它工作 \($0 + 1)", due: day(0)) }
        let overflow = TaskWidgetSnapshot(updatedAt: now, tasks: items + TaskWidgetBridge.items(more), countdowns: countdowns)
        let states: [(String, TaskWidgetSnapshot?)] = [
            ("", mixed), ("-tasks", tasksOnly), ("-overflow", overflow), ("-empty", .empty), ("-unavailable", nil)
        ]
        for (name, appearance) in [("light", NSAppearance.Name.aqua), ("dark", .darkAqua)] {
            for (suffix, value) in states {
                let heights: [CGFloat] = suffix.isEmpty ? [164, 154] : [164]
                for height in heights {
                    let sizeSuffix = height == 154 ? "-compact" : ""
                    let view = TodayTaskWidgetView(snapshot: value, date: now)
                        .environment(\.colorScheme, name == "light" ? .light : .dark)
                    let host = NSHostingView(rootView: view.frame(width: 344, height: height)
                        .background(Color(nsColor: .windowBackgroundColor)))
                    let owner = InspectorPanelTestSupport.ownerWindow(for: host, width: 344, height: height)
                    owner.appearance = NSAppearance(named: appearance)
                    InspectorPanelTestSupport.settle(owner)
                    let bitmap = try XCTUnwrap(host.bitmapImageRepForCachingDisplay(in: host.bounds))
                    host.cacheDisplay(in: host.bounds, to: bitmap)
                    if let value, value.today(at: now, calendar: calendar).entryCount > 0 {
                        let bands = leadingIconBands(in: bitmap, logicalWidth: 344, logicalHeight: height)
                        XCTAssertEqual(bands.count, min(4, value.today(at: now, calendar: calendar).entryCount),
                            "必须完整显示四行图标：\(name)\(suffix)\(sizeSuffix)")
                        let scale = CGFloat(bitmap.pixelsWide) / 344
                        XCTAssertTrue(bands.allSatisfy { CGFloat($0.count) >= 13 * scale },
                            "最后一行的勾选框不能被裁掉")
                        if height == 164 {
                            for (previous, next) in zip(bands, bands.dropFirst()) {
                                let pitch = CGFloat(next.lowerBound + next.upperBound - previous.lowerBound - previous.upperBound) / (2 * scale)
                                XCTAssertEqual(pitch, 29, accuracy: 1, "正常中号组件应保持参考图的行距")
                            }
                        }
                    }
                    try XCTUnwrap(bitmap.representation(using: .png, properties: [:]))
                        .write(to: directory.appendingPathComponent("medium-\(name)\(suffix)\(sizeSuffix).png"))
                    owner.close()
                }
            }
        }
    }


    /// Check the actual rendered icon column. App Intent controls do not expose
    /// useful AX frames in this XCTest host, so layout assertions use pixels.
    private func leadingIconBands(in bitmap: NSBitmapImageRep, logicalWidth: CGFloat,
                                  logicalHeight: CGFloat) -> [Range<Int>] {
        let scale = CGFloat(bitmap.pixelsWide) / logicalWidth
        var bands: [Range<Int>] = []
        var start: Int?
        let end = min(bitmap.pixelsHigh, Int((logicalHeight - 6) * scale))
        for y in Int(38 * scale)..<end {
            guard let background = bitmap.colorAt(x: Int(34 * scale), y: y)?.usingColorSpace(.sRGB) else { continue }
            let hasInk = (Int(12 * scale)..<Int(32 * scale)).contains { x in
                guard let color = bitmap.colorAt(x: x, y: y)?.usingColorSpace(.sRGB) else { return false }
                return max(abs(color.redComponent - background.redComponent),
                           max(abs(color.greenComponent - background.greenComponent),
                               abs(color.blueComponent - background.blueComponent))) > 0.07
            }
            if hasInk, start == nil { start = y }
            if !hasInk, let first = start { bands.append(first..<y); start = nil }
        }
        if let start { bands.append(start..<end) }
        return bands
    }

}
