import AppKit
import SwiftUI
import XCTest
@testable import WorkFollow

/// 用户截图指出的两处偏宽弹层（都出自快速添加小卡 `TaskQuickComposer`）：
/// 图1 = 清单菜单（图标 + 清单名 + 勾），图2 = 「更多属性」（提醒 / 重复）。
/// 用真实行结构量自然宽度，给出该收到多少。
@MainActor
final class PopupUserReportedWidthTests: XCTestCase {

    /// 逐类估算「自然宽 -> 夹后宽」，确认各菜单落在合理区间。
    func testResolvedWidths() {
        let cases: [(String, CGFloat, Bool)] = [   // 名称, 自然宽, 有搜索框
            ("更多属性(提醒/重复)", 76, false),
            ("清单菜单(4项带图标+勾)", 136, false),
            ("优先级(4项+旗子)", 176, false),
            ("排序(3项)", 104, false),
            ("分组与排序", 120, false),
            ("列表操作", 132, false),
            ("显示设置", 140, false),
            ("移动到清单(带搜索)", 200, true),
            ("稍后提醒(4项)", 110, false),
        ]
        for (name, natural, hasSearch) in cases {
            let resolved = hasSearch ? PopupMetrics.menuWidth
                : min(max(natural, PopupMetrics.menuWidthTight), PopupMetrics.menuWidth)
            let slack = resolved - natural
            let verdict = slack > 60 ? "偏宽" : (slack < 4 ? "偏紧" : "合适")
            print(String(format: "MENU %@ natural=%.0f resolved=%.0f slack=%.0f %@",
                         name, natural, resolved, slack, verdict))
        }
    }

    func testMeasureRealMenuRows() {
        func natural(_ name: String, @ViewBuilder _ content: () -> some View) {
            let host = NSHostingView(rootView: content())
            host.appearance = NSAppearance(named: .aqua)
            host.layoutSubtreeIfNeeded()
            RunLoop.main.run(until: Date().addingTimeInterval(0.08))
            host.layoutSubtreeIfNeeded()
            print(String(format: "MEAS %@ natural=%.0f", name, host.fittingSize.width))
        }

        // 图2：更多属性 = 「提醒」「重复」两行，无图标。
        natural("更多属性(提醒/重复)") {
            menuRows([("提醒", nil), ("重复", nil)])
        }
        // 图1：清单菜单 = 图标 + 清单名，最长「收集箱」三字 + 勾。
        natural("清单菜单(4项带图标)") {
            menuRows([("收集箱", "tray"), ("个人", "tray"), ("学习", "tray"), ("工作", "tray")],
                     showsCheckmark: true)
        }
    }

    private func menuRows(_ rows: [(String, String?)], showsCheckmark: Bool = false) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(rows, id: \.0) { title, symbol in
                HStack(spacing: 8) {
                    if let symbol { Image(systemName: symbol).frame(width: 16) }
                    Text(title).font(WFType.menu)
                    Spacer(minLength: 8)
                    if showsCheckmark {
                        Image(systemName: "checkmark").font(.system(size: 12, weight: .semibold))
                            .frame(width: 14)
                    }
                }
                .padding(.horizontal, 10)
                .frame(height: PopupMetrics.menuRowHeight)
            }
        }
        .padding(PopupMetrics.menuInset)
    }
}
