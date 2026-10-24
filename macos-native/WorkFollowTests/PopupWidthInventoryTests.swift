import AppKit
import SwiftUI
import XCTest
@testable import WorkFollow

/// 弹层宽度总盘：把**所有**弹层按给定宽度渲染，量最右墨迹，给出松紧判定。
/// 输出 `INV ...` 一行一个，作为审计文档的表。
@MainActor
final class PopupWidthInventoryTests: XCTestCase {

    struct Row {
        let name: String
        let source: String          // 宽度来源（常量名 / 字面量 / 由内容推导）
        let assigned: CGFloat
        let inkRight: CGFloat
        let height: CGFloat
        var slack: CGFloat { assigned - inkRight }
        var verdict: String {
            if inkRight <= 0 { return "量不出" }
            if slack > 60 { return "偏宽" }
            if slack < 4 { return "偏紧" }
            return "合适"
        }
    }

    private var rows: [Row] = []

    override func tearDown() {
        for r in rows {
            print(String(format: "INV|%@|%@|%.0f|%.0f|%.0f|%.0f|%@",
                         r.name, r.source, r.assigned, r.inkRight, r.slack, r.height, r.verdict))
        }
        super.tearDown()
    }

    // MARK: - 详情 / 顶栏类

    func testTaskMenu() throws {
        try add("任务类型菜单", source: "PopupMetrics.taskMenuWidth",
                width: PopupMetrics.taskMenuWidth) {
            VStack(alignment: .leading, spacing: 0) {
                MenuRowProbe(title: "文本", symbol: "text.alignleft")
                MenuRowProbe(title: "清单", symbol: "checklist")
                MenuRowProbe(title: "笔记", symbol: "note.text")
            }
        }
    }

    func testTaskActions() throws {
        try add("更多操作菜单", source: "PopupMetrics.taskActionsWidth",
                width: PopupMetrics.taskActionsWidth) {
            VStack(alignment: .leading, spacing: 0) {
                MenuRowProbe(title: "关联主任务", symbol: "arrow.triangle.branch")
                MenuRowProbe(title: "设置为重复", symbol: "repeat")
                MenuRowProbe(title: "保存为模板", symbol: "doc.badge.plus")
                MenuRowProbe(title: "设置预计专注", symbol: "timer")
            }
        }
    }

    func testNoteInfo() throws {
        try add("笔记信息", source: "PopupMetrics.noteInfoWidth",
                width: PopupMetrics.noteInfoWidth) {
            TaskNoteInfoPanel(info: TaskNoteInfo(task: Self.sampleTask()), calendar: .current)
        }
    }

    func testFocusEstimate() throws {
        try add("预计专注", source: "PopupMetrics.focusEstimateWidth",
                width: PopupMetrics.focusEstimateWidth) {
            TaskFocusEstimateEditor(estimate: TaskFocusEstimate(minutes: 480, pomodoros: nil),
                                    onSave: { _ in }, onCancel: {})
        }
    }

    // MARK: - 选择器类

    func testTagPicker() throws {
        let (environment, _) = try environment()
        try add("标签选择", source: "PopupMetrics.tagPickerWidth",
                width: PopupMetrics.tagPickerWidth) {
            TaskTagPickerPopover(initialTags: [], workspace: environment.taskWorkspace,
                                 onCancel: {}, onApply: { _ in })
                .environmentObject(environment)
        }
    }

    func testParentPicker() throws {
        let (environment, taskID) = try environment()
        try add("关联主任务", source: "PopupMetrics.parentPickerWidth",
                width: PopupMetrics.parentPickerWidth) {
            TaskParentPicker(taskIDs: [taskID], workspace: environment.taskWorkspace, onClose: {})
                .environmentObject(environment)
        }
    }

    func testRelationPicker() throws {
        let (environment, taskID) = try environment()
        try add("关联任务/笔记", source: "PopupMetrics.relationPickerWidth",
                width: PopupMetrics.relationPickerWidth) {
            TaskRelationPicker(sourceTaskID: taskID, tasks: environment.taskWorkspace.allTasks,
                               notes: [], sourceNoteID: nil, onSelect: { _ in false }, onCancel: {})
                .environmentObject(environment)
        }
    }

    func testQuickAddProperties() throws {
        let (environment, _) = try environment()
        try add("快速添加属性", source: "PopupMetrics.quickAddPropertiesWidth",
                width: PopupMetrics.quickAddPropertiesWidth) {
            QuickAddPropertiesPopover(workspace: environment.taskWorkspace,
                                      selectedPriority: .none, selectedList: "收集箱",
                                      selectedTags: [], attachments: [], displayMode: .compact,
                                      onPriority: { _ in }, onList: { _ in }, onTags: { _ in },
                                      onTemplate: {}, onAttachments: { _ in },
                                      onDisplayMode: { _ in }, onDismiss: {})
                .environmentObject(environment)
        }
    }

    func testMoveTarget() throws {
        try add("移动到分组", source: "字面量 230",
                width: 230) {
            MoveTargetPickerCard(sectionTitle: "工作",
                                 targets: [MoveTarget(name: "个人成长与长期学习计划", isCurrent: false),
                                           MoveTarget(name: "本周待办", isCurrent: false)],
                                 onPick: { _ in }, onCancel: {})
        }
    }

    func testSortOptions() throws {
        try add("排序选项", source: "字面量 264",
                width: 264) {
            VStack(alignment: .leading, spacing: 0) {
                MenuRowProbe(title: "手动排序", symbol: "line.3.horizontal")
                MenuRowProbe(title: "按日期排序", symbol: "calendar")
                MenuRowProbe(title: "按优先级排序", symbol: "flag")
                MenuRowProbe(title: "按创建时间排序", symbol: "clock")
            }
        }
    }

    // MARK: - 网格类

    func testListColorGrid() throws {
        let (environment, _) = try environment()
        try add("清单颜色", source: "7*22+6*10+2*lg（由内容推导）",
                width: 7 * 22 + 6 * 10 + 2 * WFSpace.lg) {
            ListColorGridProbe(workspace: environment.taskWorkspace)
                .environmentObject(environment)
        }
    }

    func testListIconGrid() throws {
        let (environment, _) = try environment()
        try add("清单图标", source: "6*26+5*10+2*lg（由内容推导）",
                width: 6 * 26 + 5 * 10 + 2 * WFSpace.lg) {
            ListIconGridProbe(workspace: environment.taskWorkspace)
                .environmentObject(environment)
        }
    }

    // MARK: - 长文本类（最容易偏宽）

    func testSyncStatus() throws {
        try add("同步/提醒事项状态", source: "PopupMetrics.syncStatusWidth",
                width: PopupMetrics.syncStatusWidth) {
            VStack(alignment: .leading, spacing: 8) {
                Text("已与提醒事项同步").font(.headline)
                Text("最近核对：10月24日 14:30")
                Text("“已写入”仅表示 Mac 本地写入成功；iPhone 接收由 iCloud 完成。")
                    .font(.callout).foregroundStyle(WFColors.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(16)
        }
    }

    // MARK: - Sheet / 对话框

    func testListActivitySheet() throws {
        try add("清单动态 Sheet", source: "字面量 360",
                width: 360) {
            VStack(alignment: .leading, spacing: 10) {
                Text("清单动态").font(WFType.pageTitle)
                ForEach(0..<5, id: \.self) { index in
                    Text("\(index + 1) 分钟前 完成了「写周报」")
                        .font(WFType.body)
                }
            }
            .padding(16)
        }
    }

    func testTagEditorSheet() throws {
        try add("标签编辑 Sheet", source: "字面量 420",
                width: 420) {
            VStack(alignment: .leading, spacing: 12) {
                Text("编辑标签").font(WFType.pageTitle)
                HStack(spacing: 12) {
                    Text("名称").frame(width: 64, alignment: .leading)
                    Text("工作")
                }
            }
            .padding(WFSpace.xxl)
        }
    }

    func testTemplateEducation() throws {
        try add("模板说明", source: "字面量 380",
                width: 380) {
            Text("模板可以把一组固定流程的任务一次建好：先把流程里的每一步写进清单，之后每次从模板添加只改日期。")
                .font(WFType.body)
                .fixedSize(horizontal: false, vertical: true)
                .padding(16)
        }
    }

    // MARK: - 量测

    private func add(_ name: String, source: String, width: CGFloat,
                     @ViewBuilder content: () -> some View) throws {
        let host = NSHostingView(rootView: content()
            .frame(width: width)
            .background(Color.white))
        host.appearance = NSAppearance(named: .aqua)
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: width, height: 600),
                              styleMask: [.borderless], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.appearance = NSAppearance(named: .aqua)
        window.contentView = host
        window.orderFront(nil)
        host.layoutSubtreeIfNeeded()
        RunLoop.main.run(until: Date().addingTimeInterval(0.12))
        host.layoutSubtreeIfNeeded()
        let height = max(host.fittingSize.height, 1)
        host.frame = NSRect(x: 0, y: 0, width: width, height: height)
        host.layoutSubtreeIfNeeded()
        defer { window.close() }
        rows.append(Row(name: name, source: source, assigned: width,
                        inkRight: rightmostInk(of: host, width: width, height: height),
                        height: height))
    }

    private func rightmostInk(of view: NSView, width: CGFloat, height: CGFloat) -> CGFloat {
        guard height > 2, let bitmap = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { return 0 }
        view.cacheDisplay(in: view.bounds, to: bitmap)
        let w = bitmap.pixelsWide, h = bitmap.pixelsHigh
        guard w > 2, h > 2, let background = dominantColor(bitmap, w: w, h: h) else { return 0 }
        var farthest = 0
        for x in stride(from: w - 2, through: 1, by: -1) {
            var hit = false
            for y in stride(from: 1, to: h - 1, by: 1) {
                guard let pixel = bitmap.colorAt(x: x, y: y)?.usingColorSpace(.sRGB) else { continue }
                if !same(pixel, background) { hit = true; break }
            }
            if hit { farthest = x; break }
        }
        return CGFloat(farthest) / CGFloat(w) * width
    }

    private func dominantColor(_ bitmap: NSBitmapImageRep, w: Int, h: Int) -> NSColor? {
        var buckets: [Int: (count: Int, color: NSColor)] = [:]
        for y in stride(from: 1, to: h - 1, by: 3) {
            for x in stride(from: 1, to: w - 1, by: 3) {
                guard let c = bitmap.colorAt(x: x, y: y)?.usingColorSpace(.sRGB) else { continue }
                let key = Int(c.redComponent * 31) << 10
                    | Int(c.greenComponent * 31) << 5
                    | Int(c.blueComponent * 31)
                let entry = buckets[key] ?? (0, c)
                buckets[key] = (entry.count + 1, entry.color)
            }
        }
        return buckets.values.max(by: { $0.count < $1.count })?.color
    }

    private func same(_ a: NSColor, _ b: NSColor) -> Bool {
        abs(a.redComponent - b.redComponent) < 0.04
            && abs(a.greenComponent - b.greenComponent) < 0.04
            && abs(a.blueComponent - b.blueComponent) < 0.04
    }

    private static func sampleTask() -> Task {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        return Task(id: UUID(), title: "示例任务", list: .inbox, priority: .none,
                    schedule: TaskSchedule(), parentID: nil, childOrder: 0,
                    createdAt: now, updatedAt: now)
    }

    private func environment() throws -> (AppEnvironment, UUID) {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("popup-inv-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: directory) }
        let app = AppEnvironment(directory: directory)
        let workspace = app.taskWorkspace
        for title in ["写周报", "看设计稿评审"] { _ = workspace.createTask(title: title, in: .today) }
        let id = try XCTUnwrap(workspace.allTasks.first?.id)
        return (app, id)
    }
}

private struct MenuRowProbe: View {
    let title: String
    let symbol: String
    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: symbol).frame(width: 16)
            Text(title).font(WFType.menu)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 10)
        .frame(height: PopupMetrics.menuRowHeight)
        .fixedSize(horizontal: true, vertical: false)
    }
}

/// 与 `ListColorPickerPopover` 同构的最小复刻（原类型是 fileprivate）。
private struct ListColorGridProbe: View {
    @ObservedObject var workspace: TaskWorkspaceModel
    private let columns = Array(repeating: GridItem(.fixed(22), spacing: 10), count: 7)
    var body: some View {
        VStack(spacing: WFSpace.sm) {
            Text("选择清单颜色").font(WFType.supporting).foregroundStyle(WFColors.secondaryText)
            LazyVGrid(columns: columns, spacing: 10) {
                ForEach(WFListPalette.argb.indices, id: \.self) { index in
                    Circle().fill(WFListPalette.swatch(WFListPalette.argb[index]))
                        .frame(width: 22, height: 22)
                }
            }
        }
        .padding(WFSpace.lg)
    }
}

private struct ListIconGridProbe: View {
    @ObservedObject var workspace: TaskWorkspaceModel
    private let columns = Array(repeating: GridItem(.fixed(26), spacing: 10), count: 6)
    var body: some View {
        VStack(spacing: WFSpace.sm) {
            Text("选择清单图标").font(WFType.supporting).foregroundStyle(WFColors.secondaryText)
            LazyVGrid(columns: columns, spacing: 10) {
                ForEach(["📋", "🚀", "💼", "📌", "🎯", "📚"], id: \.self) { icon in
                    Text(icon).font(.system(size: 20)).frame(width: 26, height: 26)
                }
            }
        }
        .padding(WFSpace.lg)
    }
}
