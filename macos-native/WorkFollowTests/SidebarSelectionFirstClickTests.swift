import AppKit
import SwiftUI
import XCTest
@testable import WorkFollow

@MainActor
final class SidebarSelectionFirstClickTests: XCTestCase {
    private final class ActivatableWindow: NSWindow {
        override var canBecomeKey: Bool { true }
    }

    private struct Fixture {
        let environment: AppEnvironment
        let window: NSWindow
        let host: NSHostingView<AnyView>
        let anchors: [String: NSView]
        /// 智能清单行不进 AX 树（见 GuideTourObservation），用引导锚 frame 定位。
        let navigationFrames: () -> [String: CGRect]

        func listAnchor(_ name: String) throws -> NSView {
            try XCTUnwrap(anchors["sidebar.list." + name], "侧栏清单行锚点未就绪")
        }
    }

    /// 侧栏需要清单分组可见，否则清单行不在视图里。
    private func makeFixture(listNames: [String], keyWindow: Bool) throws -> Fixture {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let now = Date()
        let tasks = listNames.map { name in
            Task(id: UUID(), title: name + "原任务", list: TaskList(name: name), priority: .none,
                 schedule: TaskSchedule(dueAt: now), childOrder: 0, createdAt: now, updatedAt: now)
        }
        try NativePreviewRepository(directory: directory).save(.init(tasks: tasks, notes: []))
        let environment = AppEnvironment(directory: directory)
        environment.companionEnabled = false
        environment.sidebarVisible = true
        environment.viewPreferences.setSidebarSectionCollapsed(.collections, false)
        environment.viewPreferences.setVisibility(.visible, for: SidebarSectionID.collections)
        environment.navigation.destination = .today
        var anchors: [String: NSView] = [:]
        var navigationFrames: [String: CGRect] = [:]
        let content = RootShellView(workspace: environment.taskWorkspace,
                                    navigation: environment.navigation)
            .environmentObject(environment)
            .environment(\.workflowActionObservation, { anchors[$0] = $1 })
            .coordinateSpace(name: "guide-tour-render")
            .onPreferenceChange(GuideTourFramesKey.self) { navigationFrames = $0 }
            .frame(width: 1280, height: 800)
        let host = NSHostingView(rootView: AnyView(content))
        let window = ActivatableWindow(contentRect: NSRect(x: 100, y: 100, width: 1280, height: 800),
                                       styleMask: [.borderless], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.appearance = NSAppearance(named: .aqua)
        window.contentView = host
        if keyWindow {
            NSApp.activate(ignoringOtherApps: true)
            window.makeKeyAndOrderFront(nil)
        } else {
            // 只摆出来不成为 key：首击必须由 FirstMouseAction 接管。
            window.orderFront(nil)
        }
        InspectorPanelTestSupport.settle(window)
        return Fixture(environment: environment, window: window, host: host, anchors: anchors,
                       navigationFrames: { navigationFrames })
    }

    /// 清单与智能清单同级、一次只能激活一个（用户要求）：真实点击在清单与
    /// 今天/明天之间来回，智能清单页不得残留清单选中态。
    func testSidebarSwitchKeepsSingleSelectionBetweenListAndSmartList() throws {
        let name = "虚构清单甲"
        let fixture = try makeFixture(listNames: [name], keyWindow: true)
        let workspace = fixture.environment.taskWorkspace
        let navigation = fixture.environment.navigation
        defer { fixture.window.close(); fixture.window.contentView = nil }

        func clickList() throws {
            let anchor = try fixture.listAnchor(name)
            try InspectorPanelTestSupport.click(anchor.bounds, in: anchor, window: fixture.window)
        }
        func clickSmartList(_ title: String) throws {
            let frame = try XCTUnwrap(fixture.navigationFrames()["nav." + title], "智能清单行锚点未就绪")
            try InspectorPanelTestSupport.click(frame, in: fixture.host, window: fixture.window)
        }

        /// 行中心点上命中的 RowHoverView 是否在画选中底色。
        /// 锚 frame 按宿主/锚点视图自身的翻转约定换算到窗口（与 click 助手同式）。
        func selectedRowHover(inAnchor anchorID: String) throws -> Bool {
            let frame = try XCTUnwrap(fixture.navigationFrames()[anchorID], "导航行锚点未就绪：" + anchorID)
            let point = CGPoint(x: frame.midX,
                                y: fixture.host.isFlipped ? frame.midY : fixture.host.bounds.height - frame.midY)
            return try hoverSelection(atWindowPoint: fixture.host.convert(point, to: nil))
        }
        func selectedRowHover(atListRow name: String) throws -> Bool {
            let anchor = try fixture.listAnchor(name)
            let point = anchor.convert(
                NSPoint(x: anchor.bounds.midX,
                        y: anchor.isFlipped ? anchor.bounds.midY : anchor.bounds.height - anchor.bounds.midY),
                to: nil)
            return try hoverSelection(atWindowPoint: point)
        }
        func hoverSelection(atWindowPoint windowPoint: NSPoint) throws -> Bool {
            var found: RowHoverView?
            func walk(_ view: NSView) {
                guard found == nil else { return }
                if let hover = view as? RowHoverView,
                   view.window === fixture.window, !view.isHiddenOrHasHiddenAncestor,
                   view.frame.contains(view.convert(windowPoint, from: nil)) {
                    found = hover
                }
                for subview in view.subviews { walk(subview) }
            }
            walk(fixture.host)
            return try XCTUnwrap(found, "锚点上没有找到行底色视图").selected
        }

        try clickList()
        XCTAssertEqual(navigation.destination, .allTasks)
        XCTAssertEqual(workspace.activeList, name)
        // 选中清单时「所有任务」行自己不亮：清单是它的宿主，同级一次一个。
        XCTAssertFalse(try selectedRowHover(inAnchor: "nav.所有任务"),
                       "选中清单时「所有任务」不应显示选中")
        XCTAssertTrue(try selectedRowHover(atListRow: name), "清单行应显示选中")
        try clickSmartList("今天")
        XCTAssertEqual(navigation.destination, .today)
        XCTAssertNil(workspace.activeList, "清单与今天互斥：去今天要清空清单选中态")
        XCTAssertTrue(try selectedRowHover(inAnchor: "nav.今天"))
        XCTAssertFalse(try selectedRowHover(inAnchor: "nav.所有任务"))
        XCTAssertFalse(try selectedRowHover(atListRow: name), "清单行不再残留选中底色")
        try clickList()
        XCTAssertEqual(navigation.destination, .allTasks)
        XCTAssertEqual(workspace.activeList, name)
        XCTAssertFalse(try selectedRowHover(inAnchor: "nav.所有任务"))
        try clickSmartList("明天")
        XCTAssertEqual(navigation.destination, .tomorrow)
        XCTAssertNil(workspace.activeList, "清单与明天互斥")
    }

    /// 窗口未激活时的第一次点击也要直接打开清单：SwiftUI 按钮首击只激活
    /// 窗口，原生任务行早已用 acceptsFirstMouse 修过同类问题，侧栏行同款。
    func testSidebarListRowRespondsToFirstClickWhileWindowInactive() throws {
        let name = "虚构清单乙"
        let fixture = try makeFixture(listNames: [name], keyWindow: false)
        let workspace = fixture.environment.taskWorkspace
        let navigation = fixture.environment.navigation
        defer { fixture.window.close(); fixture.window.contentView = nil }
        XCTAssertFalse(fixture.window.isKeyWindow, "前置：窗口必须不是 key window")

        let anchor = try fixture.listAnchor(name)
        try InspectorPanelTestSupport.click(anchor.bounds, in: anchor, window: fixture.window)
        XCTAssertEqual(navigation.destination, .allTasks, "非 key 窗口的第一次点击就应打开清单")
        XCTAssertEqual(workspace.activeList, name)
    }

    func testListRowsUseTheirFullVisibleHeightAsClickTargets() throws {
        let names = ["虚构清单甲", "虚构清单乙", "虚构清单丙"]
        let fixture = try makeFixture(listNames: names, keyWindow: true)
        defer { fixture.window.close(); fixture.window.contentView = nil }
        for name in names {
            for fraction in [CGFloat(0.1), 0.5, 0.9] {
                fixture.environment.navigate(to: .today)
                InspectorPanelTestSupport.settle(fixture.window)
                let frame = try XCTUnwrap(fixture.navigationFrames()["list." + name])
                let button = try fixture.listAnchor(name)
                XCTAssertGreaterThanOrEqual(frame.height, NavigationMetrics.rowHeight - 1)
                XCTAssertEqual(button.bounds.height, frame.height, accuracy: 1,
                               "按钮点击区域应覆盖整条清单的可视高度")
                let target = CGRect(x: frame.midX, y: frame.minY + frame.height * fraction, width: 1, height: 1)
                try InspectorPanelTestSupport.click(target, in: fixture.host, window: fixture.window)
                XCTAssertEqual(fixture.environment.navigation.destination, .allTasks,
                               "点击清单 \(name) 的高度 \(fraction) 应直接切页")
                XCTAssertEqual(fixture.environment.taskWorkspace.activeList, name)
            }
        }
    }
}
