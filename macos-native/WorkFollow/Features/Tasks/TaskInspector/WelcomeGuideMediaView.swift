import AppKit
import SwiftUI

/// 引导任务正文顶部的演示 GIF（滴答同款：打开任务就自动循环播放）。
/// 素材缺失时整个视图不出现，普通任务与还没录演示的引导任务都不受影响。
struct WelcomeGuideMediaView: View {
    let action: WelcomeGuide.Action

    var body: some View {
        if let url = WelcomeGuide.mediaURL(for: action) {
            AnimatedGIFImageView(url: url)
                .frame(maxWidth: .infinity)
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .strokeBorder(WFColors.border, lineWidth: 1)
                }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("\(action.title)演示")
        }
    }
}

/// SwiftUI 的 `Image` 只取 GIF 首帧；`NSImageView` 才会按 GIF 帧表自动循环。
private struct AnimatedGIFImageView: NSViewRepresentable {
    let url: URL

    func makeNSView(context: Context) -> NSImageView {
        let view = NSImageView()
        view.imageScaling = .scaleProportionallyUpOrDown
        view.imageAlignment = .alignCenter
        view.imageFrameStyle = .none
        view.setContentHuggingPriority(.defaultLow, for: .horizontal)
        view.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        load(into: view)
        return view
    }

    func updateNSView(_ view: NSImageView, context: Context) {
        if view.image == nil { load(into: view) }
    }

    /// 比例来自 GIF 首帧，SwiftUI 按提议宽度定高，避免 NSImageView 用像素高度
    /// 把卡片撑出详情栏。
    func sizeThatFits(_ proposal: ProposedViewSize, nsView: NSImageView,
                      context: Context) -> CGSize? {
        guard let image = nsView.image, image.size.width > 0, image.size.height > 0 else { return nil }
        let ratio = image.size.height / image.size.width
        if let width = proposal.width, width.isFinite, width > 0 {
            return CGSize(width: width, height: (width * ratio).rounded())
        }
        return image.size
    }

    private func load(into view: NSImageView) {
        view.image = NSImage(contentsOf: url)
        // 减少动态效果时停在首帧，仍然把这一步的界面交代清楚。
        view.animates = !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
    }
}
