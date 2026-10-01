import SwiftUI

struct SchedulePropertyRow: View {
    let property: ScheduleProperty
    let icon: String
    let presentation: SchedulePropertyPresentation
    var editor: AnyView?
    let onOpen: () -> Void
    let onClear: () -> Void
    let onHover: (Bool) -> Void

    private var foreground: Color { presentation.isActive ? WFColors.accent : WFColors.text }

    var body: some View {
        HStack(spacing: 8) {
            Button(action: onOpen) {
                Image(systemName: icon)
                    .font(.system(size: 14))
                    .foregroundStyle(presentation.isActive ? WFColors.accent : WFColors.secondaryText)
                    .frame(width: 18)
                    .scheduleRenderAnchor(.icon(property))
            }
            .buttonStyle(.plain)
            .accessibilityLabel("展开\(presentation.title)")
            if let editor, presentation.isActive {
                editor.onTapGesture { if !presentation.isExpanded { onOpen() } }
                Button(action: onOpen) { Color.clear.contentShape(Rectangle()) }
                    .buttonStyle(.plain)
                    .frame(maxWidth: .infinity)
                    .accessibilityHidden(true)
            } else {
                Button(action: onOpen) {
                    HStack {
                        Text(presentation.value ?? presentation.title)
                            .font(WFType.body).foregroundStyle(foreground).lineLimit(1)
                        Spacer(minLength: 4)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("展开\(presentation.title)")
            }
            // Separate hit target: clearing never executes the open/default action.
            Button(action: presentation.trailingControl == .clear ? onClear : onOpen) {
                Image(systemName: trailingSymbol)
                    .font(.system(size: presentation.trailingControl == .clear ? 9 : 10, weight: .semibold))
                    .foregroundStyle(WFColors.tertiaryText)
                    .frame(width: 18, height: 18)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help(presentation.trailingControl == .clear ? "清除\(presentation.title)" : "展开\(presentation.title)")
            .accessibilityLabel(presentation.trailingControl == .clear ? "清除\(presentation.title)" : "展开\(presentation.title)")
            .scheduleRenderAnchor(.trailing(property), label: trailingSymbol)
        }
        .padding(.horizontal, presentation.isExpanded ? 10 : 2)
        .frame(height: ScheduleMetrics.rowHeight)
        .scheduleRenderAnchor(.row(property), label: presentation.value ?? presentation.title, active: presentation.isActive)
        .scheduleRenderAnchor(.expandedRow(property), active: presentation.isExpanded)
        .background(presentation.isExpanded ? WFColors.hover : Color.clear, in: RoundedRectangle(cornerRadius: 8))
        .onHover(perform: onHover)
    }

    private var trailingSymbol: String {
        switch presentation.trailingControl {
        case .clear: "xmark"
        case .chevronDown: "chevron.down"
        case .chevronRight: "chevron.right"
        }
    }
}
