import SwiftUI

struct TemplateEducationView: View {
    var kind: TemplateKind
    var onDismiss: () -> Void

    init(kind: TemplateKind = .task, onDismiss: @escaping () -> Void) {
        self.kind = kind
        self.onDismiss = onDismiss
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Image(systemName: "checkmark.circle.fill")
                .symbolRenderingMode(.palette)
                .foregroundStyle(WFColors.accent, WFColors.accent.opacity(0.16))
                .font(.system(size: 54))
                .accessibilityHidden(true)

            Text("如何创建模板")
                .font(WFType.detailTitle)
                .foregroundStyle(WFColors.text)

            Text(kind.educationText)
                .font(.system(size: 16))
                .foregroundStyle(WFColors.text)
                .fixedSize(horizontal: false, vertical: true)
                .lineSpacing(3)

            Button(action: onDismiss) {
                Text("我知道了")
                    .font(.system(size: 16, weight: .semibold))
                    .frame(maxWidth: .infinity)
                    .frame(height: 42)
                    .foregroundStyle(WFColors.onAccent)
                    .background(WFColors.accent, in: Capsule())
            }
                .buttonStyle(.plain)
                .keyboardShortcut(.defaultAction)
        }
        .padding(24)
        .frame(width: PopupMetrics.templateNoteWidth, alignment: .leading)
        .fixedSize(horizontal: false, vertical: true)
        .background {
            ThemedPopupSurface()
                .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
        }
        .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .stroke(WFColors.border.opacity(0.45), lineWidth: 1)
        }
        .shadow(color: .black.opacity(0.12), radius: 18, y: 7)
    }
}
