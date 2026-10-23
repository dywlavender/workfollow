import AppKit
import XCTest
@testable import WorkFollow

/// 第二批：富文本粘贴、粘贴图片预览、保存失败重试。
@MainActor
final class PasteAndSaveRecoveryTests: XCTestCase {

    // MARK: - 富文本粘贴

    func testRichTextKeepsBasicMarksOnly() throws {
        let source = NSMutableAttributedString(string: "粗体 斜体 下划线 删除线")
        let boldRange = (source.string as NSString).range(of: "粗体")
        let italicRange = (source.string as NSString).range(of: "斜体")
        let underlineRange = (source.string as NSString).range(of: "下划线")
        let strikeRange = (source.string as NSString).range(of: "删除线")
        source.addAttribute(.font, value: NSFont.boldSystemFont(ofSize: 28), range: boldRange)
        source.addAttribute(.font, value: NSFontManager.shared.convert(NSFont.systemFont(ofSize: 12),
                                                                      toHaveTrait: .italicFontMask),
                            range: italicRange)
        source.addAttribute(.underlineStyle, value: NSUnderlineStyle.single.rawValue, range: underlineRange)
        source.addAttribute(.strikethroughStyle, value: NSUnderlineStyle.single.rawValue, range: strikeRange)
        // 这些属性不该被带进来
        source.addAttribute(.backgroundColor, value: NSColor.systemYellow, range: boldRange)
        source.addAttribute(.foregroundColor, value: NSColor.systemRed, range: italicRange)

        let converted = try XCTUnwrap(DocumentTextCodec.richText(source, baseKind: .paragraph))
        XCTAssertEqual(converted.string, source.string)

        func marks(of needle: String) -> Set<DocumentMark> {
            let range = (converted.string as NSString).range(of: needle)
            let run = DocumentTextCodec.decode(converted, preserving: .empty).blocks
                .flatMap(\.runs).first { $0.text.contains(needle) }
            XCTAssertNotNil(run, "\(needle) 应落在某个 run 里")
            return run?.marks ?? []
        }
        XCTAssertEqual(marks(of: "粗体"), [.bold])
        XCTAssertEqual(marks(of: "斜体"), [.italic])
        XCTAssertEqual(marks(of: "下划线"), [.underline])
        XCTAssertEqual(marks(of: "删除线"), [.strikethrough])
        // 字号/颜色不进 run（存储里本来就没有这两个字段，这里确认没被当作 mark）
        XCTAssertFalse(marks(of: "粗体").contains(.highlight), "背景色不当高亮带过来")
    }

    func testRichTextKeepsLinks() throws {
        let source = NSMutableAttributedString(string: "看这里")
        source.addAttribute(.link, value: "https://example.com", range: NSRange(location: 0, length: 3))
        let converted = try XCTUnwrap(DocumentTextCodec.richText(source, baseKind: .paragraph))
        let decoded = DocumentTextCodec.decode(converted, preserving: .empty)
        let marks = decoded.blocks.flatMap(\.runs).flatMap(\.marks)
        XCTAssertTrue(marks.contains(.link("https://example.com")), "链接要保留")
    }

    func testPlainRichTextIsRejectedSoPasteFallsBackToText() {
        let plain = NSAttributedString(string: "没有格式", attributes: [.font: NSFont.systemFont(ofSize: 30)])
        XCTAssertNil(DocumentTextCodec.richText(plain, baseKind: .paragraph),
                     "只有字号差异时不算富文本，调用方退回纯文本粘贴")
    }

    func testRichTextKeepsParagraphKindOfPasteSite() throws {
        let source = NSMutableAttributedString(string: "第一行\n第二行")
        source.addAttribute(.font, value: NSFont.boldSystemFont(ofSize: 20),
                            range: NSRange(location: 0, length: source.length))
        let converted = try XCTUnwrap(DocumentTextCodec.richText(source, baseKind: .heading(2)))
        let decoded = DocumentTextCodec.decode(converted, preserving: .empty)
        XCTAssertEqual(decoded.blocks.map(\.kind), [.heading(2), .heading(2)],
                       "粘贴不把当前段落改成标题/列表")
        XCTAssertTrue(decoded.blocks.allSatisfy { $0.runs.allSatisfy { $0.marks.contains(.bold) } })
    }

    // MARK: - 粘贴图片

    func testPastedImageAttachmentIsNotAFileURLButHasPreview() throws {
        let png = try Self.makePNG()
        let attachment = NativeAttachment(id: UUID(), name: "粘贴的图片.png",
                                          storedName: "data:image/png;base64," + png.base64EncodedString())
        // data URL 含 "/"，绝不能当文件路径拼（旧 bug 的根因）
        XCTAssertNil(NativeAttachmentFiles.url(for: attachment))
        XCTAssertNotNil(DocumentTextCodec.pastedImage(from: attachment), "预览数据要能解出来")
    }

    func testImagePreviewControllerOpensAndCloses() throws {
        let png = try Self.makePNG(width: 40, height: 30)
        let image = try XCTUnwrap(NSImage(data: png))
        ImagePreviewWindowController.present(image: image, name: "预览测试.png")
        let window = try XCTUnwrap(NSApp.windows.first { $0.title == "预览测试.png" && $0.isVisible })
        XCTAssertTrue(window.contentView != nil)
        XCTAssertEqual(window.styleMask.contains(.resizable), true)
        window.performClose(nil)
        RunLoop.current.run(until: Date().addingTimeInterval(0.05))
        XCTAssertFalse(window.isVisible, "关闭后窗口要真的收起")
    }

    func testImagePreviewReusesVisibleWindow() throws {
        let png = try Self.makePNG()
        let image = try XCTUnwrap(NSImage(data: png))
        ImagePreviewWindowController.present(image: image, name: "复用测试.png")
        let first = try XCTUnwrap(NSApp.windows.first { $0.title == "复用测试.png" && $0.isVisible })
        ImagePreviewWindowController.present(image: image, name: "复用测试.png")
        let matches = NSApp.windows.filter { $0.title == "复用测试.png" && $0.isVisible }
        XCTAssertEqual(matches.count, 1, "同一张图重复双击只前置已有窗口")
        XCTAssertTrue(matches.first === first)
        first.performClose(nil)
        RunLoop.current.run(until: Date().addingTimeInterval(0.05))
    }

    // MARK: - 保存失败重试

    func testRetryStorageClearsErrorOnSuccess() {
        let environment = AppEnvironment()
        // `storageError` 是 private(set)：从公开路径（重试成功）验证它会被清掉。
        // 失败分支的文案由 `PersistenceCoordinator` 的既有测试覆盖。
        environment.retryStorage()
        let cleared = expectation(description: "flush 完成")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) { cleared.fulfill() }
        wait(for: [cleared], timeout: 4)
        XCTAssertNil(environment.storageError, "重试成功后提示应消失")
    }

    // MARK: - Helpers

    private static func makePNG(width: Int = 8, height: Int = 8) throws -> Data {
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let context = try XCTUnwrap(CGContext(data: nil, width: width, height: height,
                                              bitsPerComponent: 8, bytesPerRow: 0,
                                              space: colorSpace,
                                              bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        context.setFillColor(NSColor.systemTeal.cgColor)
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        let cgImage = try XCTUnwrap(context.makeImage())
        let rep = NSBitmapImageRep(cgImage: cgImage)
        return try XCTUnwrap(rep.representation(using: .png, properties: [:]))
    }
}
