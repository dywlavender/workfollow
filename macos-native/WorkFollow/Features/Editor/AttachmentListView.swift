import SwiftUI
import AppKit

struct AttachmentListView: View {
    let attachments: [NativeAttachment]
    let onChange: ([NativeAttachment]) -> Void
    @State private var error: String?
    var body: some View {
        DisclosureGroup("附件 \(attachments.count)") {
            VStack(alignment: .leading, spacing: 8) {
                ForEach(attachments) { attachment in
                    HStack {
                        Button {
                            if let url = NativeAttachmentFiles.url(for: attachment), !NSWorkspace.shared.open(url) {
                                error = "无法打开附件：\(attachment.name)"
                            }
                        } label: { Label(attachment.name, systemImage: "paperclip").lineLimit(1) }
                        Spacer()
                        Button {
                            if let url = NativeAttachmentFiles.url(for: attachment) { NSWorkspace.shared.activateFileViewerSelecting([url]) }
                        } label: { Image(systemName: "folder") }.help("在 Finder 中显示")
                        Button { onChange(attachments.filter { $0.id != attachment.id }) } label: { Image(systemName: "xmark") }.help("移除附件关联")
                    }.buttonStyle(.borderless)
                }
                Button("添加附件…") {
                    NativeAttachmentFiles.choose { result in
                        switch result {
                        case .success(let added): onChange(attachments + added)
                        case .failure(let failure): error = failure.localizedDescription
                        }
                    }
                }
                if let error { Text(error).font(.caption).foregroundStyle(.red) }
            }.padding(.top, 8)
        }
    }
}
