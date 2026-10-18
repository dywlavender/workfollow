import SwiftUI

/// 顶栏的子任务进度条（TI2-07，对齐滴答 `TTTaskDetailProgressView` 的只读形态）。
///
/// 滴答的进度条在顶栏、可交互（`isProgressChangable` / `expectedProgress`）；
/// 本地先做**只读**版本：直接子任务的完成/总数，画在顶栏下沿 2pt，不改变任何几何，
/// 不做假的可拖动交互（等有"手动进度"字段再升级）。
struct TaskInspectorSubtaskProgress: Equatable {
    let done: Int
    let total: Int

    var fraction: CGFloat {
        guard total > 0 else { return 0 }
        return CGFloat(done) / CGFloat(total)
    }

    /// `SubtaskProgress` 的字符串口径（"2/5"）；格式不符返回 nil。
    static func parse(_ raw: String?) -> TaskInspectorSubtaskProgress? {
        guard let raw else { return nil }
        let parts = raw.split(separator: "/")
        guard parts.count == 2,
              let done = Int(parts[0]), let total = Int(parts[1]),
              done >= 0, total > 0, done <= total else { return nil }
        return TaskInspectorSubtaskProgress(done: done, total: total)
    }
}

struct TaskInspectorProgressBar: View {
    let progress: TaskInspectorSubtaskProgress

    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .leading) {
                Rectangle().fill(WFColors.border)
                Rectangle()
                    .fill(WFColors.accent)
                    .frame(width: geometry.size.width * progress.fraction)
            }
        }
        .frame(height: 2)
        .padding(.horizontal, TaskInspectorMetrics.horizontalPadding)
        .allowsHitTesting(false)
        .help("子任务完成 \(progress.done)/\(progress.total)")
        .accessibilityLabel("子任务进度 \(progress.done)/\(progress.total)")
    }
}
