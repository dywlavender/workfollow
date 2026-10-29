import AppKit
import XCTest
@testable import WorkFollow

@MainActor
final class WidgetQuickAddTests: XCTestCase {
    func testWidgetActionCarriesLaunchPurposeWithoutActivatingTheApp() {
        let configuration = WidgetQuickAddLaunch.configuration()
        XCTAssertEqual(configuration.arguments, [WidgetQuickAddLaunch.argument])
        XCTAssertFalse(configuration.activates)
        XCTAssertFalse(configuration.addsToRecentItems)
        XCTAssertFalse(OpenWidgetQuickAddIntent.openAppWhenRun)
    }

    func testOpeningMainAfterCaptureReopensTheAppUntilTheMainSceneExists() {
        var reopens = 0
        NativeMainWindowPresenter.activate(reopen: { reopens += 1 })
        XCTAssertEqual(reopens, 1)
        let window = NSWindow(contentRect: CGRect(x: 100, y: 100, width: 320, height: 212),
                              styleMask: [.titled], backing: .buffered, defer: false)
        window.identifier = NSUserInterfaceItemIdentifier("WorkFollowNativeMain")
        window.isReleasedWhenClosed = false
        defer { window.close() }
        NativeMainWindowPresenter.activate(reopen: { reopens += 1 })
        XCTAssertTrue(window.isVisible)
        XCTAssertEqual(reopens, 1, "已有主窗口应直接复用")
    }

    func testWidgetLaunchSuppressesOnlyTheInitialMainScene() {
        let launch = WidgetMainWindowLaunchPolicy(arguments: ["WorkFollow", WidgetQuickAddLaunch.argument])
        XCTAssertTrue(launch.startedForWidget)
        XCTAssertTrue(launch.suppressInitialMainWindow)
        launch.didFinishLaunching()
        RunLoop.current.run(until: Date().addingTimeInterval(0.03))
        XCTAssertFalse(launch.suppressInitialMainWindow, "启动后应恢复 Dock 和访达的普通打开行为")
        let normal = WidgetMainWindowLaunchPolicy(arguments: ["WorkFollow"])
        XCTAssertFalse(normal.startedForWidget)
        XCTAssertFalse(normal.suppressInitialMainWindow)
    }

    func testLegacyMainWindowIsHiddenOnlyDuringWidgetStartup() {
        let launch = WidgetMainWindowLaunchPolicy(arguments: [WidgetQuickAddLaunch.argument])
        let window = NSWindow(contentRect: CGRect(x: 100, y: 100, width: 320, height: 212),
                              styleMask: [.borderless], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        defer { window.close() }
        launch.prepareLegacyMainWindow(window)
        XCTAssertEqual(window.alphaValue, 0)
        window.orderFront(nil)
        launch.didFinishLaunching()
        InspectorPanelTestSupport.settle(window)
        XCTAssertFalse(window.isVisible)
        XCTAssertEqual(window.alphaValue, 1)
        window.orderFront(nil)
        launch.prepareLegacyMainWindow(window)
        XCTAssertTrue(window.isVisible, "后续主动打开主窗口不能继续被隐藏")
        XCTAssertEqual(window.alphaValue, 1)
    }

    private func environment() throws -> (AppEnvironment, URL) {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("widget-capture-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try NativePreviewRepository(directory: directory).save(NativeWorkspaceSnapshot(tasks: [], notes: []))
        return (AppEnvironment(directory: directory), directory)
    }

    private func titleField(in view: NSView) -> NSTextField? {
        if let field = view as? NSTextField, field.isEditable { return field }
        return view.subviews.lazy.compactMap { self.titleField(in: $0) }.first
    }

    func testWidgetLinkPresentsOneCalendarCardAndKeepsMainWorkspaceContext() throws {
        let (environment, directory) = try environment()
        defer { environment.widgetQuickAdd.dismiss(); try? FileManager.default.removeItem(at: directory) }
        let workspace = environment.taskWorkspace
        let existing = try XCTUnwrap(workspace.createTask(title: "原来正在编辑的任务", in: .inbox).taskID)
        workspace.activeList = "工作"
        workspace.activeTag = "项目"
        workspace.activeFilterID = UUID()
        workspace.bulkSelection = [existing]
        workspace.select(existing)
        environment.navigation.destination = .calendar
        let filter = workspace.activeFilterID
        let receiver = NativeResourceLinkReceiver()
        var mainActivations = 0
        receiver.configure(route: { environment.openResourceLink($0) }, activate: { mainActivations += 1 })
        let visibleMainWindows = NSApp.windows.filter { !($0 is NSPanel) && $0.isVisible }.count
        receiver.receive([TaskWidgetLink.quickAdd])
        let panel = try XCTUnwrap(environment.widgetQuickAdd.panel)
        InspectorPanelTestSupport.settle(panel)
        XCTAssertTrue(panel.isVisible)
        XCTAssertEqual(panel.frame.width, WFPlanningOverlayMetrics.composerWidth, accuracy: 0.5)
        XCTAssertEqual(panel.frame.height, WFPlanningOverlayMetrics.composerHeight, accuracy: 0.5)
        XCTAssertEqual(NSApp.windows.filter { !($0 is NSPanel) && $0.isVisible }.count, visibleMainWindows)
        let field = try XCTUnwrap(titleField(in: try XCTUnwrap(panel.contentView)))
        panel.makeFirstResponder(field)
        let editor = try XCTUnwrap(field.currentEditor() as? NSTextView)
        editor.insertText("还没有提交的草稿", replacementRange: editor.selectedRange())
        receiver.receive([TaskWidgetLink.quickAdd])
        XCTAssertTrue(environment.widgetQuickAdd.panel === panel)
        XCTAssertEqual(field.stringValue, "还没有提交的草稿")
        XCTAssertEqual(mainActivations, 0)
        XCTAssertEqual(environment.navigation.destination, .calendar)
        XCTAssertEqual(workspace.selectedTaskID, existing)
        XCTAssertEqual(workspace.activeList, "工作")
        XCTAssertEqual(workspace.activeTag, "项目")
        XCTAssertEqual(workspace.activeFilterID, filter)
        XCTAssertEqual(workspace.bulkSelection, [existing])
        XCTAssertEqual(workspace.allTasks.count, 1)
        XCTAssertTrue(PopupEscapeRegistry.shared.route(eventWindow: panel))
        XCTAssertNil(environment.widgetQuickAdd.panel)
        XCTAssertEqual(workspace.allTasks.count, 1, "取消不创建任务")
    }

    func testReturnCreatesTodayTaskWithoutSelectingItAndClosesTheCard() throws {
        let (environment, directory) = try environment()
        defer { environment.widgetQuickAdd.dismiss(); try? FileManager.default.removeItem(at: directory) }
        let workspace = environment.taskWorkspace
        let existing = try XCTUnwrap(workspace.createTask(title: "保持选中", in: .inbox).taskID)
        XCTAssertTrue(workspace.saveList("工作"))
        XCTAssertTrue(workspace.setDefaultList("工作"))
        workspace.select(existing)
        workspace.activeList = "其它清单"
        workspace.activeTag = "其它标签"
        environment.navigation.destination = .notes
        XCTAssertTrue(environment.openResourceLink(TaskWidgetLink.quickAdd))
        let panel = try XCTUnwrap(environment.widgetQuickAdd.panel)
        InspectorPanelTestSupport.settle(panel)
        let field = try XCTUnwrap(titleField(in: try XCTUnwrap(panel.contentView)))
        let editor = try XCTUnwrap(field.currentEditor() as? NSTextView)
        XCTAssertTrue(panel.firstResponder === editor, "打开后应直接输入，不需要再点标题")
        editor.insertText("组件创建任务", replacementRange: editor.selectedRange())
        editor.insertNewline(nil)
        InspectorPanelTestSupport.settle(panel)
        let task = try XCTUnwrap(workspace.allTasks.first { $0.id != existing })
        XCTAssertEqual(task.title, "组件创建任务")
        XCTAssertEqual(task.schedule.dueAt, workspace.calendar.startOfDay(for: workspace.clock()))
        XCTAssertFalse(task.schedule.hasTime)
        XCTAssertEqual(task.list.name, "工作", "组件快捷新增遵循默认清单，忽略主窗口当前浏览的清单")
        XCTAssertTrue(task.tags.isEmpty)
        XCTAssertEqual(workspace.selectedTaskID, existing)
        XCTAssertEqual(environment.navigation.destination, .notes)
        XCTAssertNil(environment.widgetQuickAdd.panel)
        XCTAssertFalse(panel.isVisible)
    }

    func testDatePickerBelongsToCaptureCardAndEscapeClosesOneLayerAtATime() throws {
        let workspace = TaskWorkspaceModel(seedDemoData: false)
        let controller = WidgetQuickAddController(workspace: workspace)
        defer { controller.dismiss() }
        controller.present()
        let panel = try XCTUnwrap(controller.panel)
        InspectorPanelTestSupport.settle(panel)
        let content = try XCTUnwrap(panel.contentView)
        let rowHeight = WFPlanningOverlayMetrics.composerRowHeight
        let dateIcon = CGRect(x: WFSpace.md, y: content.isFlipped ? 0 : content.bounds.height - rowHeight,
                              width: 32, height: rowHeight)
        try InspectorPanelTestSupport.click(dateIcon, in: content, window: panel)
        InspectorPanelTestSupport.settle(panel)
        let datePanel = try XCTUnwrap(panel.childWindows?.first { $0.isVisible })
        XCTAssertTrue(panel.isVisible, "操作日期子卡不能把快速新增收起")
        XCTAssertTrue(PopupEscapeRegistry.shared.route(eventWindow: datePanel))
        InspectorPanelTestSupport.settle(panel)
        XCTAssertTrue(panel.isVisible)
        XCTAssertFalse(datePanel.isVisible)
        XCTAssertTrue(PopupEscapeRegistry.shared.route(eventWindow: panel))
        XCTAssertNil(controller.panel)
        XCTAssertTrue(workspace.allTasks.isEmpty)
    }

    func testQueuedCaptureLinkDoesNotRequestMainActivationAfterSceneWiring() {
        let receiver = NativeResourceLinkReceiver()
        var captures = 0, mainActivations = 0
        let route: (URL) -> Bool = { url in
            if TaskWidgetLink.destination(for: url) == .quickAdd { captures += 1 }
            return true
        }
        receiver.receive([TaskWidgetLink.quickAdd])
        receiver.configure(route: route)
        XCTAssertEqual(captures, 1)
        receiver.configure(route: route, activate: { mainActivations += 1 })
        XCTAssertEqual(mainActivations, 0)
        receiver.receive([TaskWidgetLink.today])
        XCTAssertEqual(mainActivations, 1)
    }
}
