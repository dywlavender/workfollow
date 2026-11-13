import AppKit
import SwiftUI
import XCTest
@testable import WorkFollow

@MainActor
final class ProjectFolderInteractionTests: XCTestCase {
    func testWideHistoryCanCreateAndMoveProjects() throws {
        try verifyProjectFolders(width: 1150)
    }

    func testCompactHistoryCanCreateAndMoveProjects() throws {
        try verifyProjectFolders(width: 720)
    }

    /// 会议纪要与 AI 对话的文件栏必须同宽（用户 2026-11-10 反馈两页忽宽忽窄）。
    /// 会议页默认宽度来自 `MeetingMetrics.listWidth`，AI 对话侧栏在
    /// `AIChatWorkspaceView` 里是固定值；两边各起一个窗口实量锚点宽度对齐。
    func testMeetingAndChatFilePanelsShareWidth() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("workfollow-panel-width-\(UUID())")
        let environment = AppEnvironment(directory: directory)
        defer { try? FileManager.default.removeItem(at: directory) }
        var anchors: [String: NSView] = [:]

        func makeShell() -> some View {
            RootShellView(workspace: environment.taskWorkspace, navigation: environment.navigation)
                .environmentObject(environment)
                .environment(\.workflowActionObservation, { anchors[$0] = $1 })
                .frame(width: 1100, height: 800)
        }
        func measure(_ anchorID: String, at destination: NativeDestination) throws -> CGFloat {
            environment.navigation.destination = destination
            let host = NSHostingView(rootView: makeShell())
            let window = InspectorPanelTestSupport.ownerWindow(for: host, width: 1100, height: 800)
            defer { window.contentView = nil; window.close() }
            try InspectorPanelTestSupport.waitUntil("Missing anchor \(anchorID)") {
                anchors[anchorID]?.window != nil
            }
            return try XCTUnwrap(anchors[anchorID]).bounds.width
        }

        let chatWidth = try measure("ai.chat.history", at: .aiChat)
        let meetingWidth = try measure("meeting.list", at: .meetings)
        XCTAssertGreaterThan(chatWidth, 0)
        XCTAssertEqual(meetingWidth, chatWidth, accuracy: 1,
                       "会议纪要与 AI 对话的文件栏应同宽")
    }

    /// 层级契约：根级只有节点行，记录一律缩进一级；折叠「未归档」整组隐藏，
    /// 再展开记录回来（用户反馈「看不出属于哪一层级」）。
    func testProjectFolderListGroupsUnfiledRecordsUnderANode() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("workfollow-folder-hierarchy-\(UUID())")
        let environment = AppEnvironment(directory: directory)
        let chat = environment.aiChat.current
        chat.input = "层级检查对话"
        chat.send { _, _, _, _, _ in "虚构答复" }
        environment.navigation.destination = .aiChat
        var anchors: [String: NSView] = [:]
        let host = NSHostingView(rootView: RootShellView(workspace: environment.taskWorkspace, navigation: environment.navigation)
            .environmentObject(environment).environment(\.workflowActionObservation, { anchors[$0] = $1 })
            .frame(width: 1150, height: 800))
        let window = InspectorPanelTestSupport.ownerWindow(for: host, width: 1150, height: 800)
        defer {
            window.contentView = nil; window.close()
            try? FileManager.default.removeItem(at: directory)
        }

        let rowID = "ai.chat.history.\(chat.record.id)"
        try InspectorPanelTestSupport.waitUntil("Unfiled node and record row should both render") {
            anchors["projects.folder.unfiled"]?.window === window && anchors[rowID]?.window === window
        }
        let unfiled = try XCTUnwrap(anchors["projects.folder.unfiled"])
        let row = try XCTUnwrap(anchors[rowID])
        let unfiledFrame = unfiled.convert(unfiled.bounds, to: nil)
        let rowFrame = row.convert(row.bounds, to: nil)
        XCTAssertEqual(rowFrame.minX - unfiledFrame.minX, ProjectFolderListMetrics.childIndent, accuracy: 2,
                       "未归档下的记录应缩进一级")

        // 折叠后子记录从窗口上消失（锚点留在字典里但脱离窗口）。
        try InspectorPanelTestSupport.click(unfiled.bounds, in: unfiled, window: window)
        try InspectorPanelTestSupport.waitUntil("Record row should hide after collapsing the node") {
            guard let view = anchors[rowID] else { return false }
            return view.window !== window || view.isHiddenOrHasHiddenAncestor
        }
        // 再展开，记录回来；锚点字典保留旧视图，以「重新挂上窗口」判断。
        try InspectorPanelTestSupport.waitUntil("Unfiled node should stay attached") {
            anchors["projects.folder.unfiled"]?.window === window
        }
        let unfiledAgain = try XCTUnwrap(anchors["projects.folder.unfiled"])
        try InspectorPanelTestSupport.click(unfiledAgain.bounds, in: unfiledAgain, window: window)
        try InspectorPanelTestSupport.waitUntil("Record row should come back after expanding") {
            guard let view = anchors[rowID], view.window === window else { return false }
            return !view.isHiddenOrHasHiddenAncestor && view.bounds.width > 0
        }
    }

    private func verifyProjectFolders(width: CGFloat) throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("workfollow-project-folders-\(UUID())")
        let environment = AppEnvironment(directory: directory)
        let chats = environment.aiChat
        let chat = chats.current
        chat.input = "虚构项目对话"
        chat.send { _, _, _, _, _ in "虚构答复" }
        environment.navigation.destination = .aiChat
        var anchors: [String: NSView] = [:]
        var menuRows: [BusinessMenuRowFrame] = []
        let host = NSHostingView(rootView: RootShellView(workspace: environment.taskWorkspace, navigation: environment.navigation)
            .environmentObject(environment).environment(\.workflowActionObservation, { anchors[$0] = $1 })
            .environment(\.popupContentObservation, { content in
                AnyView(content.coordinateSpace(name: "business-menu")
                    .onPreferenceChange(BusinessMenuRowFrames.self) { if !$0.isEmpty { menuRows = $0 } })
            })
            .frame(width: width, height: 800))
        let window = InspectorPanelTestSupport.ownerWindow(for: host, width: width, height: 800)
        defer {
            window.contentView = nil; window.close()
            try? FileManager.default.removeItem(at: directory)
        }

        func anchor(_ id: String) throws -> (NSView, NSWindow) {
            try InspectorPanelTestSupport.waitUntil("Missing control \(id)") {
                guard let view = anchors[id], let owner = view.window else { return false }
                return owner.isVisible && !owner.ignoresMouseEvents && owner.alphaValue >= 0.99 && !view.bounds.isEmpty
            }
            let view = try XCTUnwrap(anchors[id])
            return (view, try XCTUnwrap(view.window))
        }
        func click(_ id: String) throws {
            let (view, owner) = try anchor(id)
            try InspectorPanelTestSupport.click(view.bounds, in: view, window: owner)
        }
        func rightClick(_ id: String) throws -> NSPanel {
            menuRows = []
            let (view, owner) = try anchor(id)
            let point = view.convert(NSPoint(x: view.bounds.midX, y: view.bounds.midY), to: nil)
            let event = try XCTUnwrap(NSEvent.mouseEvent(with: .rightMouseDown, location: point, modifierFlags: [],
                timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: owner.windowNumber,
                context: nil, eventNumber: 1, clickCount: 1, pressure: 1))
            NSApp.postEvent(event, atStart: true)
            let down = try XCTUnwrap(NSApp.nextEvent(matching: .rightMouseDown, until: Date(),
                inMode: .default, dequeue: true))
            NSApp.sendEvent(down)
            return try InspectorPanelTestSupport.panel(title: "操作菜单", below: owner)
        }
        func create(_ name: String) throws {
            anchors.removeValue(forKey: "dialog.button.创建")
            anchors.removeValue(forKey: "dialog.field")
            try click("projects.add")
            let (_, dialog) = try anchor("dialog.button.创建")
            try click("dialog.field")
            try InspectorPanelTestSupport.waitUntil { dialog.firstResponder is NSTextView }
            let editor = try XCTUnwrap(dialog.firstResponder as? NSTextView)
            editor.insertText(name, replacementRange: editor.selectedRange())
            InspectorPanelTestSupport.settle(dialog)
            try click("dialog.button.创建")
        }
        func chooseMenuRow(_ index: Int, in menu: NSPanel) throws {
            let content = try XCTUnwrap(menu.contentView)
            try InspectorPanelTestSupport.waitUntil("The menu row should fit in the popup") {
                menuRows.indices.contains(index) && menuRows[index].rect.maxY <= content.bounds.height
            }
            let frame = try XCTUnwrap(menuRows.indices.contains(index) ? menuRows[index].rect : nil)
            try InspectorPanelTestSupport.click(frame, in: content, window: menu)
        }
        if width < 760 { try click("ai.chat.history.toggle") }
        try create("对话项目")
        let chatFolder = try XCTUnwrap(chats.projects.folders.first)
        try chooseMenuRow(1, in: rightClick("ai.chat.history.\(chat.record.id)"))
        XCTAssertEqual(chats.projects.folderID(for: chat.record.id), chatFolder.id)
        XCTAssertTrue(environment.meetingStore.projects.folders.isEmpty)
    }
}
