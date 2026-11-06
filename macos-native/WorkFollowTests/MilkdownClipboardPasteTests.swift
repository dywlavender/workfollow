import AppKit
import SwiftUI
import XCTest
@testable import WorkFollow

@MainActor
final class MilkdownClipboardPasteTests: XCTestCase {
    private func fixture(_ document: NativeDocument = NativeDocument(plainText: "目标")) async throws -> (MilkdownEditorRuntimeTests.Model, MilkdownWebView, NSWindow) {
        let model = MilkdownEditorRuntimeTests.Model(); model.document = document
        let host = NSHostingView(rootView: MilkdownEditorRuntimeTests.Host(model: model))
        let window = InspectorPanelTestSupport.ownerWindow(for: host, width: 720, height: 480)
        addTeardownBlock { @MainActor in window.contentView = nil; window.close() }
        let editor = try await MilkdownTestSupport.editorAsync(in: host)
        try MilkdownTestSupport.command(editor, "focusEnd")
        return (model, editor, window)
    }
    private func png() throws -> Data {
        let bitmap = try XCTUnwrap(NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 8, pixelsHigh: 4,
            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
            colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0))
        return try XCTUnwrap(bitmap.representation(using: .png, properties: [:]))
    }

    func testMixedImagePasteIsOneUndoableTransactionAtCapturedSelection() async throws {
        let (model, view, _) = try await fixture()
        let original = model.document, data = try png()
        let plan = try XCTUnwrap(DocumentExternalClipboardCodec.imagePlan(fromHTML:
            "<p>前<img src='https://images.invalid/one' alt='一'/>中<img src='https://images.invalid/two' alt='二'/>后</p>"))
        let target = try XCTUnwrap(MilkdownClipboardPasteTarget(editor: view))
        let result = await view.paste(plan: plan, target: target, imageLoader: { _ in data })
        XCTAssertTrue(result)
        XCTAssertTrue(model.document.plainText.contains("前\u{fffc}中\u{fffc}后"))
        XCTAssertEqual(model.document.blocks.flatMap(\.runs).compactMap(\.attachment).map(\.name), ["一", "二"])
        try MilkdownTestSupport.command(view, "undo"); await view.flush()
        XCTAssertEqual(model.document, original)
    }

    func testSlowPasteDoesNotOverwriteSubsequentInput() async throws {
        let (model, view, _) = try await fixture()
        let data = try png()
        let plan = try XCTUnwrap(DocumentExternalClipboardCodec.imagePlan(fromHTML: "<p>图片<img src='https://images.invalid/one'/></p>"))
        let target = try XCTUnwrap(MilkdownClipboardPasteTarget(editor: view))
        let result = await view.paste(plan: plan, target: target, imageLoader: { _ in
            try MilkdownTestSupport.command(view, "insertText", ["text": "随后输入"])
            await view.flush()
            return data
        })
        XCTAssertFalse(result)
        XCTAssertEqual(model.document.plainText, "目标随后输入")
        XCTAssertTrue(model.document.blocks.flatMap(\.runs).compactMap(\.attachment).isEmpty)
    }

    func testSlowPasteRejectsSwitchedDocument() async throws {
        let (model, view, _) = try await fixture()
        let data = try png()
        let plan = try XCTUnwrap(DocumentExternalClipboardCodec.imagePlan(fromHTML: "<img src='https://images.invalid/one'/>"))
        let target = try XCTUnwrap(MilkdownClipboardPasteTarget(editor: view))
        let result = await view.paste(plan: plan, target: target, imageLoader: { _ in
            model.id = UUID(); model.document = NativeDocument(plainText: "另一篇")
            for _ in 0..<100 {
                if view.isDocumentReady && view.documentIdentity == model.id { break }
                try await _Concurrency.Task.sleep(for: .milliseconds(20))
            }
            return data
        })
        XCTAssertFalse(result); XCTAssertEqual(model.document.plainText, "另一篇")
    }

    func testKeyboardCopyOfHeadingPrefixPastesInlineWithoutSplittingTarget() async throws {
        let (model, view, _) = try await fixture(NativeDocument(blocks: [.init(kind: .heading(2), runs: [.init(text: "ABCDE")]), .init(kind: .paragraph, runs: [.init(text: "xyz")])]))
        let originalItems = NSPasteboard.general.pasteboardItems?.map { item in
            item.types.compactMap { type in item.data(forType: type).map { (type, $0) } }
        } ?? []
        defer {
            NSPasteboard.general.clearContents()
            let items = originalItems.map { values in let item = NSPasteboardItem(); for (type, data) in values { item.setData(data, forType: type) }; return item }
            if !items.isEmpty { NSPasteboard.general.writeObjects(items) }
        }
        NSPasteboard.general.clearContents()
        try MilkdownTestSupport.select(view, NSRange(location: 0, length: 2))
        try MilkdownTestSupport.script(view, "document.querySelector('.ProseMirror').dispatchEvent(new ClipboardEvent('copy',{bubbles:true,cancelable:true,clipboardData:new DataTransfer()}))")
        try MilkdownTestSupport.wait("复制片段未发布") { DocumentClipboardCodec.read(from: .general)?.document.plainText == "AB" }
        let fragment = try XCTUnwrap(DocumentClipboardCodec.read(from: .general))
        XCTAssertTrue(fragment.startsAtParagraphBoundary); XCTAssertFalse(fragment.endsAtParagraphBoundary)
        let board = NSPasteboard.withUniqueName()
        defer { board.releaseGlobally() }
        XCTAssertTrue(DocumentClipboardCodec.write(fragment, to: board))
        try MilkdownTestSupport.select(view, NSRange(location: 7, length: 0))
        XCTAssertFalse(view.isReadOnly)
        XCTAssertEqual(DocumentClipboardCodec.read(from: board)?.document.plainText, "AB")
        view.paste(from: board)
        for _ in 0..<100 {
            if model.document.plainText == "ABCDE\nxAByz" { break }
            try await _Concurrency.Task.sleep(for: .milliseconds(20))
        }
        await view.flush()
        let wire = try MilkdownTestSupport.call(view, "getDoc")
        XCTAssertNil(view.loadError)
        XCTAssertEqual(model.document.plainText, "ABCDE\nxAByz", "wire: \(wire)")
        XCTAssertEqual(model.document.blocks.count, 2)
        XCTAssertEqual(model.document.blocks[1].kind, .paragraph)
    }
}
