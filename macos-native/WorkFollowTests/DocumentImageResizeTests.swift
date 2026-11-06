import AppKit
import XCTest
@testable import WorkFollow

/// 图片拖动改尺寸：模型持久化、旧数据兼容、拖动换算与手柄命中。
@MainActor
final class DocumentImageResizeTests: XCTestCase {

    // MARK: - 模型

    func testDisplaySizeRejectsInvalidValues() {
        let base = NativeAttachment(id: UUID(), name: "a.png", storedName: "data:image/png;base64,AA")
        XCTAssertNil(base.displaySize, "未设置过尺寸")
        XCTAssertNil(NativeAttachment(id: UUID(), name: "a", storedName: "data:image/png;base64,AA",
                                      displayWidth: 0, displayHeight: 10).displaySize)
        XCTAssertNil(NativeAttachment(id: UUID(), name: "a", storedName: "data:image/png;base64,AA",
                                      displayWidth: 100, displayHeight: -1).displaySize)
        XCTAssertEqual(NativeAttachment(id: UUID(), name: "a", storedName: "data:image/png;base64,AA",
                                        displayWidth: 200, displayHeight: 120).displaySize?.width, 200)
    }

    func testLegacySnapshotWithoutSizeStillDecodes() throws {
        // 旧快照只有三个键：新增可选字段必须能无损解码。
        let legacy = #"{"id":"0B0E8C0A-0000-4000-8000-000000000001","name":"旧图.png","storedName":"data:image/png;base64,AA"}"#
        let decoded = try JSONDecoder().decode(NativeAttachment.self, from: Data(legacy.utf8))
        XCTAssertEqual(decoded.name, "旧图.png")
        XCTAssertNil(decoded.displaySize)
        XCTAssertTrue(decoded.isInlineImage)
    }

    func testSizeSurvivesEncodeDecodeRoundTrip() throws {
        let original = NativeAttachment(id: UUID(), name: "图.png",
                                        storedName: "data:image/png;base64,AA",
                                        displayWidth: 320, displayHeight: 240)
        let decoded = try JSONDecoder().decode(NativeAttachment.self,
                                               from: try JSONEncoder().encode(original))
        XCTAssertEqual(decoded.displaySize?.width, 320)
        XCTAssertEqual(decoded.displaySize?.height, 240)
    }

    func testNonImageAttachmentIsNotResizable() {
        let pdf = NativeAttachment(id: UUID(), name: "报告.pdf", storedName: "abc.pdf")
        XCTAssertFalse(pdf.isInlineImage)
    }

    // MARK: - 渲染

    func testImageBoundsUsesSavedSizeWhenPresent() throws {
        let image = try Self.makeImage(width: 100, height: 50)
        let resized = NativeAttachment(id: UUID(), name: "a.png", storedName: "data:image/png;base64,AA",
                                       displayWidth: 300, displayHeight: 150)
        let bounds = DocumentTextCodec.imageBounds(for: image, attachment: resized)
        XCTAssertEqual(bounds.width, 300)
        XCTAssertEqual(bounds.height, 150)
    }

    func testImageBoundsFallsBackToDefaultCapWithoutSavedSize() throws {
        let image = try Self.makeImage(width: 1200, height: 800)
        let bounds = DocumentTextCodec.imageBounds(for: image, attachment: nil)
        XCTAssertEqual(bounds.width, 480, "没拖动过就套用默认上限 480×320")
        XCTAssertEqual(bounds.height, 320)
    }

    func testRenderedAttachmentCarriesSavedBounds() throws {
        let encoded = try Self.png().base64EncodedString()
        let attachment = NativeAttachment(id: UUID(), name: "a.png",
                                          storedName: "data:image/png;base64," + encoded,
                                          displayWidth: 260, displayHeight: 130)
        let document = NativeDocument(blocks: [
            DocumentBlock(kind: .paragraph, runs: [DocumentRun(text: "\u{FFFC}", attachment: attachment)])
        ])
        let rendered = DocumentTextCodec.render(document)
        let marker = (rendered.string as NSString).range(of: "\u{FFFC}").location
        XCTAssertNotEqual(marker, NSNotFound)
        let cell = try XCTUnwrap(rendered.attribute(.attachment, at: marker,
                                                    effectiveRange: nil) as? NSTextAttachment)
        XCTAssertEqual(cell.bounds.width, 260, "重新渲染要沿用保存的尺寸")
        XCTAssertEqual(cell.bounds.height, 130)
    }

    // MARK: - 拖动交互

    func testHandleHitRectSitsAtBottomRightOfImage() throws {
        let view = try Self.makeEditor()
        let rect = NSRect(x: 40, y: 100, width: 200, height: 120)
        let handle = view.imageResizeHandleRect(forRect: rect)
        XCTAssertEqual(handle.maxX, rect.maxX)
        XCTAssertEqual(handle.minY, rect.minY)
        XCTAssertEqual(handle.width, NativeTextView.ImageResizeMetrics.handleSize)
    }

    func testDraggingResizesProportionallyAndCommits() throws {
        let view = try Self.makeEditor()
        let png = try Self.png(width: 400, height: 200)
        let attachment = NativeAttachment(id: UUID(), name: "图.png",
                                          storedName: "data:image/png;base64," + png.base64EncodedString())
        let document = NativeDocument(blocks: [
            DocumentBlock(kind: .paragraph, runs: [DocumentRun(text: "\u{FFFC}", attachment: attachment)])
        ])
        view.textStorage?.setAttributedString(DocumentTextCodec.render(document))
        view.setSelectedRange(NSRange(location: 1, length: 0))
        view.display()

        let rect = try XCTUnwrap(view.imageViewRect(at: 0), "图片几何应可计算")
        XCTAssertEqual(rect.width, 400, accuracy: 1)
        XCTAssertEqual(rect.height, 200, accuracy: 1)

        let handlePoint = NSPoint(x: rect.maxX - 2, y: rect.minY + 2)
        XCTAssertTrue(view.beginImageResize(at: handlePoint), "右下角应命中手柄")

        // 向右下拖 50pt：等比放大。
        view.continueImageResize(to: NSPoint(x: handlePoint.x + 50, y: handlePoint.y - 50))
        view.endImageResize()

        let data = try XCTUnwrap(view.textStorage?.attribute(DocumentTextCodec.attachmentKey, at: 0,
                                                             effectiveRange: nil) as? Data)
        let updated = try JSONDecoder().decode(NativeAttachment.self, from: data)
        let size = try XCTUnwrap(updated.displaySize, "松手后尺寸要写进模型")
        XCTAssertGreaterThan(size.width, 400, "向右下拖应放大")
        XCTAssertEqual(size.width / size.height, 2.0, accuracy: 0.05, "保持原始宽高比")
    }

    func testEndWithoutDragKeepsOriginalSize() throws {
        let view = try Self.makeEditor()
        let png = try Self.png(width: 200, height: 100)
        let attachment = NativeAttachment(id: UUID(), name: "图.png",
                                          storedName: "data:image/png;base64," + png.base64EncodedString())
        let document = NativeDocument(blocks: [
            DocumentBlock(kind: .paragraph, runs: [DocumentRun(text: "\u{FFFC}", attachment: attachment)])
        ])
        view.textStorage?.setAttributedString(DocumentTextCodec.render(document))
        view.display()

        let rect = try XCTUnwrap(view.imageViewRect(at: 0))
        XCTAssertTrue(view.beginImageResize(at: NSPoint(x: rect.maxX - 2, y: rect.minY + 2)))
        view.endImageResize()   // 没有拖动就松手

        let data = try XCTUnwrap(view.textStorage?.attribute(DocumentTextCodec.attachmentKey, at: 0,
                                                             effectiveRange: nil) as? Data)
        let updated = try JSONDecoder().decode(NativeAttachment.self, from: data)
        XCTAssertNil(updated.displaySize, "没拖动不应该写入尺寸")
    }

    func testImageIsNotResizableWhenNotEditable() throws {
        let view = try Self.makeEditor()
        let png = try Self.png(width: 200, height: 100)
        let attachment = NativeAttachment(id: UUID(), name: "图.png",
                                          storedName: "data:image/png;base64," + png.base64EncodedString())
        let document = NativeDocument(blocks: [
            DocumentBlock(kind: .paragraph, runs: [DocumentRun(text: "\u{FFFC}", attachment: attachment)])
        ])
        view.textStorage?.setAttributedString(DocumentTextCodec.render(document))
        view.display()
        view.isEditable = false

        let rect = try XCTUnwrap(view.imageViewRect(at: 0))
        XCTAssertNil(view.imageResizeHandle(at: NSPoint(x: rect.maxX - 2, y: rect.minY + 2)),
                     "只读预览不能改尺寸")
    }

    func testResizeIsUndoable() throws {
        let view = try Self.makeEditor()
        view.window?.orderFront(nil)
        let png = try Self.png(width: 400, height: 200)
        let attachment = NativeAttachment(id: UUID(), name: "图.png",
                                          storedName: "data:image/png;base64," + png.base64EncodedString())
        let document = NativeDocument(blocks: [
            DocumentBlock(kind: .paragraph, runs: [DocumentRun(text: "\u{FFFC}", attachment: attachment)])
        ])
        view.textStorage?.setAttributedString(DocumentTextCodec.render(document))
        view.display()

        let rect = try XCTUnwrap(view.imageViewRect(at: 0))
        let handle = NSPoint(x: rect.maxX - 2, y: rect.minY + 2)
        XCTAssertTrue(view.beginImageResize(at: handle))
        view.continueImageResize(to: NSPoint(x: handle.x + 40, y: handle.y - 40))
        view.endImageResize()

        func savedSize() throws -> (width: Double, height: Double)? {
            let data = try XCTUnwrap(view.textStorage?.attribute(DocumentTextCodec.attachmentKey, at: 0,
                                                                 effectiveRange: nil) as? Data)
            return try JSONDecoder().decode(NativeAttachment.self, from: data).displaySize
        }
        let resized = try XCTUnwrap(try savedSize(), "拖动后应写入尺寸")
        XCTAssertGreaterThan(resized.width, 400)

        view.undoManager?.undo()
        XCTAssertNil(try savedSize(), "撤销应把尺寸退回未设置状态")
    }

    func testMinimumSizeIsEnforced() throws {
        let view = try Self.makeEditor()
        let png = try Self.png(width: 400, height: 200)
        let attachment = NativeAttachment(id: UUID(), name: "图.png",
                                          storedName: "data:image/png;base64," + png.base64EncodedString())
        let document = NativeDocument(blocks: [
            DocumentBlock(kind: .paragraph, runs: [DocumentRun(text: "\u{FFFC}", attachment: attachment)])
        ])
        view.textStorage?.setAttributedString(DocumentTextCodec.render(document))
        view.display()

        let rect = try XCTUnwrap(view.imageViewRect(at: 0))
        let handle = NSPoint(x: rect.maxX - 2, y: rect.minY + 2)
        XCTAssertTrue(view.beginImageResize(at: handle))
        // 往左上狂拖：不能小于下限。
        view.continueImageResize(to: NSPoint(x: handle.x - 2000, y: handle.y + 2000))
        view.endImageResize()

        let data = try XCTUnwrap(view.textStorage?.attribute(DocumentTextCodec.attachmentKey, at: 0,
                                                             effectiveRange: nil) as? Data)
        let updated = try JSONDecoder().decode(NativeAttachment.self, from: data)
        let size = try XCTUnwrap(updated.displaySize)
        XCTAssertGreaterThanOrEqual(size.width, NativeTextView.ImageResizeMetrics.minimumSide)
        XCTAssertGreaterThanOrEqual(size.height, NativeTextView.ImageResizeMetrics.minimumSide)
    }

    // MARK: - Fixtures

    private static func makeEditor() throws -> NativeTextView {
        let view = NativeTextView(frame: NSRect(x: 0, y: 0, width: 600, height: 400),
                                  textContainer: nil)
        view.isEditable = true
        let window = NSWindow(contentRect: view.frame, styleMask: [.borderless],
                              backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = view
        window.makeFirstResponder(view)
        return view
    }

    private static func png(width: CGFloat = 24, height: CGFloat = 18) throws -> Data {
        let bitmap = try XCTUnwrap(NSBitmapImageRep(
            bitmapDataPlanes: nil, pixelsWide: Int(width), pixelsHigh: Int(height),
            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
            colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0))
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)
        NSColor.systemBlue.setFill()
        NSRect(x: 0, y: 0, width: width, height: height).fill()
        NSGraphicsContext.restoreGraphicsState()
        return try XCTUnwrap(bitmap.representation(using: .png, properties: [:]))
    }

    private static func makeImage(width: CGFloat, height: CGFloat) throws -> NSImage {
        try XCTUnwrap(NSImage(data: try png(width: width, height: height)))
    }
}
