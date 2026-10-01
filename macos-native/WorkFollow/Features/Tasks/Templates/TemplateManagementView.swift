import SwiftUI

struct TemplateManagementView: View {
    @ObservedObject var templateStore: TemplateStore
    var onDismiss: () -> Void

    var body: some View {
        managementList
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(WFColors.content)
    }

    private var managementList: some View {
        VStack(spacing: 0) {
            HStack {
                Button("返回", action: onDismiss)
                    .buttonStyle(.plain)
                    .foregroundStyle(WFColors.accent)
                    .frame(width: 72, alignment: .leading)
                Spacer(minLength: 0)
                Text("管理模板")
                    .font(WFType.pageTitle)
                Spacer(minLength: 0)
                Color.clear.frame(width: 72, height: 1)
            }
            .frame(height: 42)
            .padding(.horizontal, 32)
            .padding(.top, 24)

            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(templateStore.templates) { template in
                        templateRow(template)
                        if template.id != templateStore.templates.last?.id {
                            Divider().padding(.leading, 22)
                        }
                    }
                }
                .padding(.horizontal, 32)
                .padding(.top, 18)
            }
        }
    }

    private func templateRow(_ template: TaskTemplate) -> some View {
        HStack(spacing: WFSpace.md) {
            VStack(alignment: .leading, spacing: 4) {
                Text(template.name)
                    .font(WFType.listTitleMedium)
                    .foregroundStyle(WFColors.text)
                    .lineLimit(1)
                Text(template.title.isEmpty ? "暂无任务标题" : template.title)
                    .font(WFType.supporting)
                    .foregroundStyle(WFColors.secondaryText)
                    .lineLimit(1)
            }
            Spacer(minLength: WFSpace.md)
            Button("重命名") { rename(template) }
                .buttonStyle(.plain)
                .foregroundStyle(WFColors.accent)
                .accessibilityLabel("重命名模板：\(template.name)")
            Button {
                remove(template)
            } label: {
                Image(systemName: "trash")
                    .frame(width: 28, height: 28)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .foregroundStyle(WFColors.secondaryText)
            .help("删除模板")
            .accessibilityLabel("删除模板：\(template.name)")
        }
        .padding(.vertical, 13)
        .contentShape(Rectangle())
    }

    @MainActor
    private func rename(_ template: TaskTemplate) {
        guard let name = TaskNamePrompt.ask("重命名模板", value: template.name),
              name != template.name else { return }
        if !templateStore.rename(template.id, to: name) {
            TaskNamePrompt.invalidName()
        }
    }

    @MainActor
    private func remove(_ template: TaskTemplate) {
        guard TaskNamePrompt.confirm(
            "删除模板“\(template.name)”？",
            message: "删除后不可恢复，已创建的任务不受影响。"
        ) else { return }
        _ = templateStore.delete(template.id)
    }
}
