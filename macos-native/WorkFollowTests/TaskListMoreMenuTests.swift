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
        // 「全部删除」只属于已完成视图：通用条目不能因为它被改动。
        XCTAssertEqual(TaskListMoreMenuPolicy.entries(for: .completed),
                       [.viewModes, .separator, .hidesCompleted, .detailsVisibility,
                        .displaySettings, .separator, .deleteAllCompleted])
        for destination in [NativeDestination.today, .tomorrow, .inbox, .allTasks,
                            .nextSevenDays, .abandoned, .trash] {
            XCTAssertEqual(TaskListMoreMenuPolicy.entries(for: destination),
                           TaskListMoreMenuPolicy.entries,
                           "\(destination.title) 不该出现「全部删除」")
        }
        XCTAssertEqual(TaskListMoreMenuPolicy.detailsTitle(hidesDetails: false), "隐藏详细")
        XCTAssertEqual(TaskListMoreMenuPolicy.detailsTitle(hidesDetails: true), "显示详细")
        XCTAssertEqual(TaskListMoreMenuPolicy.deleteAllCompletedTitle, "全部删除")
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

    func testMenuActionsFollowTheListAfterSwitchingScopes() throws {
        let (environment, window, host, probe) = try makeWindow()
        defer { window.close() }
        let workspace = environment.taskWorkspace
        let keyA = TaskViewScopeKey.key(destination: .allTasks, activeList: "工作", activeTag: nil)
        let keyB = TaskViewScopeKey.key(destination: .allTasks, activeList: "虚构菜单清单", activeTag: nil)
        environment.viewPreferences.setHidesDetails(false, for: keyA)
        environment.viewPreferences.setHidesDetails(false, for: keyB)
        _ = workspace.createDraft(title: "虚构条目", list: "虚构菜单清单", schedule: TaskSchedule(),
                                  priority: .none, tags: [], reminder: nil, repeatFrequency: .never)
        for name in ["虚构菜单清单", "工作"] {
            environment.navigation.openTaskList(name, in: workspace)
            InspectorPanelTestSupport.settle(window)
            try openMoreMenu(in: window, host: host, probe: probe)
            try sendKey(125, to: window)
            try sendKey(125, to: window)
            try sendKey(36, to: window)
            XCTAssertTrue(environment.viewPreferences.hidesDetails(for: name == "工作" ? keyA : keyB))
        }
        XCTAssertTrue(environment.viewPreferences.hidesDetails(for: keyA))
        XCTAssertTrue(environment.viewPreferences.hidesDetails(for: keyB))
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
        XCTAssertEqual(sheet.contentView?.bounds.width ?? 0, SheetDialogMetrics.narrowWidth, accuracy: 1)
        XCTAssertEqual(sheet.contentView?.bounds.height ?? 0, 420, accuracy: 1)
        try InspectorPanelTestSupport.sendEscape(to: sheet)
        try InspectorPanelTestSupport.waitUntil("Esc 应关闭清单动态") { window.attachedSheet == nil }
    }

    /// 「已完成」视图的「⋯」多出「全部删除」：菜单里点得到、确认后整批进垃圾桶。
    ///
    /// 菜单高度用**同一窗口切换目的地前后**的对比来判断，不写死像素：条目
    /// 变多，菜单就该变高，这比"等于某个数"更不容易被无关的排版调整带崩。
    func testCompletedViewMenuAddsDeleteAllCompletedAndDeletesAfterConfirmation() throws {
        let (environment, workspace, window, host, probe) = try makeCompletedWindow()
        defer { window.close() }

        // 先量通用菜单的高度（换成收集箱量基准）。
        environment.navigation.destination = .inbox
        InspectorPanelTestSupport.settle(window)
        try openMoreMenu(in: window, host: host, probe: probe)
        let genericMenu = try InspectorPanelTestSupport.panel(title: "列表操作", below: window)
        let genericHeight = genericMenu.frame.height
        try InspectorPanelTestSupport.sendEscape(to: genericMenu)

        environment.navigation.destination = .completed
        InspectorPanelTestSupport.settle(window)
        XCTAssertEqual(workspace.completedDeletionCount(), 2)

        try openMoreMenu(in: window, host: host, probe: probe)
        let menu = try InspectorPanelTestSupport.panel(title: "列表操作", below: window)
        XCTAssertGreaterThan(menu.frame.height, genericHeight,
                             "已完成视图的菜单要比通用菜单多出「全部删除」那一行")
        XCTAssertEqual(menu.frame.width, PopupMetrics.menuWidthNarrow, accuracy: 0.5)
        try InspectorPanelTestSupport.sendEscape(to: menu)

        try triggerDeleteAllCompleted(in: window, host: host, probe: probe)
        let dialog = try deleteAllCompletedDialog(in: window)
        XCTAssertEqual(workspace.completedDeletionCount(), 2, "确认之前不能动数据")

        try clickDialogButton("全部删除", in: dialog, probe: probe)
        try InspectorPanelTestSupport.waitUntil("确认后已完成视图应清空", timeout: 2) {
            workspace.completedDeletionCount() == 0
        }
        XCTAssertEqual(workspace.deletedTasks.count, 2)
        // 未完成的那条仍在列表里，没被顺手删掉。
        XCTAssertTrue(workspace.allTasks.contains { $0.title == "还在做" && $0.deletedAt == nil })
    }

    /// 取消确认框时一条都不删：破坏性动作必须真的做到"点了取消就什么都没发生"。
    func testCancellingTheConfirmationKeepsCompletedTasks() throws {
        let (_, workspace, window, host, probe) = try makeCompletedWindow()
        defer { window.close() }
        XCTAssertEqual(workspace.completedDeletionCount(), 2)

        try triggerDeleteAllCompleted(in: window, host: host, probe: probe)
        let dialog = try deleteAllCompletedDialog(in: window)
        try clickDialogButton("取消", in: dialog, probe: probe)

        try InspectorPanelTestSupport.waitUntil("确认框应关闭", timeout: 2) {
            !(window.childWindows ?? []).contains {
                $0.title == "全部删除已完成任务" && $0.isVisible
            }
        }
        XCTAssertEqual(workspace.completedDeletionCount(), 2)
        XCTAssertTrue(workspace.deletedTasks.isEmpty)
    }

    /// 已完成为空时菜单项置灰：点下去不该弹一个"删 0 条"的确认框。
    func testEmptyCompletedViewDisablesTheMenuEntry() throws {
        let environment = try makeEnvironment(prefix: "task-list-completed-empty")
        _ = environment.taskWorkspace.createDraft(title: "还在做", list: TaskList.inbox.name,
                                                  schedule: TaskSchedule(), priority: .none,
                                                  tags: [], reminder: nil,
                                                  repeatFrequency: .never)
        environment.navigation.destination = .completed
        let (window, host, probe) = try host(environment)
        defer { window.close() }
        XCTAssertEqual(environment.taskWorkspace.completedDeletionCount(), 0)

        try openMoreMenu(in: window, host: host, probe: probe)
        let menu = try InspectorPanelTestSupport.panel(title: "列表操作", below: window)
        // 走到「全部删除」那一行回车：禁用行不该执行动作。
        for _ in 0..<4 { try sendKey(125, to: menu) }
        try sendKey(36, to: menu)
        // 禁用项被键盘跳过，回车可能落在别处；无论落在哪，都不能出现删除确认框。
        RunLoop.current.run(until: Date().addingTimeInterval(0.3))
        XCTAssertFalse((window.childWindows ?? []).contains {
            $0.title == "全部删除已完成任务" && $0.isVisible
        }, "已完成为空时不该弹确认框")
    }

    func testViewModeIconsExposeAllModesAndSwitchSelection() throws {        var selection = TaskListViewMode.list
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
        /// 主题化对话框的按钮锚点（`workflowActionAnchor` 上报，按 identifier 索引）。
        var dialogAnchors: [String: NSView] = [:]
    }

    private func makeWindow() throws -> (AppEnvironment, NSWindow, NSView, MenuProbe) {
        let environment = try makeEnvironment(prefix: "task-list-menu")
        let workspace = environment.taskWorkspace
        _ = workspace.createDraft(title: "工作安排", list: "工作", schedule: TaskSchedule(),
                                  priority: .none, tags: [], reminder: nil,
                                  repeatFrequency: .never)
        workspace.select(nil)
        workspace.activeList = "工作"
        environment.navigation.destination = .allTasks
        let (window, host, probe) = try host(environment)
        return (environment, window, host, probe)
    }

    /// 「已完成」视图的宿主：两条已完成 + 一条待办，方便断言"只删已完成的"。
    private func makeCompletedWindow()
        throws -> (AppEnvironment, TaskWorkspaceModel, NSWindow, NSView, MenuProbe) {
        let environment = try makeEnvironment(prefix: "task-list-completed-menu")
        let workspace = environment.taskWorkspace
        for title in ["完成一", "完成二"] {
            let id = workspace.createDraft(title: title, list: TaskList.inbox.name,
                                           schedule: TaskSchedule(), priority: .none, tags: [],
                                           reminder: nil, repeatFrequency: .never).taskID!
            _ = workspace.complete(id)
        }
        _ = workspace.createDraft(title: "还在做", list: TaskList.inbox.name,
                                  schedule: TaskSchedule(), priority: .none, tags: [],
                                  reminder: nil, repeatFrequency: .never)
        workspace.select(nil)
        environment.navigation.destination = .completed
        let (window, host, probe) = try host(environment)
        return (environment, workspace, window, host, probe)
    }

    private func makeEnvironment(prefix: String) throws -> AppEnvironment {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("\(prefix)-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: directory) }
        return AppEnvironment(directory: directory)
    }

    private func host(_ environment: AppEnvironment) throws -> (NSWindow, NSView, MenuProbe) {
        let probe = MenuProbe()
        let root = TaskListView(workspace: environment.taskWorkspace,
                                navigation: environment.navigation,
                                navigationVisible: false)
            .environmentObject(environment)
            .coordinateSpace(name: "business-menu")
            .onPreferenceChange(BusinessMenuTriggerFrames.self) { probe.triggers = $0 }
            // 主题化对话框的按钮是自绘的，不在 AX 树里；只能靠 debug 锚点定位。
            .environment(\.workflowActionObservation, { probe.dialogAnchors[$0] = $1 })
            .frame(width: 900, height: 800)
        let host = NSHostingView(rootView: root)
        host.appearance = NSAppearance(named: .aqua)
        let window = InspectorPanelTestSupport.ownerWindow(for: host, width: 900, height: 800)
        InspectorPanelTestSupport.settle(window)
        return (window, host, probe)
    }

    /// 点主题化对话框里的某个按钮。按钮标题即 identifier（未显式给 id 时）。
    private func clickDialogButton(_ title: String, in dialog: NSWindow,
                                   probe: MenuProbe) throws {
        let key = "dialog.button.\(title)"
        try InspectorPanelTestSupport.waitUntil("对话框按钮「\(title)」应完成布局", timeout: 2) {
            guard let anchor = probe.dialogAnchors[key] else { return false }
            return anchor.window === dialog && !anchor.bounds.isEmpty
        }
        let anchor = try XCTUnwrap(probe.dialogAnchors[key])
        try InspectorPanelTestSupport.click(anchor.bounds, in: anchor, window: dialog)
    }

    /// 等到「全部删除」确认框出现并返回它。
    private func deleteAllCompletedDialog(in window: NSWindow) throws -> NSWindow {
        try InspectorPanelTestSupport.waitUntil("应弹出全部删除确认框", timeout: 2) {
            (window.childWindows ?? []).contains {
                $0.title == "全部删除已完成任务" && $0.isVisible
            }
        }
        let dialog = try XCTUnwrap((window.childWindows ?? [])
            .first { $0.title == "全部删除已完成任务" && $0.isVisible })
        InspectorPanelTestSupport.settle(dialog)
        return dialog
    }

    /// 在「已完成」视图里打开「⋯」并用键盘落到「全部删除」那一行。
    private func triggerDeleteAllCompleted(in window: NSWindow, host: NSView,
                                           probe: MenuProbe) throws {
        try openMoreMenu(in: window, host: host, probe: probe)
        let menu = try InspectorPanelTestSupport.panel(title: "列表操作", below: window)
        // 键盘行序：隐藏已完成 → 隐藏详细 → 显示设置 → 全部删除
        //（顶部三枚视图图标是自绘块，不进键盘行序）。
        for _ in 0..<4 { try sendKey(125, to: menu) }
        try sendKey(36, to: menu)
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
            self.find(MilkdownWebView.self, in: host)?.isDocumentReady == true
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
