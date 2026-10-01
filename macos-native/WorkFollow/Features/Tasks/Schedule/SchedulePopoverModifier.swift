import SwiftUI

extension View {

    /// 统一的「无箭头锚定日程浮层」（Arrowless Anchored Schedule Popover）。
    ///
    /// 契约（macOS 27 实测结论）：
    /// - SwiftUI `.popover` **不传 `arrowEdge`**（默认 nil）→ 不画三角箭头，
    ///   得到系统圆角浮层，同时保留系统 popover 的定位、屏幕边缘避让、键盘
    ///   焦点、环境注入与「点击外部 / Esc 关闭」。
    /// - 所有日程入口（任务详情 / 任务行 / 快速添加 / 截止日期 / 四象限 /
    ///   快速组合器）统一走这一个；属性编辑在主面板内部展开。
    ///   修饰符——避免各处 popover 配置（arrowEdge / 背景）再次漂移。
    /// - `arrowEdge` 的默认行为属系统实现细节：macOS 14–26 若仍强制画箭头，
    ///   兼容层再补（见 schedule-options-flutter-parity-2026-09-28.md 的兼容策略）。
    func schedulePopover<Content: View>(
        isPresented: Binding<Bool>,
        @ViewBuilder content: @escaping () -> Content
    ) -> some View {
        modifier(SchedulePopoverPresentation(isPresented: isPresented, panel: content))
    }
}

private struct SchedulePopoverPresentation<Panel: View>: ViewModifier {
    @Binding var isPresented: Bool
    let panel: () -> Panel
    @StateObject private var owner = PopupPresentingWindow()

    func body(content: Content) -> some View {
        content
            .background(PopupPresentingWindowReader(owner: owner).allowsHitTesting(false))
            .popover(isPresented: $isPresented) {
                panel()
                    .environment(\.popupPresentingWindow, owner)
                    .presentationBackground(WFColors.content)
            }
    }
}
