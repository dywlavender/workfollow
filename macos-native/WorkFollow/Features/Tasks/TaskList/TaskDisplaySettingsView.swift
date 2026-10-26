import SwiftUI

/// 显示设置里需要测试锚定的控件；版式固定，但点击点不能写死在测试里。
enum TaskDisplaySettingsAnchor: Hashable {
    case dateMode
    case sidePeek
    case popup
    case close
}

enum TaskDisplaySettingsText {
    static let title = "显示设置"
    static let dateRow = "日期显示为"
    static let detailTitle = "任务详情样式"
    static let detailDescription = "当窗口宽度不足时，任务详情将根据你的选择显示。"
    static let close = "关闭"
}

private struct TaskDisplaySettingsFrames: PreferenceKey {
    static var defaultValue: [TaskDisplaySettingsAnchor: CGRect] = [:]
    static func reduce(value: inout [TaskDisplaySettingsAnchor: CGRect],
                       nextValue: () -> [TaskDisplaySettingsAnchor: CGRect]) {
        value.merge(nextValue(), uniquingKeysWith: { _, new in new })
    }
}

private extension View {
    func displaySettingsAnchor(_ anchor: TaskDisplaySettingsAnchor) -> some View {
        background(GeometryReader { geometry in
            Color.clear.preference(key: TaskDisplaySettingsFrames.self,
                value: [anchor: geometry.frame(in: .named("display-settings"))])
        })
    }
}

/// 列表「⋯ → 显示设置」：日期显示口径 + 窄窗口的任务详情容器。
/// 版式按滴答截图：居中标题、左上红色关闭点、两块浅灰卡片。
struct TaskDisplaySettingsView: View {
    /// 测试用：返回各控件的坐标，避免用截图/文字识别定位。
    var onFrames: (([TaskDisplaySettingsAnchor: CGRect]) -> Void)? = nil

    @Environment(\.dismiss) private var dismiss
    @AppStorage(TaskDateDisplayMode.defaultsKey) private var dateDisplayRaw =
        TaskDateDisplayMode.taskTime.rawValue
    @AppStorage(TaskDetailLayout.defaultsKey) private var detailLayoutRaw =
        TaskDetailLayout.sidePeek.rawValue

    private var dateDisplay: Binding<TaskDateDisplayMode> {
        Binding(get: { TaskDateDisplayMode(rawValue: dateDisplayRaw) ?? .taskTime },
                set: { dateDisplayRaw = $0.rawValue })
    }

    private var detailLayout: Binding<TaskDetailLayout> {
        Binding(get: { TaskDetailLayout(rawValue: detailLayoutRaw) ?? .sidePeek },
                set: { detailLayoutRaw = $0.rawValue })
    }

    var body: some View {
        VStack(spacing: 0) {
            titleBar
            VStack(spacing: WFSpace.md) {
                dateDisplayRow
                detailLayoutCard
            }
            .padding(.horizontal, WFSpace.xxl)
            Spacer(minLength: 0)
        }
        .frame(width: 500, height: 410)
        .background(WFColors.canvas)
        .coordinateSpace(name: "display-settings")
        .onPreferenceChange(TaskDisplaySettingsFrames.self) { onFrames?($0) }
        .onExitCommand { dismiss() }
    }

    private var titleBar: some View {
        ZStack {
            Text(TaskDisplaySettingsText.title).font(.system(size: 20, weight: .semibold))
            HStack {
                Button { dismiss() } label: {
                    Circle()
                        .fill(Color(nsColor: .systemRed))
                        .frame(width: 12, height: 12)
                        .contentShape(Rectangle().inset(by: -4))
                }
                .buttonStyle(.plain)
                .help(TaskDisplaySettingsText.close)
                .accessibilityLabel(TaskDisplaySettingsText.close)
                .displaySettingsAnchor(.close)
                Spacer()
            }
            .padding(.leading, WFSpace.xxl)
        }
        .padding(.top, WFSpace.xl)
        .padding(.bottom, WFSpace.lg)
    }

    private var dateDisplayRow: some View {
        HStack(spacing: WFSpace.md) {
            Text(TaskDisplaySettingsText.dateRow).font(.system(size: 15, weight: .semibold))
            Spacer(minLength: WFSpace.md)
            BusinessMenu(width: PopupMetrics.menuWidthCompact,
                         title: TaskDisplaySettingsText.dateRow) {
                ForEach(TaskDateDisplayMode.menuOrder) { mode in
                    BusinessMenuOption(mode.title, selected: dateDisplay.wrappedValue == mode) {
                        dateDisplay.wrappedValue = mode
                    }
                }
            } label: {
                HStack(spacing: 8) {
                    Text(dateDisplay.wrappedValue.title).font(WFType.body)
                    Image(systemName: "chevron.up.chevron.down")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(WFColors.secondaryText)
                }
                .padding(.horizontal, 10)
                .frame(height: 30)
                .background(WFColors.secondarySurface,
                            in: RoundedRectangle(cornerRadius: PopupMetrics.buttonCornerRadius))
                .contentShape(Rectangle())
            }
            .accessibilityLabel(TaskDisplaySettingsText.dateRow)
            .accessibilityValue(dateDisplay.wrappedValue.title)
            .displaySettingsAnchor(.dateMode)
        }
        .padding(.horizontal, 18)
        .frame(height: 64)
        .background(WFColors.panelFill, in: RoundedRectangle(cornerRadius: 12))
    }

    private var detailLayoutCard: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(TaskDisplaySettingsText.detailTitle).font(.system(size: 15, weight: .semibold))
            Text(TaskDisplaySettingsText.detailDescription)
                .font(.system(size: 13))
                .foregroundStyle(WFColors.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
            HStack(spacing: WFSpace.lg) {
                ForEach(TaskDetailLayout.menuOrder) { layout in
                    detailLayoutOption(layout)
                }
            }
            .padding(.top, 6)
            .frame(maxWidth: .infinity)
        }
        .padding(18)
        .background(WFColors.panelFill, in: RoundedRectangle(cornerRadius: 12))
    }

    private func detailLayoutOption(_ layout: TaskDetailLayout) -> some View {
        let selected = detailLayout.wrappedValue == layout
        return Button {
            detailLayout.wrappedValue = layout
        } label: {
            VStack(spacing: 10) {
                TaskDetailLayoutThumbnail(layout: layout)
                    .frame(height: 118)
                    .overlay {
                        RoundedRectangle(cornerRadius: 6)
                            .stroke(WFColors.border, lineWidth: 1)
                    }
                    .clipShape(RoundedRectangle(cornerRadius: 6))
                HStack(spacing: 8) {
                    Image(systemName: selected ? "checkmark.circle.fill" : "circle")
                        .font(.system(size: 16))
                        .foregroundStyle(selected ? WFColors.accent : WFColors.tertiaryText)
                    Text(layout.title)
                        .font(.system(size: 13, weight: selected ? .semibold : .regular))
                        .foregroundStyle(WFColors.text)
                }
            }
            .frame(maxWidth: .infinity)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(layout.title)
        .accessibilityValue(selected ? "已选择" : "未选择")
        .displaySettingsAnchor(layout == .sidePeek ? .sidePeek : .popup)
    }
}

/// 两张示意图不用位图：用几何块拼出「右侧栏」与「浮层卡片」的差别。
private struct TaskDetailLayoutThumbnail: View {
    let layout: TaskDetailLayout

    var body: some View {
        ZStack(alignment: .topLeading) {
            WFColors.content
            HStack(spacing: 3) {
                RoundedRectangle(cornerRadius: 1)
                    .fill(mock(0.12))
                    .frame(width: 7)
                RoundedRectangle(cornerRadius: 1)
                    .fill(mock(0.07))
                    .frame(width: 24)
                VStack(spacing: 4) {
                    ForEach(0..<5, id: \.self) { index in
                        RoundedRectangle(cornerRadius: 1)
                            .fill(mock(index == 1 ? 0.16 : 0.09))
                            .frame(height: 6)
                    }
                    Spacer(minLength: 0)
                }
                if layout == .sidePeek {
                    VStack(spacing: 4) {
                        RoundedRectangle(cornerRadius: 1).fill(mock(0.18)).frame(height: 6)
                        ForEach(0..<4, id: \.self) { _ in
                            RoundedRectangle(cornerRadius: 1).fill(mock(0.09)).frame(height: 5)
                        }
                        Spacer(minLength: 0)
                    }
                    .padding(5)
                    .frame(width: 58)
                    .background(WFColors.canvas)
                }
            }
            .padding(7)

            if layout == .popup {
                VStack(spacing: 4) {
                    RoundedRectangle(cornerRadius: 1).fill(mock(0.18)).frame(height: 6)
                    ForEach(0..<4, id: \.self) { _ in
                        RoundedRectangle(cornerRadius: 1).fill(mock(0.09)).frame(height: 5)
                    }
                    Spacer(minLength: 0)
                }
                .padding(6)
                .frame(width: 76, height: 66)
                .background(WFColors.canvas, in: RoundedRectangle(cornerRadius: 4))
                .shadow(color: .black.opacity(0.16), radius: 6, x: 2, y: 3)
                .padding(.leading, 62)
                .padding(.top, 18)
            }
        }
        .background(WFColors.canvas)
    }

    private func mock(_ opacity: Double) -> Color {
        Color.primary.opacity(opacity)
    }
}
