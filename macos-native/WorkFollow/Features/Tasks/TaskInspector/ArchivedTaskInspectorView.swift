import AppKit
import SwiftUI

/// Archived tasks remain selectable and copyable, with no editing controls.
struct ArchivedTaskInspectorView: View {
    let task: Task
    let showsBack: Bool
    let onClose: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                if showsBack {
                    Button(action: onClose) { Image(systemName: "chevron.left") }
                        .buttonStyle(.plain).hoverTip("返回列表").accessibilityLabel("返回列表")
                }
                Text(task.list.name).font(WFType.body).foregroundStyle(WFColors.secondaryText)
                Spacer()
                Image(systemName: "archivebox").foregroundStyle(WFColors.secondaryText)
            }.padding(20)
            Divider()
            ArchivedTaskDocument(task: task)
                .compactScrollbars()
        }.background(WFColors.content)
    }
}

private struct ArchivedTaskDocument: NSViewRepresentable {
    let task: Task
    func makeNSView(context: Context) -> NSScrollView {
        let scroll = NSScrollView()
        scroll.hasVerticalScroller = true; scroll.scrollerStyle = .overlay; scroll.drawsBackground = false
        let text = NativeTextView(frame: NSRect(x: 0, y: 0, width: 400, height: 400), textContainer: nil)
        text.isEditable = false; text.isSelectable = true
        text.textContainerInset = NSSize(width: 20, height: 20)
        text.autoresizingMask = [.width]
        scroll.documentView = text
        return scroll
    }
    func updateNSView(_ view: NSScrollView, context: Context) {
        guard let text = view.documentView as? NativeTextView else { return }
        let rendered = NSMutableAttributedString(string: task.title + "\n\n", attributes: [
            .font: NSFont.systemFont(ofSize: 22, weight: .medium), .foregroundColor: NSColor.labelColor])
        if let document = try? task.document.materialized() { rendered.append(DocumentTextCodec.render(document)) }
        if !text.attributedString().isEqual(to: rendered) { text.textStorage?.setAttributedString(rendered); text.sizeToFit() }
    }
}
