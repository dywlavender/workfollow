import AppKit
import Combine
import SwiftUI
import XCTest
@testable import WorkFollow

@MainActor
final class CalendarTaskPopupInteractionTests: XCTestCase {
    @MainActor private final class FrameProbe {
        var frames: [UUID: [CGRect]] = [:]
    }

    @MainActor private final class Fixture {
        let directory: URL
        let defaultsName = "calendar-task-popup-" + UUID().uuidString
        let defaults: UserDefaults
        let environment: AppEnvironment
        let workspace: TaskWorkspaceModel
        let host: NSHostingView<AnyView>
        let window: NSWindow
        let first: UUID
        let second: UUID
        let firstFrame: CGRect
        let secondFrame: CGRect

        init(mode: CalendarViewMode = .month, arrangePool: Bool = false) throws {
            directory = FileManager.default.temporaryDirectory.appendingPathComponent("calendar-task-popup-" + UUID().uuidString)
            defaults = try XCTUnwrap(UserDefaults(suiteName: defaultsName))
            var calendar = Calendar(identifier: .gregorian)
            calendar.timeZone = TimeZone(secondsFromGMT: 0)!
            let now = calendar.date(from: DateComponents(year: 2026, month: 10, day: 23, hour: 12))!
            func day(_ number: Int, hour: Int = 0) -> Date {
                calendar.date(from: DateComponents(year: 2026, month: 10, day: number, hour: hour, minute: mode == .day ? 30 : 0))!
            }
            let seed = TaskWorkspaceModel(clock: { now }, calendar: calendar, seedDemoData: false)
            first = try XCTUnwrap(seed.createTask(title: "日历切换甲", in: .inbox).taskID)
            second = try XCTUnwrap(seed.createTask(title: "日历切换乙", in: .inbox).taskID)
            _ = seed.setSchedule(first, TaskSchedule(dueAt: mode == .day ? day(23, hour: 8) : day(18), hasTime: mode == .day))
            if !arrangePool {
                _ = seed.setSchedule(second, TaskSchedule(dueAt: mode == .day ? day(23, hour: 16) : day(24), hasTime: mode == .day))
            }
            _ = seed.setDocument(first, NativeDocument(plainText: "甲的正文"))
            _ = seed.setDocument(second, NativeDocument(plainText: "乙的正文"))
            try NativePreviewRepository(directory: directory).save(NativeWorkspaceSnapshot(tasks: seed.allTasks, notes: []))
            environment = AppEnvironment(clock: { now }, calendar: calendar, directory: directory)
            environment.focusStore.notifier = nil
            workspace = environment.taskWorkspace
            let settings = PlanningSettingsStore(defaults: defaults)
            settings.updateCalendar { $0.mode = mode; $0.showArrangePane = arrangePool }
            let integration = CalendarSyncCoordinator(directory: directory.appendingPathComponent("calendar"), client: FakeSystemCalendarClient())
            let probe = FrameProbe()
            host = NSHostingView(rootView: AnyView(CalendarWorkspaceView(workspace: workspace, settings: settings, systemCalendar: integration)
                .environmentObject(environment).frame(width: 1200, height: 900)
                .overlayPreferenceValue(PlanningTaskAnchorsKey.self) { anchors in
                    GeometryReader { geometry in
                        let frames = anchors.mapValues { $0.map { geometry[$0] } }
                        Color.clear.onAppear { probe.frames = frames }
                            .onChange(of: frames) { _, value in probe.frames = value }
                    }.allowsHitTesting(false)
                }))
            window = InspectorPanelTestSupport.ownerWindow(for: host, width: 1200, height: 900)
            InspectorPanelTestSupport.settle(window, duration: 0.4)
            let laidOutHost = host
            let owner = window
            func screenFrame(_ id: UUID) throws -> CGRect {
                let rect = try XCTUnwrap(probe.frames[id]?.first, "日历任务条必须完成布局")
                let local = CGRect(x: rect.minX, y: laidOutHost.isFlipped ? rect.minY : laidOutHost.bounds.height - rect.maxY,
                                   width: rect.width, height: rect.height)
                return owner.convertToScreen(laidOutHost.convert(local, to: nil))
            }
            firstFrame = try screenFrame(first)
            secondFrame = try screenFrame(second)
            print("POPUP DEBUG", mode.rawValue, "window", window.frame, "host", host.frame,
                  "first", firstFrame, "second", secondFrame, "regions", probe.frames.mapValues(\.count))
        }

        var editor: NativeTextView? { Self.descendants(host).compactMap { $0 as? NativeTextView }.first }

        func click(_ frame: CGRect) throws { try InspectorPanelTestSupport.click(screenFrame: frame, in: window) }

        func close() {
            window.contentView = nil
            window.close()
            defaults.removePersistentDomain(forName: defaultsName)
            try? FileManager.default.removeItem(at: directory)
        }

        private static func descendants(_ view: NSView) -> [NSView] {
            [view] + view.subviews.flatMap(descendants)
        }

    }

    func testSingleClickSwitchesTaskAndAnchorInMonthWeekAndDayThenBlankCloses() throws {
        for mode in CalendarViewMode.allCases {
            let fixture = try Fixture(mode: mode)
            defer { fixture.close() }
            try fixture.click(fixture.firstFrame)
            // 点击后选中态与浮层编辑器都是异步就位：轮询等待而不是立刻断言。
            try InspectorPanelTestSupport.waitUntil("\(mode.label)视图应一次点击选中甲") {
                fixture.workspace.selectedTaskID == fixture.first
            }
            try InspectorPanelTestSupport.waitUntil("\(mode.label)视图浮层编辑器应就位") {
                fixture.editor != nil
            }
            let editor = try XCTUnwrap(fixture.editor)
            if let bitmap = fixture.host.bitmapImageRepForCachingDisplay(in: fixture.host.bounds) {
                fixture.host.cacheDisplay(in: fixture.host.bounds, to: bitmap)
                try bitmap.representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: "/private/tmp/workfollow-calendar-popup-\(mode.rawValue).png"))
            }
            let oldOrigin = editor.convert(CGPoint.zero, to: fixture.host)
            var changes: [UUID?] = []
            let subscription = fixture.workspace.selectionWillChange.sink { changes.append($0) }
            defer { subscription.cancel() }

            try fixture.click(fixture.secondFrame)
            try InspectorPanelTestSupport.waitUntil("\(mode.label)视图应一次点击切到乙") {
                fixture.workspace.selectedTaskID == fixture.second
            }
            XCTAssertEqual(changes, [fixture.second], "任务间切换不应先清空选中项")
            XCTAssertEqual(fixture.editor?.documentIdentity, fixture.second)
            XCTAssertEqual(fixture.editor?.string, "乙的正文")
            if let current = fixture.editor {
                XCTAssertTrue(current === editor, "切换时复用共享编辑器")
                XCTAssertNotEqual(current.convert(CGPoint.zero, to: fixture.host), oldOrigin, "浮层应跟随新任务锚点")
            }

            try fixture.click(fixture.firstFrame)
            XCTAssertEqual(fixture.workspace.selectedTaskID, fixture.first)
            XCTAssertEqual(fixture.editor?.string, "甲的正文")
            try InspectorPanelTestSupport.click(CGRect(x: 1180, y: 875, width: 10, height: 10), in: fixture.host, window: fixture.window)
            try InspectorPanelTestSupport.waitUntil("点击空白区域关闭详情") {
                fixture.workspace.selectedTaskID == nil
            }
            try InspectorPanelTestSupport.waitUntil("浮层编辑器应随空白点击撤下") {
                fixture.editor == nil
            }
        }
    }

    func testSingleClickCanSwitchBetweenCalendarAndArrangePoolWithoutSchedulingTheTask() throws {
        let fixture = try Fixture(arrangePool: true)
        defer { fixture.close() }
        let original = fixture.workspace.task(for: fixture.second)
        try fixture.click(fixture.firstFrame)
        try fixture.click(fixture.secondFrame)
        XCTAssertEqual(fixture.workspace.selectedTaskID, fixture.second)
        XCTAssertEqual(fixture.editor?.string, "乙的正文")
        XCTAssertEqual(fixture.workspace.task(for: fixture.second), original)
        try fixture.click(fixture.firstFrame)
        XCTAssertEqual(fixture.workspace.selectedTaskID, fixture.first)
    }

    func testEditedDocumentIsSavedToItsTaskWhenClickingAnotherCalendarTask() throws {
        let fixture = try Fixture()
        defer { fixture.close() }
        try fixture.click(fixture.firstFrame)
        let editor = try XCTUnwrap(fixture.editor)
        fixture.window.makeFirstResponder(editor)
        editor.setSelectedRange(NSRange(location: (editor.string as NSString).length, length: 0))
        editor.insertText("，已补充", replacementRange: editor.selectedRange())
        try fixture.click(fixture.secondFrame)
        XCTAssertEqual(fixture.workspace.selectedTaskID, fixture.second)
        XCTAssertEqual(fixture.workspace.task(for: fixture.first)?.document.plainText, "甲的正文，已补充")
        XCTAssertEqual(fixture.workspace.task(for: fixture.second)?.document.plainText, "乙的正文")
    }
}
