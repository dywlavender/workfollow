import AppKit
import SwiftUI
import XCTest
@testable import WorkFollow

@MainActor
final class TaskFocusSubmenuTests: XCTestCase {
    func testPlacementPrefersRightFlipsLeftAndClampsVertically() {
        let bounds = CGRect(x: 0, y: 0, width: 800, height: 600)
        let size = CGSize(width: 176, height: 82)
        let right = AnchoredPropertyPanelGeometry.submenuFrame(row: CGRect(x: 100, y: 200, width: 208, height: 32), size: size, bounds: bounds)
        XCTAssertEqual(right.minX, 314)
        let left = AnchoredPropertyPanelGeometry.submenuFrame(row: CGRect(x: 560, y: 200, width: 208, height: 32), size: size, bounds: bounds)
        XCTAssertEqual(left.maxX, 554)
        let low = AnchoredPropertyPanelGeometry.submenuFrame(row: CGRect(x: 560, y: 0, width: 208, height: 32), size: size, bounds: bounds)
        XCTAssertEqual(low.minY, 8)
        XCTAssertTrue(bounds.insetBy(dx: 8, dy: 8).contains(low))
    }

    func testBothActionsStartRealSessionAndBusySessionIsNotReplaced() throws {
        for stopwatch in [false, true] {
            let directory = FileManager.default.temporaryDirectory.appendingPathComponent("task-focus-\(UUID().uuidString)")
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            let store = FocusStore(clock: Date.init, directory: directory)
            let taskID = UUID()
            var presentation = TaskInspectorActionPresentationState()
            presentation.open(.more)
            presentation.openSubmenu(.focus)
            XCTAssertTrue(TaskInspectorFocusAction.start(taskID: taskID, stopwatch: stopwatch, store: store, presentation: &presentation))
            XCTAssertEqual(store.currentTaskID, taskID)
            XCTAssertEqual(store.phase, .focusing)
            XCTAssertEqual(store.sessionTiming?.projectedEndAt == nil, stopwatch)
            XCTAssertEqual(store.preferences.lastTaskID, taskID)
            XCTAssertNil(presentation.panel)
            XCTAssertNil(presentation.submenu)
            presentation.open(.more)
            presentation.openSubmenu(.focus)
            XCTAssertFalse(TaskInspectorFocusAction.start(taskID: UUID(), stopwatch: !stopwatch, store: store, presentation: &presentation))
            XCTAssertEqual(store.currentTaskID, taskID)
            XCTAssertEqual(presentation.panel, .more)
            _ = store.giveUp()
        }
    }

    func testActualInspectorFocusChildDoesNotResizeMoreAndEscapeClosesChildFirst() throws {
        let environment = AppEnvironment()
        let workspace = TaskWorkspaceModel(seedDemoData: false)
        let id = try XCTUnwrap(workspace.createTask(title: "任务操作验收", in: .inbox).taskID)
        workspace.select(id)
        var frames: [InspectorRenderAnchor: CGRect] = [:]
        let host = InspectorPanelTestSupport.inspectorHost(workspace: workspace, environment: environment) {
            frames = $0
        }
        let window = InspectorPanelTestSupport.ownerWindow(for: host)
        defer { window.close() }
        InspectorPanelTestSupport.settle(window)

        try InspectorPanelTestSupport.clickButton(containing: "更多任务操作", in: window)
        let more = try InspectorPanelTestSupport.actionPanel(in: window)
        XCTAssertEqual(more.frame.width, 208, accuracy: 0.5)
        XCTAssertEqual(more.title, InspectorPanelTestSupport.actionPanelTitle)
        let originalFrame = more.frame

        try InspectorPanelTestSupport.clickButton(containing: "开始专注", in: more)
        let submenu = try InspectorPanelTestSupport.panel(
            title: InspectorPanelTestSupport.focusSubmenuTitle, below: more)
        XCTAssertTrue(submenu.parent === more, "Focus is a child of the action panel")
        XCTAssertEqual(submenu.frame.width, 176, accuracy: 0.5)
        XCTAssertEqual(submenu.effectiveAppearance.bestMatch(from: [.aqua, .darkAqua]), .aqua)
        XCTAssertEqual(more.frame, originalFrame, "The focus child cannot resize or move More")

        try InspectorPanelTestSupport.sendEscape(to: submenu)
        XCTAssertFalse(submenu.isVisible, "The first Escape closes the nested Focus panel")
        XCTAssertTrue(more.isVisible, "The first Escape leaves More open")
        try InspectorPanelTestSupport.sendEscape(to: more)
        XCTAssertFalse(more.isVisible, "The second Escape closes More")

        try InspectorPanelTestSupport.clickButton(containing: "更多任务操作", in: window)
        let reopenedMore = try InspectorPanelTestSupport.actionPanel(in: window)
        try InspectorPanelTestSupport.clickButton(containing: "开始专注", in: reopenedMore)
        let reopenedSubmenu = try InspectorPanelTestSupport.panel(
            title: InspectorPanelTestSupport.focusSubmenuTitle, below: reopenedMore)
        // Exercise child-window event ownership without starting a session in
        // the user's real FocusStore. Domain actions use isolated stores above.
        let childHost = try XCTUnwrap(reopenedSubmenu.contentView)
        try InspectorPanelTestSupport.click(CGRect(x: 1, y: 1, width: 2, height: 2),
                                           in: childHost, window: reopenedSubmenu)
        XCTAssertTrue(reopenedSubmenu.isVisible)
        XCTAssertTrue(reopenedMore.isVisible, "Child clicks must not dismiss More")
        try InspectorPanelTestSupport.clickButton(containing: "设置日期", in: window)
        XCTAssertFalse(reopenedSubmenu.isVisible)
        XCTAssertFalse(reopenedMore.isVisible)
        let date = try InspectorPanelTestSupport.panel(title: InspectorPanelTestSupport.datePanelTitle, below: window)
        try InspectorPanelTestSupport.sendEscape(to: date)
    }

    func testMoreToDateUsesOneOutsideClickAndEscapeCancelsWithoutChangingScheduleTwentyTimes() throws {
        let environment = AppEnvironment()
        let workspace = TaskWorkspaceModel(seedDemoData: false)
        let id = try XCTUnwrap(workspace.createTask(title: "日期单击回归", in: .inbox).taskID)
        workspace.select(id)
        var frames: [InspectorRenderAnchor: CGRect] = [:]
        let host = InspectorPanelTestSupport.inspectorHost(workspace: workspace, environment: environment) {
            frames = $0
        }
        let window = InspectorPanelTestSupport.ownerWindow(for: host)
        defer { window.close() }
        let originalSchedule = try XCTUnwrap(workspace.task(for: id)).schedule

        for iteration in 0..<20 {
            try InspectorPanelTestSupport.clickButton(containing: "更多任务操作", in: window)
            let more = try InspectorPanelTestSupport.actionPanel(in: window)
            XCTAssertEqual(more.frame.width, 208, accuracy: 0.5, "More round \(iteration + 1)")

            // The main-window schedule anchor remains measurable; the button's AX frame
            // supplies the screen point for one real mouse-down/mouse-up sequence.
            XCTAssertNotNil(frames[.schedule])
            try InspectorPanelTestSupport.clickButton(containing: "设置日期", in: window)
            let date = try InspectorPanelTestSupport.panel(
                title: InspectorPanelTestSupport.datePanelTitle, below: window)
            XCTAssertFalse(more.isVisible, "The outside click closes More")
            XCTAssertEqual(date.frame.width, ScheduleMetrics.panelWidth, accuracy: 1)

            try InspectorPanelTestSupport.sendEscape(to: date)
            XCTAssertFalse(date.isVisible, "Escape cancels the date draft")
            XCTAssertEqual(workspace.task(for: id)?.schedule, originalSchedule,
                           "Cancelled date draft changed the task in round \(iteration + 1)")
        }
    }

    func testMoreOutsideClickReachesTaskTitleFieldInOneEvent() throws {
        let environment = AppEnvironment()
        let workspace = TaskWorkspaceModel(seedDemoData: false)
        let id = try XCTUnwrap(workspace.createTask(title: "标题事件接收", in: .inbox).taskID)
        workspace.select(id)
        let host = InspectorPanelTestSupport.inspectorHost(workspace: workspace, environment: environment)
        let window = InspectorPanelTestSupport.ownerWindow(for: host)
        defer { window.close() }

        try InspectorPanelTestSupport.clickButton(containing: "更多任务操作", in: window)
        let more = try InspectorPanelTestSupport.actionPanel(in: window)
        let previousResponder = ObjectIdentifier(try XCTUnwrap(window.firstResponder))
        try InspectorPanelTestSupport.clickElement(containing: "任务标题", in: window)

        XCTAssertFalse(more.isVisible, "Clicking the owner window closes More")
        XCTAssertNotEqual(ObjectIdentifier(try XCTUnwrap(window.firstResponder)), previousResponder,
                          "The same outside click must focus the title field")
        XCTAssertEqual(workspace.task(for: id)?.title, "标题事件接收")
    }
}
