import AppKit
import SwiftUI
import XCTest
@testable import WorkFollow

@MainActor
final class AIConversationAttachmentTests: XCTestCase {
    private func directory() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("ai-attachment-tests-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: url) }
        return url
    }
    private func image() throws -> Data {
        let bitmap = try XCTUnwrap(NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 24, pixelsHigh: 24,
            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
            colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0))
        let color = NSColor(deviceRed: 0.15, green: 0.45, blue: 0.9, alpha: 1)
        for x in 0..<24 { for y in 0..<24 { bitmap.setColor(color, atX: x, y: y) } }
        return try XCTUnwrap(bitmap.representation(using: .png, properties: [:]))
    }
    private func wait(_ condition: () -> Bool) async throws {
        for _ in 0..<500 {
            if condition() { return }
            try await _Concurrency.Task.sleep(for: .milliseconds(15))
        }
        XCTFail("Attachment interaction did not settle")
    }
    private func descendants(_ view: NSView) -> [NSView] { [view] + view.subviews.flatMap(descendants) }

    private func paste(_ data: Data, type: NSPasteboard.PasteboardType, into input: NSTextView, window: NSWindow) {
        let clipboard = NSPasteboard.general
        let saved = (clipboard.pasteboardItems ?? []).map { original in
            let copy = NSPasteboardItem()
            for type in original.types { if let data = original.data(forType: type) { copy.setData(data, forType: type) } }
            return copy
        }
        defer { clipboard.clearContents(); clipboard.writeObjects(saved) }
        clipboard.clearContents(); clipboard.setData(data, forType: type)
        window.makeFirstResponder(input)
        let item = NSMenuItem(title: "粘贴", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        item.keyEquivalentModifierMask = .command
        XCTAssertTrue(input.validateUserInterfaceItem(item), "图片在剪贴板时，⌘V 和粘贴菜单必须可用")
        // The isolated XCTest host has no application menu loop; start at its real first responder.
        XCTAssertTrue(window.firstResponder?.tryToPerform(#selector(NSText.paste(_:)), with: item) == true)
    }

    func testPasteCommandAcceptsScreenshotCopiedImageAndImageFile() async throws {
        let environment = AppEnvironment(directory: try directory())
        environment.focusStore.notifier = nil
        environment.navigation.destination = .aiChat
        let host = NSHostingView(rootView: RootShellView(workspace: environment.taskWorkspace, navigation: environment.navigation)
            .environmentObject(environment).frame(width: 1100, height: 740))
        let window = InspectorPanelTestSupport.ownerWindow(for: host, width: 1100, height: 740)
        defer { window.contentView = nil; window.close() }
        let input = try XCTUnwrap(descendants(host).compactMap { $0 as? AIConversationInput.Input }.first)
        let png = try image()
        paste(png, type: .png, into: input, window: window)
        let model = environment.aiChat.current
        try await wait { model.attachments.items.count == 1 }
        let tiff = try XCTUnwrap(NSBitmapImageRep(data: png)?.tiffRepresentation)
        paste(tiff, type: .tiff, into: input, window: window)
        try await wait { model.attachments.items.count == 2 }
        let jpeg = try XCTUnwrap(NSBitmapImageRep(data: png)?.representation(using: .jpeg, properties: [:]))
        paste(jpeg, type: NSPasteboard.PasteboardType("public.jpeg"), into: input, window: window)
        try await wait { model.attachments.items.count == 3 }
        let file = try directory().appendingPathComponent("复制的图片.png")
        try png.write(to: file)
        paste(try XCTUnwrap(file.dataRepresentation), type: .fileURL, into: input, window: window)
        try await wait { model.attachments.items.count == 4 }
        XCTAssertTrue(model.attachments.items.allSatisfy(\.isImage))
        XCTAssertTrue(model.canSend)
        XCTAssertEqual(input.string, "")
    }

    func testImageOnlyConversationPersistsAndRetryKeepsOriginalAttachment() async throws {
        let root = try directory(), store = AIChatStore(directory: root)
        let model = store.current
        model.attachments.add(image: try image())
        try await wait { !model.attachments.isImporting }
        let attached = try XCTUnwrap(model.attachments.items.first)
        XCTAssertTrue(model.canSend)
        model.send { _, _, _, _, _ in throw SummaryPiError.failed("测试中断") }
        try await wait { !model.isRunning }
        XCTAssertEqual(model.submittedAttachments, [attached])
        XCTAssertTrue(model.attachments.items.isEmpty)
        XCTAssertEqual(model.record.title, "粘贴的图片.png")
        let failed = try XCTUnwrap(model.record.messages.last?.id)
        model.retry(failed) { _, _, _, message, _ in
            XCTAssertEqual(message, "")
            XCTAssertEqual(model.submittedAttachments, [attached])
            return "收到图片"
        }
        try await wait { !model.isRunning }
        await withCheckedContinuation { continuation in store.flush { _ in continuation.resume() } }
        let restored = AIChatStore(directory: root)
        XCTAssertEqual(restored.current.record.messages.first?.attachments, [attached])
        store.newConversation()
        XCTAssertTrue(FileManager.default.fileExists(atPath: attached.path), "新对话不能删除历史图片")
        store.select(model.record.id)
        XCTAssertEqual(store.current.submittedAttachments, [attached])
        XCTAssertEqual(store.current.latestResult, "收到图片")
    }

    func testFullShellPasteAndFileDropImportReachPiAndRemovalUpdatesComposer() async throws {
        let root = try directory(), environment = AppEnvironment(directory: root)
        environment.focusStore.notifier = nil
        let pi = root.appendingPathComponent("fixture-pi")
        try #"""
        #!/usr/bin/python3
        import json,sys
        for line in sys.stdin:
            request=json.loads(line)
            count=len(request.get('images', []))
            document='虚构附件正文' in request['message']
            text=f'图片={count} 正文={document}'
            print(json.dumps({'type':'message_end','message':{'role':'assistant','stopReason':'stop','content':[{'type':'text','text':text}]}}),flush=True)
            print('{"type":"agent_settled"}',flush=True)
        """#.write(to: pi, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: pi.path)
        environment.meetingStore.configuration.executable = pi.path
        environment.navigation.destination = .aiChat
        var anchors: [String: NSView] = [:]
        let host = NSHostingView(rootView: RootShellView(workspace: environment.taskWorkspace, navigation: environment.navigation)
            .environmentObject(environment).environment(\.workflowActionObservation, { anchors[$0] = $1 })
            .frame(width: 1100, height: 740))
        let window = InspectorPanelTestSupport.ownerWindow(for: host, width: 1100, height: 740)
        defer { window.contentView = nil; window.close() }
        try await wait { anchors["ai.chat.attach"] != nil }
        let input = try XCTUnwrap(descendants(host).compactMap { $0 as? AIConversationInput.Input }.first)
        let pasteboard = NSPasteboard.withUniqueName()
        defer { pasteboard.releaseGlobally() }
        pasteboard.setData(try image(), forType: .png)
        XCTAssertTrue(input.receiveAttachments(from: pasteboard))
        let model = environment.aiChat.current
        try await wait { model.attachments.items.count == 1 }
        let removed = try XCTUnwrap(model.attachments.items.first)
        let removeID = "ai.attachment.remove.\(removed.id)"
        try await wait { anchors[removeID] != nil }
        let remove = try XCTUnwrap(anchors[removeID])
        try InspectorPanelTestSupport.click(remove.bounds, in: remove, window: window)
        try await wait { model.attachments.items.isEmpty }
        XCTAssertFalse(FileManager.default.fileExists(atPath: removed.path))
        XCTAssertFalse(model.canSend)
        pasteboard.clearContents(); pasteboard.setData(try image(), forType: .png)
        XCTAssertTrue(input.receiveAttachments(from: pasteboard))
        try await wait { model.attachments.items.count == 1 }
        let file = root.appendingPathComponent("虚构文件.md")
        try "虚构附件正文：周五提交演示。".write(to: file, atomically: true, encoding: .utf8)
        pasteboard.clearContents(); pasteboard.writeObjects([file as NSURL])
        // Paste and native drop share this exact pasteboard consumer.
        XCTAssertTrue(input.receiveAttachments(from: pasteboard))
        try await wait { model.attachments.items.count == 2 }
        XCTAssertEqual(input.string, "", "附件不能插入为普通路径文字")
        if let path = ProcessInfo.processInfo.environment["WORKFOLLOW_ATTACHMENT_CAPTURE"] {
            InspectorPanelTestSupport.settle(window)
            let bitmap = try XCTUnwrap(host.bitmapImageRepForCachingDisplay(in: host.bounds))
            host.cacheDisplay(in: host.bounds, to: bitmap)
            try XCTUnwrap(bitmap.representation(using: .png, properties: [:])).write(to: URL(fileURLWithPath: path))
        }
        let send = try XCTUnwrap(anchors["ai.chat.send"])
        try InspectorPanelTestSupport.click(send.bounds, in: send, window: window)
        try await wait { !model.isRunning && model.record.messages.count == 2 }
        XCTAssertEqual(model.latestResult, "图片=1 正文=True")
        XCTAssertEqual(model.record.messages.first?.attachments?.count, 2)
    }

    func testNoteSidebarForwardsAttachmentsToInitialActionFollowupAndRetry() async throws {
        let model = NoteAIConversationModel(directory: try directory())
        let context = NoteAIContext(noteID: UUID(), title: "虚构笔记", content: "原文",
            referenceDate: Date(), existingTitles: [])
        var requests: [[AIConversationAttachment]] = []
        let generate: AIConversationModel.Generate = { _, _, _, _, _ in
            requests.append(model.conversation.submittedAttachments); return "整理结果"
        }
        model.attachments.add(image: try image())
        try await wait { !model.attachments.isImporting }
        let file = try XCTUnwrap(model.attachments.items.first)
        model.ask(.organize, context: context, using: generate)
        try await wait { !model.isRunning }
        let originalMessage = try XCTUnwrap(model.conversation.record.messages.last?.id)
        model.input = "更简短"
        model.send(context: context, using: generate)
        try await wait { !model.isRunning }
        model.retry(messageID: originalMessage, using: generate)
        try await wait { !model.isRunning }
        XCTAssertEqual(requests, [[file], [], [file]], "后续聊天由 Pi 保留图片历史，重试才重新发送原附件")
        let request = AITaskRequest(source: .note(context.noteID), title: context.title, content: context.content,
            referenceDate: context.referenceDate, attachments: [file])
        let drafts = try AITaskDraft.decode(#"{"tasks":[{"title":"提交演示稿","quote":"图片中的明确行动"}]}"#, request: request)
        XCTAssertEqual(drafts.count, 1, "图片原文不能因不在笔记文字中而被静默丢弃")
        XCTAssertTrue(FileManager.default.fileExists(atPath: file.path))
        model.reset()
        XCTAssertFalse(FileManager.default.fileExists(atPath: file.path))
    }
}
