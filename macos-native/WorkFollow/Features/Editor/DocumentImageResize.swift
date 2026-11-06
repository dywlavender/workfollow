import AppKit

/// 正文图片拖动改尺寸。
///
/// 交互：鼠标移到图片右下角出现斜向手柄，按住拖动等比缩放；松手把尺寸写进
/// `NativeAttachment.displaySize` 并提交文档（可撤销）。
///
/// 为什么用手柄而不是"拖图片边缘"：正文图片是字符附件（U+FFFC），
/// 拖边缘会和拖选文字、双击开预览的手势打架；角点手柄命中区小、语义明确。
extension NativeTextView {
    /// 手柄尺寸与命中容差（点）。命中区比画出来的方块大一圈，便于抓取。
    enum ImageResizeMetrics {
        static let handleSize: CGFloat = 10
        static let hitSlop: CGFloat = 6
        static let minimumSide: CGFloat = 48
        static let maximumSide: CGFloat = 1600
    }

    /// 可拖动的图片：所在字符位置、附件、原始图片与当前显示矩形。
    struct ResizableImage {
        let location: Int
        let attachment: NativeAttachment
        let image: NSImage
        let rect: NSRect
    }

    /// 拖动会话：起点、锚定尺寸与宽高比。
    struct ImageResizeSession {
        let location: Int
        let image: NSImage
        let attachment: NativeAttachment
        let startPoint: NSPoint
        let aspect: CGFloat
        let anchorSize: NSSize
        /// 拖动中的实时尺寸；松手时写入模型。
        var currentSize: NSSize?
    }

    // MARK: - 命中

    /// 坐标下的图片附件（不区分是否落在手柄上）。
    func resizableImage(at point: NSPoint) -> ResizableImage? {
        guard let storage = textStorage, storage.length > 0 else { return nil }
        // 不用 layoutManager 取几何：它会把 TextKit 2 切回 TextKit 1，
        // 宿主的高度测量随之失效（见 updateAttachmentHover 的同类注释）。
        let insertion = characterIndexForInsertion(at: point)
        for character in [insertion, insertion - 1] where character >= 0 && character < storage.length {
            guard let rect = imageViewRect(at: character),
                  let data = storage.attribute(DocumentTextCodec.attachmentKey, at: character,
                                               effectiveRange: nil) as? Data,
                  let attachment = try? JSONDecoder().decode(NativeAttachment.self, from: data),
                  attachment.isInlineImage,
                  let image = DocumentTextCodec.pastedImage(from: attachment) else { continue }
            guard rect.contains(point) || imageResizeHandleRect(forRect: rect)
                .insetBy(dx: -ImageResizeMetrics.hitSlop, dy: -ImageResizeMetrics.hitSlop)
                .contains(point) else { continue }
            return ResizableImage(location: character, attachment: attachment,
                                  image: image, rect: rect)
        }
        return nil
    }

    /// 图片附件字符的视图矩形。
    ///
    /// 附件字符的插入点矩形只有行高、不含图片高度，所以这里取该字符所在行的
    /// 原点，再叠加渲染用的 `imageBounds` 尺寸。
    func imageViewRect(at location: Int) -> NSRect? {
        guard let storage = textStorage, location >= 0, location < storage.length,
              let data = storage.attribute(DocumentTextCodec.attachmentKey, at: location,
                                           effectiveRange: nil) as? Data,
              let attachment = try? JSONDecoder().decode(NativeAttachment.self, from: data),
              attachment.isInlineImage,
              let image = DocumentTextCodec.pastedImage(from: attachment),
              let origin = viewRect(forCharacterAt: location) else { return nil }
        let size = DocumentTextCodec.imageBounds(for: image, attachment: attachment)
        return NSRect(x: origin.minX, y: origin.minY, width: size.width, height: size.height)
    }

    /// 右下角手柄矩形（视图坐标）。
    func imageResizeHandleRect(forRect rect: NSRect) -> NSRect {
        NSRect(x: rect.maxX - ImageResizeMetrics.handleSize,
               y: rect.minY,
               width: ImageResizeMetrics.handleSize,
               height: ImageResizeMetrics.handleSize)
    }

    /// 命中手柄（含容差）返回该图片。
    func imageResizeHandle(at point: NSPoint) -> ResizableImage? {
        guard isEditable, let image = resizableImage(at: point) else { return nil }
        let handle = imageResizeHandleRect(forRect: image.rect)
            .insetBy(dx: -ImageResizeMetrics.hitSlop, dy: -ImageResizeMetrics.hitSlop)
        return handle.contains(point) ? image : nil
    }

    // MARK: - 光标

    /// 悬停在手柄上时切换成斜向缩放光标。返回是否已接管光标。
    func updateImageResizeCursor(at point: NSPoint?) -> Bool {
        guard let point, imageResizeHandle(at: point) != nil else { return false }
        imageResizeCursorActive = true
        if #available(macOS 15.0, *) {
            NSCursor.frameResize(position: .bottomRight, directions: .all).set()
        } else {
            NSCursor.crosshair.set()
        }
        return true
    }

    // MARK: - 绘制

    /// 画可拖动图片的手柄：指针悬停在该图片上时显示。
    func drawImageResizeHandles(in dirtyRect: NSRect) {
        guard isEditable, let storage = textStorage, storage.length > 0 else { return }
        guard let probe = imageResizeProbePoint else { return }
        var offset = 0
        while offset < storage.length {
            defer { offset += 1 }
            guard let rect = imageViewRect(at: offset), rect.intersects(dirtyRect) else { continue }
            let hovered = rect.contains(probe)
                || imageResizeProbePoint.map { imageResizeHandleRect(forRect: rect)
                    .insetBy(dx: -ImageResizeMetrics.hitSlop, dy: -ImageResizeMetrics.hitSlop)
                    .contains($0) } == true
            guard hovered || imageResizeSession?.location == offset else { continue }
            drawResizeHandle(at: imageResizeHandleRect(forRect: rect))
        }
    }

    private func drawResizeHandle(at rect: NSRect) {
        let path = NSBezierPath(roundedRect: rect, xRadius: 2, yRadius: 2)
        NSColor.controlBackgroundColor.setFill()
        path.fill()
        NSColor.secondaryLabelColor.setStroke()
        path.lineWidth = 1
        path.stroke()
        // 斜向箭头小记号，提示这是等比缩放手柄。
        let glyph = NSBezierPath()
        let inset = rect.insetBy(dx: 3, dy: 3)
        glyph.move(to: NSPoint(x: inset.minX, y: inset.minY))
        glyph.line(to: NSPoint(x: inset.maxX, y: inset.maxY))
        glyph.lineWidth = 1
        glyph.stroke()
    }

    // MARK: - 拖动

    /// 开始拖动。返回 false 表示该点不在手柄上，调用方继续走原有逻辑。
    @discardableResult
    func beginImageResize(at point: NSPoint) -> Bool {
        guard let target = imageResizeHandle(at: point) else { return false }
        let current = DocumentTextCodec.imageBounds(for: target.image, attachment: target.attachment)
        guard current.height > 0 else { return false }
        imageResizeSession = ImageResizeSession(
            location: target.location, image: target.image, attachment: target.attachment,
            startPoint: point, aspect: current.width / current.height,
            anchorSize: current.size, currentSize: nil)
        return true
    }

    /// 拖动中：按位移等比换算，即时改 `NSTextAttachment.bounds` 预览（不写模型）。
    func continueImageResize(to point: NSPoint) {
        guard var session = imageResizeSession else { return }
        // 右下角拖动：向右、向下都放大。斜向位移取两轴平均，手感更贴合手柄方向。
        let delta = ((point.x - session.startPoint.x) + (session.startPoint.y - point.y)) / 2
        var width = session.anchorSize.width + delta * 2
        width = min(max(width, ImageResizeMetrics.minimumSide), ImageResizeMetrics.maximumSide)
        var height = width / max(session.aspect, 0.0001)
        if height < ImageResizeMetrics.minimumSide {
            height = ImageResizeMetrics.minimumSide
            width = height * session.aspect
        }
        // 不超出正文可用宽度，避免图片撑破编辑区。
        let available = max(ImageResizeMetrics.minimumSide,
                            bounds.width - (textContainer?.lineFragmentPadding ?? 5) * 2)
        if width > available {
            width = available
            height = width / max(session.aspect, 0.0001)
        }
        session.currentSize = NSSize(width: width, height: height)
        imageResizeSession = session
        applyImageResizePreview(at: session.location, size: session.currentSize)
    }

    /// 松手：把尺寸写回模型并提交；没真正拖动过就还原预览。
    func endImageResize() {
        guard let session = imageResizeSession else { return }
        imageResizeSession = nil
        guard let size = session.currentSize else {
            applyImageResizePreview(at: session.location, size: nil)
            return
        }
        commitImageSize(at: session.location, size: size)
    }

    /// 拖动中的即时重绘：只改附件字符上的 `NSTextAttachment.bounds`。
    private func applyImageResizePreview(at location: Int, size: NSSize?) {
        guard let storage = textStorage, location >= 0, location < storage.length,
              let attachment = storage.attribute(.attachment, at: location,
                                                 effectiveRange: nil) as? NSTextAttachment else { return }
        if let size {
            attachment.bounds = NSRect(x: 0, y: 0, width: size.width, height: size.height)
        } else {
            guard let data = storage.attribute(DocumentTextCodec.attachmentKey, at: location,
                                               effectiveRange: nil) as? Data,
                  let file = try? JSONDecoder().decode(NativeAttachment.self, from: data),
                  let image = DocumentTextCodec.pastedImage(from: file) else { return }
            attachment.bounds = DocumentTextCodec.imageBounds(for: image, attachment: file)
        }
        // 附件尺寸变了必须让 TextKit 重排该段，否则行高与换行仍是旧值。
        invalidateDocumentLayout(for: NSRange(location: location, length: 1))
        needsDisplay = true
    }

    /// 把新尺寸写进附件属性（模型）并走正常的文档提交路径。
    private func commitImageSize(at location: Int, size: NSSize) {
        guard let storage = textStorage, location >= 0, location < storage.length,
              let data = storage.attribute(DocumentTextCodec.attachmentKey, at: location,
                                           effectiveRange: nil) as? Data,
              var file = try? JSONDecoder().decode(NativeAttachment.self, from: data) else { return }
        let previous = file
        file.displayWidth = Double(size.width)
        file.displayHeight = Double(size.height)
        guard let encoded = try? JSONEncoder().encode(file),
              let previousEncoded = try? JSONEncoder().encode(previous) else { return }
        let range = NSRange(location: location, length: 1)
        // 只替换附件元数据这一项属性：该字符上还挂着 .attachment（渲染用的
        // NSTextAttachment）、段落样式和悬停标题，setAttributes 会把这些一并清掉，
        // 图片会直接消失。
        //
        // 撤销必须显式登记：NSTextStorage 的属性写入不会像字符输入那样自动进栈，
        // 只改属性再 didChangeText() 会让 Cmd+Z 无从回退（实测确实不回退）。
        breakUndoCoalescing()
        undoManager?.beginUndoGrouping()
        storage.addAttribute(DocumentTextCodec.attachmentKey, value: encoded, range: range)
        undoManager?.registerUndo(withTarget: self) { view in
            view.restoreAttachmentAttributes(previousEncoded, at: location, range: range)
        }
        undoManager?.endUndoGrouping()
        applyImageResizePreview(at: location, size: size)
        didChangeText()
    }

    /// 撤销/重做时回写附件属性并重新按模型尺寸布局。
    private func restoreAttachmentAttributes(_ encoded: Data, at location: Int, range: NSRange) {
        guard let storage = textStorage, NSMaxRange(range) <= storage.length else { return }
        // 重做路径：登记反向操作，保证可以反复撤销/重做。
        if let current = storage.attribute(DocumentTextCodec.attachmentKey, at: location,
                                           effectiveRange: nil) as? Data {
            undoManager?.registerUndo(withTarget: self) { view in
                view.restoreAttachmentAttributes(current, at: location, range: range)
            }
        }
        storage.addAttribute(DocumentTextCodec.attachmentKey, value: encoded, range: range)
        applyImageResizePreview(at: location, size: nil)
        didChangeText()
    }
}
