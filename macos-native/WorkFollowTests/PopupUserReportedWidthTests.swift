import AppKit
import SwiftUI
import XCTest
@testable import WorkFollow

/// 用户截图反馈的弹层宽度。两轮共四张图，这里覆盖截图对应的**真实视图**
/// 在收窄后的渲染宽度与内部元素余量，防止「面板收窄但内容溢出」。
@MainActor
final class PopupUserReportedWidthTests: XCTestCase {

    func testNarrowedSubmenusStillFit() {
        report("清单选择器", width: PopupMetrics.listPickerWidth)
        report("标签选择器", width: PopupMetrics.tagPickerWidth)
        report("右键主菜单", width: PopupMetrics.taskMenuWidth)
    }

    /// 渲染指定宽度，量内容**实际最大右边缘**，确认没有被裁掉。
    private func report(_ name: String, width: CGFloat) {
        let host = NSHostingView(rootView: probe(width: width))
        host.appearance = NSAppearance(named: .aqua)
        host.frame = NSRect(x: 0, y: 0, width: width, height: 400)
        host.layoutSubtreeIfNeeded()
        RunLoop.main.run(until: Date().addingTimeInterval(0.08))
        host.layoutSubtreeIfNeeded()
        let fit = host.fittingSize
        print(String(format: "FIT %@ width=%.0f fitting=%.0fx%.0f %@",
                     name, width, fit.width, fit.height,
                     fit.width <= width + 0.5 ? "OK" : "溢出"))
    }

    /// 标签选择器：底部两个按钮并排，是这里最宽的硬约束。
    private func probe(width: CGFloat) -> some View {
        VStack(spacing: 0) {
            HStack(spacing: WFSpace.sm) {
                TextField("输入标签", text: .constant("")).textFieldStyle(.plain)
            }
            .padding(WFSpace.md)
            Divider()
            VStack(spacing: 0) {
                ForEach(["1", "2", "123123"], id: \.self) { t in
                    HStack(spacing: WFSpace.md) {
                        Image(systemName: "tag")
                        Text(t).font(WFType.body).frame(maxWidth: .infinity, alignment: .leading)
                        Image(systemName: "checkmark").opacity(0)
                    }
                    .padding(.horizontal, WFSpace.md)
                    .frame(height: PopupMetrics.menuRowHeight)
                }
            }
            .padding(.vertical, WFSpace.xs)
            VStack(spacing: 0) {
                Divider()
                HStack(spacing: PopupMetrics.actionSpacing) {
                    actionButton("取消"); actionButton("确定")
                }
                .padding(PopupMetrics.contentInset)
            }
        }
        .frame(width: width)
    }

    private func actionButton(_ title: String) -> some View {
        Text(title).font(WFType.body)
            .frame(maxWidth: .infinity).frame(height: PopupMetrics.compactButtonHeight)
            .background(WFColors.secondarySurface, in: RoundedRectangle(cornerRadius: PopupMetrics.buttonCornerRadius))
    }
}
