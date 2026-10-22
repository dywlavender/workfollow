import AppKit
import SwiftUI
import XCTest
@testable import WorkFollow

@MainActor
final class BusinessMenuInteractionTests: XCTestCase {
    private final class Probe {
        var triggers: [String: CGRect] = [:]
        var popupTriggers: [String: CGRect] = [:]
        var rows: [BusinessMenuRowFrame] = []
        var actions: [DialogActionAnchor: CGRect] = [:]
    }
    private final class Model: ObservableObject {
        @Published var selection = 0
        @Published var flag = false
        @Published var hovering = true
        @Published var menuPresented = false
        var actions = 0
    }
    private struct KeyboardFixture: View {
        @ObservedObject var model: Model
        var body: some View {
            BusinessMenu(title: "排序") {
                BusinessMenuOption("原顺序", selected: model.selection == 0) { model.selection = 0; model.actions += 1 }
                Button("不可用") { model.actions += 100 }.disabled(true)
                BusinessMenuOption("按日期", selected: model.selection == 2) { model.selection = 2; model.actions += 1 }
            } label: { Text("排序").frame(width: 80, height: 28) }
        }
    }
    private struct NestedFixture: View {
        @ObservedObject var model: Model
        var body: some View {
            BusinessMenu(title: "列表操作") {
                Toggle("隐藏已完成", isOn: $model.flag)
                BusinessMenu("显示设置") {
                    BusinessMenuOption("优先级") { model.actions += 1 }
                }
                Button("编辑") { model.actions += 10 }
            } label: { Text("列表操作").frame(width: 100, height: 28) }
        }
    }
    private struct SearchFixture: View {
        @ObservedObject var model: Model
        var body: some View {
            BusinessPicker("关联任务", selection: $model.selection,
                options: (0..<40).map { BusinessChoice($0, "任务 \($0)", symbol: "checklist") },
                width: PopupMetrics.relationPickerWidth).frame(width: 260)
        }
    }

    func testKeyboardSelectionSkipsDisabledRowsCommitsOnceAndClosesTheMenu() throws {
        let model = Model(), probe = Probe()
        let owner = host(KeyboardFixture(model: model), probe: probe)
        defer { owner.close() }
        let ownerFrame = owner.frame
        try open("排序", probe: probe, owner: owner)
        let menu = try panel("排序", below: owner)
        XCTAssertEqual(menu.frame.width, PopupMetrics.menuWidth, accuracy: 0.5)
        XCTAssertGreaterThanOrEqual(menu.frame.height, 3 * PopupMetrics.menuRowHeight)
        XCTAssertLessThan(menu.frame.height, 150, "短菜单按内容测高")
        XCTAssertEqual(probe.rows.count, 3)
        let first = try XCTUnwrap(probe.rows.first)
        XCTAssertEqual(first.rect.height, PopupMetrics.menuRowHeight, accuracy: 0.5)
        try key(125, to: menu)
        try InspectorPanelTestSupport.sendReturn(to: menu)
        XCTAssertEqual(model.selection, 2)
        XCTAssertEqual(model.actions, 1)
        XCTAssertFalse(menu.isVisible)
        XCTAssertEqual(owner.frame, ownerFrame)
        try open("排序", probe: probe, owner: owner)
        let reopened = try panel("排序", below: owner)
        try InspectorPanelTestSupport.sendEscape(to: reopened)
        XCTAssertFalse(reopened.isVisible)
        XCTAssertEqual(model.actions, 1, "Escape 不执行菜单动作")
    }

    func testToggleKeepsParentOpenAndChildEscapeAndSelectionRespectTheMenuChain() throws {
        let model = Model(), probe = Probe()
        let owner = host(NestedFixture(model: model), probe: probe)
        defer { owner.close() }
        try open("列表操作", probe: probe, owner: owner)
        let parent = try panel("列表操作", below: owner)
        let original = parent.frame
        let parentRows = probe.rows
        XCTAssertEqual(parentRows.count, 3)
        try click(parentRows[0].rect, in: parent)
        XCTAssertTrue(model.flag)
        XCTAssertTrue(parent.isVisible)
        try click(parentRows[1].rect, in: parent)
        let child = try panel("显示设置", below: owner)
        XCTAssertTrue(child.parent === parent)
        XCTAssertEqual(parent.frame, original)
        try InspectorPanelTestSupport.sendEscape(to: child)
        XCTAssertFalse(child.isVisible)
        XCTAssertTrue(parent.isVisible)
        try key(125, to: owner)
        try key(125, to: owner)
        try key(124, to: owner)
        let reopened = try panel("显示设置", below: owner)
        XCTAssertTrue(reopened.isVisible)
        try InspectorPanelTestSupport.sendReturn(to: owner)
        XCTAssertEqual(model.actions, 1)
        XCTAssertTrue(InspectorPanelTestSupport.visibleWindows(below: owner).isEmpty)
    }

    func testLongPickerSearchFiltersWithoutChangingValueAndResetsAfterSelection() throws {
        let model = Model(), probe = Probe()
        let owner = host(SearchFixture(model: model), probe: probe)
        defer { owner.close() }
        let frame = owner.frame
        try open("关联任务", probe: probe, owner: owner)
        let menu = try panel("关联任务", below: owner)
        XCTAssertEqual(menu.frame.width, PopupMetrics.relationPickerWidth, accuracy: 0.5)
        XCTAssertLessThanOrEqual(menu.frame.height, PopupMetrics.menuMaximumHeight + 60)
        let field = try XCTUnwrap(textFields(in: try XCTUnwrap(menu.contentView)).first { $0.isEditable })
        menu.makeFirstResponder(field)
        let editor = try XCTUnwrap(field.currentEditor() as? NSTextView)
        editor.selectAll(nil)
        editor.insertText("任务 37", replacementRange: editor.selectedRange())
        InspectorPanelTestSupport.settle(owner)
        XCTAssertEqual(model.selection, 0, "搜索不提交选择")
        XCTAssertEqual(probe.rows.count, 1)
        try key(123, to: menu)
        XCTAssertTrue(menu.isVisible, "在搜索框按左右箭头应移动光标")
        try InspectorPanelTestSupport.sendReturn(to: menu)
        XCTAssertEqual(model.selection, 37)
        XCTAssertFalse(menu.isVisible)
        try open("关联任务", probe: probe, owner: owner)
        let reopened = try panel("关联任务", below: owner)
        XCTAssertEqual(probe.rows.count, 40)
        let selected = probe.rows[37].rect
        XCTAssertTrue(try XCTUnwrap(reopened.contentView).bounds.contains(CGPoint(x: selected.midX, y: selected.midY)),
                      "重开长列表后，当前选项应滚动到可见范围")
        let search = try XCTUnwrap(textFields(in: try XCTUnwrap(reopened.contentView)).first { $0.isEditable })
        XCTAssertEqual(search.stringValue, "")
        XCTAssertEqual(owner.frame, frame)
    }

    func testSummaryNestedTagPickerPreservesCancelAndConfirmDraftSemantics() throws {
        for confirm in [false, true] {
            let probe = Probe()
            var applied: SummaryFilter?
            var cancelled = false
            let owner = host(SummaryMorePopover(filter: .all, tags: ["学习", "工作"],
                onApply: { applied = $0 }, onCancel: { cancelled = true }), probe: probe)
            defer { owner.close() }
            try open("标签", probe: probe, owner: owner)
            let tags = try panel("标签", below: owner)
            XCTAssertEqual(probe.rows.count, 3)
            try click(probe.rows[2].rect, in: tags)
            XCTAssertFalse(tags.isVisible)
            XCTAssertNil(applied)
            let action = try XCTUnwrap(probe.actions[confirm ? .primary : .cancel])
            try click(action, in: owner)
            if confirm {
                XCTAssertEqual(applied?.tagName, "工作")
                XCTAssertFalse(cancelled)
            } else {
                XCTAssertNil(applied)
                XCTAssertTrue(cancelled)
            }
        }
    }

    func testRightClickUsesTheSameRowsAndAnchorsToTheClickLocation() throws {
        let probe = Probe(), model = Model()
        let owner = host(Text("任务区域").frame(width: 240, height: 80)
            .businessContextMenu { Button("打开任务") { model.actions += 1 } }, probe: probe)
        defer { owner.close() }
        let point = CGPoint(x: 80, y: owner.contentView!.bounds.height - 55)
        let event = try XCTUnwrap(NSEvent.mouseEvent(with: .rightMouseDown, location: point,
            modifierFlags: [], timestamp: ProcessInfo.processInfo.systemUptime,
            windowNumber: owner.windowNumber, context: nil, eventNumber: 1, clickCount: 1, pressure: 1))
        XCTAssertTrue(PopupInteractionRegistry.shared.showContextMenu(for: event))
        InspectorPanelTestSupport.settle(owner)
        let menu = try panel("操作菜单", below: owner)
        let screen = owner.convertToScreen(CGRect(origin: point, size: .zero))
        XCTAssertEqual(menu.frame.minX, screen.minX, accuracy: 1)
        XCTAssertEqual(menu.frame.maxY, screen.minY, accuracy: 1)
        XCTAssertEqual(probe.rows.count, 1)
        try click(probe.rows[0].rect, in: menu)
        XCTAssertEqual(model.actions, 1)
        XCTAssertFalse(menu.isVisible)
    }

    private struct HoverFixture: View {
        @ObservedObject var model: Model
        var body: some View {
            BusinessMenu(title: "侧栏操作", isPresented: $model.menuPresented) {
                Button("编辑清单") { model.actions += 1 }
            } label: { Text("⋯").frame(width: 28, height: 28) }
            .opacity(model.hovering || model.menuPresented ? 1 : 0)
            .disabled(!model.hovering && !model.menuPresented)
        }
    }
    func testHoverOnlyEntryStaysAvailableWhileItsMenuIsOpen() throws {
        let model = Model(), probe = Probe()
        let owner = host(HoverFixture(model: model), probe: probe)
        defer { owner.close() }
        try open("侧栏操作", probe: probe, owner: owner)
        let menu = try panel("侧栏操作", below: owner)
        XCTAssertTrue(model.menuPresented)
        model.hovering = false
        InspectorPanelTestSupport.settle(owner)
        XCTAssertTrue(menu.isVisible, "移入菜单后，来源行失去悬停不能关闭或禁用菜单")
        try click(try XCTUnwrap(probe.rows.first).rect, in: menu)
        XCTAssertEqual(model.actions, 1)
        XCTAssertFalse(model.menuPresented)
        XCTAssertFalse(menu.isVisible)
    }

    func testActualInspectorListMenuMovesTheTaskAndClosesWhenSelectionChanges() throws {
        let workspace = TaskWorkspaceModel(seedDemoData: false), probe = Probe()
        XCTAssertTrue(workspace.saveList("工作"))
        let first = try XCTUnwrap(workspace.createTask(title: "待移动", in: .inbox).taskID)
        let second = try XCTUnwrap(workspace.createTask(title: "另一条", in: .inbox).taskID)
        workspace.select(first)
        let owner = host(TaskInspectorShell(workspace: workspace, showBack: false)
            .environmentObject(AppEnvironment()), probe: probe)
        defer { owner.close() }
        try open("移动到清单", probe: probe, owner: owner)
        let menu = try panel("移动到清单", below: owner)
        let index = try XCTUnwrap(workspace.availableListNames.firstIndex(of: "工作"))
        try click(probe.rows[index].rect, in: menu)
        XCTAssertEqual(workspace.task(for: first)?.list.name, "工作")
        XCTAssertFalse(menu.isVisible)
        try open("移动到清单", probe: probe, owner: owner)
        let reopened = try panel("移动到清单", below: owner)
        workspace.select(second)
        InspectorPanelTestSupport.settle(owner)
        XCTAssertFalse(reopened.isVisible, "切换详情后不能保留上一条任务的菜单")
        XCTAssertEqual(workspace.task(for: second)?.list, .inbox)
    }

    func testActualQuickComposerMenusKeepTheDraftUntilReturnCreatesTheTask() throws {
        let workspace = TaskWorkspaceModel(seedDemoData: false), probe = Probe()
        XCTAssertTrue(workspace.saveList("工作"))
        var closed = false
        let owner = host(TaskQuickComposer(workspace: workspace, fallbackSchedule: TaskSchedule(),
            presetSchedule: nil, presetPriority: .none, requestClose: { closed = true }), probe: probe)
        defer { owner.close() }
        try open("优先级", probe: probe, owner: owner)
        let priority = try panel("优先级", below: owner)
        XCTAssertEqual(priority.frame.width, PopupMetrics.taskMenuWidth, accuracy: 0.5)
        try click(probe.rows[0].rect, in: priority)
        try open("清单", probe: probe, owner: owner)
        let list = try panel("清单", below: owner)
        let index = try XCTUnwrap(workspace.availableListNames.firstIndex(of: "工作"))
        try click(probe.rows[index].rect, in: list)
        XCTAssertTrue(workspace.allTasks.isEmpty, "选择属性不能提前创建任务")
        let field = try XCTUnwrap(textFields(in: try XCTUnwrap(owner.contentView)).first { $0.isEditable })
        owner.makeFirstResponder(field)
        let editor = try XCTUnwrap(field.currentEditor() as? NSTextView)
        editor.insertText("完成周报", replacementRange: editor.selectedRange())
        InspectorPanelTestSupport.settle(owner)
        // Native text-command dispatch works in the temporary host even when
        // macOS refuses to make that process the active application.
        editor.insertNewline(nil)
        InspectorPanelTestSupport.settle(owner)
        let created = try XCTUnwrap(workspace.allTasks.first)
        XCTAssertEqual(created.title, "完成周报")
        XCTAssertEqual(created.list.name, "工作")
        XCTAssertEqual(created.priority, .high)
        XCTAssertTrue(closed)
    }

    func testMenusRenderWithTheSameGeometryInLightAndDarkAppearance() throws {
        let directory = URL(fileURLWithPath: "/Users/dongyangwei/.codex/visualizations/2026/10/13/01a135b2-f44a-7673-88db-eb71f3dc8cc1/business-popups")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        var sizes: [CGSize] = []
        for (name, appearance) in [("light", NSAppearance.Name.aqua), ("dark", .darkAqua)] {
            let controller = BusinessMenuController()
            let view = BusinessMenuContent(controller: controller, close: {}, dismissAll: {}) {
                BusinessMenuSection(title: "分组")
                BusinessMenuOption("按清单", selected: true, symbol: "tray") {}
                BusinessMenuOption("按标签", symbol: "tag") {}
                Divider()
                Button("恢复默认排序", systemImage: "arrow.counterclockwise") {}
                Button("删除分组", role: .destructive) {}
                Button("暂不可用") {}.disabled(true)
            }.frame(width: PopupMetrics.menuWidth).background(WFColors.content)
            let host = NSHostingView(rootView: view)
            let owner = InspectorPanelTestSupport.ownerWindow(for: host, width: PopupMetrics.menuWidth, height: 230)
            owner.appearance = NSAppearance(named: appearance)
            InspectorPanelTestSupport.settle(owner)
            let size = host.fittingSize
            sizes.append(size)
            let bounds = host.bounds
            let bitmap = try XCTUnwrap(host.bitmapImageRepForCachingDisplay(in: bounds))
            host.cacheDisplay(in: bounds, to: bitmap)
            try XCTUnwrap(bitmap.representation(using: .png, properties: [:]))
                .write(to: directory.appendingPathComponent("menu-\(name).png"))
            owner.close()
        }
        XCTAssertEqual(sizes[0].width, sizes[1].width, accuracy: 0.5)
        XCTAssertEqual(sizes[0].height, sizes[1].height, accuracy: 0.5)
    }

    private func host<Content: View>(_ content: Content, probe: Probe) -> NSWindow {
        let root = content.padding(24).frame(width: 640, height: 480, alignment: .topLeading)
            .coordinateSpace(name: "business-menu").coordinateSpace(name: "dialog-render")
            .onPreferenceChange(BusinessMenuTriggerFrames.self) { probe.triggers = $0 }
            .onPreferenceChange(DialogActionFrames.self) { probe.actions = $0 }
            .environment(\.popupContentObservation, { content in
                AnyView(content.coordinateSpace(name: "business-menu")
                    .onPreferenceChange(BusinessMenuRowFrames.self) { if !$0.isEmpty { probe.rows = $0 } }
                    .onPreferenceChange(BusinessMenuTriggerFrames.self) { probe.popupTriggers = $0 })
            })
        return InspectorPanelTestSupport.ownerWindow(for: NSHostingView(rootView: root), width: 640, height: 480)
    }
    private func open(_ title: String, probe: Probe, owner: NSWindow) throws {
        try click(try XCTUnwrap(probe.triggers[title]), in: owner)
    }
    private func panel(_ title: String, below owner: NSWindow) throws -> NSPanel {
        try InspectorPanelTestSupport.panel(title: title, below: owner)
    }
    private func click(_ frame: CGRect, in window: NSWindow) throws {
        try InspectorPanelTestSupport.click(frame, in: try XCTUnwrap(window.contentView), window: window)
    }
    private func key(_ code: UInt16, to window: NSWindow) throws {
        let event = try XCTUnwrap(NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [],
            timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: window.windowNumber,
            context: nil, characters: "", charactersIgnoringModifiers: "", isARepeat: false, keyCode: code))
        NSApp.sendEvent(event)
        InspectorPanelTestSupport.settle(window)
    }
    private func textFields(in view: NSView) -> [NSTextField] {
        (view as? NSTextField).map { [$0] } ?? view.subviews.flatMap { textFields(in: $0) }
    }
}
