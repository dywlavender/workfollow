import SwiftUI

/// Instantiates a template through the workspace action path so a
/// template-created task behaves exactly like a manually created one,
/// including selecting the new task.
@MainActor
enum TemplateApplier {
    @discardableResult
    static func apply(_ template: TaskTemplate, to workspace: TaskWorkspaceModel) -> UUID? {
        // A template list that no longer exists falls back to the inbox
        // instead of resurrecting a stale list name.
        let listName = template.listName.flatMap { name in
            workspace.allListNames.contains(name) ? name : nil
        } ?? TaskList.inbox.name
        let schedule = TaskSchedule(
            dueAt: template.schedule?.date(from: workspace.clock(), calendar: workspace.calendar))
        let result = workspace.createDraft(title: template.title, list: listName,
                                           schedule: schedule,
                                           priority: template.priority ?? .none,
                                           tags: template.tags,
                                           reminder: nil, repeatFrequency: .never)
        guard let id = result.taskID else { return nil }
        if !template.document.isEmpty {
            _ = workspace.setDocument(id, template.document)
        }
        for title in template.childTitles {
            _ = workspace.createChild(id, title: title)
        }
        return id
    }
}

/// Sheet listing saved templates: name, title preview and child count, with
/// apply and delete actions per row.
struct TemplatePickerView: View {
    @ObservedObject var workspace: TaskWorkspaceModel
    @ObservedObject var templateStore: TemplateStore
    var onDismiss: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: WFSpace.md) {
            Text("从模板添加").font(WFType.pageTitle)
            if templateStore.templates.isEmpty {
                emptyState
            } else {
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(templateStore.templates) { template in
                            templateRow(template)
                            Divider().padding(.leading, WFSpace.sm)
                        }
                    }
                }
            }
            HStack {
                Spacer()
                Button("关闭") { onDismiss() }.keyboardShortcut(.cancelAction)
            }
        }
        .padding(WFSpace.xxl)
        .frame(width: 460, height: 420)
    }

    private var emptyState: some View {
        VStack(spacing: WFSpace.sm) {
            Image(systemName: "doc.badge.plus").font(.title2)
            Text("还没有模板").font(WFType.body)
            Text("选中任务后，在“更多”菜单选择“保存为模板…”")
                .font(WFType.supporting)
        }
        .foregroundStyle(WFColors.secondaryText)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func templateRow(_ template: TaskTemplate) -> some View {
        HStack(spacing: WFSpace.md) {
            VStack(alignment: .leading, spacing: 2) {
                Text(template.name).font(WFType.listTitle).lineLimit(1)
                Text(rowPreview(template)).font(WFType.supporting)
                    .foregroundStyle(WFColors.secondaryText).lineLimit(1)
            }
            Spacer(minLength: WFSpace.sm)
            if !template.childTitles.isEmpty {
                Text("含 \(template.childTitles.count) 个子任务")
                    .font(WFType.supporting).foregroundStyle(WFColors.secondaryText)
            }
            Button("应用") {
                TemplateApplier.apply(template, to: workspace)
                onDismiss()
            }
            .disabled(template.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            Button {
                if TaskNamePrompt.confirm("删除模板“\(template.name)”？",
                                          message: "删除后不可恢复，已创建的任务不受影响。") {
                    _ = templateStore.delete(template.id)
                }
            } label: {
                Image(systemName: "trash").frame(width: 24, height: 24)
            }
            .buttonStyle(.plain)
            .foregroundStyle(WFColors.secondaryText)
            .help("删除模板")
            .accessibilityLabel("删除模板：\(template.name)")
        }
        .padding(.vertical, WFSpace.sm)
        .contentShape(Rectangle())
    }

    private func rowPreview(_ template: TaskTemplate) -> String {
        var parts = [template.title.isEmpty ? "无标题" : template.title]
        let body = template.document.plainText
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if !body.isEmpty { parts.append(body) }
        return parts.joined(separator: " · ")
    }
}
