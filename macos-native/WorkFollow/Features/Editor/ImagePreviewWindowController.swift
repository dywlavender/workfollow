import AppKit

/// 粘贴图片的预览窗（双击正文里的图片、或点附件行里的图片名）。
///
/// 粘贴图片在文档里是 data URL 附件（`storedName = "data:image/png;base64,…"`），
/// 不是磁盘文件，`NativeAttachmentFiles.url(for:)` 会（也应当）返回 nil，
/// 所以"双击打开"不能走 `NSWorkspace`。这里给一个只读预览窗：
/// 等比适应窗口、Esc 关闭、"存储副本…"可另存成 PNG。
@MainActor
final class ImagePreviewWindowController: NSWindowController, NSWindowDelegate {

    private let imageView = NSImageView()
    private let nameLabel = NSTextField(labelWithString: "")
    private let sizeLabel = NSTextField(labelWithString: "")
    private let image: NSImage
    private let fileName: String
    private static var retained: [ImagePreviewWindowController] = []

    init(image: NSImage, name: String) {
        self.image = image
        fileName = name
        let visible = NSScreen.main?.visibleFrame.size ?? NSSize(width: 1440, height: 900)
        let maxSize = NSSize(width: min(1000, visible.width - 80), height: min(760, visible.height - 120))
        let window = NSWindow(contentRect: NSRect(origin: .zero, size: maxSize),
                              styleMask: [.titled, .closable, .resizable], backing: .buffered, defer: false)
        window.title = name
        window.isReleasedWhenClosed = false
        window.minSize = NSSize(width: 320, height: 240)
        super.init(window: window)
        window.delegate = self

        imageView.image = image
        imageView.imageScaling = .scaleProportionallyUpOrDown
        imageView.wantsLayer = true
        imageView.layer?.backgroundColor = NSColor.black.withAlphaComponent(0.04).cgColor

        nameLabel.stringValue = name
        nameLabel.font = .systemFont(ofSize: 13, weight: .medium)
        nameLabel.lineBreakMode = .byTruncatingMiddle
        sizeLabel.stringValue = "\(Int(image.size.width)) × \(Int(image.size.height))"
        sizeLabel.font = .systemFont(ofSize: 11)
        sizeLabel.textColor = .secondaryLabelColor

        let saveButton = NSButton(title: "存储副本…", target: self, action: #selector(saveCopy))
        saveButton.bezelStyle = .rounded
        let closeButton = NSButton(title: "关闭", target: self, action: #selector(closeWindow))
        closeButton.bezelStyle = .rounded
        closeButton.keyEquivalent = "\u{1b}"

        let info = NSStackView(views: [nameLabel, sizeLabel])
        info.orientation = .vertical
        info.alignment = .leading
        info.spacing = 1
        let spacer = NSView()
        spacer.setContentHuggingPriority(.defaultLow, for: .horizontal)
        let footer = NSStackView(views: [info, spacer, saveButton, closeButton])
        footer.orientation = .horizontal
        footer.alignment = .centerY
        footer.spacing = 8
        footer.edgeInsets = NSEdgeInsets(top: 8, left: 12, bottom: 8, right: 12)

        let root = NSStackView(views: [imageView, footer])
        root.orientation = .vertical
        root.spacing = 0
        root.distribution = .fill
        imageView.setContentHuggingPriority(.defaultLow, for: .vertical)
        window.contentView = root
        root.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            root.leadingAnchor.constraint(equalTo: window.contentView!.leadingAnchor),
            root.trailingAnchor.constraint(equalTo: window.contentView!.trailingAnchor),
            root.topAnchor.constraint(equalTo: window.contentView!.topAnchor),
            root.bottomAnchor.constraint(equalTo: window.contentView!.bottomAnchor),
            imageView.heightAnchor.constraint(greaterThanOrEqualToConstant: 160)
        ])
        // 先按图片比例把窗口调到合适尺寸，小图不用开一个巨大的空窗。
        let ratio = image.size.height / max(1, image.size.width)
        let width = min(maxSize.width, max(420, image.size.width))
        let height = min(maxSize.height, max(320, width * ratio + 56))
        window.setContentSize(NSSize(width: width, height: height))
        window.center()
    }

    required init?(coder: NSCoder) { fatalError("ImagePreviewWindowController is created programmatically") }

    /// 单例式展示：同一张图重复双击只前置已有窗口。
    static func present(image: NSImage, name: String) {
        if let existing = retained.first(where: { $0.fileName == name && $0.window?.isVisible == true }) {
            existing.window?.makeKeyAndOrderFront(nil)
            return
        }
        let controller = ImagePreviewWindowController(image: image, name: name)
        retained.removeAll { $0.window?.isVisible != true }
        retained.append(controller)
        controller.showWindow(nil)
        controller.window?.makeKeyAndOrderFront(nil)
    }

    func windowWillClose(_ notification: Notification) {
        Self.retained.removeAll { $0 === self }
    }

    @objc private func closeWindow() {
        window?.performClose(nil)
    }

    @objc private func saveCopy() {
        guard let window, let data = image.pngData else { return }
        let panel = NSSavePanel()
        panel.nameFieldStringValue = (fileName as NSString).deletingPathExtension.isEmpty
            ? "图片.png" : (fileName as NSString).deletingPathExtension + ".png"
        panel.allowedContentTypes = [.png]
        panel.beginSheetModal(for: window) { response in
            guard response == .OK, let url = panel.url else { return }
            try? data.write(to: url)
        }
    }
}

extension NSImage {
    /// 统一成 PNG 数据（预览窗"存储副本"用）。
    var pngData: Data? {
        guard let tiff = tiffRepresentation, let rep = NSBitmapImageRep(data: tiff) else { return nil }
        return rep.representation(using: .png, properties: [:])
    }
}
