import Foundation

/// 倒数纪念日固定色板的**元数据**：格数、版本、以及老版本下标的搬迁表。
///
/// 这里**不放颜色值**——Domain 不依赖 SwiftUI，颜色在界面侧
/// （`Features/Countdown/CountdownPaletteColors.swift`）。两份靠 `size` 与一条测试
/// 绑在一起：改了这边不改那边，测试会红。
///
/// ## 为什么要有版本号
///
/// 色板从 6 格扩到 12 格（对齐参照实现颜色行的实测色），**下标的含义跟着变了**：
/// 老色板里 `4` 是蓝，新色板里 `4` 是黄绿。而存量 `countdowns.json` 里存的就是下标，
/// 不搬一次，用户已有的卡片会集体换色——不是崩溃，但属于「没打招呼就改了用户的数据」。
///
/// 老文件里没有版本键，解出来是 nil，按版本 1 处理。这与 `showsInSmartList` /
/// `smartListDisplay` 那套「加可选字段、旧文件回退」的做法一致。
enum CountdownPalette {
    /// 当前色板版本。`countdowns.json` 里没有 `paletteVersion` 键 = 版本 1。
    static let version = 2

    /// 色板格数。`CountdownEvent.paletteSize` 取它，两边不会各写一个数。
    static let size = 12

    /// 版本 1 → 版本 2 的下标搬迁表：老 6 色板的下标 → 新 12 色板里色相最接近的一格。
    ///
    /// 这张表是**整体配一次**、要求一一对应，不是逐格各取最近。逐格取最近会撞车：
    /// 红到珊瑚 75、到玫红 87；橙到珊瑚 83、到橙 93——两格都指向珊瑚，
    /// 撞车之后总有一格要退而求其次，结果反而更差。按色相整体配的结果是：
    ///
    /// | 老下标 | 老颜色 | 新下标 | 新颜色 |
    /// | --- | --- | --- | --- |
    /// | 0 | 红 | 7 | 玫红 |
    /// | 1 | 橙 | 5 | 橙 |
    /// | 2 | 黄 | 4 | 黄绿 |
    /// | 3 | 绿 | 3 | 绿 |
    /// | 4 | 蓝 | 0 | 蓝 |
    /// | 5 | 紫 | 8 | 紫罗兰 |
    ///
    /// `CountdownKind.defaultColorIndex` 的新值就是这张表作用在旧默认值上的结果
    /// （纪念日橙→5、倒数日蓝→0、节日红→7、生日紫→8），有测试钉住这个一致性：
    /// 新建的纪念日和存量的纪念日应该是同一个颜色。
    static let legacyRemap = [7, 5, 4, 3, 0, 8]

    /// 把一个**版本 1** 的下标搬到当前色板。负数与越界按老色板格数回绕。
    static func remap(_ index: Int) -> Int {
        let count = max(legacyRemap.count, 1)
        return legacyRemap[((index % count) + count) % count]
    }

    /// 把一份存量记录的下标搬到当前色板。已经是当前版本的原样返回（不改动、不复制）。
    ///
    /// - Parameter stored: 文件里读到的 `paletteVersion`；nil = 老文件（版本 1）。
    static func migrated(_ events: [CountdownEvent], from stored: Int?) -> [CountdownEvent] {
        let from = stored ?? 1
        guard from < version else { return events }
        return events.map { event in
            var copy = event
            copy.colorIndex = remap(event.colorIndex)
            return copy
        }
    }
}
