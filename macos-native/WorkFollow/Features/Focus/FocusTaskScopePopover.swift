import SwiftUI

struct FocusTaskScopePopover: View {
    let selectedScope: FocusTaskPickerScope
    let listNames: [String]
    let listColor: (String) -> Color
    let onSelect: (FocusTaskPickerScope) -> Void
    let onDismiss: () -> Void

    @Environment(\.colorScheme) private var colorScheme
    private var theme: FocusTheme { FocusTheme(colorScheme) }

    private let systemScopes: [FocusTaskPickerScope] = [.today, .tomorrow, .nextSevenDays, .inbox]

    private var panelHeight: CGFloat {
        let dividerHeight: CGFloat = listNames.isEmpty ? 0 : 9
        return min(420, CGFloat(systemScopes.count) * FocusTaskPickerMetrics.scopeRowHeightCompact
                   + dividerHeight
                   + CGFloat(listNames.count) * FocusTaskPickerMetrics.scopeRowHeightCompact
                   + 16)
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                ForEach(systemScopes, id: \.id) { scope in
                    scopeRow(scope)
                }
                if !listNames.isEmpty {
                    Divider().padding(.vertical, 4)
                    ForEach(listNames, id: \.self) { name in
                        scopeRow(.list(name))
                    }
                }
            }
        }
        .scrollIndicators(.automatic)
        .padding(8)
        .frame(width: FocusTaskPickerMetrics.scopeWidth, height: panelHeight)
        .background(theme.canvas, in: RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(theme.hairline, lineWidth: 1))
        .onKeyPress(.escape) {
            onDismiss()
            return .handled
        }
    }

    private func scopeRow(_ scope: FocusTaskPickerScope) -> some View {
        let selected = scope == selectedScope
        return Button { onSelect(scope) } label: {
            HStack(spacing: 8) {
                if case let .list(name) = scope {
                    Circle().fill(listColor(name))
                        .frame(width: 8, height: 8)
                        .frame(width: FocusTaskPickerMetrics.scopeIconSize)
                } else {
                    Image(systemName: scope.symbol)
                        .font(.system(size: FocusTaskPickerMetrics.scopeIconSize))
                        .foregroundStyle(selected ? theme.accent : theme.text2)
                        .frame(width: FocusTaskPickerMetrics.scopeIconSize)
                }
                Text(scope.title)
                    .font(.system(size: FocusTaskPickerMetrics.taskFontSize,
                                  weight: selected ? .medium : .regular))
                    .foregroundStyle(selected ? theme.accent : theme.text)
                    .lineLimit(1)
                Spacer(minLength: 0)
                if selected {
                    Image(systemName: "checkmark")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(theme.accent)
                }
            }
            .padding(.horizontal, FocusTaskPickerMetrics.scopeHorizontalPadding)
            .frame(maxWidth: .infinity, minHeight: FocusTaskPickerMetrics.scopeRowHeightCompact)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

extension FocusTaskPickerScope {
    var symbol: String {
        switch self {
        case .today: "calendar"
        case .tomorrow: "sun.max"
        case .nextSevenDays: "calendar"
        case .inbox: "tray"
        case .list: "circle.fill"
        }
    }
}
