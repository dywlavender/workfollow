import AppKit
import SwiftUI
import XCTest
@testable import WorkFollow

/// 滴答侧栏布局契约：整栏单滚动、侧栏不画滚动条、分组折叠与空态提示。
@MainActor
final class SidebarLayoutTests: XCTestCase {
    private final class MenuProbe {
        var triggers: [String: CGRect] = [:]
        var rows: [BusinessMenuRowFrame] = []
    }

    private struct Fixture {
        let environment: AppEnvironment
        let window: NSWindow
        let host: NSView
        let probe: MenuProbe
    }

    private func makeSidebar(height: CGFloat = 480) throws -> Fixture {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("sidebar-layout-" + UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let environment = AppEnvironment(directory: directory)
        let navigation = AppNavigation(destination: .today)
        let probe = MenuProbe()
        let host = NSHostingView(rootView: AnyView(
            NavigationColumnView(workspace: environment.taskWorkspace, navigation: navigation,
                                 filterStore: environment.filterStore)
                .environmentObject(environment)
                .frame(width: WFMetrics.navigationWidth, height: height)
                .coordinateSpace(name: "business-menu")
                .onPreferenceChange(BusinessMenuTriggerFrames.self) { probe.triggers = $0 }
                .environment(\.popupContentObservation, { content in
                    AnyView(content
                        .coordinateSpace(name: "business-menu")
                        .onPreferenceChange(BusinessMenuRowFrames.self) {
                            if !$0.isEmpty { probe.rows = $0 }
                        })
                })
        ))
        let window = InspectorPanelTestSupport.ownerWindow(for: host,
                                                           width: WFMetrics.navigationWidth,
                                                           height: height)
        addTeardownBlock {
            window.close()
            try? FileManager.default.removeItem(at: directory)
        }
        InspectorPanelTestSupport.settle(window)
        return Fixture(environment: environment, window: window, host: host, probe: probe)
    }

    /// 智能清单、分组和底部清单必须都在同一个滚动容器里：
    /// 只有一个 scroll view，没有可见滚动条，且内容高度超过视口。
    func testTaskSidebarUsesOneHiddenScrollForAllRows() throws {
        let fixture = try makeSidebar()
        let scrolls = scrollViews(in: fixture.host)
        XCTAssertEqual(scrolls.count, 1, "侧栏必须只有一个滚动容器")
        let scroll = try XCTUnwrap(scrolls.first)
        XCTAssertTrue(scroll.verticalScroller == nil || scroll.verticalScroller?.isHidden == true,
                      "侧栏不显示悬浮滚动条")
        let content = try XCTUnwrap(scroll.documentView)
        XCTAssertGreaterThan(content.frame.height, scroll.contentView.bounds.height,
                             "智能清单和底部清单也在同一段可滚动内容里")
    }

    func testCollapsingFilterSectionHidesHintAndRestoresContent() throws {
        let fixture = try makeSidebar()
        let scroll = try XCTUnwrap(scrollViews(in: fixture.host).first)
        let expandedHeight = try XCTUnwrap(scroll.documentView).frame.height

        fixture.environment.viewPreferences.setSidebarSectionCollapsed(.filters, true)
        InspectorPanelTestSupport.settle(fixture.window)
        XCTAssertTrue(fixture.environment.viewPreferences.isSidebarSectionCollapsed(.filters))
        let collapsedHeight = try XCTUnwrap(scroll.documentView).frame.height
        XCTAssertLessThan(collapsedHeight, expandedHeight - 30,
                          "收起过滤器后空态提示卡一并隐藏")

        fixture.environment.viewPreferences.setSidebarSectionCollapsed(.filters, false)
        InspectorPanelTestSupport.settle(fixture.window)
        XCTAssertFalse(fixture.environment.viewPreferences.isSidebarSectionCollapsed(.filters))
        XCTAssertEqual(try XCTUnwrap(scroll.documentView).frame.height, expandedHeight, accuracy: 1)
    }

    /// 滴答标签头「⋯」（实测 2026-10-25）：只有三个显示状态、菜单用紧凑宽度；
    /// 选「隐藏」只收组内标签行，分组头保留，入口随时能点开改回来。
    func testTagSectionMenuIsCompactAndHidesRowsWithoutLosingHeader() throws {
        let fixture = try makeSidebar(height: 900)
        let scroll = try XCTUnwrap(scrollViews(in: fixture.host).first)
        let expandedHeight = try XCTUnwrap(scroll.documentView).frame.height

        try openTagMenu(fixture)
        let menu = try InspectorPanelTestSupport.panel(title: "标签显示", below: fixture.window)
        XCTAssertEqual(menu.frame.width, PopupMetrics.menuWidthNarrow, accuracy: 0.5,
                       "显示菜单收窄到 176，不再沿用 224 的右键菜单口径")
        XCTAssertEqual(fixture.probe.rows.count, 3, "与滴答一致：三个显示状态")
        XCTAssertEqual(fixture.environment.viewPreferences.visibility(for: .tags), .visible)

        try InspectorPanelTestSupport.click(try XCTUnwrap(fixture.probe.rows.last).rect,
                                            in: try XCTUnwrap(menu.contentView), window: menu)
        XCTAssertEqual(fixture.environment.viewPreferences.visibility(for: .tags), .hidden)
        InspectorPanelTestSupport.settle(fixture.window)

        let hiddenHeight = try XCTUnwrap(scroll.documentView).frame.height
        XCTAssertLessThan(hiddenHeight, expandedHeight - 30, "隐藏后组内标签行一并收起")
        XCTAssertNotNil(fixture.probe.triggers["标签显示"], "分组头保留，菜单还能重新打开")

        try openTagMenu(fixture)
        let reopened = try InspectorPanelTestSupport.panel(title: "标签显示", below: fixture.window)
        try InspectorPanelTestSupport.click(try XCTUnwrap(fixture.probe.rows[1]).rect,
                                            in: try XCTUnwrap(reopened.contentView), window: reopened)
        XCTAssertEqual(fixture.environment.viewPreferences.visibility(for: .tags), .visible)
        InspectorPanelTestSupport.settle(fixture.window)
        XCTAssertEqual(try XCTUnwrap(scroll.documentView).frame.height, expandedHeight, accuracy: 1)
    }

    private func openTagMenu(_ fixture: Fixture) throws {
        try InspectorPanelTestSupport.click(try XCTUnwrap(fixture.probe.triggers["标签显示"]),
                                            in: fixture.host, window: fixture.window)
    }

    // MARK: - 工具

    private func scrollViews(in view: NSView) -> [NSScrollView] {
        var result: [NSScrollView] = []
        if let scroll = view as? NSScrollView { result.append(scroll) }
        for subview in view.subviews { result += scrollViews(in: subview) }
        return result
    }
}
