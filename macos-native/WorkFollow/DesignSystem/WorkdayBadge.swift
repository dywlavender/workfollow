import SwiftUI

/// 「这一天是放假还是补班」这一个状态本身，不带版式。
///
/// 只有**国务院公布的调休安排**落得到这里：`ChineseWorkCalendar.override` 对普通
/// 周末返回 nil，所以周六周日没有徽标。这是刻意的——周末是常识，把它印成「休」
/// 会把真正需要提醒的那几天（补班的周六、假期中段）淹掉。滴答同此口径：
/// 2026-10 实测 10/10（官方指定周六上班）有红「班」，10/17（普通周六）什么都没有。
///
/// 月网格把它当上标挂在日号右侧，日期弹层把它钉在格子右上角——**落点不同，
/// 记号相同**，所以它是共用的一个视图而不是两处各画一遍。
enum WorkdayBadgeKind: Equatable {
    /// 法定休息日（放假）。
    case rest
    /// 调休上班日（补班）。
    case makeup

    /// 把 `ChineseWorkCalendar.override` 的取值翻成记号：`true` 是补班、`false` 是
    /// 放假、`nil`（普通工作日与普通周末）没有记号。
    ///
    /// 翻译只留这一处。月网格与日期弹层各写一遍 `override ? .makeup : .rest`，
    /// 就是在两个地方维护同一条映射——分开写的两份总会在某一天分叉。
    init?(_ override: Bool?) {
        switch override {
        case .some(true): self = .makeup
        case .some(false): self = .rest
        case .none: return nil
        }
    }
}

/// 徽标的尺寸。只有一个直径，字与它成比例：这是"一个圆里塞一个汉字"，
/// 圆与字各自定值必然在某一档上撑破或缩成墨点。
enum WorkdayBadgeMetrics {
    /// 直径。滴答 2026-10 截图实测：休、班两枚的圆盘**都是 22px（2× 图）= 11pt**，
    /// 直接取参照值。
    ///
    /// 这里走过一段弯路：曾按"我们日号 12.5pt 对滴答 13.5pt"折成 10pt。那条比例
    /// 是拿**墨迹高**跨字体推的（2026-10-04 重测：我们 9.0pt 对滴答 9.5pt，比值
    /// 0.947 而非 0.926），而**圆是几何图形，可以逐像素直接比，根本不需要这层换算**
    /// ——同一把 0.5 覆盖率等值线量出来就是 22px vs 20px。故改回 11。
    static let diameter: CGFloat = 11
    /// 字占直径的比例。滴答白字墨迹高 6.0pt / 直径 11pt = **0.545**，我们实测 0.550
    /// ——两者本来就同比例，所以直径改回 11 后这个值不动，字跟着圆一起长。
    static let glyphRatio: CGFloat = 0.6
}

struct WorkdayBadge: View {
    let kind: WorkdayBadgeKind

    var body: some View {
        Text(kind == .makeup ? "班" : "休")
            .font(.system(size: WorkdayBadgeMetrics.diameter * WorkdayBadgeMetrics.glyphRatio,
                          weight: .semibold))
            .foregroundStyle(WFColors.onWorkdayBadge)
            .frame(width: WorkdayBadgeMetrics.diameter, height: WorkdayBadgeMetrics.diameter)
            .background(Circle().fill(kind == .makeup ? WFColors.makeupWorkday : WFColors.restDay))
            // 徽标是**状态**不是装饰。屏幕阅读器要靠它知道"这格为什么带个红点"，
            // 验收也要靠它读数——没有标签，这件事只能靠看像素来判断。
            .accessibilityLabel(kind == .makeup ? "调休上班" : "放假")
    }
}
