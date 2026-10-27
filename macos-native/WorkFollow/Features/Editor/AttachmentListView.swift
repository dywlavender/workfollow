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
                    AttachmentRow(attachment: attachment,
                                  onRemove: { onChange(attachments.filter { $0.id != attachment.id }) },
                                  onError: { error = $0 })
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

/// 一行附件。粘贴图片（data URL）走预览窗，真实文件走 `NSWorkspace`；
/// 「在 Finder 中显示」只对真实文件出现。
private struct AttachmentRow: View {
    let attachment: NativeAttachment
    let onRemove: () -> Void
    let onError: (String) -> Void

    private var pastedImage: NSImage? { DocumentTextCodec.pastedImage(from: attachment) }
    private var fileURL: URL? { NativeAttachmentFiles.url(for: attachment) }

    var body: some View {
        HStack {
            Button(action: open) {
                Label(attachment.name, systemImage: pastedImage == nil ? "paperclip" : "photo")
                    .lineLimit(1)
            }
            Spacer()
            if let fileURL {
                Button { NSWorkspace.shared.activateFileViewerSelecting([fileURL]) } label: {
                    Image(systemName: "folder")
                }
                .help("在 Finder 中显示")
            }
            Button(action: onRemove) { Image(systemName: "xmark") }
                .help("移除附件关联")
        }
        .padding(.horizontal, 6).padding(.vertical, 4)
        .contentShape(Rectangle())
        .rowHoverBackground(cornerRadius: 6)
        .buttonStyle(.borderless)
    }

    private func open() {
        if let pastedImage {
            ImagePreviewWindowController.present(image: pastedImage, name: attachment.name)
            return
        }
        guard let fileURL else {
            onError("无法打开附件：\(attachment.name)")
            return
        }
        if !NSWorkspace.shared.open(fileURL) { onError("无法打开附件：\(attachment.name)") }
    }
}
