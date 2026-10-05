import SwiftUI

/// 「移动到」自绘卡片：顶部搜索框 + 清单行（图标 / 名称 / 当前清单打勾）。
///
/// 只负责渲染 `MoveTargetPicker`（过滤与高亮都在那层，有测试），这里管画、悬停与按键：
/// ↑↓ 移动高亮、回车选择、Esc 关闭。滴答那版子菜单带搜索框，系统 `Menu` 做不到，
/// 所以这一处自绘；主菜单仍用系统菜单。
struct MoveTargetPickerCard: View {
    let sectionTitle: String
    let targets: [MoveTarget]
    let onPick: (String) -> Void
    let onCancel: () -> Void

    @State private var model: MoveTargetPicker
    @State private var query = ""
    @FocusState private var searchFocused: Bool

    init(sectionTitle: String, targets: [MoveTarget],
         onPick: @escaping (String) -> Void, onCancel: @escaping () -> Void) {
        self.sectionTitle = sectionTitle
        self.targets = targets
        self.onPick = onPick
        self.onCancel = onCancel
        _model = State(initialValue: MoveTargetPicker(allTargets: targets))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: WFSpace.xs) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 11))
                    .foregroundStyle(WFColors.tertiaryText)
                TextField("搜索", text: $query)
                    .textFieldStyle(.plain)
                    .font(WFType.listBody)
                    .focused($searchFocused)
                    .onSubmit { pick(model.selected) }
                    .onChange(of: query) { _, value in model.setQuery(value) }
            }
            .padding(.horizontal, WFSpace.sm)
            .frame(height: 30)
            Divider()
            if model.rows.isEmpty {
                Text("没有匹配的清单")
                    .font(WFType.supporting)
                    .foregroundStyle(WFColors.tertiaryText)
                    .padding(.horizontal, WFSpace.sm)
                    .frame(height: 32)
            } else {
                ForEach(Array(model.rows.enumerated()), id: \.element.id) { index, target in
                    row(target, highlighted: index == model.highlighted)
                        .onHover { inside in if inside { model.highlight(row: index) } }
                        .onTapGesture { pick(target) }
                }
            }
        }
        .frame(width: 230)
        .padding(.vertical, WFSpace.xs)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(WFColors.border))
        .shadow(color: .black.opacity(0.18), radius: 12, y: 4)
        .onAppear { searchFocused = true }
        // 老 API：onMoveCommand / onExitCommand 在 macOS 上最稳（onKeyPress 要 macOS 14+）。
        .onMoveCommand { direction in
            switch direction {
            case .up: model.moveHighlight(by: -1)
            case .down: model.moveHighlight(by: 1)
            default: break
            }
        }
        .onExitCommand { onCancel() }
        .accessibilityLabel("移动分组「\(sectionTitle)」到清单")
    }

    private func row(_ target: MoveTarget, highlighted: Bool) -> some View {
        HStack(spacing: WFSpace.xs) {
            Image(systemName: "list.bullet")
                .font(.system(size: 11))
                .foregroundStyle(WFColors.secondaryText)
            Text(target.title).font(WFType.listBody).foregroundStyle(WFColors.text)
            Spacer(minLength: 0)
            if target.isCurrent {
                Image(systemName: "checkmark")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(WFColors.secondaryText)
            }
        }
        .padding(.horizontal, WFSpace.sm)
        .frame(height: 28)
        .background(highlighted ? WFColors.listSelection.opacity(0.55) : Color.clear)
        .contentShape(Rectangle())
    }

    private func pick(_ target: MoveTarget?) {
        guard let target else { return }
        onPick(target.name)
    }
}
