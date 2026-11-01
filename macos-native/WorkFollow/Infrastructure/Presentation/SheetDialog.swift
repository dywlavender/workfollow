import SwiftUI

/// 表单类 sheet 的统一外壳：标题 + 分隔线 + 可滚动内容 + 底部操作栏。
///
/// 37 个 sheet 里原来至少有 5 套头部（`DialogHeader` 18 semibold、`WFType.section` 13、
/// `.title3` 20、`.headline`、以及页内自绘模态）和 3 套底部（`DialogFooter`、
/// 裸 HStack、只有关闭 ×），内边距从 16 到 24 都有。结果同一批表单弹出来
/// 标题字号、分割线有无、主按钮是否强调色全不一致。
///
/// 这个外壳只固定**结构**，表单内容仍由各页自己给；宽度与高度由调用方决定，
/// 但会用 `screenHeightLimit` 按屏幕高度收紧，避免小屏上底部按钮被推出屏幕。
struct SheetDialog<Content: View, Status: View>: View {
    let title: String
    var width: CGFloat = SheetDialogMetrics.regularWidth
    /// 内容区的自然高度；`nil` 表示由内容撑开（不强制滚动）。
    var contentHeight: CGFloat? = nil
    var cancelTitle = "取消"
    var primaryTitle = "保存"
    var canSubmit = true
    var cancelIdentifier = ""
    var primaryIdentifier = ""
    /// 给底部两个按钮补测试锚点等装饰；不传则原样。
    var cancelDecoration: (AnyView) -> AnyView = { $0 }
    var primaryDecoration: (AnyView) -> AnyView = { $0 }
    let onCancel: () -> Void
    let onSubmit: () -> Void
    /// 标题对齐。默认左对齐（与 12 个既有弹框一致）；
    /// 清单编辑器按滴答口径用居中大标题。
    var titleAlignment: HorizontalAlignment = .leading
    /// 滴答口径：部分弹框的取消/保存居中（清单编辑）。默认保持右对齐。
    var buttonsCentered = false
    @ViewBuilder let content: () -> Content
    @ViewBuilder let status: () -> Status

    var body: some View {
        VStack(spacing: 0) {
            DialogHeader(title: title, alignment: titleAlignment)
            Divider()
            // ScrollView 不给内容定宽，里面的 HStack 会按固有宽度排布，
            // 固定宽度的标签列会被可伸展控件（TextField）挤到 0。
            // 显式撑满可用宽度，标签列才拿得到 72pt。
            if let contentHeight {
                ScrollView {
                    content()
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(PopupMetrics.formInset)
                }
                .compactScrollbars()
                .frame(height: contentHeight)
            } else {
                ScrollView {
                    content()
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(PopupMetrics.formInset)
                }
                .compactScrollbars()
            }
            // DialogFooter 是 memberwise init，参数必须按声明顺序：
            // buttonWidth 在 cancelIdentifier 之前。
            DialogFooter(cancelTitle: cancelTitle, primaryTitle: primaryTitle,
                         canSubmit: canSubmit, buttonWidth: 72,
                         cancelIdentifier: cancelIdentifier,
                         primaryIdentifier: primaryIdentifier,
                         cancelDecoration: cancelDecoration,
                         primaryDecoration: primaryDecoration,
                         buttonsCentered: buttonsCentered,
                         onCancel: onCancel, onSubmit: onSubmit, status: status)
        }
        .frame(width: width)
        .frame(maxHeight: SheetDialogMetrics.heightLimit)
        .workfollowPopupSurface()
    }
}

extension SheetDialog where Status == EmptyView {
    init(title: String, width: CGFloat = SheetDialogMetrics.regularWidth,
         contentHeight: CGFloat? = nil,
         cancelTitle: String = "取消", primaryTitle: String = "保存", canSubmit: Bool = true,
         cancelIdentifier: String = "", primaryIdentifier: String = "",
         onCancel: @escaping () -> Void, onSubmit: @escaping () -> Void,
         @ViewBuilder content: @escaping () -> Content) {
        self.init(title: title, width: width, contentHeight: contentHeight,
                  cancelTitle: cancelTitle, primaryTitle: primaryTitle, canSubmit: canSubmit,
                  cancelIdentifier: cancelIdentifier, primaryIdentifier: primaryIdentifier,
                  onCancel: onCancel, onSubmit: onSubmit,
                  content: content, status: { EmptyView() })
    }
}

/// 表单弹框的宽度只有四档，新增弹框请从这四档里选，不要再写裸数字。
///
/// 原先散落 11 种宽度（360/380/400/420/440/480/500/520/560/640/760），
/// 彼此只差 20pt，用户连着开几个弹框会觉得窗口在「乱跳」。
enum SheetDialogMetrics {
    /// 窄档：只读详情、单列极短表单（专注记录、清单动态）。
    static let narrowWidth: CGFloat = 360
    /// 紧凑档：单列短表单（清单编辑、标签编辑、摘要预览）。
    static let compactWidth: CGFloat = 400
    /// 常规档：带分组与说明的表单（日历显示设置、过滤器）。
    static let regularWidth: CGFloat = 480
    /// 宽档：双列或多区块（模板库、象限规则、AI 任务拆分）。
    static let wideWidth: CGFloat = 640
    /// 按屏幕高度收紧：留出标题栏与 Dock 的余量，避免底部按钮落到屏幕外。
    static let heightLimit: CGFloat = 640
}

/// 设置类面板：改动即时生效，底部只有一个「完成」。
/// 和 `SheetDialog` 共用标题/滚动区/底栏结构，但不提供「保存」语义——
/// 这类面板没有取消回滚，画一个取消按钮会让人以为可以撤销。
struct SheetSettingsPanel<Content: View>: View {
    let title: String
    var width: CGFloat = SheetDialogMetrics.regularWidth
    var contentHeight: CGFloat? = nil
    var doneTitle = "完成"
    let onDone: () -> Void
    @ViewBuilder let content: () -> Content

    var body: some View {
        VStack(spacing: 0) {
            DialogHeader(title: title)
            Divider()
            if let contentHeight {
                ScrollView { content().padding(PopupMetrics.formInset) }
                    .compactScrollbars().frame(height: contentHeight)
            } else {
                ScrollView { content().padding(PopupMetrics.formInset) }
                    .compactScrollbars()
            }
            VStack(spacing: 0) {
                Divider()
                HStack {
                    Spacer()
                    Button(doneTitle, action: onDone)
                        .buttonStyle(.borderedProminent)
                        .keyboardShortcut(.defaultAction)
                }
                .padding(.horizontal, PopupMetrics.formInset)
                .padding(.vertical, PopupMetrics.formFooterInset)
            }
            .fixedSize(horizontal: false, vertical: true)
        }
        .frame(width: width)
        .frame(maxHeight: SheetDialogMetrics.heightLimit)
        .workfollowPopupSurface()
    }
}
