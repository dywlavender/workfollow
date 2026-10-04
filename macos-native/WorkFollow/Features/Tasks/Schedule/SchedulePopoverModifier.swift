import SwiftUI

enum ScheduleTrigger: Hashable { case date, recurrence }

private struct ScheduleTriggerAnchors: PreferenceKey {
    static var defaultValue: [ScheduleTrigger: Anchor<CGRect>] { [:] }
    static func reduce(value: inout [ScheduleTrigger: Anchor<CGRect>],
                       nextValue: () -> [ScheduleTrigger: Anchor<CGRect>]) {
        value.merge(nextValue(), uniquingKeysWith: { _, latest in latest })
    }
}

extension View {
    /// Mark the actual control, not its row/header/container, as a popup trigger.
    func scheduleTrigger(_ trigger: ScheduleTrigger = .date) -> some View {
        anchorPreference(key: ScheduleTriggerAnchors.self, value: .bounds) { [trigger: $0] }
    }

    /// 统一的「无箭头锚定日程浮层」（Arrowless Anchored Schedule Popover）。
    ///
    /// 契约：共享 borderless NSPanel 从架构上保证无箭头；主面板尺寸由
    /// SchedulePopoverContainer 决定，属性子卡片不参与父面板测量。
    /// - 所有日程入口（任务详情 / 任务行 / 快速添加 / 截止日期 / 四象限 /
    ///   快速组合器）统一走这一个；属性编辑由独立行锚定子卡片呈现。
    ///   修饰符——避免各处呈现壳、焦点与关闭规则再次漂移。
    func schedulePopover<Content: View>(
        isPresented: Binding<Bool>,
        trigger: ScheduleTrigger = .date,
        explicitAnchor: CGRect? = nil,
        @ViewBuilder content: @escaping () -> Content
    ) -> some View {
        modifier(SchedulePopoverPresentation(isPresented: isPresented, trigger: trigger,
                                             explicitAnchor: explicitAnchor, panel: content))
    }
}

private struct SchedulePopoverPresentation<Panel: View>: ViewModifier {
    @Binding var isPresented: Bool
    let trigger: ScheduleTrigger
    let explicitAnchor: CGRect?
    let panel: () -> Panel
    @StateObject private var owner = PopupPresentingWindow()

    func body(content: Content) -> some View {
        content
            .background(PopupPresentingWindowReader(owner: owner).allowsHitTesting(false))
            .overlayPreferenceValue(ScheduleTriggerAnchors.self) { anchors in
                GeometryReader { geometry in
                    // Direct-button hosts need no marker. Container hosts must
                    // mark their trigger or supply the context-click rectangle.
                    let rect = explicitAnchor ?? anchors[trigger].map { geometry[$0] }
                        ?? CGRect(origin: .zero, size: geometry.size)
                    AnchoredPropertyPanel(isPresented: $isPresented,
                                          width: ScheduleMetrics.panelWidth,
                                          placement: .schedule,
                                          focusPolicy: .panelWindow) {
                        panel().environment(\.popupPresentingWindow, owner)
                    }
                    .frame(width: rect.width, height: rect.height)
                    .offset(x: rect.minX, y: rect.minY)
                }
                .allowsHitTesting(false)
            }
    }
}
