import AppKit
import SwiftUI
import XCTest
@testable import WorkFollow

@MainActor
final class TaskListRefreshTests: XCTestCase {
    @MainActor private final class Fixture {
        let environment = AppEnvironment()
        let workspace = TaskWorkspaceModel(seedDemoData: false)
        let navigation = AppNavigation(destination: .today)
        let host: NSHostingView<AnyView>
        let window: NSWindow

        init(initialTitle: String? = nil) throws {
            if let initialTitle {
                _ = workspace.createTask(title: initialTitle, in: .today)
            }
            host = NSHostingView(rootView: AnyView(
                RootShellView(workspace: workspace, navigation: navigation)
                    .environmentObject(environment).frame(width: 1280, height: 800)))
            window = InspectorPanelTestSupport.ownerWindow(for: host, width: 1280, height: 800)
        }

        func add(_ title: String) throws -> UUID {
            let previousIDs = Set(workspace.allTasks.map(\.id))
            let field = try XCTUnwrap(find(QuickAddFocusReportingField.self, in: host))
            field.onMouseDown?()
            window.makeFirstResponder(field)
            let editor = try XCTUnwrap(field.currentEditor() as? NSTextView)
            field.stringValue = title
            field.delegate?.controlTextDidChange?(Notification(name: NSControl.textDidChangeNotification,
                                                               object: field))
            InspectorPanelTestSupport.settle(window)
            XCTAssertEqual(field.delegate?.control?(field, textView: editor,
                doCommandBy: #selector(NSResponder.insertNewline(_:))), true)
            InspectorPanelTestSupport.settle(window)
            let created = try XCTUnwrap(workspace.allTasks.first { !previousIDs.contains($0.id) },
                "回车后任务标题：\(workspace.allTasks.map(\.title))，输入框：\(field.stringValue)")
            XCTAssertEqual(created.title, title)
            return created.id
        }

        func outline() throws -> NativeTaskOutline.OutlineView {
            try XCTUnwrap(find(NativeTaskOutline.OutlineView.self, in: host))
        }

        func visibleTaskIDs() throws -> [String] {
            let outline = try outline()
            return (0..<outline.numberOfRows).compactMap {
                (outline.item(atRow: $0) as? NativeTaskOutline.Item)?.id
            }
        }

        func renderedTitle(for id: UUID) throws -> String? {
            let outline = try outline()
            guard let index = (0..<outline.numberOfRows).first(where: {
                (outline.item(atRow: $0) as? NativeTaskOutline.Item)?.id.contains(id.uuidString) == true
            }), let cell = outline.view(atColumn: 0, row: index, makeIfNecessary: false) else { return nil }
            return find(TaskRowTitleField.Field.self, in: cell)?.stringValue
        }

        func close() { window.contentView = nil; window.close() }

        private func find<V: NSView>(_ type: V.Type, in view: NSView) -> V? {
            if let match = view as? V { return match }
            return view.subviews.lazy.compactMap { self.find(type, in: $0) }.first
        }
    }

    func testTodayQuickAddUpdatesExistingGroupWithoutSwitchingPages() throws {
        let fixture = try Fixture(initialTitle: "已有的今日任务")
        defer { fixture.close() }
        let originalOutline = try fixture.outline()
        for title in ["录入验收甲", "录入验收乙"] {
            let id = try fixture.add(title)
            XCTAssertEqual(fixture.navigation.destination, .today)
            XCTAssertTrue(try fixture.outline() === originalOutline, "新增应更新现有列表宿主")
            XCTAssertTrue(fixture.workspace.groups(for: .today).flatMap(\.tasks).contains { $0.id == id })
            XCTAssertTrue(try fixture.visibleTaskIDs().contains { $0.contains(id.uuidString) },
                          "任务创建后应立即进入当前原生列表，无需切换页面")
            XCTAssertEqual(try fixture.renderedTitle(for: id), title, "可视区内应实际绘制新增任务的标题")
        }
    }

    func testTodayQuickAddReplacesEmptyStateWithoutSwitchingPages() throws {
        let fixture = try Fixture()
        defer { fixture.close() }
        let originalOutline = try fixture.outline()
        let id = try fixture.add("空态录入验收")
        XCTAssertEqual(fixture.navigation.destination, .today)
        XCTAssertTrue(try fixture.outline() === originalOutline)
        XCTAssertTrue(try fixture.visibleTaskIDs().contains { $0.contains(id.uuidString) },
                      "空列表新增第一条任务时应即时显示")
        XCTAssertEqual(try fixture.renderedTitle(for: id), "空态录入验收")
        XCTAssertEqual(try fixture.outline().enclosingScrollView?.contentView.bounds.minY, 0,
                       "空列表的底部留白不能成为滚动锚点，将新增任务推到可视区上方")
    }

    func testShrinkingScrolledOutlineKeepsRemainingRowVisible() throws {
        let coordinator = NativeTaskOutline.Coordinator()
        let scroll = NativeTaskOutline.makeScrollView(coordinator: coordinator)
        let window = InspectorPanelTestSupport.ownerWindow(for: scroll, width: 400, height: 200)
        defer { window.contentView = nil; window.close() }
        func row(_ index: Int) -> NativeTaskOutline.Row {
            .init(id: "row-\(index)", state: index, layout: 50) {
                Text("任务\(index)").frame(height: 50)
            }
        }
        coordinator.update((0..<30).map(row), in: scroll)
        InspectorPanelTestSupport.settle(window)
        let outline = try XCTUnwrap(coordinator.outline)
        outline.scrollRowToVisible(29)
        InspectorPanelTestSupport.settle(window)
        XCTAssertGreaterThan(scroll.contentView.bounds.minY, 0)
        coordinator.update([row(0)], in: scroll)
        InspectorPanelTestSupport.settle(window)
        XCTAssertEqual(scroll.contentView.bounds.minY, 0)
        XCTAssertTrue(outline.visibleRect.intersects(outline.rect(ofRow: 0)))
    }
}
