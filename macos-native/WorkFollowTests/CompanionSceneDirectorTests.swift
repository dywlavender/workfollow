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
            CompanionOverdueTask(id: id, title: "交季度报告", delayText: "2天")
        }
        var postponedID: UUID?
        director.onPostponeOverdue = { postponedID = $0; return true }

        director.setEnabled(true)
        XCTAssertEqual(director.presentation?.scene, .overdue)
        XCTAssertEqual(director.presentation?.actionTitle, "顺延到明天")
        XCTAssertTrue(director.presentation?.message.contains("延迟2天") == true)

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

    func testBubbleShapeAddsLeftTailNearMascotHead() {
        let rect = CGRect(x: 0, y: 0, width: CompanionLayout.bubbleWidth, height: 72)
        let path = CompanionBubbleShape().path(in: rect)
        XCTAssertEqual(path.boundingRect.minX, -8, accuracy: 0.01)
        XCTAssertEqual(path.boundingRect.maxX, rect.maxX, accuracy: 0.01)
        XCTAssertEqual(path.boundingRect.minY, rect.minY, accuracy: 0.01)
        XCTAssertEqual(path.boundingRect.maxY, rect.maxY, accuracy: 0.01)
        XCTAssertTrue(path.contains(CGPoint(x: -4, y: 57)),
                      "Tail tip should sit 15pt above the bubble bottom")
        XCTAssertFalse(path.contains(CGPoint(x: -4, y: 30)))
        XCTAssertFalse(path.contains(CGPoint(x: -9, y: 57)))
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
