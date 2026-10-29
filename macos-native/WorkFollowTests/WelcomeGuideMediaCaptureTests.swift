import AppKit
import ImageIO
import SwiftUI
import UniformTypeIdentifiers
import XCTest
@testable import WorkFollow

/// 引导 GIF 的离线录制器（不是常规断言测试）。
///
/// 屏幕录制权限被拒，所以演示素材由测试宿主自己渲染真实界面、`cacheDisplay`
/// 逐帧抓取，再用 ImageIO 合成 GIF。只有存在 `/tmp/wf-capture-guide-media`
/// 时才运行，避免日常测试变慢或偷偷写资源目录。
@MainActor
final class WelcomeGuideMediaCaptureTests: XCTestCase {
    private static let captureFlag = "/tmp/wf-capture-guide-media"

    override func setUpWithError() throws {
        try XCTSkipUnless(FileManager.default.fileExists(atPath: Self.captureFlag),
                          "touch \(Self.captureFlag) to record guide demos.")
    }

    // MARK: - 演示脚本

    func testRecordQuickAdd() throws {
        let fixture = Fixture(destination: .today)
        defer { fixture.close() }
        seedTodayTasks(fixture.environment.taskWorkspace, now: fixture.now)

        let recorder = GuideGIFRecorder(window: fixture.window, host: fixture.host,
                                        output: try Self.output(named: "guide-quick-add"))
        recorder.start()
        recorder.parkCursor(at: CGPoint(x: 660, y: 520))

        let field = try fixture.field(identifier: "quick-add-title")
        let target = fixture.point(in: field)
        recorder.moveCursor(to: target, over: 0.45)
        recorder.wait(0.5)
        recorder.click(at: target)
        // 测试宿主不持前台激活，窗口拿不到 key status，NSTextField 不会因点击
        // 自己取焦点；这里补上真实的聚焦路径，展开与输入行为与用户点击一致。
        _ = fixture.window.makeFirstResponder(field)
        field.selectText(nil)
        recorder.wait(0.35)
        recorder.moveCursor(to: CGPoint(x: target.x + 120, y: target.y + 46), over: 0.25)

        try fixture.type("给团队写周报", characterDelay: 0.075, recorder: recorder)
        recorder.wait(0.55)
        try InspectorPanelTestSupport.sendReturn(to: fixture.window)
        recorder.wait(1.1)
        recorder.stop()
    }

    func testRecordScheduleDate() throws {
        let fixture = Fixture(destination: .today)
        defer { fixture.close() }
        let workspace = fixture.environment.taskWorkspace
        let ids = seedTodayTasks(workspace, now: fixture.now)
        let taskID = try XCTUnwrap(ids.first)
        workspace.select(taskID)
        fixture.settle(0.4)

        let recorder = GuideGIFRecorder(window: fixture.window, host: fixture.host,
                                        output: try Self.output(named: "guide-schedule"))
        recorder.start()
        recorder.parkCursor(at: CGPoint(x: 980, y: 520))

        let chip = try fixture.button(accessibilityLabelPrefix: "今天")
        let chipPoint = fixture.point(in: chip)
        recorder.moveCursor(to: chipPoint, over: 0.5)
        recorder.wait(0.4)
        recorder.click(at: chipPoint)
        if let action = chip.action {
            NSApp.sendAction(action, to: chip.target, from: chip)
        }
        recorder.wait(1.0)

        let panel = try XCTUnwrap(fixture.window.childWindows?.first {
            $0.title == "日期属性" && $0.isVisible
        })
        let content = try XCTUnwrap(panel.contentView)
        func clickPanel(_ rect: CGRect) throws {
            try InspectorPanelTestSupport.click(rect, in: content, window: panel)
        }
        let tomorrow = try XCTUnwrap(fixture.scheduleFrames[.shortcut("明天")]?.frame)
        let tomorrowPoint = fixture.point(
            screenFrame: panel.convertToScreen(content.convert(tomorrow, to: nil)))
        recorder.moveCursor(to: tomorrowPoint, over: 0.35)
        recorder.wait(0.25)
        recorder.click(at: tomorrowPoint)
        try clickPanel(tomorrow)
        recorder.wait(0.5)

        // 日期之后接着演示提醒：展开提醒行 → 勾选提前一天 → 确认子卡。
        let reminderRow = try XCTUnwrap(fixture.scheduleFrames[.row(.reminder)]?.frame)
        let reminderPoint = fixture.point(
            screenFrame: panel.convertToScreen(content.convert(reminderRow, to: nil)))
        recorder.moveCursor(to: reminderPoint, over: 0.4)
        recorder.wait(0.25)
        recorder.click(at: reminderPoint)
        try clickPanel(reminderRow)
        fixture.settle(0.6)

        func childPanel() throws -> NSPanel {
            try XCTUnwrap(panel.childWindows?.compactMap { $0 as? NSPanel }
                .first { $0.isVisible && $0.frame.width > 20 })
        }
        func clickChild(_ rect: CGRect) throws {
            let child = try childPanel()
            try InspectorPanelTestSupport.click(rect, in: try XCTUnwrap(child.contentView),
                                                window: child)
        }

        var offset: CGRect?
        let deadline = Date().addingTimeInterval(1.5)
        while Date() < deadline, offset == nil {
            offset = fixture.scheduleChildFrames[.reminderOffset(-1440)]?.frame
            if offset == nil { fixture.settle(0.05) }
        }
        let reminder = try XCTUnwrap(offset)
        let child = try childPanel()
        let reminderPoint2 = fixture.point(screenFrame: child.convertToScreen(
            try XCTUnwrap(child.contentView).convert(reminder, to: nil)))
        recorder.moveCursor(to: reminderPoint2, over: 0.35)
        recorder.wait(0.25)
        recorder.click(at: reminderPoint2)
        try clickChild(reminder)
        recorder.wait(0.4)

        var reminderFooterFrame: CGRect?
        let footerDeadline = Date().addingTimeInterval(1.5)
        while Date() < footerDeadline, reminderFooterFrame == nil {
            reminderFooterFrame = fixture.scheduleChildFrames[.editorFooter(.reminder)]?.frame
            if reminderFooterFrame == nil { fixture.settle(0.05) }
        }
        let reminderFooter = try XCTUnwrap(reminderFooterFrame,
            "child keys: \(fixture.scheduleChildFrames.keys.map(String.init(describing:)))")
        let reminderConfirm = CGRect(x: reminderFooter.minX + reminderFooter.width * 0.75,
                                     y: reminderFooter.midY - 10, width: 20, height: 20)
        let reminderConfirmPoint = fixture.point(screenFrame: child.convertToScreen(
            try XCTUnwrap(child.contentView).convert(reminderConfirm, to: nil)))
        recorder.moveCursor(to: reminderConfirmPoint, over: 0.35)
        recorder.wait(0.25)
        recorder.click(at: reminderConfirmPoint)
        try clickChild(reminderConfirm)
        recorder.wait(0.6)

        let footer = try XCTUnwrap(fixture.scheduleFrames[.mainFooter]?.frame)
        let confirm = CGRect(x: footer.minX + footer.width * 0.75, y: footer.midY - 10,
                             width: 20, height: 20)
        let confirmPoint = fixture.point(
            screenFrame: panel.convertToScreen(content.convert(confirm, to: nil)))
        recorder.moveCursor(to: confirmPoint, over: 0.35)
        recorder.wait(0.3)
        recorder.click(at: confirmPoint)
        try clickPanel(confirm)
        recorder.wait(1.0)
        recorder.stop()

        XCTAssertEqual(workspace.task(for: taskID)?.schedule.dueAt, workspace.dateFromToday(1))
        XCTAssertEqual(workspace.task(for: taskID)?.reminderOffsets, [-1440])
        XCTAssertFalse(panel.isVisible)
    }

    func testRecordCompleteTask() throws {
        let fixture = Fixture(destination: .today)
        defer { fixture.close() }
        let ids = seedTodayTasks(fixture.environment.taskWorkspace, now: fixture.now)
        let firstID = try XCTUnwrap(ids.first)
        fixture.settle(0.3)

        let recorder = GuideGIFRecorder(window: fixture.window, host: fixture.host,
                                        output: try Self.output(named: "guide-complete"))
        recorder.start()
        recorder.parkCursor(at: CGPoint(x: 980, y: 520))

        let checkbox = try XCTUnwrap(fixture.taskFrames[
            TaskTreeRenderAnchor(taskID: firstID, part: .checkbox)])
        let point = CGPoint(x: checkbox.midX, y: checkbox.midY)
        recorder.moveCursor(to: point, over: 0.5)
        recorder.wait(0.4)
        recorder.click(at: point)
        try InspectorPanelTestSupport.click(checkbox, in: fixture.host, window: fixture.window)
        recorder.wait(0.35)
        recorder.moveCursor(to: CGPoint(x: point.x + 170, y: point.y + 54), over: 0.3)
        recorder.wait(1.3)
        recorder.stop()
    }

    // MARK: 功能页导览

    func testRecordListsTour() throws {
        try recordTour("guide-list", navAnchor: "list.工作") { fixture in
            fixture.environment.navigation.destination = .allTasks
            fixture.environment.taskWorkspace.activeList = "工作"
            fixture.environment.taskWorkspace.activeTag = nil
        } seed: { fixture in
            let workspace = fixture.environment.taskWorkspace
            _ = workspace.addListSection("工作", title: "本周重点")
            guard let section = workspace.listSections(forList: "工作").first else { return }
            let first = workspace.createDraft(title: "整理季度目标", list: "工作",
                schedule: TaskSchedule(dueAt: fixture.now), priority: .high,
                tags: [], reminder: nil, repeatFrequency: .never,
                selectCreatedTask: false).taskID
            if let first { _ = workspace.setTaskSection(first, sectionID: section.id) }
            let second = workspace.createDraft(title: "和设计确认新版首页", list: "工作",
                schedule: TaskSchedule(dueAt: fixture.now), priority: .medium,
                tags: [], reminder: nil, repeatFrequency: .never,
                selectCreatedTask: false).taskID
            if let second { _ = workspace.setTaskSection(second, sectionID: section.id) }
            _ = workspace.createDraft(title: "回复客户邮件", list: "工作",
                schedule: TaskSchedule(dueAt: fixture.now), priority: .none,
                tags: [], reminder: nil, repeatFrequency: .never, selectCreatedTask: false)
        } after: { _, recorder in
            recorder.moveCursor(to: CGPoint(x: 520, y: 330), over: 0.6)
        }
    }

    func testRecordMatrixTour() throws {
        try recordTour("guide-matrix", navAnchor: "rail.四象限") { fixture in
            fixture.environment.navigate(to: .matrix)
        } seed: { fixture in
            self.seedPriorities(fixture)
        } after: { fixture, recorder in
            let workspace = fixture.environment.taskWorkspace
            let task = try XCTUnwrap(workspace.allTasks.first { $0.title == "准备季度复盘" })
            let source = CGPoint(x: 330, y: 190)
            let target = CGPoint(x: 950, y: 260)
            recorder.drag(from: source, to: target, over: 1.0)
            _ = workspace.moveTaskToMatrix(task.id, .schedule)
            recorder.wait(1.3)
            XCTAssertEqual(workspace.task(for: task.id)?.schedule.dueAt,
                           workspace.dateFromToday(7))
        }
    }

    func testRecordCalendarTour() throws {
        let settings = PlanningSettingsStore.shared
        let previousMode = settings.calendar.mode
        defer { settings.updateCalendar { $0.mode = previousMode } }
        settings.updateCalendar { $0.mode = .month }

        try recordTour("guide-calendar", navAnchor: "rail.日历") { fixture in
            fixture.environment.navigate(to: .calendar)
        } seed: { fixture in
            let workspace = fixture.environment.taskWorkspace
            let calendar = workspace.calendar
            let nine = calendar.date(bySettingHour: 9, minute: 0, second: 0, of: fixture.now)!
            let two = calendar.date(bySettingHour: 14, minute: 0, second: 0, of: fixture.now)!
            _ = workspace.createDraft(title: "产品评审会", list: "工作",
                schedule: TaskSchedule(dueAt: nine, hasTime: true), priority: .high,
                tags: [], reminder: nil, repeatFrequency: .never, selectCreatedTask: false)
            _ = workspace.createDraft(title: "整理下周排期", list: "工作",
                schedule: TaskSchedule(dueAt: two, hasTime: true), priority: .medium,
                tags: [], reminder: nil, repeatFrequency: .never, selectCreatedTask: false)
        } after: { fixture, recorder in
            let workspace = fixture.environment.taskWorkspace
            let task = try XCTUnwrap(workspace.allTasks.first { $0.title == "产品评审会" })

            settings.updateCalendar { $0.mode = .week }
            recorder.moveCursor(to: CGPoint(x: 1160, y: 28), over: 0.6)
            recorder.wait(1.0)
            settings.updateCalendar { $0.mode = .month }
            recorder.wait(1.0)

            let source = fixture.monthCellPoint(for: task.schedule.dueAt ?? fixture.now)
            let target = fixture.monthCellPoint(for: workspace.dateFromToday(1))
            recorder.drag(from: source, to: target, over: 0.9)
            let next = workspace.calendar.date(byAdding: .day, value: 1, to: task.schedule.dueAt!)!
            _ = workspace.setSchedule(task.id, TaskSchedule(dueAt: next, hasTime: true))
            recorder.wait(1.3)
            XCTAssertEqual(workspace.task(for: task.id)?.schedule.dueAt, next)
        }
    }

    func testRecordFocusTour() throws {
        try recordTour("guide-focus", navAnchor: "rail.专注") { fixture in
            fixture.environment.navigate(to: .focus)
        } seed: { fixture in
            _ = fixture.environment.taskWorkspace.createDraft(
                title: "完成季度复盘", list: "工作",
                schedule: TaskSchedule(dueAt: fixture.now), priority: .high,
                tags: [], reminder: nil, repeatFrequency: .never,
                selectCreatedTask: false)
        } after: { fixture, recorder in
            let workspace = fixture.environment.taskWorkspace
            let task = try XCTUnwrap(workspace.allTasks.first { $0.title == "完成季度复盘" })
            _ = fixture.environment.focusStore.start(taskID: task.id, minutes: 25)
            recorder.wait(1.2)
            recorder.moveCursor(to: CGPoint(x: 760, y: 400), over: 0.6)
            XCTAssertEqual(fixture.environment.focusStore.currentTaskID, task.id)
        }
    }

    func testRecordMeetingsTour() throws {
        try recordTour("guide-meetings", navAnchor: "rail.会议纪要") { fixture in
            fixture.environment.navigate(to: .meetings)
        } seed: { fixture in
            let store = fixture.environment.meetingStore
            store.create()
            guard let id = store.selectedID else { return }
            store.rename("产品周会")
            store.appendTranscriptForTesting("这周五前把新版首页设计稿交付给开发。", speaker: "张敏")
            store.appendTranscriptForTesting("下周一安排一次用户访谈，确认导航改版方向。", speaker: "李响")
            store.editMinutes("""
            ## 本周结论
            - 10 月 24 日前交付新版首页设计稿
            - 下周一安排 3 位用户访谈
            """)
            store.selectedID = id

            try? FileManager.default.createDirectory(at: fixture.directory, withIntermediateDirectories: true)
            let script = fixture.directory.appendingPathComponent("fixture-pi")
            try? """
            #!/bin/sh
            cat <<'RESULT'
            {"tasks":[{"title":"交付新版首页设计稿","quote":"10 月 24 日前交付新版首页设计稿"},{"title":"安排用户访谈","quote":"下周一安排 3 位用户访谈"}]}
            RESULT

            """.write(to: script, atomically: true, encoding: .utf8)
            try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: script.path)
            fixture.environment.meetingStore.configuration.executable = script.path
        } after: { fixture, recorder in
            let store = fixture.environment.meetingStore
            XCTAssertEqual(store.meetings.count, 1)
            let frame = try fixture.tourFrame("meeting.extract")
            let point = CGPoint(x: frame.midX, y: frame.midY)
            recorder.moveCursor(to: point, over: 0.9)
            recorder.wait(0.3)
            recorder.click(at: point)
            let screen = fixture.window.convertToScreen(fixture.host.convert(frame, to: nil))
            try InspectorPanelTestSupport.click(screenFrame: screen, in: fixture.window)

            // SwiftUI 只在 AX 虚拟元素上暴露「候选任务标题」，NSTextField 自身读不到；
            // 用有内容的标题输入框判断预览就绪。
            var sheet: NSWindow?
            let deadline = Date().addingTimeInterval(8)
            while Date() < deadline {
                if let attached = fixture.window.attachedSheet,
                   fixture.descendants(of: attached).compactMap({ $0 as? NSTextField })
                    .contains(where: { !$0.stringValue.isEmpty && $0.isEditable }) {
                    sheet = attached
                    break
                }
                fixture.settle(0.2)
            }
            let preview = try XCTUnwrap(sheet, "AI 提取预览未出现")
            let content = try XCTUnwrap(preview.contentView)
            content.layoutSubtreeIfNeeded()

            let draftField = try XCTUnwrap(fixture.descendants(of: preview)
                .compactMap { $0 as? NSTextField }.first { !$0.stringValue.isEmpty })
            let rowScreen = preview.convertToScreen(draftField.convert(draftField.bounds, to: nil))
            let rowPoint = fixture.point(screenFrame: rowScreen.insetBy(dx: -30, dy: -12))
            recorder.moveCursor(to: rowPoint, over: 0.6)
            recorder.wait(0.9)

            let create = CGRect(x: content.bounds.width - 122, y: content.bounds.height - 46,
                                width: 106, height: 30)
            let createPoint = fixture.point(
                screenFrame: preview.convertToScreen(content.convert(create, to: nil)))
            recorder.moveCursor(to: createPoint, over: 0.5)
            recorder.wait(0.35)
            recorder.click(at: createPoint)
            try InspectorPanelTestSupport.click(create, in: content, window: preview)
            recorder.wait(1.6)
            XCTAssertNil(fixture.window.attachedSheet, "创建后预览应关闭")
        }
    }

    func testRecordNotesTour() throws {
        try recordTour("guide-notes", navAnchor: "rail.笔记") { fixture in
            fixture.environment.navigate(to: .notes)
        } seed: { fixture in
            let notes = fixture.environment.notesWorkspace
            let id = notes.create(select: true)
            notes.edit(id) {
                $0.title = "读书笔记"
                $0.document = NativeDocument(plainText: "把想法和任务放在一起：\n· 读到有启发的一段，先记下来\n· 需要行动的部分，直接转成任务")
            }
        } after: { fixture, recorder in
            let editor = try XCTUnwrap(fixture.descendants(of: fixture.window)
                .compactMap { $0 as? NativeTextView }
                .first { $0.isEditable }, "笔记编辑器未出现")
            fixture.window.makeFirstResponder(editor)
            let text = editor.string as NSString
            let range = text.range(of: "需要行动的部分，直接转成任务")
            XCTAssertNotEqual(range.location, NSNotFound)
            editor.setSelectedRange(range)
            editor.refreshSelectionToolbar()
            recorder.wait(0.5)

            var toolbar: NSPanel?
            let deadline = Date().addingTimeInterval(2)
            while Date() < deadline {
                toolbar = fixture.window.childWindows?.compactMap { $0 as? NSPanel }
                    .first { $0.isVisible && $0.frame.height > 20 && $0.frame.height < 80 }
                if toolbar != nil { break }
                fixture.settle(0.05)
            }
            let panel = try XCTUnwrap(toolbar, "选区工具条未出现")
            let content = try XCTUnwrap(panel.contentView)
            let actionRect = CGRect(x: 10, y: content.bounds.midY - 13, width: 68, height: 26)
            let actionPoint = fixture.point(
                screenFrame: panel.convertToScreen(content.convert(actionRect, to: nil)))
            recorder.moveCursor(to: actionPoint, over: 0.6)
            recorder.wait(0.4)
            recorder.click(at: actionPoint)
            try InspectorPanelTestSupport.click(actionRect, in: content, window: panel)
            recorder.wait(1.2)

            let notes = fixture.environment.notesWorkspace
            let note = try XCTUnwrap(notes.notes.first { $0.title == "读书笔记" })
            XCTAssertFalse(note.linkedTaskIDs.isEmpty)
            recorder.moveCursor(to: CGPoint(x: 760, y: 380), over: 0.7)
        }
    }

    func testRecordAllTasksTour() throws {
        try recordTour("guide-all-tasks", navAnchor: "nav.所有任务") { fixture in
            fixture.environment.navigate(to: .allTasks)
        } seed: { fixture in
            let workspace = fixture.environment.taskWorkspace
            self.seedPriorities(fixture)
            if let tagged = workspace.allTasks.first?.id {
                _ = workspace.setTags(tagged, ["会议"])
            }
        } after: { fixture, recorder in
            fixture.environment.taskWorkspace.activeTag = "会议"
            recorder.wait(0.8)
            recorder.moveCursor(to: CGPoint(x: 330, y: 420), over: 0.6)
        }
    }

    func testRecordSummaryTour() throws {
        try recordTour("guide-summary", navAnchor: "nav.摘要") { fixture in
            fixture.environment.navigate(to: .summary)
        } seed: { fixture in
            let workspace = fixture.environment.taskWorkspace
            for title in ["交付新版首页", "完成产品周报", "整理季度目标"] {
                if let id = workspace.createDraft(title: title, list: "工作",
                    schedule: TaskSchedule(dueAt: fixture.now), priority: .high,
                    tags: [], reminder: nil, repeatFrequency: .never,
                    selectCreatedTask: false).taskID {
                    _ = workspace.complete(id)
                }
            }
            self.seedPriorities(fixture)
        } after: { fixture, recorder in
            recorder.moveCursor(to: CGPoint(x: 700, y: 330), over: 0.7)
            recorder.wait(0.4)

            let copyFrame = try fixture.tourFrame("summary.footer.复制")
            let copyPoint = CGPoint(x: copyFrame.midX, y: copyFrame.midY)
            recorder.moveCursor(to: copyPoint, over: 0.5)
            recorder.wait(0.25)
            recorder.click(at: copyPoint)
            let copyScreen = fixture.window.convertToScreen(fixture.host.convert(copyFrame, to: nil))
            try InspectorPanelTestSupport.click(screenFrame: copyScreen, in: fixture.window)

            try fixture.waitForMenuRows(3)
            let menu = try InspectorPanelTestSupport.panel(title: "复制", below: fixture.window)
            let content = try XCTUnwrap(menu.contentView)
            let row = try XCTUnwrap(fixture.menuRows.first)
            let rowPoint = fixture.point(
                screenFrame: menu.convertToScreen(content.convert(row.rect, to: nil)))
            recorder.moveCursor(to: rowPoint, over: 0.5)
            recorder.wait(0.3)
            recorder.click(at: rowPoint)
            try InspectorPanelTestSupport.click(row.rect, in: content, window: menu)
            recorder.wait(0.4)
            recorder.moveCursor(to: CGPoint(x: 760, y: 360), over: 0.3)
            recorder.wait(0.2)
            XCTAssertTrue(NSPasteboard.general.string(forType: .string)?.contains("交付新版首页") == true)
        }
    }

    private func seedPriorities(_ fixture: Fixture) {
        let workspace = fixture.environment.taskWorkspace
        let specs: [(String, TaskPriority)] = [
            ("准备季度复盘", .high), ("整理销售数据", .medium), ("预订出差机票", .low)
        ]
        for (title, priority) in specs {
            _ = workspace.createDraft(title: title, list: "工作",
                schedule: TaskSchedule(dueAt: fixture.now), priority: priority,
                tags: [], reminder: nil, repeatFrequency: .never, selectCreatedTask: false)
        }
    }

    private func recordTour(_ name: String, navAnchor: String,
                            navigate: (Fixture) -> Void,
                            seed: (Fixture) throws -> Void,
                            after: (Fixture, GuideGIFRecorder) throws -> Void) throws {
        let fixture = Fixture(destination: .today)
        defer { fixture.close() }
        try seed(fixture)
        fixture.settle(0.4)

        let recorder = GuideGIFRecorder(window: fixture.window, host: fixture.host,
                                        output: try Self.output(named: name))
        recorder.start()
        recorder.parkCursor(at: CGPoint(x: 700, y: 640))

        let navPoint = try fixture.tourPoint(navAnchor)
        recorder.moveCursor(to: navPoint, over: 0.5)
        recorder.wait(0.4)
        recorder.click(at: navPoint)
        let clickRect = CGRect(x: navPoint.x - 1, y: navPoint.y - 1, width: 2, height: 2)
        try InspectorPanelTestSupport.click(clickRect, in: fixture.host, window: fixture.window)
        navigate(fixture)
        recorder.wait(1.2)
        try after(fixture, recorder)
        recorder.wait(1.2)
        recorder.stop()
    }

    func testRecordWelcomeSheet() throws {
        let fixture = Fixture(destination: .today)
        defer { fixture.close() }
        let suite = "welcome-sheet-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }

        XCTAssertEqual(fixture.environment.ensureWelcomeGuideIfNeeded(defaults: defaults, allowInTests: true), .seeded)
        fixture.settle(0.8)

        let sheet = try XCTUnwrap(fixture.window.attachedSheet)
        let content = try XCTUnwrap(sheet.contentView)
        content.layoutSubtreeIfNeeded()
        let bitmap = try XCTUnwrap(content.bitmapImageRepForCachingDisplay(in: content.bounds))
        content.cacheDisplay(in: content.bounds, to: bitmap)
        let data = try XCTUnwrap(bitmap.representation(using: .png, properties: [:]))
        try data.write(to: URL(fileURLWithPath: "/private/tmp/guide-welcome-sheet.png"))

        XCTAssertTrue(fixture.environment.taskWorkspace.listNames.contains(WelcomeGuide.listName))
    }

    func testRecordFloatingNote() throws {
        let fixture = Fixture(destination: .today)
        defer { fixture.close() }
        seedTodayTasks(fixture.environment.taskWorkspace, now: fixture.now)

        let recorder = GuideGIFRecorder(window: fixture.window, host: fixture.host,
                                        output: try Self.output(named: "guide-floating-note"))
        var floating: NSWindow?
        // 悬浮笔记是独立 NSPanel，不在主窗口的 childWindows 里。
        recorder.extraWindows = { floating.map { [$0] } ?? [] }
        // 控制器是全局单例；用例自己接线，别依赖其它用例先跑过。
        FloatingNoteWindowController.shared.attach(environment: fixture.environment)
        recorder.start()
        recorder.parkCursor(at: CGPoint(x: 700, y: 640))

        let noteID = try XCTUnwrap(fixture.environment.newFloatingNote())
        defer { FloatingNoteWindowController.shared.close(noteID: noteID) }
        let window = try XCTUnwrap(NSApp.windows.first {
            $0.title == "笔记浮窗" && $0.isVisible
        })
        floating = window
        let mainFrame = fixture.window.frame
        window.setFrameOrigin(NSPoint(x: mainFrame.minX + 680, y: mainFrame.minY + 140))
        recorder.wait(0.9)

        let center = fixture.point(screenFrame: window.frame)
        recorder.moveCursor(to: CGPoint(x: center.x - 170, y: center.y - 250), over: 0.5)
        recorder.wait(0.3)
        if let editor = fixture.descendants(of: window).compactMap({ $0 as? NSTextView })
            .first(where: \.isEditable) {
            _ = window.makeFirstResponder(editor)
        }
        try fixture.type("边看资料边记：\n把刚想到的先写在这里。", in: window,
                         characterDelay: 0.06, recorder: recorder)
        recorder.wait(1.4)
        recorder.stop()
    }

    func testRecordCommandPalette() throws {
        let fixture = Fixture(destination: .today)
        defer { fixture.close() }
        let workspace = fixture.environment.taskWorkspace
        seedTodayTasks(workspace, now: fixture.now)
        _ = workspace.createDraft(title: "整理会议笔记", list: "工作",
            schedule: TaskSchedule(dueAt: fixture.now), priority: .medium,
            tags: [], reminder: nil, repeatFrequency: .never, selectCreatedTask: false)

        let recorder = GuideGIFRecorder(window: fixture.window, host: fixture.host,
                                        output: try Self.output(named: "guide-command-palette"))
        recorder.extraWindows = { [fixture.window.attachedSheet].compactMap { $0 } }
        recorder.start()
        recorder.parkCursor(at: CGPoint(x: 700, y: 640))

        let search = CGPoint(x: 31, y: 725)
        recorder.moveCursor(to: search, over: 0.45)
        recorder.wait(0.3)
        recorder.click(at: search)
        fixture.environment.commandPalettePresented = true
        recorder.wait(0.9)

        let sheet = try XCTUnwrap(fixture.window.attachedSheet)
        let field = try XCTUnwrap(fixture.descendants(of: sheet).compactMap { $0 as? NSTextField }
            .first { ($0.placeholderString ?? "").contains("搜索") })
        let fieldPoint = fixture.point(
            screenFrame: sheet.convertToScreen(field.convert(field.bounds, to: nil)))
        recorder.moveCursor(to: fieldPoint, over: 0.35)
        _ = sheet.makeFirstResponder(field)
        field.selectText(nil)
        try fixture.type("笔记", in: sheet, characterDelay: 0.14, recorder: recorder)
        recorder.wait(0.8)
        let fieldScreen = sheet.convertToScreen(field.convert(field.bounds, to: nil))
        let rowFrame = CGRect(x: fieldScreen.midX + 150, y: fieldScreen.midY - 80,
                              width: 40, height: 20)
        recorder.moveCursor(to: fixture.point(screenFrame: rowFrame), over: 0.35)
        recorder.wait(0.25)
        recorder.click(at: fixture.point(screenFrame: rowFrame))
        try InspectorPanelTestSupport.click(screenFrame: rowFrame, in: sheet)
        recorder.wait(1.2)
        recorder.stop()
    }

    private func seedTodayTasks(_ workspace: TaskWorkspaceModel, now: Date) -> [UUID] {
        ["整理本周会议纪要", "回复客户邮件", "预订下周会议室"].compactMap { title in
            workspace.createDraft(title: title, list: "工作",
                                  schedule: TaskSchedule(dueAt: now), priority: .none,
                                  tags: [], reminder: nil, repeatFrequency: .never,
                                  selectCreatedTask: false).taskID
        }
    }

    private static func output(named name: String) throws -> URL {
        try outputDirectory().appendingPathComponent(name + ".gif")
    }

    private static func outputDirectory() throws -> URL {
        if let override = ProcessInfo.processInfo.environment["WF_GUIDE_MEDIA_OUT"] {
            return URL(fileURLWithPath: override, isDirectory: true)
        }
        let repo = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        return repo.appendingPathComponent("WorkFollow/Resources/WelcomeGuide", isDirectory: true)
    }

    // MARK: - 窗口夹具

    @MainActor
    private final class Fixture {
        let now: Date
        let directory: URL
        let environment: AppEnvironment
        let host: NSHostingView<AnyView>
        let window: NSWindow
        let frameBox = TaskFrameBox()
        let scheduleBox = ScheduleFrameBox()
        let tourBox = GuideTourFrameBox()
        let menuBox = MenuRowBox()

        init(destination: NativeDestination) {
            var calendar = Calendar(identifier: .gregorian)
            calendar.timeZone = TimeZone(secondsFromGMT: 28800)!
            let fixedNow = calendar.date(from: DateComponents(year: 2026, month: 10, day: 21, hour: 12))!
            now = fixedNow
            directory = FileManager.default.temporaryDirectory
                .appendingPathComponent("guide-media-" + UUID().uuidString)
            environment = AppEnvironment(clock: { fixedNow }, calendar: calendar, directory: directory)
            environment.navigation.destination = destination
            let frames = frameBox
            let schedule = scheduleBox
            let tour = tourBox
            let menu = menuBox
            host = NSHostingView(rootView: AnyView(
                RootShellView(workspace: environment.taskWorkspace, navigation: environment.navigation)
                    .environmentObject(environment)
                    .environment(\.recordsTaskTreeFrames, true)
                    .coordinateSpace(name: "task-tree-render")
                    .onPreferenceChange(TaskTreeFramesKey.self) { frames.frames = $0 }
                    .coordinateSpace(name: "guide-tour-render")
                    .onPreferenceChange(GuideTourFramesKey.self) { tour.frames = $0 }
                    .environment(\.popupContentObservation, { content in
                        AnyView(content
                            .coordinateSpace(name: "schedule-render")
                            .onPreferenceChange(ScheduleFramesKey.self) { values in
                                if values[.panel] != nil { schedule.main = values }
                                else if !values.isEmpty { schedule.child = values }
                            }
                            .onPreferenceChange(BusinessMenuRowFrames.self) { values in
                                if !values.isEmpty { menu.rows = values }
                            })
                    })))
            window = InspectorPanelTestSupport.ownerWindow(for: host, width: 1280, height: 800)
            settle()
        }

        func settle(_ duration: TimeInterval = 0.2) {
            host.layoutSubtreeIfNeeded()
            RunLoop.current.run(until: Date().addingTimeInterval(duration))
            host.layoutSubtreeIfNeeded()
        }

        func field(identifier: String) throws -> NSTextField {
            let deadline = Date().addingTimeInterval(2)
            while Date() < deadline {
                if let field = descendants(of: window)
                    .compactMap({ $0 as? NSTextField })
                    .first(where: { $0.identifier?.rawValue == identifier }) {
                    return field
                }
                settle(0.1)
            }
            throw XCTSkip("Missing field " + identifier)
        }

        func point(in view: NSView) -> CGPoint {
            let rect = view.convert(view.bounds, to: host)
            return CGPoint(x: rect.midX, y: rect.midY)
        }

        /// AX 帧是屏幕坐标；光标轨迹用详情栏（host）坐标。
        func point(screenFrame: CGRect) -> CGPoint {
            let local = host.convert(window.convertFromScreen(screenFrame), from: nil)
            return CGPoint(x: local.midX, y: local.midY)
        }

        var taskFrames: [TaskTreeRenderAnchor: CGRect] { frameBox.frames }
        var scheduleFrames: [ScheduleRenderAnchor: ScheduleRenderValue] { scheduleBox.main }
        var scheduleChildFrames: [ScheduleRenderAnchor: ScheduleRenderValue] { scheduleBox.child }

        func button(accessibilityLabelPrefix prefix: String) throws -> NSButton {
            let deadline = Date().addingTimeInterval(2)
            while Date() < deadline {
                let matches = descendants(of: window).compactMap({ $0 as? NSButton })
                    .filter { ($0.accessibilityLabel() ?? "").hasPrefix(prefix) }
                if let button = matches.max(by: { point(in: $0).x < point(in: $1).x }) {
                    return button
                }
                settle(0.1)
            }
            let labels = descendants(of: window).compactMap { $0 as? NSButton }
                .map { String(describing: $0.accessibilityLabel()) }
            print("guide capture: available buttons", labels)
            throw XCTSkip("Missing button " + prefix)
        }

        func tourFrame(_ id: String) throws -> CGRect {
            let deadline = Date().addingTimeInterval(2)
            while Date() < deadline {
                if let frame = tourBox.frames[id], !frame.isEmpty { return frame }
                settle(0.1)
            }
            throw XCTSkip("Missing tour anchor " + id)
        }

        func tourPoint(_ id: String) throws -> CGPoint {
            let frame = try tourFrame(id)
            return CGPoint(x: frame.midX, y: frame.midY)
        }

        var menuRows: [BusinessMenuRowFrame] { menuBox.rows }

        func waitForMenuRows(_ count: Int, timeout: TimeInterval = 2) throws {
            let deadline = Date().addingTimeInterval(timeout)
            while Date() < deadline {
                if menuBox.rows.count >= count { return }
                settle(0.05)
            }
            throw XCTSkip("Menu rows did not appear: \(menuBox.rows.count)/\(count)")
        }

        /// 月视图格心。日历页没有暴露日期格锚点，按工具栏/周标题/6 行网格
        /// 的生产几何换算；只用于演示光标落点，日期改动由工作区真实执行。
        func monthCellPoint(for day: Date) -> CGPoint {
            let calendar = environment.taskWorkspace.calendar
            let month = calendar.date(from: calendar.dateComponents([.year, .month], from: day)) ?? day
            let days = PlanningProjection.monthGridDays(containing: month, calendar: calendar)
            let target = calendar.startOfDay(for: day)
            let index = days.firstIndex { calendar.isDate($0, inSameDayAs: target) } ?? 0
            let column = index % 7
            let row = index / 7
            let left: CGFloat = 62
            let top: CGFloat = 88
            let width = host.bounds.width - left - 10
            let height = host.bounds.height - top - 10
            return CGPoint(x: left + (CGFloat(column) + 0.5) * width / 7,
                           y: top + (CGFloat(row) + 0.55) * height / 6)
        }

        func click(_ view: NSView) throws {
            try InspectorPanelTestSupport.click(view.convert(view.bounds, to: host),
                                                in: host, window: window)
        }


        func type(_ text: String, characterDelay: TimeInterval,
                  recorder: GuideGIFRecorder) throws {
            try type(text, in: window, characterDelay: characterDelay, recorder: recorder)
        }

        func type(_ text: String, in window: NSWindow, characterDelay: TimeInterval,
                  recorder: GuideGIFRecorder) throws {
            for character in text {
                if character == "\n" {
                    try sendReturn(to: window)
                    recorder.wait(characterDelay)
                    continue
                }
                let event = try XCTUnwrap(NSEvent.keyEvent(
                    with: .keyDown, location: .zero, modifierFlags: [],
                    timestamp: ProcessInfo.processInfo.systemUptime,
                    windowNumber: window.windowNumber, context: nil,
                    characters: String(character), charactersIgnoringModifiers: String(character),
                    isARepeat: false, keyCode: 0))
                window.sendEvent(event)
                recorder.wait(characterDelay)
            }
        }

        func sendReturn(to window: NSWindow) throws {
            let event = try XCTUnwrap(NSEvent.keyEvent(
                with: .keyDown, location: .zero, modifierFlags: [],
                timestamp: ProcessInfo.processInfo.systemUptime,
                windowNumber: window.windowNumber, context: nil,
                characters: "\r", charactersIgnoringModifiers: "\r",
                isARepeat: false, keyCode: 36))
            window.sendEvent(event)
        }

        func descendants(of window: NSWindow) -> [NSView] {
            var result: [NSView] = []
            func walk(_ view: NSView) {
                result.append(view)
                view.subviews.forEach(walk)
            }
            if let content = window.contentView { walk(content) }
            for child in window.childWindows ?? [] {
                if let content = child.contentView { walk(content) }
            }
            return result
        }

        func close() {
            window.childWindows?.forEach { $0.orderOut(nil) }
            window.contentView = nil
            window.close()
            try? FileManager.default.removeItem(at: directory)
        }
    }
}

@MainActor
private final class TaskFrameBox {
    var frames: [TaskTreeRenderAnchor: CGRect] = [:]
}

@MainActor
private final class ScheduleFrameBox {
    var main: [ScheduleRenderAnchor: ScheduleRenderValue] = [:]
    var child: [ScheduleRenderAnchor: ScheduleRenderValue] = [:]
}

@MainActor
private final class GuideTourFrameBox {
    var frames: [String: CGRect] = [:]
}

@MainActor
private final class MenuRowBox {
    var rows: [BusinessMenuRowFrame] = []
}

// MARK: - 录制器

@MainActor
private final class GuideGIFRecorder {
    private let window: NSWindow
    private let host: NSView
    private let output: URL
    private let frameInterval: TimeInterval = 0.1
    private let targetWidth: CGFloat = 960

    private var frames: [(image: CGImage, time: TimeInterval)] = []
    private var timer: Timer?
    private var captureStart = Date()
    private var cursorMarks: [(TimeInterval, CGPoint)] = []
    private var clickMarks: [(TimeInterval, CGPoint)] = []
    /// 独立窗口（悬浮笔记等）与 sheet 不在 childWindows 里，录制时单独叠加。
    var extraWindows: () -> [NSWindow] = { [] }

    init(window: NSWindow, host: NSView, output: URL) {
        self.window = window
        self.host = host
        self.output = output
    }

    private var elapsed: TimeInterval { Date().timeIntervalSince(captureStart) }

    func start() {
        captureStart = Date()
        captureFrame()
        let timer = Timer(timeInterval: frameInterval, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.captureFrame() }
        }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    func wait(_ seconds: TimeInterval) {
        RunLoop.current.run(until: Date().addingTimeInterval(seconds))
    }

    func parkCursor(at point: CGPoint) {
        cursorMarks.append((elapsed, point))
    }

    func moveCursor(to point: CGPoint, over duration: TimeInterval) {
        let startPoint = cursorMarks.last?.1 ?? point
        let steps = max(2, Int(duration / (frameInterval / 2)))
        for step in 1...steps {
            let progress = CGFloat(step) / CGFloat(steps)
            let eased = progress * progress * (3 - 2 * progress)
            let point = CGPoint(x: startPoint.x + (point.x - startPoint.x) * eased,
                                y: startPoint.y + (point.y - startPoint.y) * eased)
            cursorMarks.append((elapsed, point))
            wait(duration / TimeInterval(steps))
        }
    }

    func click(at point: CGPoint) {
        clickMarks.append((elapsed, point))
    }

    /// 演示级拖拽：光标沿路径移动，落到目标后由调用方执行真实状态变更。
    func drag(from start: CGPoint, to end: CGPoint, over duration: TimeInterval) {
        moveCursor(to: start, over: 0.35)
        wait(0.15)
        clickMarks.append((elapsed, start))
        let steps = max(6, Int(duration / (frameInterval / 2)))
        for step in 1...steps {
            let progress = CGFloat(step) / CGFloat(steps)
            let point = CGPoint(x: start.x + (end.x - start.x) * progress,
                                y: start.y + (end.y - start.y) * progress)
            cursorMarks.append((elapsed, point))
            wait(duration / TimeInterval(steps))
        }
    }

    func stop() {
        timer?.invalidate()
        timer = nil
        guard !frames.isEmpty else { return }
        try? FileManager.default.createDirectory(at: output.deletingLastPathComponent(),
                                                 withIntermediateDirectories: true)
        let decorated = frames.map { decorate($0.image, at: $0.time) }
        writeGIF(decorated)
        writeSamples(decorated)
    }

    // MARK: 抓帧

    private func captureFrame() {
        guard let composite = compositeWindowGraph() else { return }
        let width = Int(targetWidth)
        let height = max(1, Int((CGFloat(composite.height) * targetWidth
                                 / CGFloat(composite.width)).rounded()))
        guard let context = CGContext(data: nil, width: width, height: height,
                                      bitsPerComponent: 8, bytesPerRow: 0,
                                      space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        else { return }
        context.interpolationQuality = .high
        context.draw(composite, in: CGRect(x: 0, y: 0, width: width, height: height))
        if let image = context.makeImage() { frames.append((image, elapsed)) }
    }

    private func compositeWindowGraph() -> CGImage? {
        guard let content = window.contentView else { return nil }
        let scale = window.backingScaleFactor
        let width = Int((content.bounds.width * scale).rounded())
        let height = Int((content.bounds.height * scale).rounded())
        guard let context = CGContext(data: nil, width: width, height: height,
                                      bitsPerComponent: 8, bytesPerRow: 0,
                                      space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        else { return nil }
        context.interpolationQuality = .high
        if let main = render(content) {
            context.draw(main, in: CGRect(x: 0, y: 0, width: width, height: height))
        }
        let mainScreen = window.convertToScreen(content.convert(content.bounds, to: nil))
        // 弹层可以再挂弹层（日程面板 → 属性子卡片），只抓直接子窗口会漏掉孙窗口。
        var overlays: [NSWindow] = []
        var seen = Set<ObjectIdentifier>()
        func appendTree(_ root: NSWindow) {
            guard seen.insert(ObjectIdentifier(root)).inserted else { return }
            overlays.append(root)
            for child in root.childWindows ?? [] { appendTree(child) }
        }
        for child in window.childWindows ?? [] { appendTree(child) }
        if let sheet = window.attachedSheet { appendTree(sheet) }
        for extra in extraWindows() { appendTree(extra) }
        for child in overlays where child.isVisible {
            guard let childContent = child.contentView,
                  childContent.bounds.width >= 2, childContent.bounds.height >= 2,
                  let image = render(childContent) else { continue }
            let screen = child.convertToScreen(childContent.convert(childContent.bounds, to: nil))
            let x = (screen.minX - mainScreen.minX) * scale
            // 位图坐标原点在左下：子窗口的底边减去主窗口底边，不能用顶边差。
            let y = (screen.minY - mainScreen.minY) * scale
            let rect = CGRect(x: x, y: y, width: screen.width * scale,
                              height: screen.height * scale)
            // 内容位图没有窗口阴影；补一层，弹层与悬浮笔记才像浮在页面上。
            context.saveGState()
            context.setShadow(offset: CGSize(width: 0, height: -3 * scale),
                              blur: 9 * scale,
                              color: NSColor.black.withAlphaComponent(0.30).cgColor)
            let backing = CGPath(roundedRect: rect.insetBy(dx: 1, dy: 1),
                                 cornerWidth: 10 * scale, cornerHeight: 10 * scale,
                                 transform: nil)
            context.addPath(backing)
            context.setFillColor(NSColor.windowBackgroundColor.cgColor)
            context.fillPath()
            context.restoreGState()
            context.draw(image, in: rect)
        }
        return context.makeImage()
    }

    private func render(_ view: NSView) -> CGImage? {
        view.layoutSubtreeIfNeeded()
        guard let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { return nil }
        view.cacheDisplay(in: view.bounds, to: rep)
        return rep.cgImage
    }

    // MARK: 光标与合成

    private func decorate(_ frame: CGImage, at time: TimeInterval) -> CGImage {
        guard let point = cursorPoint(at: time) else { return frame }
        let width = frame.width
        let height = frame.height
        guard let context = CGContext(data: nil, width: width, height: height,
                                      bitsPerComponent: 8, bytesPerRow: 0,
                                      space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        else { return frame }
        context.draw(frame, in: CGRect(x: 0, y: 0, width: width, height: height))
        let sx = CGFloat(width) / host.bounds.width
        let sy = CGFloat(height) / host.bounds.height

        if let click = clickMarks.last(where: { $0.0 <= time }) {
            let age = time - click.0
            if age < 0.32 {
                let progress = CGFloat(age / 0.32)
                context.saveGState()
                context.translateBy(x: click.1.x * sx, y: CGFloat(height) - click.1.y * sy)
                context.setStrokeColor(NSColor(WFColors.accent).withAlphaComponent(0.7 * (1 - progress)).cgColor)
                context.setLineWidth(2)
                let radius = 5 + 17 * progress
                context.strokeEllipse(in: CGRect(x: -radius, y: -radius,
                                                 width: radius * 2, height: radius * 2))
                context.restoreGState()
            }
        }

        context.saveGState()
        context.translateBy(x: point.x * sx, y: CGFloat(height) - point.y * sy)
        // 位图上下文 y 轴向上；箭头路径按屏幕坐标（y 向下）编写，纵向翻转后再画，
        // 否则笔尖朝下、尾巴朝上，看起来是倒着的箭头。
        context.scaleBy(x: 1.35, y: -1.35)
        let arrow = CGMutablePath()
        arrow.move(to: CGPoint(x: 0, y: 0))
        arrow.addLine(to: CGPoint(x: 0, y: 17))
        arrow.addLine(to: CGPoint(x: 4.3, y: 13.3))
        arrow.addLine(to: CGPoint(x: 6.9, y: 18.6))
        arrow.addLine(to: CGPoint(x: 9.7, y: 17.4))
        arrow.addLine(to: CGPoint(x: 7.1, y: 12.1))
        arrow.addLine(to: CGPoint(x: 12.4, y: 12.1))
        arrow.closeSubpath()
        context.addPath(arrow)
        context.setLineWidth(2.4)
        context.setStrokeColor(NSColor.white.cgColor)
        context.strokePath()
        context.addPath(arrow)
        context.setFillColor(NSColor.black.withAlphaComponent(0.88).cgColor)
        context.fillPath()
        context.restoreGState()
        return context.makeImage() ?? frame
    }

    private func cursorPoint(at time: TimeInterval) -> CGPoint? {
        guard let first = cursorMarks.first else { return nil }
        if time <= first.0 { return first.1 }
        for index in 1..<cursorMarks.count where time <= cursorMarks[index].0 {
            let previous = cursorMarks[index - 1]
            let next = cursorMarks[index]
            let span = max(0.001, next.0 - previous.0)
            let progress = CGFloat((time - previous.0) / span)
            return CGPoint(x: previous.1.x + (next.1.x - previous.1.x) * progress,
                           y: previous.1.y + (next.1.y - previous.1.y) * progress)
        }
        return cursorMarks.last!.1
    }

    // MARK: 输出

    private func writeGIF(_ frames: [CGImage]) {
        guard let destination = CGImageDestinationCreateWithURL(
            output as CFURL, UTType.gif.identifier as CFString, frames.count, nil) else { return }
        CGImageDestinationSetProperties(destination, [
            kCGImagePropertyGIFDictionary: [kCGImagePropertyGIFLoopCount: 0]
        ] as CFDictionary)
        for (index, frame) in frames.enumerated() {
            let next = index + 1 < self.frames.count ? self.frames[index + 1].time : frameTime(index) + frameInterval
            let delay = min(0.3, max(0.04, next - frameTime(index)))
            CGImageDestinationAddImage(destination, frame, [
                kCGImagePropertyGIFDictionary: [kCGImagePropertyGIFDelayTime: delay]
            ] as CFDictionary)
        }
        CGImageDestinationFinalize(destination)
        print("guide media written:", output.path, frames.count, "frames")
    }

    private func frameTime(_ index: Int) -> TimeInterval {
        index < frames.count ? frames[index].time : 0
    }

    private func writeSamples(_ frames: [CGImage]) {
        let directory = URL(fileURLWithPath: "/private/tmp/guide-media-samples", isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let name = output.deletingPathExtension().lastPathComponent
        for index in Set(stride(from: 0, to: frames.count, by: 4)) {
            guard index >= 0, index < frames.count,
                  let data = NSBitmapImageRep(cgImage: frames[index])
                    .representation(using: .png, properties: [:]) else { continue }
            try? data.write(to: directory.appendingPathComponent("\(name)-\(index).png"))
        }
    }
}
