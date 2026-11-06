import AppKit
import XCTest
@testable import WorkFollow

/// 图片粘贴回归：修复前正文"只能粘进图片地址"的两条根因。
///
/// 1. `importsGraphics = false` 让 `readablePasteboardTypes` 不含 png/tiff，
///    NSTextView 默认校验把**纯图片剪贴板**（截图 ⌘⇧4）判定为不可粘贴，
///    ⌘V 变灰、`paste(_:)` 不执行，正文里那条图片转 data URL 的逻辑不可达。
/// 2. 网页复制图片时剪贴板只有 html 的远程 `<img>`，HTMLReader 只认
///    `data:image/`，整段解析返回 nil，最后退回纯文本兜底 —— 粘进来的正是那个 URL。
@MainActor
final class ImagePasteRegressionTests: XCTestCase {

    // MARK: - 根因 1：纯位图剪贴板必须允许粘贴

    func testImageOnlyPasteboardIsPasteable() throws {
        let png = try Self.makePNG()
        let board = NSPasteboard.general
        board.clearContents()
        board.setData(png, forType: .png)
        defer { board.clearContents() }

        let view = try Self.makeEditor()
        let item = NSMenuItem(title: "粘贴", action: #selector(NSText.paste(_:)), keyEquivalent: "v")

        // 前提：纯位图剪贴板确实不在 NSTextView 的默认可读类型里。
        XCTAssertFalse(view.readablePasteboardTypes.contains(.png),
                       "前提失效：系统已把 png 纳入默认可读类型，这条修复可以移除")
        XCTAssertTrue(view.validateUserInterfaceItem(item),
                      "纯图片剪贴板必须让「粘贴」可用，否则 paste(_:) 永远不被调用")
    }

    func testImageOnlyPasteInsertsInlineImageNotText() throws {
        let png = try Self.makePNG()
        let board = NSPasteboard.general
        board.clearContents()
        board.setData(png, forType: .png)
        defer { board.clearContents() }

        let view = try Self.makeEditor()
        view.setSelectedRange(NSRange(location: 0, length: 0))
        view.paste(nil)

        let document = DocumentTextCodec.decode(view.attributedString(), preserving: .empty)
        let attachment = try XCTUnwrap(
            document.blocks.flatMap(\.runs).compactMap(\.attachment).first,
            "截图粘贴应落成图片附件，而不是什么都没发生")
        XCTAssertTrue(attachment.storedName.hasPrefix("data:image/png;base64,"))
        XCTAssertNotNil(DocumentTextCodec.pastedImage(from: attachment), "应该能渲染成真实图片")
    }

    // MARK: - 根因 2：HTML 里的远程图片地址不再退化成本文

    func testRemoteImageURLIsExtractedFromHTML() throws {
        let html = "<html><body><img src=\"https://example.com/pic.png\" /></body></html>"
        XCTAssertEqual(DocumentExternalClipboardCodec.firstRemoteImageURL(inHTML: html)?.absoluteString,
                       "https://example.com/pic.png")
    }

    func testDataURLImagesAreNotTreatedAsRemote() throws {
        let html = "<html><body><img src=\"data:image/png;base64,AAAA\" /></body></html>"
        XCTAssertNil(DocumentExternalClipboardCodec.firstRemoteImageURL(inHTML: html),
                     "内嵌 data URL 不是远程地址，应继续走原有的 HTML 解析路径")
    }

    func testLocalFileImageURLIsExtractedForDirectRead() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("image-paste-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: directory) }
        let file = directory.appendingPathComponent("shot.png")
        try Self.makePNG().write(to: file)

        let html = "<html><body><img src=\"\(file.absoluteString)\" /></body></html>"
        let found = try XCTUnwrap(DocumentExternalClipboardCodec.firstRemoteImageURL(inHTML: html))
        XCTAssertTrue(found.isFileURL, "file:// 图片应被识别，供本地直接读取")
    }

    func testHTMLWithoutImageYieldsNoRemoteURL() throws {
        let html = "<html><body><p>只有文字</p></body></html>"
        XCTAssertNil(DocumentExternalClipboardCodec.firstRemoteImageURL(inHTML: html))
    }

    // MARK: - 笔记与任务详情对齐：粘贴文件交给宿主

    func testNoteProfileRoutesPastedFilesToHost() {
        let profile = NoteDocumentProfile.make(host: NoteEditorHostActions(
            createTaskFromSelection: { _ in }, pasteFiles: { _ in }))
        XCTAssertNotNil(profile.onPasteFiles,
                        "笔记必须和任务详情一样把粘贴的文件交给宿主落盘成附件")
    }

    // MARK: - Fixtures

    private static func makeEditor() throws -> NativeTextView {
        let view = NativeTextView(frame: NSRect(x: 0, y: 0, width: 600, height: 200),
                                  textContainer: nil)
        view.isEditable = true
        let window = NSWindow(contentRect: view.frame, styleMask: [.borderless],
                              backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = view
        window.makeFirstResponder(view)
        return view
    }

    private static func makePNG(width: CGFloat = 24, height: CGFloat = 18) throws -> Data {
        let bitmap = try XCTUnwrap(NSBitmapImageRep(
            bitmapDataPlanes: nil, pixelsWide: Int(width), pixelsHigh: Int(height),
            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
            colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0))
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)
        NSColor.systemTeal.setFill()
        NSRect(x: 0, y: 0, width: width, height: height).fill()
        NSGraphicsContext.restoreGraphicsState()
        return try XCTUnwrap(bitmap.representation(using: .png, properties: [:]))
    }
}
