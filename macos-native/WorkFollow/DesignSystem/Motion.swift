import AppKit
import SwiftUI

/// 动效总闸。所有界面动画（SwiftUI `withAnimation` / `.animation`、AppKit
/// 行动画、窗口过渡）都应经此判定：
///
/// - 系统开启「减弱动态效果」时一律降级为瞬时变化；
/// - XCTest 宿主下禁用，交互测试的时序不因动画抖动。
@MainActor
enum WFMotion {
    /// 测试覆写：动画路径的单元测试置 true，即可在 XCTest 宿主内覆盖动画分支。
    static var overrideEnabled: Bool?
    static var enabled: Bool {
        overrideEnabled ?? (NSClassFromString("XCTestCase") == nil
            && !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion)
    }

    /// 在总闸关闭时给出 `nil` 动画（SwiftUI 约定：nil = 立即赋值，无过渡）。
    static var noneIfDisabled: Animation? { enabled ? .snappy(duration: 0.3) : nil }
}
