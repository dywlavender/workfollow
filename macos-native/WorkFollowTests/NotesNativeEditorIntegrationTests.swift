import AppKit
import SwiftUI
import XCTest
@testable import WorkFollow

@MainActor
final class NotesNativeEditorIntegrationTests: XCTestCase {
    private var directories: [ObjectIdentifier: URL] = [:]
    private func fixture() -> AppEnvironment {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("notes-native-editor-\(UUID().uuidString)")
        addTeardownBlock { try? FileManager.default.removeItem(at: directory) }
        let environment = AppEnvironment(directory: directory)
        directories[ObjectIdentifier(environment)] = directory
        environment.navigation.destination = .notes
        return environment
    }

    private func host(_ environment: AppEnvironment,
                      onToolbarFrames: @escaping ([String: CGRect]) -> Void = { _ in },
                      onToolbarBounds: @escaping (CGRect) -> Void = { _ in },
                      onMenuTriggers: @escaping ([String: CGRect]) -> Void = { _ in },
                      onPopupRows: @escaping ([BusinessMenuRowFrame]) -> Void = { _ in }) -> NSHostingView<some View> {
        NSHostingView(rootView: NotesWorkspaceView(notes: environment.notesWorkspace,
            navigation: environment.navigation, tasks: environment.taskWorkspace)
            .environmentObject(environment)
            .coordinateSpace(name: "business-menu")
            .environment(\.popupContentObservation, { content in
                AnyView(content
                    .coordinateSpace(name: "business-menu")
                    .onPreferenceChange(BusinessMenuRowFrames.self, perform: onPopupRows))
            })
            .onPreferenceChange(BusinessMenuTriggerFrames.self, perform: onMenuTriggers)
            .onPreferenceChange(EditorToolbarCommandFramesKey.self, perform: onToolbarFrames)
            .onPreferenceChange(DocumentFormattingToolbarBoundsKey.self, perform: onToolbarBounds))
    }

    private func editor(in view: NSView) -> NativeTextView? {
        if let editor = view as? NativeTextView { return editor }
        return view.subviews.lazy.compactMap { self.editor(in: $0) }.first
    }

    func testNoteUsesTaskEditorAndRealFormattingControls() throws {
        let environment = fixture()
        let notes = environment.notesWorkspace
        notes.create()
        let id = try XCTUnwrap(notes.selectedID)
        notes.edit(id) { $0.title = "原生笔记"; $0.document = NativeDocument(plainText: "正文") }
        var toolbarFrames: [String: CGRect] = [:]
        var toolbarBounds = CGRect.zero
        let host = host(environment, onToolbarFrames: { toolbarFrames = $0 },
                        onToolbarBounds: { toolbarBounds = $0 })
        let window = InspectorPanelTestSupport.ownerWindow(for: host, width: 1100, height: 720)
        defer { window.close() }
        let editor = try XCTUnwrap(editor(in: host))
        XCTAssertEqual(editor.documentIdentity, id)
        XCTAssertEqual(editor.font?.pointSize, EditorPreferences.bodyFontSize)
        XCTAssertTrue(editor.usesHostScrollView)
        editor.setSelectedRange(NSRange(location: 0, length: 2))
        // 格式工具条常驻在正文上方，不再依赖底栏 A 开关。
        try InspectorPanelTestSupport.waitUntil("Formatting toolbar did not render") {
            toolbarFrames["format.bold"] != nil && toolbarBounds.width > 0
        }
        let bold = try XCTUnwrap(toolbarFrames["format.bold"])
        XCTAssertGreaterThan(toolbarBounds.width, 0)
        let boldInHost = bold.offsetBy(dx: toolbarBounds.minX, dy: toolbarBounds.minY)
        try InspectorPanelTestSupport.click(boldInHost, in: host, window: window)
        InspectorPanelTestSupport.settle(window)
        let document = try XCTUnwrap(notes.notes.first { $0.id == id }?.document)
        XCTAssertTrue(document.blocks[0].runs[0].marks.contains(.bold))
        XCTAssertTrue(window.firstResponder === editor)
    }

    func testSwitchingNotesFlushesOutgoingCompositionAndPersistsEachDocument() throws {
        let environment = fixture()
        let notes = environment.notesWorkspace
        notes.create()
        let first = try XCTUnwrap(notes.selectedID)
        notes.edit(first) { $0.title = "第一篇"; $0.document = NativeDocument(plainText: "甲") }
        notes.create()
        let second = try XCTUnwrap(notes.selectedID)
        notes.edit(second) { $0.title = "第二篇"; $0.document = NativeDocument(plainText: "乙") }
        notes.selectedID = first
        let host = host(environment)
        let window = InspectorPanelTestSupport.ownerWindow(for: host, width: 1100, height: 720)
        defer { window.close() }
        let editor = try XCTUnwrap(editor(in: host))
        window.makeFirstResponder(editor)
        editor.setSelectedRange(NSRange(location: 1, length: 0))
        editor.setMarkedText("组合输入", selectedRange: NSRange(location: 4, length: 0),
                             replacementRange: editor.selectedRange())
        XCTAssertTrue(editor.hasMarkedText())
        notes.selectedID = second
        InspectorPanelTestSupport.settle(window)
        let rebound = try XCTUnwrap(self.editor(in: host))
        XCTAssertTrue(rebound === editor, "The shared editor rebinds its document rather than replacing its host")
        XCTAssertEqual(rebound.documentIdentity, second)
        XCTAssertEqual(rebound.string, "乙")
        XCTAssertEqual(notes.notes.first { $0.id == first }?.document.plainText, "甲组合输入")
        XCTAssertFalse(rebound.hasMarkedText())
        rebound.setSelectedRange(NSRange(location: 1, length: 0))
        rebound.insertText("续写", replacementRange: rebound.selectedRange())
        InspectorPanelTestSupport.settle(window)
        let saved = expectation(description: "notes saved")
        environment.flush { error in XCTAssertNil(error); saved.fulfill() }
        wait(for: [saved], timeout: 5)
        let directory = try XCTUnwrap(directories[ObjectIdentifier(environment)])
        let reopened = try XCTUnwrap(NativePreviewRepository(directory: directory).load())
        XCTAssertEqual(reopened.tasks.first { $0.id == first }?.document.plainText, "甲组合输入")
        XCTAssertEqual(reopened.tasks.first { $0.id == second }?.document.plainText, "乙续写")
    }

    func testNoteActionsMenuConvertsNoteToTaskInPlace() throws {
        let environment = fixture()
        let notes = environment.notesWorkspace
        let id = notes.create()
        notes.edit(id) { $0.title = "待转任务"; $0.document = NativeDocument(plainText: "保留正文") }
        var menuTriggers: [String: CGRect] = [:]
        var menuRows: [BusinessMenuRowFrame] = []
        let host = host(environment, onMenuTriggers: { menuTriggers = $0 },
                        onPopupRows: { menuRows = $0 })
        let window = InspectorPanelTestSupport.ownerWindow(for: host, width: 1100, height: 720)
        defer { window.close() }

        try InspectorPanelTestSupport.click(try XCTUnwrap(menuTriggers["笔记操作"]), in: host, window: window)
        let menu = try InspectorPanelTestSupport.panel(title: "笔记操作", below: window)
        XCTAssertEqual(menuRows.count, 4)
        // Rows: 收藏 / 复制笔记正文 / 转换为任务 / 移到垃圾桶.
        let convert = try XCTUnwrap(menuRows.dropLast().last)
        try InspectorPanelTestSupport.click(convert.rect,
                                            in: try XCTUnwrap(menu.contentView), window: menu)

        XCTAssertTrue(notes.notes.isEmpty)
        XCTAssertNil(notes.selectedID)
        XCTAssertEqual(environment.taskWorkspace.task(for: id)?.kind, .text)
        XCTAssertEqual(environment.taskWorkspace.task(for: id)?.document.plainText, "保留正文")
        XCTAssertEqual(environment.taskWorkspace.tasksInActiveLists.map(\.id), [id])
    }

    /// 列表首行：页头 44 + 间距 8 + 搜索栏 34 + 间距 8 + 行高约 52，取行中心。
    /// SwiftUI 列表行不暴露 AX 元素，这里按固定的列布局定位。
    private func rightClickFirstNoteRow(in window: NSWindow) throws {
        let height = try XCTUnwrap(window.contentView).bounds.height
        let point = NSPoint(x: 96, y: height - 120)
        let event = try XCTUnwrap(NSEvent.mouseEvent(with: .rightMouseDown, location: point,
            modifierFlags: [], timestamp: ProcessInfo.processInfo.systemUptime,
            windowNumber: window.windowNumber, context: nil,
            eventNumber: 1, clickCount: 1, pressure: 1))
        XCTAssertTrue(PopupInteractionRegistry.shared.showContextMenu(for: event))
        InspectorPanelTestSupport.settle(window)
    }

    func testNoteRowRightClickSelectsRowAndTogglesFavorite() throws {
        let environment = fixture()
        let notes = environment.notesWorkspace
        // 新笔记插在列表最前：先建「另一篇」，再建要右键的那篇。
        let other = notes.create()
        notes.edit(other) { $0.title = "另一篇"; $0.document = NativeDocument(plainText: "另一篇正文") }
        let first = notes.create()
        notes.edit(first) { $0.title = "右键笔记"; $0.document = NativeDocument(plainText: "正文") }
        notes.selectedID = other
        var menuRows: [BusinessMenuRowFrame] = []
        let host = host(environment, onPopupRows: { menuRows = $0 })
        let window = InspectorPanelTestSupport.ownerWindow(for: host, width: 1100, height: 720)
        defer { window.close() }

        // 行上挂 .draggable 后，普通点击仍要能选中并打开详情。
        try InspectorPanelTestSupport.click(CGRect(x: 96, y: 112, width: 12, height: 12),
                                            in: host, window: window)
        XCTAssertEqual(notes.selectedID, first)
        notes.selectedID = other

        try rightClickFirstNoteRow(in: window)
        let menu = try InspectorPanelTestSupport.panel(title: "操作菜单", below: window)
        XCTAssertEqual(notes.selectedID, first, "右键先选中目标行")
        // 打开笔记 / 收藏 / 移动到 / 复制笔记正文 / 转换为任务 / 移到垃圾桶
        XCTAssertEqual(menuRows.count, 6)
        try InspectorPanelTestSupport.click(menuRows[1].rect,
                                            in: try XCTUnwrap(menu.contentView), window: menu)
        XCTAssertEqual(notes.notes.first { $0.id == first }?.favorite, true)
        XCTAssertFalse(menu.isVisible)
    }

    func testNoteRowContextMenuMovesNoteIntoFolderThroughSubmenu() throws {
        let environment = fixture()
        let notes = environment.notesWorkspace
        XCTAssertTrue(notes.addFolder("会议"))
        let id = notes.create()
        notes.edit(id) { $0.title = "待归档笔记"; $0.document = NativeDocument(plainText: "正文") }
        var menuRows: [BusinessMenuRowFrame] = []
        let host = host(environment, onPopupRows: { menuRows = $0 })
        let window = InspectorPanelTestSupport.ownerWindow(for: host, width: 1100, height: 720)
        defer { window.close() }

        try rightClickFirstNoteRow(in: window)
        let menu = try InspectorPanelTestSupport.panel(title: "操作菜单", below: window)
        try InspectorPanelTestSupport.click(menuRows[2].rect,
                                            in: try XCTUnwrap(menu.contentView), window: menu)
        let child = try InspectorPanelTestSupport.panel(title: "移动到", below: window)
        // 子菜单行不暴露 AX；按共用菜单几何点第二行（未归档 / 会议 / 移到新文件夹…）。
        let rowTop = PopupMetrics.menuInset + PopupMetrics.menuRowHeight + 2
        try InspectorPanelTestSupport.click(
            CGRect(x: 20, y: rowTop, width: 60, height: PopupMetrics.menuRowHeight),
            in: try XCTUnwrap(child.contentView), window: child)

        XCTAssertEqual(notes.notes.first { $0.id == id }?.folder, "会议")
        XCTAssertEqual(notes.notes.first { $0.id == id }?.folderID, notes.folderID(named: "会议"))
    }

    func testLongNoteUsesOuterCompactScrollView() throws {
        let environment = fixture()
        let notes = environment.notesWorkspace
        notes.create()
        let id = try XCTUnwrap(notes.selectedID)
        let body = (1...70).map { "第\($0)段：检查长笔记滚动" }.joined(separator: "\n")
        notes.edit(id) { $0.title = "长笔记"; $0.document = NativeDocument(plainText: body) }
        let host = host(environment)
        let window = InspectorPanelTestSupport.ownerWindow(for: host, width: 1100, height: 720)
        defer { window.close() }
        let editor = try XCTUnwrap(editor(in: host))
        let scroll = try XCTUnwrap(editor.enclosingScrollView)
        XCTAssertFalse(scroll.documentView === editor)
        XCTAssertEqual(scroll.scrollerStyle, .overlay)
        editor.scrollRangeToVisible(NSRange(location: (body as NSString).length - 1, length: 1))
        InspectorPanelTestSupport.settle(window)
        XCTAssertGreaterThan(scroll.contentView.bounds.minY, 0)
        XCTAssertEqual(editor.string, body)
    }

    func testPlainPlaceholderDoesNotCoverAnEmptyFormattedBlock() {
        XCTAssertTrue(DocumentEditorPlaceholder.isVisible(for: .empty))
        for kind: DocumentBlockKind in [.heading(1), .bullet, .checklist(false), .quote, .code] {
            let document = NativeDocument(blocks: [DocumentBlock(kind: kind)])
            XCTAssertFalse(DocumentEditorPlaceholder.isVisible(for: document))
        }
    }
}
