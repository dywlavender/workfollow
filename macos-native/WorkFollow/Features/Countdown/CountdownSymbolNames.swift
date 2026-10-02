import Foundation

/// 倒数纪念日图标的**中文名**（纯展示）。
///
/// 域模型里 `CountdownEvent.symbolOptions` 只存 SF Symbol 名——`symbol` 是持久化
/// 字段，往里加「名字」就是改数据模型，所以名字留在视图层。
///
/// **为什么必须有这一层**：图标网格原来一个文字都没有，只能靠图形猜用途
/// （`cross.case` 画的是医疗箱、`party.popper` 是彩带、`graduationcap` 是学士帽）；
/// 无障碍标签更是直接把符号名当标签传下去（`accessibilityLabel(option)`），
/// 中文界面里读屏念的是一串英文符号名。参照图那边给的正是**带名字的选项**——
/// 名字本身就是用户据以挑选的那层信息。
///
/// 取名按**用途**而不是**图形**：用户是拿它记事的，不是按形状挑的
/// （`cross.case` 图形是医疗箱，用途叫「健康」）。
enum CountdownSymbolNames {
    /// 与 `CountdownEvent.symbolOptions` **一一对应**；有测试盯着，
    /// 那边加一个图标而这里漏一个，测试就挂。
    static let all: [String: String] = [
        "heart": "心意",
        "gift": "礼物",
        "hourglass": "倒数",
        "flag": "目标",
        "star": "纪念",
        "bell": "提醒",
        "party.popper": "庆祝",
        "birthday.cake": "生日",
        "airplane": "旅行",
        "graduationcap": "毕业",
        "cross.case": "健康",
        "house": "家庭",
    ]

    /// 取不到名字时回退成符号名本身——宁可显示英文，也不要显示空白。
    static func name(for symbol: String) -> String {
        all[symbol] ?? symbol
    }
}
