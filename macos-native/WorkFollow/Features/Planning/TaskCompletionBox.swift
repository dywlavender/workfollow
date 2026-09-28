import SwiftUI

/// 任务勾选框：任何位置上的任务都用这一个形状标记。
///
/// 对齐 Flutter `widgets/task_completion_box.dart`。圆角是方框自身边长的比例，
/// 不是各页各挑一个数：任务行里 14.58、日历条上 9.9，两者是同一个形状按比例
/// 缩放，所以小框不会退化成圆圈或尖角方块，整个家族也能只改边长来缩放。
///
/// 它只表达状态、不接收点击。凡是可以勾任务的地方，这个方框都落在某个本来就是
/// 目标的控件里（任务行的按钮、编辑栏的按钮），再套一个更小的目标只会多一个瞄不
/// 准的东西。
///
/// 一处例外：日历条与周视图胶囊上的框由调用方外扩一圈命中区（
/// `WFCalendarMetrics.taskBarCheckboxHitPadding`）自己接点击——原版那里点了开的是
/// 编辑器，本工程按需求让框直接勾选。形状仍由这里定义，命中区归调用方。
struct TaskCompletionBox: View {
    /// 方框边长，圆角与描边都从它推出来。
    let size: CGFloat
    let completed: Bool

    /// 未完成时的描边色。不传取三级墨色——日历条上的框是中性灰，不跟清单色。
    var openColor: Color?

    /// 完成时的填充色。不传取完成态那一档（`taskCompletedCheckbox`）。
    var doneColor: Color?

    /// 圆角 = 边长 × 4.5 / 18。4.5 是任务行槽位（18pt）的角，也是 Flutter 自己
    /// 的 Checkbox 画出来的角。
    private var radius: CGFloat { size * 0.25 }

    /// 描边随之等比变细，但不细到看不出有边。
    private var borderWidth: CGFloat { max(1, size * 1.5 / 18) }

    var body: some View {
        if completed {
            RoundedRectangle(cornerRadius: radius)
                .fill(doneColor ?? WFColors.taskCompletedCheckbox)
                .frame(width: size, height: size)
                .overlay {
                    // 勾是从内容色切出来的：底越浅，勾与底的对比也越弱，两者同步。
                    Image(systemName: "checkmark")
                        .font(.system(size: size * 0.68, weight: .semibold))
                        .foregroundStyle(WFColors.content)
                }
        } else {
            RoundedRectangle(cornerRadius: radius)
                .strokeBorder(openColor ?? WFColors.secondaryText, lineWidth: borderWidth)
                .frame(width: size, height: size)
        }
    }
}
