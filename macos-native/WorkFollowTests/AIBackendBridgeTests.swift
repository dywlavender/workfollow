import XCTest
@testable import WorkFollow

@MainActor
final class AIBackendBridgeTests: XCTestCase {
    private func fixture() throws -> (AIBackendBridge, URL) {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("ai-backend-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let script = root.appendingPathComponent("backend.py")
        try #"""
        import json, os, pathlib, sys
        root = pathlib.Path(__file__).parent
        with (root / 'starts').open('a') as f: f.write(str(os.getpid()) + '\n')
        print('{"ready":1}', flush=True)
        for line in sys.stdin:
            request = json.loads(line)
            method = request.get('method')
            if method == 'cancel':
                (root / 'cancelled').write_text(request['params']['requestID'])
            elif method == 'crash':
                sys.exit(1)
            elif method == 'wait':
                (root / 'waiting').write_text('ready')
            elif method == 'event':
                print(json.dumps({'channel':request['params']['channel'],'event':{'kind':'final','text':'最后一句'}}),flush=True)
                print(json.dumps({'id':request['id'],'result':{}}),flush=True)
            elif method == 'limited':
                print(json.dumps({'id':request['id'],'error':{'code':'rate_limited','message':'模型服务触发速率限制','retryAfterSeconds':12.5}}),flush=True)
            elif method == 'note.rewrite':
                (root / 'request.json').write_text(json.dumps(request))
                print(json.dumps({'channel':request['params']['progressChannel'],'event':{'kind':'text','text':'正在输出的正文'}}),flush=True)
                print(json.dumps({'id':request['id'],'result':{'text':'完整草稿'}}),flush=True)
            else:
                (root / 'request.json').write_text(json.dumps(request))
                print(json.dumps({'id':request['id'],'result':{'text':'草稿','protocol':1}}),flush=True)
        (root / 'stopped').write_text('EOF')
        """#.write(to: script, atomically: true, encoding: .utf8)
        let bridge = AIBackendBridge(root: root, launch: { _ in
            (URL(fileURLWithPath: "/usr/bin/python3"), ["-u", script.path])
        })
        addTeardownBlock { bridge.shutdown(); try? FileManager.default.removeItem(at: root) }
        return (bridge, root)
    }

    private func wait(_ condition: () -> Bool) async throws {
        for _ in 0..<300 {
            if condition() { return }
            try await _Concurrency.Task.sleep(for: .milliseconds(10))
        }
        XCTFail("Backend did not settle")
    }

    func testScenariosShareOneBackendAndCarryStructuredOptions() async throws {
        let (bridge, root) = try fixture()
        var client = SummaryPiOptimizer(); client.backend = bridge; client.model = "P/text"
        var options = SummaryAIOptions(); options.length = .brief; options.profession = "产品经理"
        let text = try await client.optimize(text: "尾部事实", options: options)
        XCTAssertEqual(text, "草稿")
        let request = try XCTUnwrap(try JSONSerialization.jsonObject(with: Data(contentsOf: root.appendingPathComponent("request.json"))) as? [String: Any])
        XCTAssertEqual(request["method"] as? String, "text.summary")
        let params = try XCTUnwrap(request["params"] as? [String: Any])
        XCTAssertEqual(params["content"] as? String, "尾部事实")
        XCTAssertEqual(params["model"] as? String, "P/text")
        XCTAssertEqual((params["options"] as? [String: Any])?["profession"] as? String, "产品经理")
        async let one: AITextResponse = bridge.call("one")
        async let two: AITextResponse = bridge.call("two")
        _ = try await (one, two)
        XCTAssertEqual(try String(contentsOf: root.appendingPathComponent("starts"), encoding: .utf8).split(separator: "\n").count, 1)
        bridge.shutdown()
        try await wait { FileManager.default.fileExists(atPath: root.appendingPathComponent("stopped").path) }
    }

    func testCancellationAndTimeoutCancelOnlyTheRequest() async throws {
        let (bridge, root) = try fixture()
        let work = _Concurrency.Task { () -> AITextResponse in try await bridge.call("wait") }
        try await wait { FileManager.default.fileExists(atPath: root.appendingPathComponent("waiting").path) }
        work.cancel()
        do { _ = try await work.value; XCTFail("Cancelled request returned a result") }
        catch is CancellationError { }
        try await wait { FileManager.default.fileExists(atPath: root.appendingPathComponent("cancelled").path) }
        do {
            let _: AITextResponse = try await bridge.call("wait", timeout: 0.1)
            XCTFail("Expected timeout")
        } catch { XCTAssertTrue(error.localizedDescription.contains("超时")) }
        let _: AITextResponse = try await bridge.call("still-alive")
        XCTAssertEqual(try String(contentsOf: root.appendingPathComponent("starts"), encoding: .utf8).split(separator: "\n").count, 1)
    }

    func testUnexpectedExitFailsCurrentRequestAndNextRequestRestarts() async throws {
        let (bridge, root) = try fixture()
        do {
            let _: AITextResponse = try await bridge.call("crash", timeout: 3)
            XCTFail("Expected disconnection")
        } catch { XCTAssertTrue(error.localizedDescription.contains("退出")) }
        let _: AITextResponse = try await bridge.call("retry")
        XCTAssertEqual(try String(contentsOf: root.appendingPathComponent("starts"), encoding: .utf8).split(separator: "\n").count, 2)
    }

    func testMissingBundledRuntimeReportsInstallationProblem() async {
        let bridge = AIBackendBridge(root: URL(fileURLWithPath: "/nonexistent-workfollow-ai"))
        do {
            let _: EmptyAIResponse = try await bridge.call("health")
            XCTFail("Expected missing runtime")
        } catch { XCTAssertTrue(error.localizedDescription.contains("完整应用")) }
    }

    func testAgentTextUsesChannelWithoutChunkJobsAndServiceFailureKeepsRetryDelay() async throws {
        let (bridge, root) = try fixture()
        var client = SummaryPiOptimizer(); client.backend = bridge
        let request = NoteRewriteRequest(noteID: UUID(), title: "虚构笔记", content: "保留细节。", action: .polish)
        let progress = expectation(description: "agent text")
        let text = try await client.rewriteNote(request) { event in
            XCTAssertEqual(event.text, "正在输出的正文")
            progress.fulfill()
        }
        await fulfillment(of: [progress], timeout: 2)
        XCTAssertEqual(text, "完整草稿")
        let payload = try XCTUnwrap(try JSONSerialization.jsonObject(with: Data(contentsOf: root.appendingPathComponent("request.json"))) as? [String: Any])
        XCTAssertNil((payload["params"] as? [String: Any])?["jobID"])
        do {
            let _: EmptyAIResponse = try await bridge.call("limited")
            XCTFail("Expected rate limit")
        } catch let AIBackendError.service(code, message, delay) {
            XCTAssertEqual(code, "rate_limited"); XCTAssertTrue(message.contains("速率限制")); XCTAssertEqual(delay, 12.5)
        }
    }
}
