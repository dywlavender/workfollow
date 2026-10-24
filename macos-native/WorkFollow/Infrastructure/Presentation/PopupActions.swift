import SwiftUI

#if DEBUG
enum DialogActionAnchor: Hashable { case cancel, primary }
struct DialogActionFrames: PreferenceKey {
    static let defaultValue: [DialogActionAnchor: CGRect] = [:]
    static func reduce(value: inout [DialogActionAnchor: CGRect], nextValue: () -> [DialogActionAnchor: CGRect]) {
        value.merge(nextValue(), uniquingKeysWith: { _, latest in latest })
    }
}
#endif

extension View {
    @ViewBuilder func dialogActionAnchor(_ primary: Bool) -> some View {
        #if DEBUG
        background(GeometryReader { geometry in
            Color.clear.preference(key: DialogActionFrames.self,
                value: [primary ? .primary : .cancel: geometry.frame(in: .named("dialog-render"))])
        })
        #else
        self
        #endif
    }
}

/// Compact cards share button geometry; each host keeps its own commit and
/// keyboard rules (Return in a search field is not automatically a submission).
struct PopupActionButton: View {
    let title: String
    var primary = false
    var tint: Color = WFColors.accent
    let action: () -> Void
    @Environment(\.isEnabled) private var isEnabled

    var body: some View {
        Button(action: action) {
            Text(title).font(WFType.body)
                .foregroundStyle(primary ? Color.white : WFColors.secondaryText)
                .frame(maxWidth: .infinity).frame(height: PopupMetrics.compactButtonHeight)
                .background(primary ? tint : Color.clear,
                            in: RoundedRectangle(cornerRadius: PopupMetrics.buttonCornerRadius))
                .overlay {
                    if !primary {
                        RoundedRectangle(cornerRadius: PopupMetrics.buttonCornerRadius)
                            .stroke(WFColors.border, lineWidth: 1)
                    }
                }
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .opacity(isEnabled ? 1 : 0.45)
        .dialogActionAnchor(primary)
    }
}

struct PopupActionBar<Actions: View>: View {
    @ViewBuilder let actions: () -> Actions
    var body: some View {
        VStack(spacing: 0) {
            Divider()
            HStack(spacing: PopupMetrics.actionSpacing, content: actions)
                .padding(PopupMetrics.contentInset)
        }
    }
}

struct DialogTitle: View {
    let text: String
    var body: some View {
        Text(text).font(.system(size: 18, weight: .semibold))
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct DialogHeader: View {
    let title: String
    var body: some View { DialogTitle(text: title).padding(PopupMetrics.formInset) }
}

/// The status slot reserves two lines, keeping actions in place when validation
/// fails. Scrollable content belongs above this footer, not around it.
struct DialogFooter<Status: View>: View {
    var cancelTitle = "取消"
    var primaryTitle = "保存"
    var canSubmit = true
    var buttonWidth: CGFloat = 72
    var cancelIdentifier = ""
    var primaryIdentifier = ""
    let onCancel: () -> Void
    let onSubmit: () -> Void
    @ViewBuilder let status: () -> Status

    var body: some View {
        VStack(spacing: 0) {
            Divider()
            HStack(spacing: PopupMetrics.actionSpacing) {
                ZStack(alignment: .leading) {
                    Color.clear.frame(height: 32).accessibilityHidden(true)
                    status().font(WFType.supporting).lineLimit(2)
                }.frame(maxWidth: .infinity, minHeight: 32, alignment: .leading)
                Button(action: onCancel) {
                    Text(cancelTitle).frame(minWidth: buttonWidth - 24)
                }
                .buttonStyle(.bordered).keyboardShortcut(.cancelAction)
                .accessibilityIdentifier(cancelIdentifier).workflowActionAnchor(cancelIdentifier)
                .dialogActionAnchor(false)
                Button(action: onSubmit) {
                    Text(primaryTitle).frame(minWidth: buttonWidth - 24)
                }
                .buttonStyle(.borderedProminent).keyboardShortcut(.defaultAction)
                .disabled(!canSubmit).accessibilityIdentifier(primaryIdentifier).workflowActionAnchor(primaryIdentifier)
                .dialogActionAnchor(true)
            }
            .controlSize(.regular)
            .padding(.horizontal, PopupMetrics.formInset)
            .padding(.vertical, PopupMetrics.formFooterInset)
        }
        .fixedSize(horizontal: false, vertical: true)
    }
}

struct DialogCloseFooter: View {
    var title = "完成"
    let onClose: () -> Void
    var body: some View {
        VStack(spacing: 0) {
            Divider()
            HStack {
                Spacer()
                Button(action: onClose) { Text(title).frame(minWidth: 48) }
                    .buttonStyle(.borderedProminent).keyboardShortcut(.cancelAction)
            }
            .frame(height: 32)
            .padding(.horizontal, PopupMetrics.formInset)
            .padding(.vertical, PopupMetrics.formFooterInset)
        }
    }
}
