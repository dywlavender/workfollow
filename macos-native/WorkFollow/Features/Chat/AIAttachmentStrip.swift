import AppKit
import ImageIO
import SwiftUI

struct AIAttachmentStrip: View {
    let items: [AIConversationAttachment]
    var remove: ((UUID) -> Void)? = nil

    var body: some View {
        if !items.isEmpty {
            ScrollView(.horizontal) {
                HStack(spacing: 8) {
                    ForEach(items) { item in
                        HStack(spacing: 7) {
                            Button { NSWorkspace.shared.open(item.url) } label: {
                                HStack(spacing: 7) {
                                    AIAttachmentThumbnail(item: item)
                                    Text(item.name).font(WFType.caption).lineLimit(1).frame(maxWidth: 150)
                                }.contentShape(Rectangle())
                            }.buttonStyle(.plain).accessibilityLabel("查看附件：\(item.name)")
                            if let remove {
                                Button { remove(item.id) } label: { Image(systemName: "xmark").font(.system(size: 10)) }
                                    .buttonStyle(.plain).accessibilityLabel("移除附件：\(item.name)")
                                    .workflowActionAnchor("ai.attachment.remove.\(item.id)")
                            }
                        }.padding(7).background(WFColors.content, in: RoundedRectangle(cornerRadius: 9))
                            .overlay(RoundedRectangle(cornerRadius: 9).stroke(WFColors.overlayBorder, lineWidth: 1))
                    }
                }
            }.fixedSize(horizontal: false, vertical: true).compactScrollbars()
        }
    }
}

private struct AIAttachmentThumbnail: View {
    let item: AIConversationAttachment
    @State private var thumbnail: NSImage?
    var body: some View {
        Group {
            if let thumbnail { Image(nsImage: thumbnail).resizable().scaledToFill() }
            else { Image(systemName: item.isImage ? "photo" : "doc.text").foregroundStyle(WFColors.secondaryText) }
        }.frame(width: 38, height: 38).clipped().clipShape(RoundedRectangle(cornerRadius: 5))
            .onAppear {
                guard item.isImage, let source = CGImageSourceCreateWithURL(item.url as CFURL, nil),
                      let image = CGImageSourceCreateThumbnailAtIndex(source, 0, [
                        kCGImageSourceCreateThumbnailFromImageAlways: true,
                        kCGImageSourceThumbnailMaxPixelSize: 100,
                        kCGImageSourceCreateThumbnailWithTransform: true
                      ] as CFDictionary) else { return }
                thumbnail = NSImage(cgImage: image, size: .zero)
            }
    }
}

struct AIAttachmentDraftStatus: View {
    @ObservedObject var draft: AIAttachmentDraft
    var body: some View {
        if draft.isImporting {
            HStack(spacing: 6) { ProgressView().controlSize(.small); Text("正在添加附件…").font(WFType.caption) }
        }
        if let error = draft.error { Text(error).font(WFType.caption).foregroundStyle(WFColors.danger) }
    }
}
