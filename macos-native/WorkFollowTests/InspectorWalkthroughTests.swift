import AppKit
import SwiftUI
import XCTest
@testable import WorkFollow

/// 手动走查脚本（默认跳过）：把真实 Inspector 拉起来逐步操作并抓图。
///
/// 运行方式：
/// `touch /tmp/workfollow-walkthrough.enable` 后运行
/// `xcodebuild test ... -only-testing:WorkFollowTests/InspectorWalkthroughTests`；
/// 截图默认写到 `/tmp/workfollow-walkthrough`。
/// 注意：脚本不关窗（`AppEnvironment` + `NSHostingView` 的关窗释放在 XCTest 内存检查里会过释放）。
@MainActor
final class InspectorWalkthroughTests: XCTestCase {

    private var outputDirectory: URL {
        URL(fileURLWithPath: "/tmp/workfollow-walkthrough", isDirectory: true)
    }

    private func capture(_ window: NSWindow, _ name: String) throws {
        try FileManager.default.createDirectory(at: outputDirectory, withIntermediateDirectories: true)
        window.contentView?.layoutSubtreeIfNeeded()
        let cg = try XCTUnwrap(CGWindowListCreateImage(.null, .optionIncludingWindow,
                                                        CGWindowID(window.windowNumber),
                                                        [.bestResolution, .boundsIgnoreFraming]))
        let rep = NSBitmapImageRep(cgImage: cg)
        let png = try XCTUnwrap(rep.representation(using: .png, properties: [:]))
        try png.write(to: outputDirectory.appendingPathComponent("\(name).png"))
    }

    func testWalkthrough() throws {
        // xcodebuild 不会把任意环境变量带进测试宿主，用标记文件开关。
        try XCTSkipUnless(FileManager.default.fileExists(atPath: "/tmp/workfollow-walkthrough.enable"),
                          "手动走查：touch /tmp/workfollow-walkthrough.enable 后运行")

        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("walk-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let environment = AppEnvironment(directory: dir)
        let workspace = environment.taskWorkspace
        let id = try XCTUnwrap(workspace.createTask(title: "走查任务", in: .inbox).taskID)
        workspace.setDocument(id, NativeDocument(blocks: [
            DocumentBlock(kind: .paragraph, runs: [DocumentRun(text: "第一段正文")]),
            DocumentBlock(kind: .paragraph, runs: [
                DocumentRun(text: "官网"),
                DocumentRun(text: "链接", marks: [.link("https://example.com")])
            ]),
            DocumentBlock(kind: .checklist(false), runs: [DocumentRun(text: "检查项一")])
        ]))
        workspace.setTags(id, ["工作", "重要"])
        _ = workspace.createChild(id, title: "子任务甲")
        let deadline = workspace.calendar.date(byAdding: .day, value: 3, to: workspace.clock()) ?? workspace.clock()
        workspace.setDeadline(id, deadline)
        workspace.select(id)

        let host = InspectorPanelTestSupport.inspectorHost(
            workspace: workspace, environment: environment,
            commentStore: environment.taskCommentStore)
        let window = InspectorPanelTestSupport.ownerWindow(for: host, width: 880, height: 900)
        InspectorPanelTestSupport.settle(window)
        try capture(window, "01-initial")

        try InspectorPanelTestSupport.clickButton(containing: "设置日期", in: window)
        let datePanel = try InspectorPanelTestSupport.panel(title: InspectorPanelTestSupport.datePanelTitle, below: window)
        try capture(datePanel, "02-date-panel")

        // 截止日期面板只能从顶栏的次要日期进入（滴答的日期面板没有「截止日期」行，
        // 2026-10-19 实测）；任务在 setup 阶段已带截止日期，这里点它。
        try InspectorPanelTestSupport.sendEscape(to: window)
        InspectorPanelTestSupport.settle(window)
        try InspectorPanelTestSupport.clickButton(containing: "截止日期", in: window)
        let deadlinePanel = try InspectorPanelTestSupport.panel(title: InspectorPanelTestSupport.datePanelTitle, below: window)
        try capture(deadlinePanel, "03-deadline-panel")
        try InspectorPanelTestSupport.sendReturn(to: deadlinePanel)
        InspectorPanelTestSupport.settle(window)
        try capture(window, "04-after-deadline")

        if let textView = firstTextView(in: window) {
            let point = NSPoint(x: DocumentEditorGeometry.decorationMarkerX(visibleMinX: textView.decorationVisibleMinX) + 2,
                                y: (textView.viewRect(forCharacterAt: 0) ?? .zero).midY)
            _ = textView.openBlockMenu(at: point)
            RunLoop.main.run(until: Date().addingTimeInterval(0.25))
            if let panel = textView.slashPanel, panel.isVisible { try capture(panel, "05-block-menu") }
            textView.dismissSlash()
        }

        if let textView = firstTextView(in: window) {
            window.makeFirstResponder(textView)
            let end = (textView.string as NSString).length
            textView.setSelectedRange(NSRange(location: end, length: 0))
            textView.insertText("\n#", replacementRange: textView.selectedRange())
            RunLoop.main.run(until: Date().addingTimeInterval(0.2))
            if let panel = textView.tagPanel, panel.isVisible { try capture(panel, "06-tag-completion") }
            textView.dismissTagCompletion()
        }

        if let textView = firstTextView(in: window) {
            let source = textView.string as NSString
            let linkRange = source.range(of: "链接")
            if linkRange.location != NSNotFound,
               let line = textView.viewRect(forCharacterAt: linkRange.location),
               let event = NSEvent.mouseEvent(with: .mouseMoved,
                                              location: textView.convert(NSPoint(x: line.minX + 8, y: line.midY), to: nil),
                                              modifierFlags: [], timestamp: ProcessInfo.processInfo.systemUptime,
                                              windowNumber: window.windowNumber, context: nil,
                                              eventNumber: 0, clickCount: 0, pressure: 0) {
                textView.mouseMoved(with: event)
                RunLoop.main.run(until: Date().addingTimeInterval(0.2))
                if let panel = textView.linkHoverPanel, panel.isVisible { try capture(panel, "07-link-hover") }
                textView.hideLinkHoverMenu()
            }
        }

        try InspectorPanelTestSupport.clickButton(containing: "任务类型", in: window)
        if let menu = InspectorPanelTestSupport.visibleWindows(below: window).first(where: { $0.title == "任务类型" }) {
            try capture(menu, "08-kind-menu")
        }
        workspace.setKind(id, .checklist)
        try InspectorPanelTestSupport.sendEscape(to: window)
        InspectorPanelTestSupport.settle(window)
        try capture(window, "09-checklist-mode")

        try InspectorPanelTestSupport.clickButton(containing: "笔记信息", in: window)
        if let panel = InspectorPanelTestSupport.visibleWindows(below: window).first(where: { $0.title == "笔记信息" }) {
            try capture(panel, "10-note-info")
        }
        try InspectorPanelTestSupport.sendEscape(to: window)

        try InspectorPanelTestSupport.clickButton(containing: "在独立窗口打开", in: window)
        RunLoop.main.run(until: Date().addingTimeInterval(0.4))
        if let detail = NSApp.windows.first(where: { $0.title == "任务详情" && $0.isVisible }) {
            try capture(detail, "11-detach-window")
        }

        environment.taskCommentStore.add(taskID: id, text: "走查时留下的评论")
        InspectorPanelTestSupport.settle(window)
        try InspectorPanelTestSupport.clickButton(containing: "评论", in: window)
        InspectorPanelTestSupport.settle(window)
        try capture(window, "12-comments-open")
    }

    private func firstTextView(in window: NSWindow) -> NativeTextView? {
        var found: NativeTextView?
        func walk(_ view: NSView) {
            if found != nil { return }
            if let text = view as? NativeTextView { found = text; return }
            for child in view.subviews { walk(child) }
        }
        if let root = window.contentView { walk(root) }
        return found
    }
}
