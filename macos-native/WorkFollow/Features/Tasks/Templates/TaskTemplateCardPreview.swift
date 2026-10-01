import SwiftUI

struct TaskTemplateCardPreview: View {
    let document: NativeDocument
    var title: String? = nil
    var maximumRows: Int = 7

    private var rows: [PreviewRow] {
        var result: [PreviewRow] = []
        if let title {
            let text = title.trimmingCharacters(in: .whitespacesAndNewlines)
            if !text.isEmpty {
                result.append(PreviewRow(id: "task-title", kind: .paragraph, text: text))
            }
        }
        result += document.blocks.compactMap { block in
            let text = block.plainText.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !text.isEmpty else { return nil }
            return PreviewRow(id: block.id.uuidString, kind: block.kind, text: text)
        }
        return Array(result.prefix(max(0, maximumRows)))
    }

    var body: some View {
        Group {
            if rows.isEmpty {
                Text("暂无预览内容")
                    .font(WFType.supporting)
                    .foregroundStyle(WFColors.tertiaryText)
            } else {
                VStack(alignment: .leading, spacing: 10) {
                    ForEach(rows) { row in
                        previewRow(row)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder
    private func previewRow(_ row: PreviewRow) -> some View {
        switch row.kind {
        case .checklist(let checked):
            HStack(alignment: .top, spacing: 9) {
                Image(systemName: checked ? "checkmark.square.fill" : "square")
                    .font(.system(size: 15, weight: .regular))
                    .foregroundStyle(checked ? WFColors.accent : WFColors.secondaryText)
                    .frame(width: 18, height: 20, alignment: .topLeading)
                    .accessibilityHidden(true)
                Text(row.text)
                    .font(.system(size: 14))
                    .foregroundStyle(WFColors.secondaryText)
                    .lineLimit(1)
                    .fixedSize(horizontal: false, vertical: true)
            }
        default:
            Text(row.text)
                .font(.system(size: 14))
                .foregroundStyle(WFColors.secondaryText)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private struct PreviewRow: Identifiable {
        let id: String
        let kind: DocumentBlockKind
        let text: String
    }
}
