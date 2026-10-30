import AppKit
import SwiftUI
import XCTest
@testable import WorkFollow

final class CompanionSceneDirectorTests: XCTestCase {
    private var now = Date(timeIntervalSince1970: 1_800_000_000)
    private var calendar: Calendar = {
        var value = Calendar(identifier: .gregorian)
        value.timeZone = TimeZone(secondsFromGMT: 0)!
        return value
    }()

    @MainActor
    private func makeDirector() -> CompanionSceneDirector {
        CompanionSceneDirector(now: { [weak self] in self?.now ?? Date() }, calendar: calendar)
    }

    private func task(_ id: UUID, _ title: String, status: TaskStatus = .active,
                      priority: TaskPriority = .none) -> CompanionTaskState {
        CompanionTaskState(id: id, title: title, status: status, priority: priority)
    }

    private func note(_ id: UUID, _ title: String, hasContent: Bool = true) -> CompanionTaskState {
        CompanionTaskState(id: id, title: title, isNote: true, hasContent: hasContent)
    }

    @MainActor
    func testNoteScenesWaitForRealContentAndTrackConversions() {
        let director = makeDirector()
        director.setEnabled(true)
        let noteID = UUID(), freshID = UUID(), taskID = UUID()
        let base = [note(noteID, "", hasContent: false),
                    task(taskID, "写方案")]
        director.updateTaskSnapshot(base)

        // 浮窗会先建空草稿：只是新建还不算“记下”，不冒泡。
        now = now.addingTimeInterval(1)
        director.updateTaskSnapshot([note(noteID, "", hasContent: false),
                                     note(freshID, "", hasContent: false),
                                     task(taskID, "写方案")])
        XCTAssertNil(director.presentation)

        // 标题或正文有内容后才算真的写下第一笔。
        now = now.addingTimeInterval(1)
        director.updateTaskSnapshot([note(noteID, "周会纪要"),
                                     note(freshID, "", hasContent: false),
                                     task(taskID, "写方案")])
        XCTAssertEqual(director.presentation?.scene, .noteWritten)
        XCTAssertTrue(director.presentation?.message.contains("周会纪要") == true)

        // 笔记转任务：同一 id 变成 text，提示转成待办。
        now = now.addingTimeInterval(21)
        director.tick()
        director.updateTaskSnapshot([task(noteID, "周会纪要"),
                                     note(freshID, "", hasContent: false),
                                     task(taskID, "写方案")])
        XCTAssertEqual(director.presentation?.scene, .noteConverted)
        XCTAssertTrue(director.presentation?.message.contains("变成待办") == true)

        // 任务转笔记：同一 id 变回 note，用的是“整理成笔记”文案。
        now = now.addingTimeInterval(21)
        director.tick()
        director.updateTaskSnapshot([note(noteID, "周会纪要"),
                                     note(freshID, "", hasContent: false),
                                     task(taskID, "写方案")])
        XCTAssertEqual(director.presentation?.scene, .noteWritten)
        XCTAssertTrue(director.presentation?.message.contains("整理成笔记") == true)
    }

    @MainActor
    func testBulkNoteConversionUsesCountCopy() {
        let director = makeDirector()
        director.setEnabled(true)
        let a = UUID(), b = UUID()
        director.updateTaskSnapshot([note(a, "A"), note(b, "B")])

        now = now.addingTimeInterval(1)
        director.updateTaskSnapshot([task(a, "A"), task(b, "B")])
        XCTAssertEqual(director.presentation?.scene, .noteConverted)
        XCTAssertEqual(director.presentation?.message, "2 条笔记变成待办了，我帮你盯住")
    }

    @MainActor
    func testTaskSnapshotMapsCreateCompleteAndHighPriority() {
        let director = makeDirector()
        director.setEnabled(true)
        let a = UUID(), b = UUID(), c = UUID()
        director.updateTaskSnapshot([task(a, "A"), task(b, "B")])

        now = now.addingTimeInterval(1)
        director.updateTaskSnapshot([task(a, "A"), task(b, "B"), task(c, "C")])
        XCTAssertEqual(director.presentation?.scene, .taskCreated)
        XCTAssertTrue(director.presentation?.message.contains("C") == true)

        now = now.addingTimeInterval(4)
        director.tick()
        XCTAssertNil(director.presentation)

        now = now.addingTimeInterval(1)
        director.updateTaskSnapshot([task(a, "A", status: .completed), task(b, "B"), task(c, "C")])
        XCTAssertEqual(director.presentation?.scene, .taskCompleted)

        now = now.addingTimeInterval(4)
        director.tick()
        XCTAssertNil(director.presentation)

        now = now.addingTimeInterval(1)
        director.updateTaskSnapshot([task(a, "A", status: .completed),
                                     task(b, "B", priority: .high), task(c, "C")])
        XCTAssertEqual(director.presentation?.scene, .priorityRaised)
    }

    @MainActor
    func testFocusAndMeetingPrecedenceRestoresFocusAfterMeeting() {
        let director = makeDirector()
        director.setEnabled(true)
        director.setFocusPhase(.focusing)
        XCTAssertEqual(director.presentation?.scene, .focus)

        let id = UUID()
        director.updateTaskSnapshot([task(id, "写方案")])
        now = now.addingTimeInterval(1)
        director.updateTaskSnapshot([task(id, "写方案", status: .completed)])
        XCTAssertEqual(director.presentation?.scene, .focus)

        director.setMeetingActive(true)
        XCTAssertEqual(director.presentation?.scene, .meeting)

        director.setMeetingActive(false)
        XCTAssertEqual(director.presentation?.scene, .focus)

        director.setFocusPhase(.breaking)
        XCTAssertEqual(director.presentation?.scene, .breakTime)

        director.setFocusPhase(.idle)
        XCTAssertNil(director.presentation)
    }

    @MainActor
    func testAIAndSyncUseStickyScenesThenFinishBubbles() {
        let director = makeDirector()
        director.setEnabled(true)

        director.setAIThinking(true)
        XCTAssertEqual(director.presentation?.scene, .aiThinking)
        director.setAIThinking(false)
        XCTAssertEqual(director.presentation?.scene, .aiFinished)
        now = now.addingTimeInterval(3)
        director.tick()
        XCTAssertNil(director.presentation)

        director.setSyncActive(true)
        XCTAssertEqual(director.presentation?.scene, .sync)
        now = now.addingTimeInterval(1)
        director.setSyncActive(false)
        XCTAssertEqual(director.presentation?.scene, .syncFinished)
        now = now.addingTimeInterval(3)
        director.tick()
        XCTAssertNil(director.presentation)
    }

    @MainActor
    func testThreeCompletionsWithinWindowTriggerStreak() {
        let director = makeDirector()
        director.setEnabled(true)
        let a = UUID(), b = UUID(), c = UUID()
        director.updateTaskSnapshot([task(a, "A"), task(b, "B"), task(c, "C")])

        now = now.addingTimeInterval(1)
        director.updateTaskSnapshot([task(a, "A", status: .completed), task(b, "B"), task(c, "C")])
        XCTAssertEqual(director.presentation?.scene, .taskCompleted)

        now = now.addingTimeInterval(1)
        director.updateTaskSnapshot([task(a, "A", status: .completed),
                                     task(b, "B", status: .completed), task(c, "C")])

        now = now.addingTimeInterval(1)
        director.updateTaskSnapshot([task(a, "A", status: .completed),
                                     task(b, "B", status: .completed),
                                     task(c, "C", status: .completed)])
        XCTAssertEqual(director.presentation?.scene, .streak)
    }

    @MainActor
    func testNightSceneOnlyOncePerNight() {
        now = calendar.date(from: DateComponents(year: 2026, month: 10, day: 30,
                                                 hour: 23, minute: 0))!
        let director = makeDirector()
        director.setEnabled(true)
        XCTAssertEqual(director.presentation?.scene, .night)

        now = now.addingTimeInterval(7)
        director.tick()
        XCTAssertNil(director.presentation)

        now = now.addingTimeInterval(60)
        director.tick()
        XCTAssertNil(director.presentation)

        now = calendar.date(from: DateComponents(year: 2026, month: 10, day: 31,
                                                 hour: 22, minute: 31))!
        director.tick()
        XCTAssertEqual(director.presentation?.scene, .night)
    }

    @MainActor
    func testOverdueProviderAndPostponeAction() {
        let director = makeDirector()
        let id = UUID()
        director.overdueProvider = {
            CompanionOverdueTask(id: id, title: "整理第三季度复盘材料", delayText: "2天3小时")
        }
        var postponedID: UUID?
        director.onPostponeOverdue = { postponedID = $0; return true }

        director.setEnabled(true)
        XCTAssertEqual(director.presentation?.scene, .overdue)
        XCTAssertEqual(director.presentation?.actionTitle, "顺延到明天")
        // 带按钮的气泡只留一行：标题缩到 6 字，延迟只保留最大单位。
        XCTAssertEqual(director.presentation?.message, "「整理第三季度…」逾期2天")

        director.postponeOverdueTask()
        XCTAssertEqual(postponedID, id)
        XCTAssertEqual(director.presentation?.scene, .postponed)
    }

    @MainActor
    func testCompletingOverdueTaskDismissesOverdueBubble() {
        let director = makeDirector()
        let id = UUID()
        director.overdueProvider = {
            CompanionOverdueTask(id: id, title: "交报告", delayText: "1天")
        }
        director.setEnabled(true)
        director.updateTaskSnapshot([task(id, "交报告")])
        XCTAssertEqual(director.presentation?.scene, .overdue)

        now = now.addingTimeInterval(1)
        director.updateTaskSnapshot([task(id, "交报告", status: .completed)])
        XCTAssertEqual(director.presentation?.scene, .taskCompleted)
        XCTAssertNotEqual(director.presentation?.scene, .overdue)
    }

    @MainActor
    func testDisabledDirectorIgnoresEventsAndShowsCurrentFocusOnEnable() {
        let director = makeDirector()
        director.setFocusPhase(.focusing)
        XCTAssertNil(director.presentation)

        director.setEnabled(true)
        XCTAssertEqual(director.presentation?.scene, .focus)

        director.setEnabled(false)
        XCTAssertNil(director.presentation)

        director.setMeetingActive(true)
        XCTAssertNil(director.presentation)
    }

    @MainActor
    func testNoteAIStoreFlagsAnyRunningForCompanion() async {
        let store = NoteAIConversationStore()
        let model = store.model(for: UUID())
        XCTAssertFalse(store.isAnyRunning)

        let context = NoteAIContext(noteID: UUID(), title: "周会纪要", content: "结论",
                                    referenceDate: now, existingTitles: [])
        model.ask(.organize, context: context, using: { _, _, _, _, _ in
            try await _Concurrency.Task.sleep(nanoseconds: 2_000_000_000)
            return "{}"
        })
        XCTAssertTrue(model.isRunning)
        try? await _Concurrency.Task.sleep(nanoseconds: 150_000_000)
        XCTAssertTrue(store.isAnyRunning, "笔记右侧 AI 生成时小伙伴要进入思考状态")

        model.stop()
        try? await _Concurrency.Task.sleep(nanoseconds: 150_000_000)
        XCTAssertFalse(store.isAnyRunning)
    }

    func testBubbleShapeAddsLeftTailNearMascotHead() {
        let rect = CGRect(x: 0, y: 0, width: CompanionLayout.bubbleWidth, height: 72)
        let path = CompanionBubbleShape().path(in: rect)
        XCTAssertEqual(path.boundingRect.minX, -8, accuracy: 0.01)
        XCTAssertEqual(path.boundingRect.maxX, rect.maxX, accuracy: 0.01)
        XCTAssertEqual(path.boundingRect.minY, rect.minY, accuracy: 0.01)
        XCTAssertEqual(path.boundingRect.maxY, rect.maxY, accuracy: 0.01)
        XCTAssertTrue(path.contains(CGPoint(x: -4, y: 36)),
                      "Tail should sit at the bubble's vertical center")
        XCTAssertFalse(path.contains(CGPoint(x: -4, y: 10)))
        XCTAssertFalse(path.contains(CGPoint(x: -9, y: 36)))
    }

    @MainActor
    func testDismissHidesOverdueBubbleThenRepeatsAfterCooldown() {
        let director = makeDirector()
        let id = UUID()
        director.overdueProvider = {
            CompanionOverdueTask(id: id, title: "交报告", delayText: "1天")
        }
        director.setEnabled(true)
        XCTAssertEqual(director.presentation?.scene, .overdue)

        director.dismissPresentation()
        XCTAssertNil(director.presentation, "点 × 后气泡应立刻收起")

        now = now.addingTimeInterval(60)
        director.checkOverdue(force: true)
        XCTAssertNil(director.presentation, "冷却期内不该马上再弹")

        now = now.addingTimeInterval(601)
        director.checkOverdue(force: true)
        XCTAssertEqual(director.presentation?.scene, .overdue,
                       "收起只是暂时的，冷却结束后还能再提醒")

        // 收起后的任务仍可顺延：再次出现时按钮仍然有效。
        var postponedID: UUID?
        director.onPostponeOverdue = { postponedID = $0; return true }
        director.postponeOverdueTask()
        XCTAssertEqual(postponedID, id)
    }

    @MainActor
    func testDismissLeavesStickyScenesAlone() {
        let director = makeDirector()
        director.setEnabled(true)
        director.setFocusPhase(.focusing)
        XCTAssertEqual(director.presentation?.scene, .focus)

        director.dismissPresentation()
        XCTAssertEqual(director.presentation?.scene, .focus,
                       "常驻场景没有 ×，收起接口不应误伤")
    }

    @MainActor
    func testHoverKeepsShortBubbleAliveLongEnoughToReachTheX() {
        let director = makeDirector()
        director.setEnabled(true)
        director.pet()
        XCTAssertEqual(director.presentation?.scene, .pet)
        XCTAssertEqual(director.presentation?.isSticky, false)

        director.setBubbleHovered(true)
        now = now.addingTimeInterval(3)
        director.tick()
        XCTAssertEqual(director.presentation?.scene, .pet, "鼠标压着气泡时先不收回")

        director.setBubbleHovered(false)
        now = now.addingTimeInterval(1)
        director.tick()
        XCTAssertNil(director.presentation)

        director.pet()
        director.setBubbleHovered(true)
        now = now.addingTimeInterval(26)
        director.tick()
        XCTAssertNil(director.presentation, "悬停最多多留 20 秒，指针一直压着也会到期")
    }

    @MainActor
    func testPetInterruptsStickySceneButNeverHidesOverdueAction() {
        let director = makeDirector()
        director.setEnabled(true)
        director.setFocusPhase(.focusing)
        XCTAssertEqual(director.presentation?.scene, .focus)

        director.pet()
        XCTAssertEqual(director.presentation?.scene, .pet)
        XCTAssertEqual(director.presentation?.isSticky, false)

        now = now.addingTimeInterval(3)
        director.tick()
        XCTAssertEqual(director.presentation?.scene, .focus,
                       "Petting must fall back to the active focus scene")

        director.setFocusPhase(.idle)
        XCTAssertNil(director.presentation)

        let id = UUID()
        director.overdueProvider = {
            CompanionOverdueTask(id: id, title: "交报告", delayText: "1天")
        }
        director.onPostponeOverdue = { $0 == id }
        director.checkOverdue(force: true)
        XCTAssertEqual(director.presentation?.scene, .overdue)
        director.pet()
        XCTAssertEqual(director.presentation?.scene, .overdue,
                       "The postpone action must survive a pet")
        director.postponeOverdueTask()
        XCTAssertEqual(director.presentation?.scene, .postponed)
    }

    func testOverduePlannerKeepsTodaysAllDayAndTimedClock() {
        let start = calendar.date(from: DateComponents(year: 2026, month: 10, day: 30,
                                                       hour: 15, minute: 20))!
        let tomorrowStart = calendar.date(byAdding: .day, value: 1,
                                          to: calendar.startOfDay(for: start))!

        let allDay = TaskSchedule(dueAt: start, hasTime: false)
        let allDayTarget = CompanionOverduePlanner.tomorrow(for: allDay, now: start, calendar: calendar)
        XCTAssertEqual(allDayTarget, tomorrowStart)

        let timedStart = calendar.date(from: DateComponents(year: 2026, month: 10, day: 28,
                                                            hour: 9, minute: 30))!
        let timed = TaskSchedule(dueAt: timedStart, hasTime: true)
        let timedTarget = CompanionOverduePlanner.tomorrow(for: timed, now: start, calendar: calendar)
        let components = calendar.dateComponents([.hour, .minute], from: timedTarget)
        XCTAssertEqual(components.hour, 9)
        XCTAssertEqual(components.minute, 30)
        XCTAssertEqual(calendar.startOfDay(for: timedTarget), tomorrowStart)
    }

    @MainActor
    func testMascotRendersBothCharactersInEveryPhase() throws {
        let phases: [CompanionPhase] = [.idle, .happy, .focus, .sleep, .celebrate]
        let props: [String?] = ["⏰", "💛", "🎙️", "🌙", "🔥"]
        let view = VStack(spacing: 10) {
            ForEach(0..<2, id: \.self) { row in
                HStack(spacing: 8) {
                    ForEach(Array(phases.enumerated()), id: \.offset) { index, phase in
                        VStack(spacing: 2) {
                            CompanionMascotView(character: row == 0 ? .cat : .bunny,
                                                phase: phase, prop: props[index],
                                                animated: false, size: 90)
                            Text(String(describing: phase))
                                .font(.system(size: 9))
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
        }
        .padding(16)
        .background(Color(red: 0.98, green: 0.96, blue: 0.92))

        let renderer = ImageRenderer(content: view)
        renderer.scale = 2
        guard let image = renderer.nsImage,
              let tiff = image.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiff),
              let png = bitmap.representation(using: .png, properties: [:]) else {
            XCTFail("小伙伴绘制失败")
            return
        }
        try png.write(to: URL(fileURLWithPath: "/tmp/wf-companion-mascots.png"))
    }
}
