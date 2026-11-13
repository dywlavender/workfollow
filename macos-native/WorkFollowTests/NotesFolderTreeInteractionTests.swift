import AppKit
import SwiftUI
import XCTest
@testable import WorkFollow

/// 树视图的点击回归：两个按钮曾经都点不动——作用域按钮命中区域只剩文字字形，
/// 新建子文件夹的同步模态又嵌在手势跟踪里。这里用真实鼠标事件验证。
@MainActor
final class NotesFolderTreeInteractionTests: XCTestCase {
    private func fixture() -> AppEnvironment {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("notes-tree-interaction-\(UUID().uuidString)")
        addTeardownBlock { try? FileManager.default.removeItem(at: directory) }
        let environment = AppEnvironment(directory: directory)
        environment.navigation.destination = .notes
        return environment
    }

    private func host(_ environment: AppEnvironment) -> NSHostingView<some View> {
        NSHostingView(rootView: NotesWorkspaceView(
            notes: environment.notesWorkspace,
            navigation: environment.navigation,
            tasks: environment.taskWorkspace)
            .environmentObject(environment))
    }

    func testFavoritesScopeButtonIsClickable() throws {
        let environment = fixture()
        let notes = environment.notesWorkspace
        notes.create()
        let view = host(environment)
        let window = InspectorPanelTestSupport.ownerWindow(for: view, width: 1100, height: 720)
        defer { window.close() }
        InspectorPanelTestSupport.settle(window)

        XCTAssertFalse(notes.favoritesOnly)
        // SwiftUI 树节点不暴露 AX 元素，按列布局定位：作用域条距顶 94..122，
        // 目录栏（2026-11-08 起独立宽度，默认 236）内两个按钮均分。
        // 宽度从模型现算，别再硬编码——宽度自适应后会变。走真实鼠标事件。
        let pane = notes.effectiveTreePaneWidth
        let buttonSpan = (pane - 20 - 4) / 2   // 两侧 padding 10 + 分段内边距 2×2
        let allCenterX = 10 + 2 + buttonSpan / 2
        let favoriteCenterX = 10 + 2 + buttonSpan * 1.5
        try InspectorPanelTestSupport.click(CGRect(x: favoriteCenterX - 6, y: 102, width: 12, height: 12),
                                            in: view, window: window)
        XCTAssertTrue(notes.favoritesOnly)

        try InspectorPanelTestSupport.click(CGRect(x: allCenterX - 6, y: 102, width: 12, height: 12),
                                            in: view, window: window)
        XCTAssertFalse(notes.favoritesOnly)
    }
}
