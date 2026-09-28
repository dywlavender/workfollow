import Foundation

enum WFSpace {
    static let xs: CGFloat = 4
    static let sm: CGFloat = 8
    static let md: CGFloat = 12
    static let lg: CGFloat = 16
    static let xl: CGFloat = 20
    static let xxl: CGFloat = 24
    static let page: CGFloat = 32

    // 与 Flutter `WorkFollowSpacing` 的语义间距角色一一对应的部分。上面的
    // 前后端通用刻度不足以表达日历与四象限的实测节奏（月格内边距 3、象限内
    // 边距 14、行分隔线缩进 29 等），这些值原样照抄 Flutter，改动两处会同时
    // 漂移，所以只在这里定义一次。
    static let hairline: CGFloat = 1
    static let micro: CGFloat = 2
    static let tight: CGFloat = 3
    static let dense: CGFloat = 5
    static let inline: CGFloat = 6
    static let compact: CGFloat = 7
    static let compactInset: CGFloat = 9
    static let control: CGFloat = 10
    static let cardInset: CGFloat = 10
    static let relaxed: CGFloat = 14
    static let nestedContentIndent: CGFloat = 29
    /// 日历页工具条与页头共用的左右／上内边距。
    static let pageHorizontal: CGFloat = 26
    static let pageTop: CGFloat = 23
}
