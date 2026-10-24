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
