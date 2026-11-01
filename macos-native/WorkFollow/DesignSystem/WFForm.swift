import SwiftUI

/// 自研表单分区：替代系统 `Form` + `.formStyle(.grouped)` 的最后一处视觉
/// 分叉（弹框视觉统一的延续）。系统 grouped Form 的白底圆角卡片、系统
/// 分区标题和行高与全 app 的平面 + 发丝线语言不一致。
///
/// 行式样对齐专注页节奏弹层：标签在左、控件在右、10pt 纵向节奏、
/// `menuDivider` 发丝线分隔（最后一行不吃线）。
struct WFFormSection<Content: View>: View {
    let title: String?
    var footnote: String? = nil
    @ViewBuilder var content: () -> Content

    init(_ title: String? = nil, footnote: String? = nil,
         @ViewBuilder content: @escaping () -> Content) {
        self.title = title
        self.footnote = footnote
        self.content = content
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            if let title {
                Text(title).font(WFType.supporting).foregroundStyle(WFColors.secondaryText)
            }
            content()
            if let footnote {
                Text(footnote).font(WFType.supporting).foregroundStyle(WFColors.tertiaryText)
            }
        }
    }
}

/// 表单行：标题在左（`text`），控件靠右；行间用发丝线分隔。
/// 控件保持原生（Switch/Stepper/Slider/DatePicker）——要替换的是 Form 的
/// 卡片容器视觉，不是控件本身。
struct WFFormRow<Control: View>: View {
    let title: String
    var showsDivider: Bool = true
    @ViewBuilder var control: () -> Control

    init(_ title: String, showsDivider: Bool = true,
         @ViewBuilder control: @escaping () -> Control) {
        self.title = title
        self.showsDivider = showsDivider
        self.control = control
    }

    var body: some View {
        HStack {
            Text(title).foregroundStyle(WFColors.text)
            Spacer(minLength: WFSpace.md)
            control()
        }
        .font(WFType.body)
        .padding(.vertical, 10)
        .overlay(alignment: .bottom) {
            if showsDivider {
                Rectangle().fill(WFColors.menuDivider).frame(height: WFSpace.hairline)
            }
        }
        .padding(.horizontal, WFSpace.md)
    }
}

/// 开关行的便捷构造：右侧原生 Switch（labelsHidden），行高与普通行一致。
struct WFFormToggleRow: View {
    let title: String
    @Binding var isOn: Bool
    var showsDivider: Bool = true

    init(_ title: String, isOn: Binding<Bool>, showsDivider: Bool = true) {
        self.title = title
        self._isOn = isOn
        self.showsDivider = showsDivider
    }

    var body: some View {
        WFFormRow(title, showsDivider: showsDivider) {
            Toggle("", isOn: $isOn).toggleStyle(.switch).labelsHidden()
                .controlSize(.small)
                .tint(WFColors.accent)
        }
    }
}

/// 纯说明行：无控件，弱化文字（设置页的辅助说明不再借系统 Section 蓝标题）。
struct WFFormNote: View {
    let text: String

    init(_ text: String) { self.text = text }

    var body: some View {
        Text(text).font(WFType.supporting).foregroundStyle(WFColors.tertiaryText)
            .padding(.horizontal, WFSpace.md).padding(.bottom, 8)
    }
}

/// 弹层与设置共用的分段控件：浅色轨道 + 白色选中胶囊。
/// 系统 `.pickerStyle(.segmented)` 在非激活窗口会整块退成灰底，与自绘界面不一致。
struct WFSegmentedControl<Value: Hashable>: View {
    struct Option: Identifiable {
        let value: Value
        let title: String
        var id: Value { value }

        init(_ value: Value, _ title: String) {
            self.value = value; self.title = title
        }
    }

    @Binding var selection: Value
    let options: [Option]
    @Environment(\.colorScheme) private var colorScheme

    private var trackFill: Color {
        colorScheme == .dark ? Color.white.opacity(0.09) : Color.primary.opacity(0.06)
    }
    private var thumbFill: Color {
        colorScheme == .dark ? Color.white.opacity(0.14) : .white
    }

    var body: some View {
        HStack(spacing: 2) {
            ForEach(options) { option in
                optionButton(option)
            }
        }
        .padding(2)
        .background(trackFill, in: RoundedRectangle(cornerRadius: 8))
        .animation(.easeOut(duration: 0.14), value: selection)
    }

    private func optionButton(_ option: Option) -> some View {
        let selected = option.value == selection
        return Button { selection = option.value } label: {
            Text(option.title)
                .font(selected ? WFType.controlLabelStrong : WFType.controlLabel)
                .foregroundStyle(selected ? WFColors.text : WFColors.secondaryText)
                .lineLimit(1)
                .frame(maxWidth: .infinity)
                .frame(height: 24)
                .background {
                    if selected {
                        RoundedRectangle(cornerRadius: 6)
                            .fill(thumbFill)
                            .shadow(color: .black.opacity(0.08), radius: 1.5, y: 0.5)
                    }
                }
                .contentShape(RoundedRectangle(cornerRadius: 6))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(option.title)
        .accessibilityValue(selected ? "已选择" : "未选择")
    }
}
