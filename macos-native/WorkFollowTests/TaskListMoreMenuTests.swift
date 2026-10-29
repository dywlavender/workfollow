import AppKit
import SwiftUI
import XCTest
@testable import WorkFollow

/// 清单页「⋯」与「显示设置」按滴答截图对齐：视图三图标、动态隐藏/显示详细、
/// 无打印；显示设置有日期口径与详情样式两项。
@MainActor
final class TaskListMoreMenuTests: XCTestCase {
    private let dateDisplayKey = TaskDateDisplayMode.defaultsKey
    private let detailLayoutKey = TaskDetailLayout.defaultsKey

    override func tearDown() {
        UserDefaults.standard.removeObject(forKey: dateDisplayKey)
        UserDefaults.standard.removeObject(forKey: detailLayoutKey)
        super.tearDown()
    }

    func testMoreMenuMatchesTickTickWithoutPrint() throws {
        let (_, window, host, probe) = try makeWindow()
        defer { window.close() }

        XCTAssertEqual(TaskListMoreMenuPolicy.entries,
                       [.viewModes, .separator, .hidesCompleted, .detailsVisibility, .displaySettings],
                       "条目集合与顺序按滴答截图，打印/撤销/模板/分组/清单动态都不在这张菜单里")
        XCTAssertEqual(TaskListMoreMenuPolicy.detailsTitle(hidesDetails: false), "隐藏详细")
        XCTAssertEqual(TaskListMoreMenuPolicy.detailsTitle(hidesDetails: true), "显示详细")
        for mode in TaskListViewMode.allCases {
            XCTAssertEqual(TaskListMoreMenuPolicy.viewModeHelp(mode), mode.title + "视图")
        }

        try openMoreMenu(in: window, host: host, probe: probe)
        let menu = try InspectorPanelTestSupport.panel(title: "列表操作", below: window)
        XCTAssertEqual(menu.frame.width, PopupMetrics.menuWidthNarrow, accuracy: 0.5,
                       "清单菜单按滴答收窄到 176")
    }

    func testDetailRowLabelFollowsVisibilityAndPersistsPerView() throws {
        let (environment, window, host, probe) = try makeWindow()
        defer { window.close() }
        let key = TaskViewScopeKey.key(destination: environment.navigation.destination,
                                       activeList: environment.taskWorkspace.activeList,
                                       activeTag: nil)
        XCTAssertFalse(environment.viewPreferences.hidesDetails(for: key))

        // 键盘导航：第一条是隐藏已完成，第二条是隐藏/显示详细。
        try openMoreMenu(in: window, host: host, probe: probe)
        try sendKey(125, to: window)
        try sendKey(125, to: window)
        try sendKey(36, to: window)
        XCTAssertTrue(environment.viewPreferences.hidesDetails(for: key),
                      "第二行必须切换隐藏详细")

        try openMoreMenu(in: window, host: host, probe: probe)
        try sendKey(125, to: window)
        try sendKey(125, to: window)
        try sendKey(36, to: window)
        XCTAssertFalse(environment.viewPreferences.hidesDetails(for: key),
                       "再次执行同一行应恢复显示详细")
    }

    func testDisplaySettingsSheetOpensFromMenuAndCloses() throws {
        let (_, window, host, probe) = try makeWindow()
        defer { window.close() }

        XCTAssertEqual(TaskDisplaySettingsText.title, "显示设置")
        XCTAssertEqual(TaskDisplaySettingsText.dateRow, "日期显示为")
        XCTAssertEqual(TaskDisplaySettingsText.detailTitle, "任务详情样式")
        XCTAssertEqual(TaskDisplaySettingsText.detailDescription,
                       "当窗口宽度不足时，任务详情将根据你的选择显示。")

        // 第三行（显示设置）打开设置弹层。
        try openMoreMenu(in: window, host: host, probe: probe)
        try sendKey(125, to: window)
        try sendKey(125, to: window)
        try sendKey(125, to: window)
        try sendKey(36, to: window)
        let sheet = try attachedSheet(of: window)
        InspectorPanelTestSupport.settle(sheet)
        XCTAssertEqual(sheet.contentView?.bounds.width ?? 0, 500, accuracy: 1)
        XCTAssertEqual(sheet.contentView?.bounds.height ?? 0, 410, accuracy: 1)

        try InspectorPanelTestSupport.sendEscape(to: sheet)
        try InspectorPanelTestSupport.waitUntil("显示设置应关闭") { window.attachedSheet == nil }
    }

    func testDisplaySettingsControlsWritePreferences() throws {
        UserDefaults.standard.removeObject(forKey: dateDisplayKey)
        UserDefaults.standard.removeObject(forKey: detailLayoutKey)
        var frames: [TaskDisplaySettingsAnchor: CGRect] = [:]
        let root = TaskDisplaySettingsView(onFrames: { frames = $0 })
            .frame(width: 500, height: 410)
        let host = NSHostingView(rootView: root)
        host.appearance = NSAppearance(named: .aqua)
        let window = InspectorPanelTestSupport.ownerWindow(for: host, width: 500, height: 410)
        defer { window.close() }
        try InspectorPanelTestSupport.waitUntil("显示设置控件应完成布局") {
            frames[.dateMode] != nil && frames[.sidePeek] != nil
                && frames[.popup] != nil && frames[.close] != nil
        }

        try InspectorPanelTestSupport.click(try XCTUnwrap(frames[.dateMode]),
                                            in: host, window: window)
        _ = try visiblePanel(titled: TaskDisplaySettingsText.dateRow)
        try sendKey(125, to: window) // 当前选中任务时间，向下切到倒数日
        try sendKey(36, to: window)
        XCTAssertEqual(UserDefaults.standard.string(forKey: dateDisplayKey),
                       TaskDateDisplayMode.countdown.rawValue)

        try InspectorPanelTestSupport.click(try XCTUnwrap(frames[.sidePeek]),
                                            in: host, window: window)
        XCTAssertEqual(UserDefaults.standard.string(forKey: detailLayoutKey),
                       TaskDetailLayout.sidePeek.rawValue)
        try InspectorPanelTestSupport.click(try XCTUnwrap(frames[.popup]),
                                            in: host, window: window)
        XCTAssertEqual(UserDefaults.standard.string(forKey: detailLayoutKey),
                       TaskDetailLayout.popup.rawValue)
    }

    func testListTitleContextMenuKeepsListActivityEntry() throws {
        let (_, window, host, _) = try makeWindow()
        defer { window.close() }
        // 页头标题（“工作”）右键：清单动态与添加分组从「⋯」移到这里保留入口。
        var opened = false
        for x in [70, 85, 100, 115] {
            let titleTopLeft = NSPoint(x: x, y: 32)
            let local = NSPoint(x: titleTopLeft.x,
                                y: host.isFlipped ? titleTopLeft.y : host.bounds.height - titleTopLeft.y)
            try rightClick(host.convert(local, to: nil), in: window)
            if NSApp.windows.contains(where: { $0.title == "操作菜单" && $0.isVisible }) {
                opened = true
                break
            }
        }
        XCTAssertTrue(opened, "页头标题右键应打开清单操作菜单")
        _ = try InspectorPanelTestSupport.panel(title: "操作菜单", below: window)
        for _ in 0..<5 { try sendKey(125, to: window) }
        try sendKey(36, to: window)
        let sheet = try attachedSheet(of: window)
        InspectorPanelTestSupport.settle(sheet)
        XCTAssertEqual(sheet.contentView?.bounds.width ?? 0, PopupMetrics.activitySheetWidth, accuracy: 1)
        XCTAssertEqual(sheet.contentView?.bounds.height ?? 0, 420, accuracy: 1)
        try InspectorPanelTestSupport.sendEscape(to: sheet)
        try InspectorPanelTestSupport.waitUntil("Esc 应关闭清单动态") { window.attachedSheet == nil }
    }

    func testViewModeIconsExposeAllModesAndSwitchSelection() throws {
        var selection = TaskListViewMode.list
        var frames: [TaskListViewMode: CGRect] = [:]
        let binding = Binding(get: { selection }, set: { selection = $0 })
        let root = TaskListMenuViewModes(selection: binding,
                                         options: [.list, .kanban, .timeline],
                                         onFrames: { frames = $0 })
            .padding(8)
        let host = NSHostingView(rootView: root)
        host.appearance = NSAppearance(named: .aqua)
        let window = InspectorPanelTestSupport.ownerWindow(for: host, width: 220, height: 90)
        defer { window.close() }
        try InspectorPanelTestSupport.waitUntil("三枚视图图标应完成布局") { frames.count == 3 }
        try InspectorPanelTestSupport.click(try XCTUnwrap(frames[.kanban]),
                                            in: host, window: window)
        XCTAssertEqual(selection, .kanban)
        try InspectorPanelTestSupport.click(try XCTUnwrap(frames[.timeline]),
                                            in: host, window: window)
        XCTAssertEqual(selection, .timeline)
    }

    func testNarrowDetailLayoutKeepsListForBothStyles() throws {
        try assertNarrowLayout(.popup)
        try assertNarrowLayout(.sidePeek)
    }

    func testDateDisplayLabelsAndMenuOrders() {
        XCTAssertEqual(TaskDateDisplayMode.menuOrder, [.taskTime, .countdown])
        XCTAssertEqual(TaskDetailLayout.menuOrder, [.sidePeek, .popup])
        XCTAssertEqual(TaskDateDisplayMode.taskTime.title, "任务时间")
        XCTAssertEqual(TaskDateDisplayMode.countdown.title, "倒数日")
        XCTAssertEqual(TaskDetailLayout.sidePeek.title, "侧边栏")
        XCTAssertEqual(TaskDetailLayout.popup.title, "弹窗")

        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Asia/Shanghai")!
        let now = calendar.date(from: DateComponents(year: 2026, month: 10, day: 25, hour: 9))!
        let later = calendar.date(byAdding: .day, value: 3, to: now)!
        let past = calendar.date(byAdding: .day, value: -2, to: now)!

        XCTAssertEqual(TaskListViewDefaults.scheduleLabel(
            dueAt: later, hasTime: false, now: now, calendar: calendar,
            dateDisplay: .countdown), "3天后")
        XCTAssertEqual(TaskListViewDefaults.scheduleLabel(
            dueAt: now, hasTime: true, now: now, calendar: calendar,
            dateDisplay: .countdown), "今天 09:00")
        XCTAssertEqual(TaskListViewDefaults.scheduleLabel(
            dueAt: past, hasTime: false, now: now, calendar: calendar,
            dateDisplay: .countdown), "逾期2天")
        XCTAssertEqual(TaskListViewDefaults.scheduleLabel(
            dueAt: now, hasTime: true, now: now, calendar: calendar,
            dateDisplay: .taskTime), "09:00", "任务时间口径保持原来的纯时间")
        XCTAssertEqual(TaskListViewDefaults.scheduleLabel(
            dueAt: later, hasTime: false, now: now, calendar: calendar,
            dateDisplay: .taskTime), "10月28日")
    }

    // MARK: - Helpers

    private final class MenuProbe {
        var triggers: [String: CGRect] = [:]
    }

    private func makeWindow() throws -> (AppEnvironment, NSWindow, NSView, MenuProbe) {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("task-list-menu-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: directory) }
        let environment = AppEnvironment(directory: directory)
        let workspace = environment.taskWorkspace
        _ = workspace.createDraft(title: "工作安排", list: "工作", schedule: TaskSchedule(),
                                  priority: .none, tags: [], reminder: nil,
                                  repeatFrequency: .never)
        workspace.select(nil)
        workspace.activeList = "工作"
        environment.navigation.destination = .allTasks
        let probe = MenuProbe()
        let root = TaskListView(workspace: workspace, navigation: environment.navigation,
                                navigationVisible: false)
            .environmentObject(environment)
            .coordinateSpace(name: "business-menu")
            .onPreferenceChange(BusinessMenuTriggerFrames.self) { probe.triggers = $0 }
            .frame(width: 900, height: 800)
        let host = NSHostingView(rootView: root)
        host.appearance = NSAppearance(named: .aqua)
        let window = InspectorPanelTestSupport.ownerWindow(for: host, width: 900, height: 800)
        InspectorPanelTestSupport.settle(window)
        return (environment, window, host, probe)
    }

    private func assertNarrowLayout(_ layout: TaskDetailLayout) throws {
        UserDefaults.standard.set(layout.rawValue, forKey: detailLayoutKey)
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("narrow-detail-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: directory) }
        let environment = AppEnvironment(directory: directory)
        let workspace = environment.taskWorkspace
        let id = try XCTUnwrap(workspace.createTask(title: "窄窗详情", in: .inbox).taskID)
        workspace.select(id)
        environment.navigation.destination = .inbox
        let host = NSHostingView(rootView: RootShellView(workspace: workspace,
                                                         navigation: environment.navigation)
            .environmentObject(environment))
        host.appearance = NSAppearance(named: .aqua)
        let window = InspectorPanelTestSupport.ownerWindow(for: host, width: 600, height: 700)
        defer { window.close() }
        try InspectorPanelTestSupport.waitUntil("\(layout.title)详情的正文编辑器应就位") {
            self.find(NativeTextView.self, in: host) != nil
        }
        XCTAssertNotNil(find(NativeTaskOutline.OutlineView.self, in: host),
                        "\(layout.title)形态下列表必须留在详情后面")
    }

    private func find<T: NSView>(_ type: T.Type, in view: NSView) -> T? {
        if let hit = view as? T { return hit }
        for child in view.subviews {
            if let hit = find(type, in: child) { return hit }
        }
        return nil
    }

    private func openMoreMenu(in window: NSWindow, host: NSView, probe: MenuProbe) throws {
        let frame = try XCTUnwrap(probe.triggers["列表操作"],
                                  "找不到列表操作触发按钮：\(probe.triggers.keys)")
        try InspectorPanelTestSupport.click(frame, in: host, window: window)
        _ = try InspectorPanelTestSupport.panel(title: "列表操作", below: window)
    }

    private func sendKey(_ keyCode: UInt16, to window: NSWindow) throws {
        let event = try XCTUnwrap(NSEvent.keyEvent(
            with: .keyDown, location: .zero, modifierFlags: [],
            timestamp: ProcessInfo.processInfo.systemUptime,
            windowNumber: window.windowNumber, context: nil,
            characters: keyCode == 36 ? "\r" : "", charactersIgnoringModifiers: "",
            isARepeat: false, keyCode: keyCode))
        NSApp.sendEvent(event)
        InspectorPanelTestSupport.settle(window, duration: 0.05)
    }

    private func rightClick(_ point: NSPoint, in window: NSWindow) throws {
        let event = try XCTUnwrap(NSEvent.mouseEvent(
            with: .rightMouseDown, location: point, modifierFlags: [],
            timestamp: ProcessInfo.processInfo.systemUptime,
            windowNumber: window.windowNumber, context: nil,
            eventNumber: 1, clickCount: 1, pressure: 1))
        NSApp.postEvent(event, atStart: true)
        let down = try XCTUnwrap(NSApp.nextEvent(matching: .rightMouseDown, until: Date(),
                                                inMode: .default, dequeue: true))
        NSApp.sendEvent(down)
        InspectorPanelTestSupport.settle(window)
    }

    private func attachedSheet(of window: NSWindow) throws -> NSWindow {
        let deadline = Date().addingTimeInterval(1.5)
        while Date() < deadline {
            if let sheet = window.attachedSheet, sheet.contentView != nil { return sheet }
            RunLoop.current.run(until: Date().addingTimeInterval(0.02))
        }
        return try XCTUnwrap(window.attachedSheet, "显示设置 sheet 未出现")
    }

    private func visiblePanel(titled title: String) throws -> NSPanel {
        let deadline = Date().addingTimeInterval(1.5)
        while Date() < deadline {
            if let panel = NSApp.windows.first(where: { $0.title == title && $0.isVisible }) as? NSPanel {
                return panel
            }
            RunLoop.current.run(until: Date().addingTimeInterval(0.02))
        }
        return try XCTUnwrap(NSApp.windows.first { $0.title == title && $0.isVisible } as? NSPanel,
                             "没有可见的 \(title) 面板")
    }
}
