import AppKit
import SwiftUI
import XCTest
@testable import WorkFollow

@MainActor
final class TaskContextPanelTests: XCTestCase {
    private typealias Adapter = AnchoredPropertyPanel<AnyView>
    private final class MenuProbe {
        var rows: [TaskContextMenuAnchor: CGRect] = [:]
        var tags: [TaskTagPickerAnchor: CGRect] = [:]
        var focus: [InspectorRenderAnchor: CGRect] = [:]
        var actions: [DialogActionAnchor: CGRect] = [:]
        var lists: [TaskContextSubmenuAnchor: CGRect] = [:]
        var sections: [TaskContextSubmenuAnchor: CGRect] = [:]
        var menuRows: [BusinessMenuRowFrame] = []
    }

    private func openMenu(workspace: TaskWorkspaceModel, taskID: UUID, environment: AppEnvironment,
                          probe: MenuProbe, appearance: NSAppearance.Name = .aqua) throws -> (NSWindow, TaskContextMenuPresenter.Session) {
        let ownerView = NSView(frame: CGRect(x: 0, y: 0, width: 1000, height: 700))
        let owner = InspectorPanelTestSupport.ownerWindow(for: ownerView, width: 1000, height: 700)
        owner.appearance = NSAppearance(named: appearance)
        environment.focusStore.notifier = nil
        let session = TaskContextMenuPresenter.Session(in: try XCTUnwrap(owner.contentView),
            at: CGPoint(x: 150, y: owner.contentLayoutRect.height - 12))
        let presenter = PopupPresentingWindow()
        presenter.window = owner
        session.coordinator.presentingWindow = presenter
        session.coordinator.root = AnyView(TaskContextMenuPopover(workspace: workspace,
            isPresented: Binding(get: { [weak session] in session?.coordinator.presented == true },
                                 set: { [weak session] in if !$0 { session?.close() } }),
            task: try XCTUnwrap(workspace.task(for: taskID)), onCustomDate: {}, onChooseParent: {})
            .environmentObject(environment)
            .onPreferenceChange(TaskContextMenuFrames.self) { probe.rows = $0 }
            .onPreferenceChange(BusinessMenuRowFrames.self) { probe.menuRows = $0 }
            .environment(\.popupContentObservation, { content in
                AnyView(content.coordinateSpace(name: "inspector-render").coordinateSpace(name: "dialog-render")
                    .onPreferenceChange(TaskTagPickerFrames.self) { if !$0.isEmpty { probe.tags = $0 } }
                    .onPreferenceChange(InspectorFramesKey.self) { if !$0.isEmpty { probe.focus = $0 } }
                    .onPreferenceChange(TaskContextSubmenuFrames.self) {
                        if $0[.search] != nil { probe.lists = $0 }
                        else if $0[.addSection] != nil { probe.sections = $0 }
                    }
                    .onPreferenceChange(DialogActionFrames.self) { if !$0.isEmpty { probe.actions = $0 } })
            }))
        session.coordinator.update()
        settle()
        return (owner, session)
    }

    private func click(_ rect: CGRect, in window: NSWindow) throws {
        try InspectorPanelTestSupport.click(rect, in: try XCTUnwrap(window.contentView), window: window)
    }

    private func savePreview(_ name: String, of window: NSWindow) throws {
        guard let directory = ProcessInfo.processInfo.environment["WF_CONTEXT_MENU_ARTIFACTS"] else { return }
        let host = try XCTUnwrap(window.contentView)
        let bitmap = try XCTUnwrap(host.bitmapImageRepForCachingDisplay(in: host.bounds))
        host.cacheDisplay(in: host.bounds, to: bitmap)
        try XCTUnwrap(bitmap.representation(using: .png, properties: [:]))
            .write(to: URL(fileURLWithPath: directory).appendingPathComponent(name + ".png"))
    }

    private func field(placeholder: String, in window: NSWindow) throws -> NSTextField {
        func fields(_ view: NSView) -> [NSTextField] {
            (view as? NSTextField).map { [$0] } ?? view.subviews.flatMap(fields)
        }
        return try XCTUnwrap(fields(try XCTUnwrap(window.contentView)).first {
            $0.isEditable && $0.placeholderString == placeholder
        })
    }

    private func enter(_ text: String, placeholder: String, in window: NSWindow) throws {
        let field = try field(placeholder: placeholder, in: window)
        window.makeFirstResponder(field)
        let editor = try XCTUnwrap(field.currentEditor() as? NSTextView)
        editor.selectAll(nil)
        editor.insertText(text, replacementRange: editor.selectedRange())
        InspectorPanelTestSupport.settle(window)
    }

    private func key(_ code: UInt16, in window: NSWindow) throws {
        let event = try XCTUnwrap(NSEvent.keyEvent(with: .keyDown, location: .zero,
            modifierFlags: [], timestamp: ProcessInfo.processInfo.systemUptime,
            windowNumber: window.windowNumber, context: nil, characters: "", charactersIgnoringModifiers: "",
            isARepeat: false, keyCode: code))
        NSApp.sendEvent(event)
        InspectorPanelTestSupport.settle(window)
    }

    func testMoveSubmenuSearchesAndMovesToListWithUndo() throws {
        let workspace = TaskWorkspaceModel(seedDemoData: false)
        XCTAssertTrue(workspace.saveList("工作"))
        XCTAssertTrue(workspace.saveList("生活"))
        let id = try XCTUnwrap(workspace.createTask(title: "移动清单验收", in: .inbox).taskID)
        let probe = MenuProbe()
        let (owner, session) = try openMenu(workspace: workspace, taskID: id,
            environment: AppEnvironment(), probe: probe)
        defer { session.close(); owner.close() }
        let menu = try XCTUnwrap(session.coordinator.panel)
        let original = menu.frame
        try click(try XCTUnwrap(probe.rows[.action("移动到")]), in: menu)
        let lists = try InspectorPanelTestSupport.panel(title: "移动到清单", below: owner)
        XCTAssertEqual(lists.frame.width, PopupMetrics.menuWidth, accuracy: 0.5)
        XCTAssertLessThan(lists.frame.height, 230, "少量清单按内容收高")
        try savePreview("move-lists", of: lists)
        try enter("工作", placeholder: "搜索", in: lists)
        XCTAssertNotNil(probe.lists[.list("工作")])
        XCTAssertNil(probe.lists[.list("生活")])
        XCTAssertEqual(workspace.task(for: id)?.list, .inbox, "搜索不应移动任务")
        try click(try XCTUnwrap(probe.lists[.list("工作")]), in: lists)
        XCTAssertEqual(workspace.task(for: id)?.list.name, "工作")
        XCTAssertTrue(lists.isVisible)
        XCTAssertTrue(menu.isVisible)
        XCTAssertEqual(menu.frame, original)
        workspace.undo()
        XCTAssertEqual(workspace.task(for: id)?.list, .inbox)
        try InspectorPanelTestSupport.sendEscape(to: owner)
        XCTAssertFalse(lists.isVisible)
        XCTAssertTrue(menu.isVisible)
    }

    func testMoveSectionArrowAndKeyboardOpenWithoutMovingThenSelectionIsAtomic() throws {
        let workspace = TaskWorkspaceModel(seedDemoData: false)
        XCTAssertTrue(workspace.saveList("工作"))
        XCTAssertTrue(workspace.addListSection("工作", title: "进行中"))
        let section = try XCTUnwrap(workspace.listSections(forList: "工作").first)
        let id = try XCTUnwrap(workspace.createTask(title: "跨清单分组验收", in: .inbox).taskID)
        let probe = MenuProbe()
        let (owner, session) = try openMenu(workspace: workspace, taskID: id,
            environment: AppEnvironment(), probe: probe)
        defer { session.close(); owner.close() }
        let menu = try XCTUnwrap(session.coordinator.panel)
        try click(try XCTUnwrap(probe.rows[.action("移动到")]), in: menu)
        let lists = try InspectorPanelTestSupport.panel(title: "移动到清单", below: owner)
        lists.makeFirstResponder(nil)
        let index = try XCTUnwrap(workspace.availableListNames.firstIndex(of: "工作"))
        for _ in 0...index { try key(125, in: lists) }
        try key(124, in: lists)
        let first = try InspectorPanelTestSupport.panel(title: "移动到分组", below: owner)
        XCTAssertEqual(workspace.task(for: id)?.list, .inbox, "右箭头只展开分组")
        try key(123, in: first)
        XCTAssertFalse(first.isVisible)
        XCTAssertTrue(lists.isVisible)
        let row = try XCTUnwrap(probe.lists[.list("工作")])
        try click(CGRect(x: row.maxX - 12, y: row.midY, width: 1, height: 1), in: lists)
        let groups = try InspectorPanelTestSupport.panel(title: "移动到分组", below: owner)
        XCTAssertTrue(groups.parent === lists)
        XCTAssertEqual(workspace.task(for: id)?.list, .inbox, "点击展开按钮也不能提前移动")
        try savePreview("move-sections", of: groups)
        let originalSection = try XCTUnwrap(probe.sections[.section(section.id)])
        try click(originalSection, in: groups)
        XCTAssertEqual(workspace.task(for: id)?.list.name, "工作")
        XCTAssertEqual(workspace.task(for: id)?.sectionID, section.id)
        XCTAssertEqual(probe.sections[.section(section.id)], originalSection, "选中后分组候选保持原位")
        workspace.undo()
        InspectorPanelTestSupport.settle(groups)
        XCTAssertEqual(workspace.task(for: id)?.list, .inbox)
        XCTAssertNil(workspace.task(for: id)?.sectionID, "一次撤销同时恢复清单和分组")
        try click(try XCTUnwrap(probe.sections[.section(section.id)]), in: groups)
        XCTAssertEqual(workspace.task(for: id)?.sectionID, section.id)
        try click(try XCTUnwrap(probe.sections[.clearSection]), in: groups)
        XCTAssertEqual(workspace.task(for: id)?.list.name, "工作")
        XCTAssertNil(workspace.task(for: id)?.sectionID)
        workspace.undo()
        XCTAssertEqual(workspace.task(for: id)?.sectionID, section.id)
    }

    func testNewSectionFormValidatesCancelsAndCreatesThenMoves() throws {
        let workspace = TaskWorkspaceModel(seedDemoData: false)
        XCTAssertTrue(workspace.saveList("工作"))
        XCTAssertTrue(workspace.addListSection("工作", title: "进行中"))
        let id = try XCTUnwrap(workspace.createTask(title: "新建分组验收", in: .inbox).taskID)
        let probe = MenuProbe()
        let (owner, session) = try openMenu(workspace: workspace, taskID: id,
            environment: AppEnvironment(), probe: probe)
        defer { session.close(); owner.close() }
        let menu = try XCTUnwrap(session.coordinator.panel)
        try click(try XCTUnwrap(probe.rows[.action("移动到")]), in: menu)
        let lists = try InspectorPanelTestSupport.panel(title: "移动到清单", below: owner)
        let row = try XCTUnwrap(probe.lists[.list("工作")])
        try click(CGRect(x: row.maxX - 12, y: row.midY, width: 1, height: 1), in: lists)
        let groups = try InspectorPanelTestSupport.panel(title: "移动到分组", below: owner)
        try click(try XCTUnwrap(probe.sections[.addSection]), in: groups)
        let form = try InspectorPanelTestSupport.panel(title: "添加分组", below: owner)
        let original = form.frame
        try enter("进行中", placeholder: "分组名称", in: form)
        try click(try XCTUnwrap(probe.actions[.primary]), in: form)
        XCTAssertEqual(workspace.listSections(forList: "工作").count, 1)
        XCTAssertEqual(form.frame, original, "校验错误不能推走操作栏")
        try click(try XCTUnwrap(probe.actions[.cancel]), in: form)
        XCTAssertFalse(form.isVisible)
        XCTAssertEqual(workspace.task(for: id)?.list, .inbox)
        try click(try XCTUnwrap(probe.sections[.addSection]), in: groups)
        let reopened = try InspectorPanelTestSupport.panel(title: "添加分组", below: owner)
        try enter("验收", placeholder: "分组名称", in: reopened)
        try savePreview("add-section", of: reopened)
        try click(try XCTUnwrap(probe.actions[.primary]), in: reopened)
        let added = try XCTUnwrap(workspace.listSections(forList: "工作").first { $0.title == "验收" })
        XCTAssertEqual(workspace.task(for: id)?.list.name, "工作")
        XCTAssertEqual(workspace.task(for: id)?.sectionID, added.id)
        XCTAssertFalse(reopened.isVisible)
        XCTAssertTrue(groups.isVisible)
    }

    func testReferenceMenuKeepsAllActionsInOrderWithFourDateShortcutsAndVisibleDelete() throws {
        let workspace = TaskWorkspaceModel(seedDemoData: false)
        let id = try XCTUnwrap(workspace.createTask(title: "截图菜单验收", in: .inbox).taskID)
        _ = workspace.createTask(title: "可关联的主任务", in: .inbox)
        _ = workspace.createTag("1")
        _ = workspace.createTag("rea 标签甲")
        workspace.setTags(id, ["REA 标签验收"])
        let environment = AppEnvironment()
        let titles = ["添加子任务", "关联主任务", "置顶", "放弃", "移动到", "标签", "开始专注",
                      "创建副本", "复制链接", "打开便签", "转换为笔记", "删除"]
        for (name, appearance) in [("light", NSAppearance.Name.aqua), ("dark", .darkAqua)] {
            let probe = MenuProbe()
            let (owner, session) = try openMenu(workspace: workspace, taskID: id,
                environment: environment, probe: probe, appearance: appearance)
            defer { session.close(); owner.close() }
            let menu = try XCTUnwrap(session.coordinator.panel)
            let bounds = try XCTUnwrap(menu.contentView).bounds
            let frames = try titles.map { try XCTUnwrap(probe.rows[.action($0)], "缺少菜单项：" + $0) }
            XCTAssertEqual(frames.map(\.minY), frames.map(\.minY).sorted())
            for frame in frames { XCTAssertTrue(bounds.insetBy(dx: -1, dy: -1).contains(frame), "菜单项不能被裁切") }
            let shortcuts: [TaskContextMenuAnchor] = [.date(0), .date(1), .date(7), .customDate]
            let dates = try shortcuts.map { try XCTUnwrap(probe.rows[$0]) }
            XCTAssertEqual(dates.map(\.minX), dates.map(\.minX).sorted())
            XCTAssertEqual(dates.count, 4)
            XCTAssertEqual(probe.menuRows.count, titles.count, "主菜单动作也必须使用共享菜单行")
            for row in probe.menuRows {
                XCTAssertEqual(row.rect.height, PopupMetrics.menuRowHeight, accuracy: 0.5)
                XCTAssertEqual(row.rect.minX, PopupMetrics.menuInset, accuracy: 0.5)
                XCTAssertEqual(row.rect.maxX, bounds.width - PopupMetrics.menuInset, accuracy: 0.5)
            }
            let original = menu.frame
            try savePreview("task-menu-" + name, of: menu)
            try click(try XCTUnwrap(probe.rows[.action("标签")]), in: menu)
            let tags = try InspectorPanelTestSupport.panel(title: "任务标签", below: owner)
            XCTAssertTrue(tags.parent === menu)
            XCTAssertNotNil(probe.tags[.remove("REA 标签验收")])
            XCTAssertEqual(menu.frame, original)
            try savePreview("task-tags-" + name, of: tags)
            try InspectorPanelTestSupport.sendEscape(to: owner)
            XCTAssertFalse(tags.isVisible)
            XCTAssertTrue(menu.isVisible)
            try click(try XCTUnwrap(probe.rows[.action("移动到")]), in: menu)
            let lists = try InspectorPanelTestSupport.panel(title: "移动到清单", below: owner)
            try savePreview("move-lists-" + name, of: lists)
            try InspectorPanelTestSupport.sendEscape(to: owner)
            try click(try XCTUnwrap(probe.rows[.action("开始专注")]), in: menu)
            let focus = try InspectorPanelTestSupport.panel(title: "任务专注", below: owner)
            try savePreview("task-focus-" + name, of: focus)
            try click(try XCTUnwrap(probe.focus[.focusEstimate]), in: focus)
            let estimate = try InspectorPanelTestSupport.panel(title: "预计专注", below: owner)
            try savePreview("focus-estimate-" + name, of: estimate)
            try InspectorPanelTestSupport.sendEscape(to: owner)
            XCTAssertEqual(menu.frame, original)
        }
    }

    func testContextTagChipRemovalUsesDraftAndConfirmIsUndoable() throws {
        let workspace = TaskWorkspaceModel(seedDemoData: false)
        let id = try XCTUnwrap(workspace.createTask(title: "标签草稿验收", in: .inbox).taskID)
        workspace.setTags(id, ["原标签"])
        _ = workspace.createTag("工作")
        let probe = MenuProbe()
        let (owner, session) = try openMenu(workspace: workspace, taskID: id,
            environment: AppEnvironment(), probe: probe)
        defer { session.close(); owner.close() }
        let menu = try XCTUnwrap(session.coordinator.panel)
        try click(try XCTUnwrap(probe.rows[.action("标签")]), in: menu)
        let tags = try InspectorPanelTestSupport.panel(title: "任务标签", below: owner)
        let footer = try XCTUnwrap(probe.tags[.confirm])
        try click(try XCTUnwrap(probe.tags[.remove("原标签")]), in: tags)
        XCTAssertEqual(workspace.task(for: id)?.tags, ["原标签"])
        XCTAssertEqual(probe.tags[.confirm], footer)
        try click(try XCTUnwrap(probe.tags[.cancel]), in: tags)
        XCTAssertFalse(tags.isVisible)
        XCTAssertTrue(menu.isVisible)
        try click(try XCTUnwrap(probe.rows[.action("标签")]), in: menu)
        let reopened = try InspectorPanelTestSupport.panel(title: "任务标签", below: owner)
        try click(try XCTUnwrap(probe.tags[.remove("原标签")]), in: reopened)
        try click(try XCTUnwrap(probe.tags[.tag("工作")]), in: reopened)
        XCTAssertEqual(workspace.task(for: id)?.tags, ["原标签"])
        try click(try XCTUnwrap(probe.tags[.confirm]), in: reopened)
        XCTAssertEqual(workspace.task(for: id)?.tags, ["工作"])
        XCTAssertFalse(menu.isVisible)
        XCTAssertFalse(reopened.isVisible)
        workspace.undo()
        XCTAssertEqual(workspace.task(for: id)?.tags, ["原标签"])
    }

    func testRootMenuKeyboardEntersListAndFocusWithoutExecutingAnAction() throws {
        let workspace = TaskWorkspaceModel(seedDemoData: false)
        let id = try XCTUnwrap(workspace.createTask(title: "主卡键盘入口", in: .inbox).taskID)
        _ = workspace.createTask(title: "可关联主任务", in: .inbox)
        let environment = AppEnvironment(), probe = MenuProbe()
        let (owner, session) = try openMenu(workspace: workspace, taskID: id,
            environment: environment, probe: probe)
        defer { session.close(); owner.close() }
        let menu = try XCTUnwrap(session.coordinator.panel)
        menu.makeFirstResponder(nil)
        for _ in 0..<5 { try key(125, in: menu) }
        try key(124, in: menu)
        let lists = try InspectorPanelTestSupport.panel(title: "移动到清单", below: owner)
        XCTAssertEqual(workspace.task(for: id)?.list, .inbox)
        try InspectorPanelTestSupport.sendEscape(to: owner)
        XCTAssertFalse(lists.isVisible)
        try key(125, in: menu)
        try key(125, in: menu)
        try key(124, in: menu)
        let focus = try InspectorPanelTestSupport.panel(title: "任务专注", below: owner)
        XCTAssertEqual(environment.focusStore.phase, .idle)
        try key(123, in: focus)
        XCTAssertFalse(focus.isVisible)
        XCTAssertTrue(menu.isVisible)
    }

    func testContextFocusSubmenuStartsTheChosenModeOnlyAfterSelection() throws {
        for stopwatch in [false, true] {
            let workspace = TaskWorkspaceModel(seedDemoData: false)
            let id = try XCTUnwrap(workspace.createTask(title: "右键专注验收", in: .inbox).taskID)
            let environment = AppEnvironment(), probe = MenuProbe()
            let (owner, session) = try openMenu(workspace: workspace, taskID: id,
                environment: environment, probe: probe)
            defer { _ = environment.focusStore.giveUp(); session.close(); owner.close() }
            let menu = try XCTUnwrap(session.coordinator.panel)
            try click(try XCTUnwrap(probe.rows[.action("开始专注")]), in: menu)
            let focus = try InspectorPanelTestSupport.panel(title: "任务专注", below: owner)
            XCTAssertTrue(focus.parent === menu)
            XCTAssertEqual(focus.frame.width, PopupMetrics.taskMenuWidth, accuracy: 0.5)
            XCTAssertEqual(environment.focusStore.phase, .idle, "展开子菜单不能直接启动专注")
            try savePreview("task-focus", of: focus)
            if stopwatch {
                focus.makeFirstResponder(nil)
                try key(125, in: focus)
                try key(125, in: focus)
                try key(36, in: focus)
            } else {
                try click(try XCTUnwrap(probe.focus[.focusPomodoro]), in: focus)
            }
            XCTAssertEqual(environment.focusStore.currentTaskID, id)
            XCTAssertEqual(environment.focusStore.phase, .focusing)
            XCTAssertEqual(environment.focusStore.sessionTiming?.projectedEndAt == nil, stopwatch)
            XCTAssertEqual(environment.navigation.destination, .focus)
            XCTAssertFalse(menu.isVisible)
            XCTAssertFalse(focus.isVisible)
        }
    }

    func testContextFocusEstimateCancelsOrSavesWithoutStartingTimer() throws {
        let workspace = TaskWorkspaceModel(seedDemoData: false)
        let id = try XCTUnwrap(workspace.createTask(title: "右键预计专注", in: .inbox).taskID)
        let environment = AppEnvironment(), probe = MenuProbe()
        let (owner, session) = try openMenu(workspace: workspace, taskID: id,
            environment: environment, probe: probe)
        defer { session.close(); owner.close() }
        let menu = try XCTUnwrap(session.coordinator.panel)
        func openEstimate() throws -> NSPanel {
            try click(try XCTUnwrap(probe.rows[.action("开始专注")]), in: menu)
            let focus = try InspectorPanelTestSupport.panel(title: "任务专注", below: owner)
            try click(try XCTUnwrap(probe.focus[.focusEstimate]), in: focus)
            let estimate = try InspectorPanelTestSupport.panel(title: "预计专注", below: owner)
            XCTAssertFalse(focus.isVisible)
            XCTAssertTrue(menu.isVisible)
            XCTAssertEqual(environment.focusStore.phase, .idle)
            return estimate
        }

        let canceled = try openEstimate()
        try enter("40", placeholder: "数值", in: canceled)
        try click(try XCTUnwrap(probe.actions[.cancel]), in: canceled)
        XCTAssertFalse(canceled.isVisible)
        XCTAssertNil(workspace.task(for: id)?.focusEstimate)

        let estimate = try openEstimate()
        try enter("40", placeholder: "数值", in: estimate)
        try InspectorPanelTestSupport.clickElement(containing: "番茄数", in: estimate)
        XCTAssertEqual(try field(placeholder: "数值", in: estimate).stringValue, "1")
        try enter("2", placeholder: "数值", in: estimate)
        try InspectorPanelTestSupport.clickElement(containing: "时长", in: estimate)
        XCTAssertEqual(try field(placeholder: "数值", in: estimate).stringValue, "40", "切换单位保留各自的草稿")
        try InspectorPanelTestSupport.clickElement(containing: "番茄数", in: estimate)
        XCTAssertEqual(try field(placeholder: "数值", in: estimate).stringValue, "2")
        try savePreview("focus-estimate", of: estimate)
        try click(try XCTUnwrap(probe.actions[.primary]), in: estimate)
        XCTAssertEqual(workspace.task(for: id)?.focusEstimate?.pomodoros, 2)
        XCTAssertNil(workspace.task(for: id)?.focusEstimate?.minutes)
        XCTAssertFalse(estimate.isVisible)
        XCTAssertTrue(menu.isVisible)
        XCTAssertEqual(environment.focusStore.phase, .idle)

        let clear = try openEstimate()
        try click(try XCTUnwrap(probe.focus[.focusEstimateClear]), in: clear)
        XCTAssertFalse(clear.isVisible)
        XCTAssertNil(workspace.task(for: id)?.focusEstimate)
        workspace.undo()
        XCTAssertEqual(workspace.task(for: id)?.focusEstimate?.pomodoros, 2)
        workspace.undo()
        XCTAssertNil(workspace.task(for: id)?.focusEstimate)
    }

    private final class EscapeProbeView: NSView {
        var escapes = 0
        override var acceptsFirstResponder: Bool { true }
        override func keyDown(with event: NSEvent) {
            if event.keyCode == 53 { escapes += 1 }
            else { super.keyDown(with: event) }
        }
    }

    func testRepeatedEscapeClosesContextWithoutReachingPresenterResponder() throws {
        let probe = EscapeProbeView(frame: CGRect(x: 0, y: 0, width: 700, height: 600))
        let owner = InspectorPanelTestSupport.ownerWindow(for: probe, width: 700, height: 600)
        defer { owner.close() }
        XCTAssertTrue(owner.makeFirstResponder(probe))

        for _ in 0..<20 {
            let session = TaskContextMenuPresenter.Session(in: probe, at: CGPoint(x: 300, y: 400))
            session.coordinator.root = AnyView(Color.clear.frame(height: 250))
            session.coordinator.update()
            settle()
            XCTAssertNotNil(session.coordinator.panel)
            try InspectorPanelTestSupport.sendEscape(to: owner)
            XCTAssertNil(session.coordinator.panel)
            XCTAssertEqual(probe.escapes, 0, "关闭菜单的 Esc 不能继续落到任务列表")
            session.close()
        }

        try InspectorPanelTestSupport.sendEscape(to: owner)
        XCTAssertEqual(probe.escapes, 1, "没有浮层时底层仍应收到 Esc")
    }

    private func owner() -> NSWindow {
        let screen = NSScreen.main!.visibleFrame
        let window = NSWindow(contentRect: CGRect(x: screen.minX + 40, y: screen.minY + 40,
                                                  width: min(1000, screen.width - 80), height: min(700, screen.height - 80)),
                              styleMask: [.borderless], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = NSView(frame: window.contentLayoutRect)
        window.orderFront(nil)
        return window
    }

    private func settle() { RunLoop.main.run(until: Date().addingTimeInterval(0.15)) }

    func testCursorCardUsesBorderlessWindowAndCleansAnchor() throws {
        let owner = owner()
        let view = try XCTUnwrap(owner.contentView)
        let originalCount = view.subviews.count
        let session = TaskContextMenuPresenter.Session(in: view,
            at: CGPoint(x: 350, y: view.bounds.maxY - 12))
        let workspace = TaskWorkspaceModel(seedDemoData: false)
        let id = try XCTUnwrap(workspace.createTask(title: "无箭头菜单验收", in: .inbox).taskID)
        let task = try XCTUnwrap(workspace.allTasks.first { $0.id == id })
        session.coordinator.root = AnyView(TaskContextMenuPopover(
            workspace: workspace,
            isPresented: Binding(get: { [weak session] in session?.coordinator.presented == true },
                                 set: { [weak session] value in if !value { session?.close() } }),
            task: task, onCustomDate: {}, onChooseParent: {}))
        session.coordinator.update()
        settle()
        defer { session.close(); owner.close() }
        let panel = try XCTUnwrap(session.coordinator.panel)
        XCTAssertTrue(panel.styleMask.contains(.nonactivatingPanel))
        XCTAssertFalse(panel.styleMask.contains(.titled))
        XCTAssertTrue(panel.parent === owner)
        XCTAssertEqual(panel.frame.width, PopupMetrics.menuWidth, accuracy: 0.5)
        let anchor = owner.convertToScreen(session.anchor.convert(session.anchor.bounds, to: nil))
        XCTAssertEqual(panel.frame.minX, anchor.minX, accuracy: 0.5)
        XCTAssertEqual(panel.frame.maxY, anchor.minY, accuracy: 0.5)
        session.close()
        XCTAssertNil(session.coordinator.panel)
        XCTAssertEqual(view.subviews.count, originalCount)
        XCTAssertFalse(panel.isVisible)
    }

    func testContextSessionReplacesMenuWithParentPickerAndKeepsSelectionDraftUntilConfirm() throws {
        let workspace = TaskWorkspaceModel(seedDemoData: false)
        let source = try XCTUnwrap(workspace.createTask(title: "待关联任务", in: .inbox).taskID)
        let parent = try XCTUnwrap(workspace.createTask(title: "目标主任务", in: .inbox).taskID)
        let environment = AppEnvironment()
        let view = NSView(frame: CGRect(x: 0, y: 0, width: 700, height: 700))
        let owner = InspectorPanelTestSupport.ownerWindow(for: view, width: 700, height: 700)
        defer { TaskContextMenuPresenter.activeSession?.close(); owner.close() }
        var parentFrames: [TaskParentPickerAnchor: CGRect] = [:]

        func openPicker() throws -> NSPanel {
            TaskContextMenuPresenter.show(in: view, at: CGPoint(x: 300, y: 680),
                environment: environment, workspace: workspace,
                task: try XCTUnwrap(workspace.task(for: source)), onCustomDate: {})
            InspectorPanelTestSupport.settle(owner)
            let menu = try InspectorPanelTestSupport.panel(title: "任务右键菜单", below: owner)
            let session = try XCTUnwrap(TaskContextMenuPresenter.activeSession)
            // This component test exercises the production Session transition;
            // the menu button's wiring is covered by native acceptance. The
            // in-process host does not expose this menu's SwiftUI AX children.
            session.showParentPicker(taskID: source, workspace: workspace, environment: environment)
            parentFrames = [:]
            let content = session.coordinator.root
            session.coordinator.root = AnyView(content.onPreferenceChange(TaskParentPickerFrames.self) {
                parentFrames = $0
            })
            session.coordinator.update()
            InspectorPanelTestSupport.settle(owner)
            let picker = try InspectorPanelTestSupport.panel(title: "关联主任务", below: owner)
            XCTAssertFalse(menu.isVisible)
            XCTAssertEqual(picker.frame.width, 280, accuracy: 1)
            XCTAssertEqual(picker.frame.height, 340, accuracy: 1)
            return picker
        }

        let canceled = try openPicker()
        try InspectorPanelTestSupport.click(try XCTUnwrap(parentFrames[.candidate(parent)]),
            in: try XCTUnwrap(canceled.contentView), window: canceled)
        XCTAssertNil(workspace.task(for: source)?.parentID)
        try InspectorPanelTestSupport.sendEscape(to: owner)
        XCTAssertFalse(canceled.isVisible)
        XCTAssertNil(TaskContextMenuPresenter.activeSession)
        XCTAssertNil(workspace.task(for: source)?.parentID)

        let confirmed = try openPicker()
        try InspectorPanelTestSupport.click(try XCTUnwrap(parentFrames[.candidate(parent)]),
            in: try XCTUnwrap(confirmed.contentView), window: confirmed)
        XCTAssertNil(workspace.task(for: source)?.parentID)
        try InspectorPanelTestSupport.click(try XCTUnwrap(parentFrames[.confirm]),
            in: try XCTUnwrap(confirmed.contentView), window: confirmed)
        XCTAssertEqual(workspace.task(for: source)?.parentID, parent)
        XCTAssertFalse(confirmed.isVisible)
        XCTAssertNil(TaskContextMenuPresenter.activeSession)
        workspace.undo()
        XCTAssertNil(workspace.task(for: source)?.parentID)
    }

    func testSubmenuUsesRootBoundsNotSmallMenuBoundsAndEscapeIsHierarchical() throws {
        let owner = owner()
        let session = TaskContextMenuPresenter.Session(in: owner.contentView!, at: CGPoint(x: 350, y: 500))
        let presenter = PopupPresentingWindow()
        presenter.window = owner
        session.coordinator.presentingWindow = presenter
        session.coordinator.root = AnyView(Color.clear.frame(height: 350))
        session.coordinator.update()
        settle()
        let main = try XCTUnwrap(session.coordinator.panel)
        let frame = main.frame
        let child = Adapter.Coordinator()
        let anchor = Adapter.AnchorView(frame: CGRect(x: 0, y: 250, width: 264, height: 30))
        let host = try XCTUnwrap(main.contentView)
        let container = NSView(frame: host.frame)
        main.contentView = container
        container.addSubview(host)
        container.addSubview(anchor)
        child.anchor = anchor
        child.width = 196
        child.placement = .submenu
        child.presentingWindow = presenter
        child.presented = true
        child.root = AnyView(Color.clear.frame(height: 300))
        child.dismiss = { child.presented = false; child.close() }
        child.update()
        settle()
        defer { child.close(); session.close(); owner.close() }
        let panel = try XCTUnwrap(child.panel)
        XCTAssertEqual(panel.frame.width, 196, accuracy: 0.5)
        XCTAssertTrue(panel.frame.minX >= main.frame.maxX || panel.frame.maxX <= main.frame.minX)
        XCTAssertEqual(main.frame, frame)
        try InspectorPanelTestSupport.sendEscape(to: owner)
        XCTAssertNil(child.panel)
        XCTAssertNotNil(session.coordinator.panel)
        try InspectorPanelTestSupport.sendEscape(to: owner)
        XCTAssertNil(session.coordinator.panel)
    }

    func testMainCardFollowsOwnerMovementAndOwnerClose() throws {
        let owner = owner()
        let session = TaskContextMenuPresenter.Session(in: owner.contentView!, at: CGPoint(x: 300, y: 400))
        session.coordinator.root = AnyView(Color.clear.frame(height: 200))
        session.coordinator.update()
        settle()
        defer { session.close(); owner.close() }
        let panel = try XCTUnwrap(session.coordinator.panel)
        let original = panel.frame
        owner.setFrameOrigin(CGPoint(x: owner.frame.minX + 10, y: owner.frame.minY + 10))
        settle()
        XCTAssertEqual(panel.frame.minX, original.minX + 10, accuracy: 0.5)
        XCTAssertEqual(panel.frame.minY, original.minY + 10, accuracy: 0.5)
        owner.close()
        settle()
        XCTAssertNil(session.coordinator.panel)
        XCTAssertNil(session.anchor.superview)
    }

    func testOutsideClickDismissesButChildClickKeepsMainCard() throws {
        let owner = owner()
        let session = TaskContextMenuPresenter.Session(in: owner.contentView!, at: CGPoint(x: 350, y: 500))
        session.coordinator.root = AnyView(Color.clear.frame(height: 350))
        session.coordinator.update()
        settle()
        let main = try XCTUnwrap(session.coordinator.panel)
        let child = NSPanel(contentRect: CGRect(x: main.frame.maxX + 6, y: main.frame.minY, width: 196, height: 100),
                            styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        child.isReleasedWhenClosed = false
        main.addChildWindow(child, ordered: .above)
        child.orderFront(nil)
        defer { child.close(); session.close(); owner.close() }
        func click(_ window: NSWindow) throws {
            NSApp.sendEvent(try XCTUnwrap(NSEvent.mouseEvent(with: .leftMouseDown,
                location: CGPoint(x: 5, y: 5), modifierFlags: [], timestamp: 0,
                windowNumber: window.windowNumber, context: nil, eventNumber: 1, clickCount: 1, pressure: 1)))
        }
        try click(child)
        XCTAssertNotNil(session.coordinator.panel)
        try click(owner)
        XCTAssertNil(session.coordinator.panel)
        XCTAssertNil(session.anchor.superview)
    }
}
