import SwiftUI

struct TemplateEducationView: View {
    var onDismiss: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Image(systemName: "checkmark.circle.fill")
                .symbolRenderingMode(.palette)
                .foregroundStyle(WFColors.accent, WFColors.accent.opacity(0.16))
                .font(.system(size: 54))
                .accessibilityHidden(true)

            Text("如何创建模板")
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(WFColors.text)

            Text("在任务详情页中先编辑好内容，再点击右下角“…”，选择“保存为模板”，输入标题即可将任务创建为模板")
                .font(.system(size: 16))
                .foregroundStyle(WFColors.text)
                .fixedSize(horizontal: false, vertical: true)
                .lineSpacing(3)

            Button(action: onDismiss) {
                Text("我知道了")
                    .font(.system(size: 16, weight: .semibold))
                    .frame(maxWidth: .infinity)
                    .frame(height: 42)
                    .foregroundStyle(.white)
                    .background(WFColors.accent, in: Capsule())
            }
                .buttonStyle(.plain)
                .keyboardShortcut(.defaultAction)
        }
        .padding(24)
        .frame(width: 380, alignment: .leading)
        .fixedSize(horizontal: false, vertical: true)
        .background(WFColors.content)
        .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .stroke(WFColors.border.opacity(0.45), lineWidth: 1)
        }
        .shadow(color: .black.opacity(0.12), radius: 18, y: 7)
    }
}
