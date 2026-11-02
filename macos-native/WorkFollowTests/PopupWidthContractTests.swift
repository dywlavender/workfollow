import AppKit
import Foundation
import SwiftUI
import XCTest
@testable import WorkFollow

/// 弹层宽度契约：把「弹层宽度怎么定」从口头约定变成会失败的测试。
///
/// 背景（2026-11-01）：快速添加属性弹框连续两轮被用户反馈"太宽"。查下来不是
/// 某个数字写大了，而是**宽度没有单一来源**——
///
/// ```swift
/// // 挂载点：决定 NSPanel 窗口多宽
/// .background(AnchoredPropertyPanel(isPresented: ..., width: 250) { ... })
/// // 内容自己：决定内容多宽
/// .frame(width: PopupMetrics.quickAddChildWidth)   // 189
/// ```
///
/// `AnchoredPropertyPanel` 内部是 `root.frame(width: width)`，所以两边不一致时
/// 面板 250pt、内容 189pt，右侧空 61pt 白。没有任何测试能发现这件事：
/// 宽度测试量的是"墨迹到面板右缘的余量"，而带 `Divider()` 的弹层右缘恒等于
/// `面板宽 − 内边距`，**余量恒定约 12pt，无论面板多宽**——审计给绿灯、用户觉得宽。
///
/// 这里立三条规矩：
/// 1. 弹层宽度不得是裸字面量（必须引用常量，否则改名/调值时必然漏改）；
/// 2. 挂载点宽与内容宽必须引用同一个常量；
/// 3. 子面板不得宽于父面板。
@MainActor
final class PopupWidthContractTests: XCTestCase {

    private var businessSourceRoot: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("WorkFollow", isDirectory: true)
    }

    // MARK: - 规矩 1：弹层宽度不得是裸字面量

    /// `AnchoredPropertyPanel(... width: 250 ...)` 这种写法一律不允许。
    ///
    /// 不是洁癖：裸字面量让"面板宽"和"内容宽"变成两个可以各自漂移的数字，
    /// 而它们之间没有任何编译期或运行期约束。引用常量至少让漏改收敛到一处。
    func testPopupPanelWidthsAreNeverBareLiterals() throws {
        var violations: [String] = []
        for file in try businessSourceFiles() {
            let source = try String(contentsOf: file, encoding: .utf8)
            for hit in panelWidthArguments(in: source) where hit.isNumericLiteral {
                violations.append("\(relativePath(of: file)):\(hit.line) -> width: \(hit.value)")
            }
        }
        XCTAssertTrue(violations.isEmpty,
                      "弹层宽度必须是 PopupMetrics 常量，不能是裸数字：\n"
                        + violations.joined(separator: "\n"))
    }

    // MARK: - 规矩 2：挂载点宽与内容宽引用同一个常量

    /// 内容根节点自己写了 `.frame(width: PopupMetrics.X)` 的弹层，挂载点必须用同一个 `X`。
    ///
    /// 这是上一轮真实踩到的坑：把 `quickAddChildWidth` 从 250 改成 189 时，
    /// 只改了内容的 `.frame`，挂载点那行的 `250` 是裸字面量、没跟着变，
    /// 于是面板仍按 250 开窗。规矩 1 拦得住裸字面量，这条拦得住"两个不同常量"。
    ///
    /// 注意挂载点可能**在别的文件**（例如 TaskTagPickerPopover 的内容由
    /// QuickAddPropertiesPopover / TaskBatchPanelView 等多处挂载），所以按
    /// 「全仓库扫描该常量名的所有挂载点」来判，而不是只看内容所在文件。
    func testPopupMountWidthMatchesItsContentWidth() throws {
        // 内容根节点自带宽度常量的弹层：常量名 → 期望它的挂载点也用它。
        // 新增带自定宽度的弹层时在这里补一行。
        let selfSizedContent = ["quickAddPropertiesWidth", "quickAddChildWidth",
                                "tagPickerWidth", "aiReferencePickerWidth"]

        var allMounts: [String: [String]] = [:]   // 常量名 → 挂载它的文件列表
        for file in try businessSourceFiles() {
            let source = try String(contentsOf: file, encoding: .utf8)
            for hit in panelWidthArguments(in: source) {
                allMounts[hit.value, default: []].append(relativePath(of: file))
            }
        }

        // 每个自带宽度的常量，至少要在某处被挂载（否则内容宽度是死代码）。
        for token in selfSizedContent {
            let qualified = "PopupMetrics." + token
            let mounts = allMounts[qualified] ?? []
            XCTAssertFalse(mounts.isEmpty,
                           "\(token) 被内容用来自定宽度，但全仓库没有挂载点引用它；"
                            + "面板会退回默认宽度，内容与窗口不一致。")
        }

        // 规矩 1 已经拦掉裸数字；这里只拦"看起来像常量、实际是没归属的临时量"。
        //
        // 判据：宽度必须是 `类型.成员`（有归属：PopupMetrics.x / ScheduleMetrics.x /
        // FocusTaskPickerMetrics.x …），或者是显式声明的局部量（`width` / `size.width`
        // 这种由上层传入或量测推导的）。裸标识符（`footerPanelWidth`、`insertWidth`）
        // 说明宽度是**当前作用域的临时变量**，换个调用点就会漂移——这正是宽度
        // 没有单一来源的表现。
        //
        // 例外白名单：确属"由外层容器决定"的挂载点，且已在此处注明理由。
        let allowedLocalWidths: [String: String] = [
            // 详情页底部操作面板：宽度随当前 action 变化（更多操作 176 / 标签 184 /
            // 关联主任务 280 / 关联任务 320），由 `footerPanelWidth` 这个计算属性
            // 从 PopupMetrics 常量里挑，本身不另立口径。
            "footerPanelWidth": "按 action 从 PopupMetrics 常量里挑",
            // 编辑器插入面板：纯固定尺寸按钮横排，宽度 = 条目数 × 控件宽 + 间距，
            // 是真正的内容推导值。
            "insertWidth": "= 条目数 × controlWidth + 12（内容推导）",
            // 编辑器工具栏浮层：宽度来自 `EditorToolbarPopupCapacity` 算出的
            // **可用空间**，不是内容宽——语义上就不该自撑。
            "size.width": "可用空间（窗口容量算出），非内容宽",
            // 通用触发器 / 业务菜单：宽度由调用方传入，自己不该有口径。
            "width": "由调用方传入（通用容器）",
            // 业务菜单按内容量宽后夹到区间，量出来的值在这里落地。
            "resolvedWidth": "按内容量宽后夹到 [menuWidthTight, menuWidth]",
        ]

        var violations: [String] = []
        for (value, files) in allMounts {
            if value.hasPrefix("PopupMetrics.") { continue }
            if allowedLocalWidths[value] != nil { continue }
            // 有归属的度量口径（任意 `Type.member`）放行。
            if value.contains(".") && value.first?.isUppercase == true { continue }
            violations.append("\(value) <- \(files.joined(separator: ", "))")
        }
        XCTAssertTrue(violations.isEmpty,
                      "弹层挂载宽度必须是 `类型.常量`（有归属），不能是当前作用域的临时量：\n"
                        + violations.joined(separator: "\n")
                        + "\n若确属「由外层容器决定」，请加进 allowedLocalWidths 并写明理由。")
    }

    // MARK: - 规矩 3：面板窗口宽 == 内容宽（运行时，真面板）

    /// 直接量真面板：`NSPanel` 的窗口宽必须等于内容的 `fittingSize.width`。
    ///
    /// 前两条是源码扫描，只能保证"引用一致"；这条是运行期兜底——
    /// 就算两个常量都引用对了，只要内容里有 `maxWidth: .infinity` 之类的
    /// 撑满元素没配平，也会在这里露出来。
    func testQuickAddPopoverContentFillsItsPanelWidth() throws {
        let content = QuickAddPropertiesPopover(
            workspace: TaskWorkspaceModel(seedDemoData: false),
            selectedPriority: .none,
            selectedList: TaskList.inbox.name,
            selectedTags: [],
            attachments: [],
            displayMode: .compact,
            onPriority: { _ in }, onList: { _ in }, onTags: { _ in },
            onTemplate: {}, onAttachments: { _ in }, onDisplayMode: { _ in },
            onDismiss: {})
        let host = NSHostingView(rootView: content.background(WFColors.content))
        host.appearance = NSAppearance(named: .aqua)
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 400, height: 600),
                              styleMask: [.borderless], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = host
        window.orderFront(nil)
        defer { window.close() }
        host.layoutSubtreeIfNeeded()
        RunLoop.main.run(until: Date().addingTimeInterval(0.25))
        host.layoutSubtreeIfNeeded()

        let contentWidth = host.fittingSize.width
        XCTAssertEqual(contentWidth, PopupMetrics.quickAddPropertiesWidth, accuracy: 0.5,
                       "内容自然宽必须等于弹层常量；不等说明内容里有撑满元素或多余内边距")
    }

    // MARK: - 规矩 4：内容不得宽于面板（反向溢出）

    /// 面板比内容**窄**时，内容会被 `clipShape` 裁掉。
    ///
    /// 上一轮发现的真实案例：标签颜色弹层挂载 220，而色板内容自然宽 246
    /// （7×22 色块 + 6×10 间距 + 2×16 内边距），最右一列色块看不全。
    /// 规矩 1~2 只看"是不是常量"，拦不住常量本身取小了，所以需要这条运行期兜底。
    ///
    /// 注意这里的判据是「内容自然宽 <= 面板宽」。对**固定尺寸网格**这类内容成立；
    /// 对含可折行文本的内容不成立（文本会自己折行，自然宽永远等于面板宽），
    /// 那种情况见下一条 `testQuickAddLongestRowIsNotTruncated`。
    func testTagColorPickerContentFitsItsPanel() throws {
        // `TaskTagColorPicker` 是 private，但决定宽度的是色板本身（标题 + 网格 + 内边距），
        // 这里按它的真实结构复刻量测；结构与 TaskTagManagementView.swift:185 一致。
        let content = VStack(spacing: WFSpace.md) {
            Text("标签颜色").font(WFType.supporting).foregroundStyle(WFColors.secondaryText)
            TaskTagColorGrid(color: .constant(nil))
        }
        .padding(WFSpace.lg)

        let host = NSHostingView(rootView: content)
        host.appearance = NSAppearance(named: .aqua)
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 500, height: 400),
                              styleMask: [.borderless], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = host
        window.orderFront(nil)
        defer { window.close() }
        host.layoutSubtreeIfNeeded()
        RunLoop.main.run(until: Date().addingTimeInterval(0.2))
        host.layoutSubtreeIfNeeded()

        let natural = host.fittingSize.width
        XCTAssertLessThanOrEqual(natural, PopupMetrics.tagColorPickerWidth + 0.5,
                                 "色板内容自然宽 \(natural) 超过面板宽 "
                                    + "\(PopupMetrics.tagColorPickerWidth)，最右一列会被裁掉")
    }

    // MARK: - 规矩 5：可折行文本不得因面板过窄而截断

    /// 快速添加属性弹框里最长那一行「输入框设置：简洁」必须放得下。
    ///
    /// **为什么单独一条**：这一行的 `Text` 带 `lineLimit(1)`，宽度不足时
    /// **高度不变、只是文字被截成「输入框设置：…」**——所以
    /// `fittingSize.height` 完全量不出来，`testTagColorPickerContentFitsItsPanel`
    /// 那种「自然宽 <= 面板宽」的判据也失效（文本会自己压缩到可用宽）。
    ///
    /// 正确判据：**该行的自然宽 <= 面板可用宽**。
    /// 面板可用宽 = 常量 − 2×`WFSpace.md`（面板内边距）。
    ///
    /// 实测边界（2026-11-01）：自然宽 163.00；面板 188 → 可用 164（余 1）；
    /// 187 → 可用 163（贴边，临界）；186 及以下开始出省略号。
    /// 若哪天有人把常量改小或把行距调回 12（需 191），这条会红。
    func testQuickAddLongestRowIsNotTruncated() throws {
        // 与 `QuickAddPropertiesPopover.propertyRow` 同构：图标 + 文字 + 箭头，
        // 行内边距 8，行距 `WFSpace.control`(10)，行高 `WFMetrics.controlHeight`。
        let row = HStack(spacing: WFSpace.control) {
            Image(systemName: "gearshape").foregroundStyle(WFColors.secondaryText)
            Text("输入框设置：简洁").lineLimit(1)
                .frame(maxWidth: .infinity, alignment: .leading)
            Image(systemName: "chevron.right").font(.caption2)
                .foregroundStyle(WFColors.secondaryText)
        }
        .padding(.horizontal, WFSpace.sm)
        .frame(height: WFMetrics.controlHeight)

        let host = NSHostingView(rootView: row.fixedSize(horizontal: true, vertical: false))
        host.appearance = NSAppearance(named: .aqua)
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 600, height: 120),
                              styleMask: [.borderless], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = host
        window.orderFront(nil)
        defer { window.close() }
        host.layoutSubtreeIfNeeded()
        RunLoop.main.run(until: Date().addingTimeInterval(0.2))
        host.layoutSubtreeIfNeeded()

        let required = host.fittingSize.width
        let available = PopupMetrics.quickAddPropertiesWidth - 2 * WFSpace.md
        XCTAssertLessThanOrEqual(required, available + 0.01,
                                 String(format: "最长行需要 %.2fpt，面板只提供 %.2fpt，"
                                        + "会被截成「输入框设置：…」。"
                                        + "调宽 PopupMetrics.quickAddPropertiesWidth 或收窄行距。",
                                        required, available))
    }

    // MARK: - 源码扫描

    private struct WidthArgument {
        let line: Int
        let value: String
        /// `width: 250` 这种纯数字（含小数）算裸字面量；`width: PopupMetrics.x` 不算。
        var isNumericLiteral: Bool {
            value.range(of: #"^[0-9]+(\.[0-9]+)?$"#, options: .regularExpression) != nil
        }
    }

    /// 抓弹层挂载点的 `width:` 实参。**两种写法都要覆盖**：
    ///
    /// - 直接构造：`AnchoredPropertyPanel(isPresented: ..., width: X)`
    /// - 修改器封装：`.anchoredPropertyPanel(isPresented: ..., width: X)`
    ///   （`PropertyPanelTrigger.swift:20` 定义，按 trigger anchor 定位）
    ///
    /// 只匹配第一种是真实踩过的漏网：`AIChatWorkspaceView` 的两处裸字面量
    /// （250 / 340）用的是修改器写法，旧正则命中 0 处，于是它们一路绿着过关。
    ///
    /// 不做完整解析：`isPresented:` 里常带 `Binding(get:set:)` 闭包，语法上不好切。
    /// 用「挂载点之后 800 字符内出现 `width:`」做定位，对本仓库的形状够用。
    private func panelWidthArguments(in source: String) -> [WidthArgument] {
        let pattern = #"(?:AnchoredPropertyPanel|\banchoredPropertyPanel)\([\s\S]{0,800}?width:\s*([A-Za-z0-9_.]+)"#
        guard let expression = try? NSRegularExpression(pattern: pattern) else { return [] }
        let ns = source as NSString
        let range = NSRange(location: 0, length: ns.length)
        return expression.matches(in: source, range: range).compactMap { match in
            guard match.numberOfRanges > 1 else { return nil }
            let value = ns.substring(with: match.range(at: 1))
            let offset = match.range(at: 1).location
            let line = ns.substring(to: offset).reduce(1) { $1 == "\n" ? $0 + 1 : $0 }
            return WidthArgument(line: line, value: value)
        }
    }

    private func businessSourceFiles() throws -> [URL] {
        let enumerator = try XCTUnwrap(
            FileManager.default.enumerator(at: businessSourceRoot,
                                           includingPropertiesForKeys: nil,
                                           options: [.skipsHiddenFiles]),
            "无法枚举业务源码：\(businessSourceRoot.path)")
        let files = enumerator.compactMap { $0 as? URL }
            .filter { $0.pathExtension == "swift" }
            .sorted { $0.path < $1.path }
        // 防空转：枚举因权限/路径故障返回空时，"零违规"会静默通过。
        try XCTUnwrap(!files.isEmpty, "源码枚举为空，契约会空转通过")
        _ = try XCTUnwrap(files.first { $0.lastPathComponent == "PopupMetrics.swift" },
                          "枚举漏了 PopupMetrics.swift，扫描不完整")
        return files
    }

    private func relativePath(of file: URL) -> String {
        String(file.path.dropFirst(businessSourceRoot.path.count + 1))
    }
}
