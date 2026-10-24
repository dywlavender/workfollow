import SwiftUI

/// 顶栏的子任务进度条（TI2-07）。
///
/// 滴答的 `TTTaskDetailProgressView` 有 `isProgressChangable` + `progressChangedHandler`
/// + `expectedProgress`，重写了 `mouseDown:`/`mouseMoved:`/`updateTrackingAreas` ——
/// 是真的可以拖的。它没有"手动百分比"字段：进度就是子任务完成度，所以拖动
/// 等价于"按比例勾选/取消勾选子任务"，不需要新的存储字段。
///
/// 本地口径：
/// - **子任务进度可拖**：拖到 k/total 就把前 k 条标完成、其余取消（保留层级顺序）。
///   一次拖动只算一步撤销 —— 由宿主把整段拖动合并成一次写入。
/// - **清单形态只读**：那份进度来自正文检查项，拖动会与正文编辑抢同一份状态，
///   保持只读（`expectedProgress` 参照线也还没有数据源）。
struct TaskInspectorSubtaskProgress: Equatable {
    let done: Int
    let total: Int
    /// 是否允许拖动改变进度。清单形态为 false。
    var isAdjustable: Bool = true

    var fraction: CGFloat {
        guard total > 0 else { return 0 }
        return CGFloat(done) / CGFloat(total)
    }

    /// 拖动/点击的 x 位置换算成"应该完成几条"，夹在 0...total。
    func targetDone(for fraction: CGFloat, step: CGFloat = 0) -> Int {
        guard total > 0 else { return 0 }
        var raw = fraction * CGFloat(total)
        // 有步进时先吸附到最近的格，避免像素抖动在两条之间反复横跳。
        if step > 0 { raw = (raw / step).rounded() * step }
        return min(max(Int(raw.rounded()), 0), total)
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
    /// 拖动/点击结束时回调目标完成数；nil 表示只读。
    var onAdjust: ((Int) -> Void)? = nil

    @State private var dragFraction: CGFloat?

    private var shownFraction: CGFloat {
        dragFraction ?? progress.fraction
    }

    private var canAdjust: Bool {
        progress.isAdjustable && onAdjust != nil
    }

    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .leading) {
                Rectangle().fill(WFColors.border)
                Rectangle()
                    .fill(WFColors.accent)
                    .frame(width: geometry.size.width * shownFraction)
            }
            .frame(maxHeight: .infinity)
            .contentShape(Rectangle())
            // 2pt 的条太细，命中区上下各放宽 4pt；仍不改变 Header 几何。
            .padding(.vertical, -4)
            .gesture(dragGesture(width: geometry.size.width), including: canAdjust ? .all : .none)
            .onHover { inside in
                guard canAdjust else { return }
                if inside { NSCursor.resizeLeftRight.push() } else { NSCursor.pop() }
            }
        }
        .frame(height: 2)
        .padding(.horizontal, TaskInspectorMetrics.horizontalPadding)
        .help(helpText)
        .accessibilityLabel(accessibilityText)
        .accessibilityAdjustableAction { direction in
            guard canAdjust else { return }
            let target = progress.done + (direction == .increment ? 1 : -1)
            guard target >= 0, target <= progress.total else { return }
            onAdjust?(target)
        }
    }

    private var helpText: String {
        canAdjust
            ? "子任务完成 \(progress.done)/\(progress.total) · 拖动可调整"
            : "子任务完成 \(progress.done)/\(progress.total)"
    }

    private var accessibilityText: String {
        "子任务进度 \(progress.done)/\(progress.total)"
    }

    private func dragGesture(width: CGFloat) -> some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { value in
                guard width > 0 else { return }
                let raw = min(max(value.location.x / width, 0), 1)
                // 拖动过程只改显示，避免每一步都写一次任务（撤销会碎成 N 步）。
                dragFraction = CGFloat(progress.targetDone(for: raw)) / CGFloat(max(progress.total, 1))
            }
            .onEnded { value in
                defer { dragFraction = nil }
                guard width > 0 else { return }
                let raw = min(max(value.location.x / width, 0), 1)
                let target = progress.targetDone(for: raw)
                guard target != progress.done else { return }
                onAdjust?(target)
            }
    }
}
