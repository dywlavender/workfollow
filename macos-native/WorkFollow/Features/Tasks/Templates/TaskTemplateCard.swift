import SwiftUI

struct TaskTemplateCard: View {
    let item: TaskTemplateCatalogItem

    private var template: TaskTemplate { item.template }
    private var previewTitle: String? {
        let title = template.title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty,
              title.localizedCaseInsensitiveCompare(template.name.trimmingCharacters(in: .whitespacesAndNewlines)) != .orderedSame
        else { return nil }
        return title
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(template.name)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(WFColors.text)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)

            TaskTemplateCardPreview(
                document: template.document,
                title: previewTitle,
                maximumRows: 7
            )

            Spacer(minLength: 0)
        }
        .padding(16)
        .frame(maxWidth: .infinity, minHeight: 220, alignment: .topLeading)
        .background(WFColors.secondarySurface.opacity(0.44))
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .contentShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
    }
}
