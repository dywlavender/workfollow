import AppKit
import SwiftUI
import XCTest
@testable import WorkFollow

@MainActor
final class AIConversationComposerTests: XCTestCase {
    private final class RunningComposer: ObservableObject, AIConversationComposing {
        @Published var input = "准备下一问"
        @Published var isRunning = true
        let attachments: AIAttachmentDraft
        var canSend = true
        var stopCount = 0
        init(directory: URL) { attachments = AIAttachmentDraft(directory: directory) }
        func stop() { stopCount += 1; isRunning = false }
    }
    private func wait(_ condition: () -> Bool) async throws {
        for _ in 0..<500 {
            if condition() { return }
            try await _Concurrency.Task.sleep(for: .milliseconds(15))
        }
        XCTFail("Shared composer interaction did not settle")
    }
    private func descendants(_ view: NSView) -> [NSView] { [view] + view.subviews.flatMap(descendants) }
    private func directory() throws -> URL {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("ai-composer-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: root) }
        return root
    }

    func testReturnDuringGenerationKeepsDraftAndOnlyButtonStopsForBothSizes() throws {
        for compact in [false, true] {
            let model = RunningComposer(directory: try directory())
            var sent = 0
            var anchors: [String: NSView] = [:]
            let host = NSHostingView(rootView: AIConversationComposer(
                model: model, placeholder: "输入要求",
                submit: { sent += 1 }, compact: compact)
                .environment(\.workflowActionObservation, { anchors[$0] = $1 })
                .padding(20).frame(width: compact ? 360 : 760, height: 230))
            let window = InspectorPanelTestSupport.ownerWindow(for: host, width: compact ? 360 : 760, height: 230)
            defer { window.contentView = nil; window.close() }
            let input = try XCTUnwrap(descendants(host).compactMap { $0 as? AIConversationInput.Input }.first)
            window.makeFirstResponder(input)
            let event = try XCTUnwrap(NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [],
                timestamp: 0, windowNumber: window.windowNumber, context: nil, characters: "\r",
                charactersIgnoringModifiers: "\r", isARepeat: false, keyCode: 36))
            input.keyDown(with: event)
            XCTAssertEqual(sent, 0)
            XCTAssertEqual(model.stopCount, 0)
            XCTAssertEqual(model.input, "准备下一问")
            let button = try XCTUnwrap(anchors["ai.chat.send"])
            try InspectorPanelTestSupport.click(button.bounds, in: button, window: window)
            XCTAssertEqual(model.stopCount, 1)
            XCTAssertEqual(sent, 0)
        }
    }

    func testNoteSidebarSharedComposerPastesImageStopsBackendAndCanRunAgain() async throws {
        let root = try directory(), environment = AppEnvironment(directory: root)
        environment.focusStore.notifier = nil
        let pi = root.appendingPathComponent("fixture-pi")
        try #"""
        #!/usr/bin/python3
        import json,sys,time,pathlib
        for line in sys.stdin:
            request=json.loads(line)
            if '本轮快捷提问：将当前内容整理为' in request['message']:
                pathlib.Path(__file__).with_name('started.json').write_text(json.dumps({'images':len(request.get('images', []))}))
                text='已生成的虚构要点，图片='+str(len(request.get('images', [])))
                print(json.dumps({'type':'message_update','assistantMessageEvent':{'type':'text_delta','delta':text}}),flush=True)
                time.sleep(30)
            else:
                text='虚构笔记的完整润色正文'
            print(json.dumps({'type':'message_end','message':{'role':'assistant','stopReason':'stop','content':[{'type':'text','text':text}]}}),flush=True)
            print('{"type":"agent_settled"}',flush=True)
        """#.write(to: pi, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: pi.path)
        environment.meetingStore.configuration.executable = pi.path
        let id = environment.notesWorkspace.create()
        environment.notesWorkspace.edit(id) { $0.title = "虚构笔记"; $0.document = NativeDocument(plainText: "周五核对方案。") }
        environment.navigation.destination = .notes
        var anchors: [String: NSView] = [:]
        let host = NSHostingView(rootView: RootShellView(workspace: environment.taskWorkspace, navigation: environment.navigation)
            .environmentObject(environment).environment(\.workflowActionObservation, { anchors[$0] = $1 })
            .frame(width: 1200, height: 800))
        let window = InspectorPanelTestSupport.ownerWindow(for: host, width: 1200, height: 800)
        defer { window.contentView = nil; window.close() }
        try await wait { anchors["note.ai"] != nil }
        let open = try XCTUnwrap(anchors["note.ai"])
        try InspectorPanelTestSupport.click(open.bounds, in: open, window: window)
        try await wait { anchors["note.ai.composer"] != nil }
        let input = try XCTUnwrap(descendants(host).compactMap { $0 as? AIConversationInput.Input }.first)
        let clipboard = NSPasteboard.withUniqueName()
        defer { clipboard.releaseGlobally() }
        let bitmap = try XCTUnwrap(NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 16, pixelsHigh: 16,
            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
            colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0))
        let png = try XCTUnwrap(bitmap.representation(using: .png, properties: [:]))
        clipboard.setData(png, forType: .png)
        XCTAssertTrue(input.receiveAttachments(from: clipboard))
        try await wait { anchors.keys.contains { $0.hasPrefix("ai.attachment.remove.") && anchors[$0]?.window === window } }
        let organize = try XCTUnwrap(anchors["note.ai.organize"])
        try InspectorPanelTestSupport.click(organize.bounds, in: organize, window: window)
        let marker = root.appendingPathComponent("started.json")
        try await wait { FileManager.default.fileExists(atPath: marker.path) }
        let received = try JSONSerialization.jsonObject(with: Data(contentsOf: marker)) as? [String: Int]
        XCTAssertEqual(received?["images"], 1)
        let stop = try XCTUnwrap(anchors["note.ai.send"])
        try InspectorPanelTestSupport.click(stop.bounds, in: stop, window: window)
        try await wait {
            descendants(host).compactMap { $0 as? NSButton }.contains { $0.title == "继续回复" } ||
            anchors["note.ai.polish"]?.window === window
        }
        XCTAssertNil(anchors["note.ai.save"]?.window)
        let polish = try XCTUnwrap(anchors["note.ai.polish"])
        try InspectorPanelTestSupport.click(polish.bounds, in: polish, window: window)
        try await wait { anchors["note.ai.save"]?.window === window }
        XCTAssertTrue(descendants(host).compactMap { $0 as? NSTextView }.contains { $0.string.contains("完整润色正文") })
    }
}
