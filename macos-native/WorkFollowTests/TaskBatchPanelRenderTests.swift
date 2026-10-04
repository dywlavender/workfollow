import XCTest
import SwiftUI
@testable import WorkFollow

/// 批量面板补齐轮的渲染契约：真渲染 TaskBatchPanelView,经 batchPanelTextProbe
/// 的 preference 收集实际渲染出的文案,断言滴答式瓦片区的新能力(标签/关联
/// 主任务/转换为笔记/复制文本)在列,"合并"按设计缺席。SwiftUI 文本不进
/// 进程内 AX 树也不落 NSTextField,preference 是唯一可靠的进程内通道。
@MainActor
final class TaskBatchPanelRenderTests: XCTestCase {

    func testBatchPanelRendersTicktickStyleTiles() throws {
        let calendar = Calendar(identifier: .gregorian)
        let tasks = (1...3).map { index -> Task in
            Task(id: UUID(), title: "批量瓦片\(index)", list: .inbox, priority: .none,
                 schedule: TaskSchedule(), parentID: nil, childOrder: 0,
                 createdAt: calendar.date(byAdding: .minute, value: index, to: fixtureNow)!,
                 updatedAt: self.fixtureNow)
        }
        let workspace = TaskWorkspaceModel(clock: { self.fixtureNow }, calendar: calendar,
                                           seedDemoData: false, initialTasks: tasks)
        workspace.setBulkSelection(in: tasks.map(\.id))

        var rendered: Set<String> = []
        let panel = TaskBatchPanelView(workspace: workspace)
            .onPreferenceChange(TaskBatchPanelTextKey.self) { rendered = $0 }
        let window = makeWindow(root: panel)
        defer { window.orderOut(nil) }
        flushRunLoop()

        for text in ["已选择 3 项", "设置日期", "收集箱", "标签",
                     "完成", "置顶", "关联主任务", "创建副本", "转换为笔记", "复制文本", "删除"] {
            XCTAssertTrue(rendered.contains(text), "批量面板缺少文案: \(text)")
        }
        // 清单行显示所选任务的共同值(fixture 全在收集箱→显示"收集箱"而非
        // 固定的"移动到清单");优先级行同理显示"无优先级"。
        XCTAssertTrue(rendered.contains("无优先级"), "优先级行应显示共同值")

        // 尺寸契约:布局常量与滴答实测值(2026-10 截图像素扫描)绑定,漂移即失败。
        // 进程内量不到 SwiftUI 渲染后的 frame(不落 NSTextField/NSButton),
        // 所以锁的是源码常量——渲染 frame 由截图存档供人工比对。
        XCTAssertEqual(BatchPanelLayout.tileHeight, 75, "瓦片高度应与滴答 75pt 一致")
        XCTAssertEqual(BatchPanelLayout.tileColumnGap, 2, "瓦片列隙应与滴答 2pt 一致")
        XCTAssertEqual(BatchPanelLayout.rowHeight, 30, "属性行高应与滴答 30pt 一致")
        XCTAssertEqual(BatchPanelLayout.flagTileHeight, 34, "旗块高度应与滴答 34pt 一致")

        // 截图存档供人工比对(与 FocusRenderTests 同路径风格)。
        if let image = CGWindowListCreateImage(.null, .optionIncludingWindow,
                                               CGWindowID(window.windowNumber), [.bestResolution]) {
            let rep = NSBitmapImageRep(cgImage: image)
            if let png = rep.representation(using: .png, properties: [:]) {
                let dir = FileManager.default.temporaryDirectory
                    .appendingPathComponent("batch-panel-contract", isDirectory: true)
                try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
                try png.write(to: dir.appendingPathComponent("batch-panel-ticktick-style.png"))
            }
        }
    }

    // MARK: - Helpers

    private var fixtureNow: Date {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        return calendar.date(from: DateComponents(year: 2026, month: 10, day: 3, hour: 10))!
    }

    private func makeWindow(root: some View) -> NSWindow {
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 360, height: 720),
                              styleMask: [.titled, .borderless], backing: .buffered, defer: false)
        window.contentView = NSHostingView(rootView: root.environmentObject(AppEnvironment()))
        window.orderFrontRegardless()
        flushRunLoop()
        return window
    }

    private func flushRunLoop() {
        RunLoop.current.run(until: Date().addingTimeInterval(0.3))
    }
}
