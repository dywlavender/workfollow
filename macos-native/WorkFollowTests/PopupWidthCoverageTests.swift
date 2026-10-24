import AppKit
import SwiftUI
import XCTest
@testable import WorkFollow

/// 弹层宽度审计（补漏）：`PopupWidthInventoryTests` 之外的所有浮层。
///
/// 一边量一边把「未进 `PopupMetrics` 的裸字面量」逐个收编：这轮的产物是
/// `PopupMetrics` 里新增的 `sortOptionWidth` / `settingsSheetWidth` /
/// `activitySheetWidth` / `templateNoteWidth` / `rhythmPopoverWidth` /
/// `goalPopoverWidth` / `symbolPickerWidth`。
@MainActor
final class PopupWidthCoverageTests: XCTestCase {

    struct Row {
        let name: String
        let source: String
        let assigned: CGFloat
        let inkRight: CGFloat
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
            print(String(format: "COV|%@|%@|%.0f|%.0f|%.0f|%@",
                         r.name, r.source, r.assigned, r.inkRight, r.slack, r.verdict))
        }
        super.tearDown()
    }

    // MARK: - 已收编的常量

    func testTagEditorSheet() throws {
        let (environment, _) = try environment()
        try add("标签编辑 Sheet", source: "PopupMetrics.settingsSheetWidth",
                width: PopupMetrics.settingsSheetWidth) {
            TaskTagEditorView(workspace: environment.taskWorkspace, tag: nil, parentID: nil,
                              onSaved: { _ in }, onDismiss: {})
                .environmentObject(environment)
        }
    }

    func testActivitySheet() throws {
        let (environment, _) = try environment()
        try add("清单动态 Sheet", source: "PopupMetrics.activitySheetWidth",
                width: PopupMetrics.activitySheetWidth) {
            ListActivitySheet(listName: TaskList.inbox.name,
                              workspace: environment.taskWorkspace,
                              activity: environment.taskActivityStore,
                              onClose: {})
                .environmentObject(environment)
        }
    }

    func testSortOptionMenu() throws {
        try add("排序选项", source: "PopupMetrics.sortOptionWidth",
                width: PopupMetrics.sortOptionWidth) {
            VStack(alignment: .leading, spacing: 0) {
                MenuRowProbe(title: "按创建时间排序", symbol: "clock")
                MenuRowProbe(title: "按修改时间排序", symbol: "pencil")
            }
        }
    }

    func testTemplateEducation() throws {
        try add("模板说明", source: "PopupMetrics.templateNoteWidth",
                width: PopupMetrics.templateNoteWidth) {
            Text("模板可以把一组固定流程的任务一次建好：先把流程里的每一步写进清单，之后每次从模板添加只改日期。")
                .font(WFType.body)
                .fixedSize(horizontal: false, vertical: true)
                .padding(16)
        }
    }

    // MARK: - 本轮新收编

    func testRhythmPopover() throws {
        try add("专注节奏设置", source: "PopupMetrics.rhythmPopoverWidth",
                width: PopupMetrics.rhythmPopoverWidth) {
            VStack(alignment: .leading, spacing: 12) {
                Text("节奏设置").font(WFType.sectionSemibold)
                ForEach(["专注时长", "短休息", "长休息"], id: \.self) { title in
                    HStack(spacing: 12) {
                        Text(title).font(WFType.body)
                        Spacer(minLength: 0)
                        Stepper("", value: .constant(25), in: 1...120).labelsHidden()
                        Text("25 分钟").font(WFType.supporting)
                    }
                }
            }
            .padding(16)
            .frame(width: PopupMetrics.rhythmPopoverWidth)
        }
    }

    func testGoalPopover() throws {
        try add("每日目标", source: "PopupMetrics.goalPopoverWidth",
                width: PopupMetrics.goalPopoverWidth) {
            VStack(alignment: .leading, spacing: 10) {
                Text("每日目标").font(WFType.sectionSemibold)
                Text("4 小时").font(WFType.body)
            }
            .padding(16)
            .frame(width: PopupMetrics.goalPopoverWidth)
        }
    }

    func testSymbolPicker() throws {
        try add("图标选择", source: "PopupMetrics.symbolPickerWidth",
                width: PopupMetrics.symbolPickerWidth) {
            LazyVGrid(columns: Array(repeating: GridItem(.fixed(28), spacing: 8), count: 6),
                      spacing: 8) {
                ForEach(["🎂", "🎉", "🎄", "❤️", "⭐️", "🏆",
                         "🎯", "📌", "🎵", "🌸", "☀️", "🌙"], id: \.self) { symbol in
                    Text(symbol).font(.system(size: 18)).frame(width: 28, height: 28)
                }
            }
            .padding(WFSpace.md)
        }
    }

    // MARK: - 快速添加的两个 250

    func testQuickAddListPicker() throws {
        let (environment, _) = try environment()
        try add("快速添加·清单选择", source: "字面量 250（未收编）",
                width: 250) {
            VStack(alignment: .leading, spacing: 0) {
                MenuRowProbe(title: "个人成长与长期学习计划", symbol: "list.bullet")
                MenuRowProbe(title: "本周待办", symbol: "list.bullet")
            }
            .padding(WFSpace.sm)
        }
        _ = environment
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
                        inkRight: rightmostInk(of: host, width: width, height: height)))
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

    private func environment() throws -> (AppEnvironment, UUID) {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("popup-cov-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: directory) }
        let app = AppEnvironment(directory: directory)
        _ = app.taskWorkspace.createTask(title: "写周报", in: .today)
        let id = try XCTUnwrap(app.taskWorkspace.allTasks.first?.id)
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

/// 补漏第二轮：Sheet / 编辑器窗口 / 清单级弹层（上一轮只覆盖了属性面板与菜单）。
@MainActor
final class PopupWidthSecondPassTests: XCTestCase {

    private var rows: [(String, CGFloat, CGFloat)] = []

    override func tearDown() {
        for (name, assigned, ink) in rows {
            let slack = assigned - ink
            let verdict = ink <= 0 ? "量不出" : (slack > 60 ? "偏宽" : (slack < 4 ? "偏紧" : "合适"))
            print(String(format: "COV2|%@|%.0f|%.0f|%.0f|%@", name, assigned, ink, slack, verdict))
        }
        super.tearDown()
    }

    func testFilterEditorSheet() throws {
        let (environment, _) = try environment()
        try add("筛选器编辑 Sheet", width: 520) {
            FilterEditorView(store: environment.filterStore, workspace: environment.taskWorkspace,
                             initial: nil, onDismiss: {})
                .environmentObject(environment)
        }
    }

    func testTaskComposerSheet() throws {
        let (environment, _) = try environment()
        try add("任务新建面板", width: 360) {
            TaskComposer(workspace: environment.taskWorkspace, onClose: { _ in },
                         title: "", list: TaskList.inbox.name, scheduled: false, date: Date(),
                         initialSchedule: nil, initialProperties: QuickAddPropertiesOverrides())
                .environmentObject(environment)
        }
    }

    func testTagColorPickerPanel() throws {
        // 这是「标签颜色」网格弹层（7 列 × 22 + 6 × 10 间距 = 214，加 20 内边距）。
        let (environment, _) = try environment()
        let tagID = try XCTUnwrap(environment.taskWorkspace.createTag("色彩"))
        try add("标签颜色网格", width: 220) {
            VStack(spacing: WFSpace.md) {
                Text("标签颜色").font(WFType.supporting).foregroundStyle(WFColors.secondaryText)
                TaskTagColorGrid(color: .constant(nil))
            }
            .padding(WFSpace.lg)
        }
        _ = tagID
    }

    func testQuickAddListPickerRows() throws {
        try add("快速添加·清单候选", width: 250) {
            VStack(alignment: .leading, spacing: 0) {
                MenuRowProbe(title: "个人成长与长期学习计划", symbol: "list.bullet")
                MenuRowProbe(title: "本周待办", symbol: "list.bullet")
            }
            .padding(WFSpace.sm)
        }
    }

    // MARK: - 量测

    private func add(_ name: String, width: CGFloat, @ViewBuilder content: () -> some View) throws {
        let host = NSHostingView(rootView: content().frame(width: width).background(Color.white))
        host.appearance = NSAppearance(named: .aqua)
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: width, height: 700),
                              styleMask: [.borderless], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.appearance = NSAppearance(named: .aqua)
        window.contentView = host
        window.orderFront(nil)
        host.layoutSubtreeIfNeeded()
        RunLoop.main.run(until: Date().addingTimeInterval(0.15))
        host.layoutSubtreeIfNeeded()
        let height = max(host.fittingSize.height, 1)
        host.frame = NSRect(x: 0, y: 0, width: width, height: height)
        host.layoutSubtreeIfNeeded()
        defer { window.close() }
        rows.append((name, width, rightmostInk(of: host, width: width, height: height)))
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
                if abs(pixel.redComponent - background.redComponent) > 0.04
                    || abs(pixel.greenComponent - background.greenComponent) > 0.04
                    || abs(pixel.blueComponent - background.blueComponent) > 0.04 {
                    hit = true; break
                }
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

    private func environment() throws -> (AppEnvironment, UUID) {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("popup-cov2-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: directory) }
        let app = AppEnvironment(directory: directory)
        _ = app.taskWorkspace.createTask(title: "写周报", in: .today)
        let id = try XCTUnwrap(app.taskWorkspace.allTasks.first?.id)
        return (app, id)
    }
}

/// 补漏第三轮：`NSPanel` 直接建窗的三个浮层（不走 `AnchoredPropertyPanel`）。
@MainActor
final class PopupWidthThirdPassTests: XCTestCase {

    private var rows: [(String, CGFloat, CGFloat)] = []

    override func tearDown() {
        for (name, assigned, ink) in rows {
            let slack = assigned - ink
            let verdict = ink <= 0 ? "量不出" : (slack > 60 ? "偏宽" : (slack < 4 ? "偏紧" : "合适"))
            print(String(format: "COV3|%@|%.0f|%.0f|%.0f|%@", name, assigned, ink, slack, verdict))
        }
        super.tearDown()
    }

    func testReminderPanel() throws {
        let now = Date()
        let delivery = ReminderDelivery(id: UUID().uuidString, kind: .task,
                                        sourceID: UUID(), occurrence: nil,
                                        title: "写季度总结的第二版草稿并同步给团队",
                                        body: "今天 18:00 到期 · 收集箱",
                                        originalDate: now, fireDate: now)
        try add("任务提醒弹窗", width: 350) {
            VStack(alignment: .leading, spacing: 14) {
                Label(delivery.title, systemImage: "bell.badge").font(.headline).lineLimit(2)
                Text(delivery.body).font(.subheadline).foregroundStyle(.secondary)
                HStack {
                    Button("打开任务") {}
                    Spacer()
                    Button("稍后提醒") {}
                    Button("停止") {}
                }
            }
            .padding(20)
        }
    }

    /// Mini 专注窗：真实内容有 44pt 计时、阶段标签、按钮行（`FocusCompactPresentation`）。
    /// 手工仿写会漏掉尾部元素、量出偏小，所以这里**按真实结构**复刻并只做宽度参考。
    func testFocusMiniWindow() throws {
        // 真实视图是 `.frame(maxWidth: .infinity, maxHeight: .infinity)` 撑满窗口：
        // 宽度由窗口（300）决定，不是内容决定。余量是它自己居中的留白，不动。
        try add("Mini 专注窗（内容区，撑满型）", width: 300) {
            VStack(spacing: 16) {
                Text("计时").font(.headline)
                Text("25:00").font(.system(size: 44, weight: .light)).monospacedDigit()
                Text("专注中").font(.caption)
                HStack(spacing: 12) {
                    Button("暂停") {}
                    Button("结束") {}
                }
            }
            .padding(20)
        }
    }

    /// Slash 菜单：宽度由 `SlashMenuMetrics` 的行内元素（14 槽 + 图标 + 11 隙 +
    /// 文本 + 12 尾白）算出，不是"文字多宽就多宽"。这里只量**真实行结构**。
    func testSlashMenuCompact() throws {
        // 160 是 `SlashMenuMetrics.width` 的固定口径（14 槽 + 图标 + 11 隙 + 12 尾白），
        // 不是"文字多宽就多宽"。菜单类刻意等宽，不动。
        try add("Slash 菜单（compact，等宽型）", width: SlashMenuMetrics.width) {
            VStack(alignment: .leading, spacing: 0) {
                ForEach(["正文", "标题 1", "清单", "分割线"], id: \.self) { title in
                    HStack(spacing: 0) {
                        Color.clear.frame(width: SlashMenuMetrics.itemLeading)
                        Image(systemName: "circle").frame(width: SlashMenuMetrics.glyphSlot)
                        Color.clear.frame(width: SlashMenuMetrics.glyphGap)
                        Text(title).font(.system(size: SlashMenuMetrics.labelSize)).lineLimit(1)
                        Spacer(minLength: 0)
                        Color.clear.frame(width: SlashMenuMetrics.itemTrailing)
                    }
                    .frame(height: SlashMenuMetrics.rowHeight)
                    .padding(.horizontal, SlashMenuMetrics.itemInset)
                }
            }
            .padding(SlashMenuMetrics.padding)
        }
    }

    private func add(_ name: String, width: CGFloat, @ViewBuilder content: () -> some View) throws {
        let host = NSHostingView(rootView: content().frame(width: width).background(Color.white))
        host.appearance = NSAppearance(named: .aqua)
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: width, height: 700),
                              styleMask: [.borderless], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.appearance = NSAppearance(named: .aqua)
        window.contentView = host
        window.orderFront(nil)
        host.layoutSubtreeIfNeeded()
        RunLoop.main.run(until: Date().addingTimeInterval(0.15))
        host.layoutSubtreeIfNeeded()
        let height = max(host.fittingSize.height, 1)
        host.frame = NSRect(x: 0, y: 0, width: width, height: height)
        host.layoutSubtreeIfNeeded()
        defer { window.close() }
        rows.append((name, width, rightmostInk(of: host, width: width, height: height)))
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
                if abs(pixel.redComponent - background.redComponent) > 0.04
                    || abs(pixel.greenComponent - background.greenComponent) > 0.04
                    || abs(pixel.blueComponent - background.blueComponent) > 0.04 {
                    hit = true; break
                }
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

    private func environment() throws -> (AppEnvironment, UUID) {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("popup-cov2-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: directory) }
        let app = AppEnvironment(directory: directory)
        _ = app.taskWorkspace.createTask(title: "写周报", in: .today)
        let id = try XCTUnwrap(app.taskWorkspace.allTasks.first?.id)
        return (app, id)
    }
}

/// 补漏第三轮：`NSPanel` 直接建窗的三个浮层（不走 `AnchoredPropertyPanel`）。
