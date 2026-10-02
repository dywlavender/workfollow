import SwiftUI

/// 倒数纪念日的 12 色板，**界面侧唯一一份**。
///
/// 卡片、编辑器、样式弹窗、智能清单小节都从这里取。早先
/// `CountdownWorkspaceView` 与 `CountdownEditorView` 各存了一份 6 色板，
/// 两份靠一句注释约定「同序同值」——扩到 12 色时合并成了这一份，
/// 那种靠记得来维持的一致性不该再留第二处。
///
/// ## 色值怎么来的
///
/// **逐像素取自参照实现的颜色行**（`docs/screenshots/ticktick-reference/17-countdown-add-step2-style.png`）：
/// 用 Pillow 扫过色板圆心那一行，按「非背景像素的连续段」切出 12 个实色圆，
/// 取各自的圆心 RGB。不是目测、也不是抄某个设计系统的近似色。
///
/// 两点要知道的边界：
/// - 参照的颜色行**还有两格**我们没有：「无颜色」（白底灰环 + 红斜杠）与
///   「自定义」彩虹拾色器。`CountdownEvent.colorIndex` 是**不可选** `Int`，
///   色板每一格都得是实色，所以这两格落不了地。这是取舍，不是对齐。
/// - 截图的色彩空间没有核对过（可能是 Display P3）。当成 sRGB 读会有轻微偏移，
///   这是「照参照量」能达到的精度上限；要更准得拿参照实现的原始色值。
let countdownPaletteColors: [Color] = [
    Color(.sRGB, red: 81.0 / 255, green: 113.0 / 255, blue: 241.0 / 255, opacity: 1),   // 蓝
    Color(.sRGB, red: 91.0 / 255, green: 160.0 / 255, blue: 248.0 / 255, opacity: 1),   // 天蓝
    Color(.sRGB, red: 115.0 / 255, green: 217.0 / 255, blue: 190.0 / 255, opacity: 1),  // 薄荷
    Color(.sRGB, red: 121.0 / 255, green: 203.0 / 255, blue: 135.0 / 255, opacity: 1),  // 绿
    Color(.sRGB, red: 169.0 / 255, green: 207.0 / 255, blue: 85.0 / 255, opacity: 1),   // 黄绿
    Color(.sRGB, red: 242.0 / 255, green: 170.0 / 255, blue: 90.0 / 255, opacity: 1),   // 橙
    Color(.sRGB, red: 238.0 / 255, green: 126.0 / 255, blue: 78.0 / 255, opacity: 1),   // 珊瑚
    Color(.sRGB, red: 217.0 / 255, green: 93.0 / 255, blue: 118.0 / 255, opacity: 1),   // 玫红
    Color(.sRGB, red: 140.0 / 255, green: 118.0 / 255, blue: 238.0 / 255, opacity: 1),  // 紫罗兰
    Color(.sRGB, red: 50.0 / 255, green: 62.0 / 255, blue: 114.0 / 255, opacity: 1),    // 深蓝
    Color(.sRGB, red: 110.0 / 255, green: 60.0 / 255, blue: 45.0 / 255, opacity: 1),    // 棕
    Color(.sRGB, red: 25.0 / 255, green: 25.0 / 255, blue: 25.0 / 255, opacity: 1),     // 黑
]

/// 色板下标安全取色（负数/越界自动回绕）。
///
/// **不是 private**：智能清单里的倒计时行（`CountdownSmartListRow`）也要画同一枚
/// 徽章，两处必须取到同一个颜色，所以只留一份实现给两处调。
func countdownColor(_ index: Int) -> Color {
    let count = max(countdownPaletteColors.count, 1)
    return countdownPaletteColors[((index % count) + count) % count]
}
