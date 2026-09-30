import SwiftUI

struct TaskEmptyInspectorView: View {
    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "hand.point.up.left").font(.title2)
            Text("选择一个任务").font(WFType.body)
            Text("标题、备注、日期和子任务都会在这里展开。")
                .font(WFType.caption).multilineTextAlignment(.center)
        }
        .foregroundStyle(WFColors.secondaryText)
        .inspectorRenderAnchor(.emptyContent)
        .padding(.horizontal, TaskInspectorMetrics.horizontalPadding)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
    }
}
