import AppKit
import SwiftUI

/// The schedule's state-aware handler must win over the presentation shell's
/// generic dismissal in the same window. Deeper child windows still win first.
///
/// 名次用 `PopupEscapeRank.schedule`（以前是裸的 `4`）：它不是层数，
/// 而是同窗口内的竞争排序——"先弹哪一层"由面板的导航 reducer 决定。
struct ScheduleEscapeRouter: View {
    let onEscape: () -> Void

    var body: some View {
        PopupEscapeRouter(depth: PopupEscapeRank.schedule, onEscape: onEscape)
    }
}
