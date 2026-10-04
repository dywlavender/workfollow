import SwiftUI

/// 详情右栏空态（阶段3）：统一空态组件的线稿插画，替换原三个占位星形
/// （原实现自认 "artwork remains pending"）。保持壳层既有契约：
/// 纯装饰（不可交互、无引导文案），`.emptyContent` 锚点仍包住 176 宽的
/// 插画本体——契约测试锁定宽度 176 与面板内居中，勿改组件的固定宽度。
struct TaskEmptyInspectorView: View {
    var body: some View {
        TaskEmptyStateView(style: .inspector)
            .inspectorRenderAnchor(.emptyContent)
            .padding(.horizontal, TaskInspectorMetrics.horizontalPadding)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
    }
}
