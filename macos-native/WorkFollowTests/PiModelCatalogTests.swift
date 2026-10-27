import XCTest
@testable import WorkFollow

@MainActor
final class PiModelCatalogTests: XCTestCase {
    private let response = #"{"type":"response","id":"workfollow-models","command":"get_available_models","success":true,"data":{"models":[{"id":"shared","provider":"B","name":"Shared B","input":["text"],"headers":{"ignored":"value"}},{"id":"shared","provider":"A","name":"Shared A","input":["text"]},{"id":"shared","provider":"A","input":["text"]},{"id":"qwen-audio-3.1-asr-flash-streaming","provider":"ali-Pi","input":["text"]}]}}"#

    private func directory() throws -> URL {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("pi-models-test-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: root) }
        return root
    }
    private func fixture(_ root: URL, body: String) throws -> URL {
        let script = root.appendingPathComponent("fixture-pi")
        try ("#!/usr/bin/env python3\n" + body + "\n").write(to: script, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: script.path)
        return script
    }

    func testStructuredCatalogKeepsProviderIdentityAndIgnoresUnrelatedEvents() throws {
        XCTAssertNil(try PiModelCatalogClient.models(from: Data(#"{"type":"agent_start"}"#.utf8)))
        let models = try XCTUnwrap(PiModelCatalogClient.models(from: Data(response.utf8)))
        XCTAssertEqual(models.map(\.id), ["A/shared", "B/shared", "ali-Pi/qwen-audio-3.1-asr-flash-streaming"])
        XCTAssertEqual(models.first?.title, "Shared A")
        XCTAssertThrowsError(try PiModelCatalogClient.models(from: Data(#"{"id":"workfollow-models","command":"get_available_models","success":false}"#.utf8)))
    }

    func testRoleFilteringUsesTheActualAudioTransportRatherThanTextInputMetadata() {
        let voice = PiModelChoice(modelID: "qwen-audio-3.1-asr-flash-streaming", provider: "ali-Pi")
        XCTAssertTrue(voice.supportsTranscription)
        XCTAssertFalse(voice.supportsText, "Pi 当前将该语音模型也标为 text，不能直接据此用作文字生成")
        XCTAssertTrue(PiModelChoice(modelID: "qwen-audio-3.1-asr-flash", provider: "ali-Pi").supportsTranscription)
        XCTAssertTrue(PiModelChoice(modelID: "qwen3.8-omni-flash-realtime", provider: "ali-Pi").supportsTranscription)
        XCTAssertFalse(PiModelChoice(modelID: "qwen-audio-3.1-asr-flash-filetrans", provider: "ali-Pi").supportsTranscription)
        XCTAssertFalse(PiModelChoice(modelID: "gemini-3.8-live", provider: "Gemini-Pi").supportsText)
        XCTAssertTrue(PiModelChoice(modelID: "text-model", provider: "provider").supportsText)
    }

    func testLegacyShortNamesResolveOnlyWhenUnambiguous() async throws {
        let models = try XCTUnwrap(PiModelCatalogClient.models(from: Data(response.utf8)))
        let catalog = PiModelCatalog { _ in models }
        await catalog.refresh(executable: "fixture")
        XCTAssertNil(catalog.model(for: "shared"))
        XCTAssertEqual(catalog.model(for: "B/shared")?.title, "Shared B")
        XCTAssertEqual(catalog.model(for: "qwen-audio-3.1-asr-flash-streaming")?.provider, "ali-Pi")
    }

    func testRPCQueryRequestsModelsWithoutGeneratingContent() async throws {
        let root = try directory()
        let script = try fixture(root, body: """
        import json, pathlib, sys
        command = json.loads(sys.stdin.readline())
        pathlib.Path(__file__).with_name('request.json').write_text(json.dumps({'arguments':sys.argv[1:], 'command':command}))
        print('diagnostic line', flush=True)
        print(\(String(reflecting: response)), flush=True)
        """)
        let models = try await PiModelCatalogClient().fetch(executable: script.path)
        XCTAssertEqual(models.count, 3)
        let record = try JSONSerialization.jsonObject(with: Data(contentsOf: root.appendingPathComponent("request.json"))) as? [String: Any]
        let command = record?["command"] as? [String: String]
        XCTAssertEqual(command?["type"], "get_available_models")
        XCTAssertNil(command?["message"])
        XCTAssertTrue((record?["arguments"] as? [String])?.contains("--no-session") == true)
    }

    func testRefreshReplacesCatalogAndFailureKeepsTheLastList() async {
        var calls = 0
        let first = PiModelChoice(modelID: "first", provider: "P"), second = PiModelChoice(modelID: "second", provider: "P")
        let catalog = PiModelCatalog { _ in
            calls += 1
            if calls == 3 { throw PiModelCatalogError.invalidResponse }
            return calls == 1 ? [first] : [second]
        }
        await catalog.refresh(executable: "fixture")
        XCTAssertEqual(catalog.models, [first])
        await catalog.refresh(executable: "fixture")
        XCTAssertEqual(catalog.models, [second])
        await catalog.refresh(executable: "fixture")
        XCTAssertEqual(catalog.models, [second])
        XCTAssertNotNil(catalog.error)
        XCTAssertFalse(catalog.loading)
    }

    func testTimeoutAndCancellationStopTheOwnedQuery() async throws {
        let root = try directory()
        let script = try fixture(root, body: "import pathlib, time\npathlib.Path(__file__).with_name('started').write_text('yes')\ntime.sleep(5)")
        var client = PiModelCatalogClient(); client.timeout = 0.2
        do { _ = try await client.fetch(executable: script.path); XCTFail("Expected timeout") }
        catch { XCTAssertTrue(error.localizedDescription.contains("超时")) }
        if FileManager.default.fileExists(atPath: root.appendingPathComponent("started").path) {
            try FileManager.default.removeItem(at: root.appendingPathComponent("started"))
        }
        let work = _Concurrency.Task { try await PiModelCatalogClient().fetch(executable: script.path) }
        for _ in 0..<300 {
            if FileManager.default.fileExists(atPath: root.appendingPathComponent("started").path) { break }
            try await _Concurrency.Task.sleep(for: .milliseconds(10))
        }
        XCTAssertTrue(FileManager.default.fileExists(atPath: root.appendingPathComponent("started").path))
        work.cancel()
        do { _ = try await work.value; XCTFail("Expected cancellation") } catch is CancellationError { }
    }

    func testRoleSelectionsPersistAndRemainIndependent() async throws {
        let root = try directory()
        let store = MeetingStore(directory: root, automaticallyUpdate: false)
        store.configuration.transcriptionModel = "ali-Pi/qwen-audio-3.1-asr-flash-streaming"
        store.configuration.minutesModel = "P/text-model"
        await withCheckedContinuation { continuation in store.flush { _ in continuation.resume() } }
        let restored = MeetingStore(directory: root, automaticallyUpdate: false)
        XCTAssertEqual(restored.configuration.forTranscription().resolvedModel, "ali-Pi/qwen-audio-3.1-asr-flash-streaming")
        XCTAssertEqual(restored.configuration.forMinutes().resolvedModel, "P/text-model")
        restored.configuration.minutesModel = ""
        XCTAssertEqual(restored.configuration.resolvedMinutesModel, "")
        XCTAssertEqual(restored.configuration.resolvedTranscriptionModel, store.configuration.resolvedTranscriptionModel)
    }

    func testInstalledPiCatalogWhenEnabled() async throws {
        guard ProcessInfo.processInfo.environment["PI_MODEL_CATALOG_INTEGRATION"] == "1" else {
            throw XCTSkip("Enable PI_MODEL_CATALOG_INTEGRATION=1 to query installed Pi metadata")
        }
        let models = try await PiModelCatalogClient().fetch(executable: "/opt/homebrew/bin/pi")
        XCTAssertFalse(models.isEmpty)
        XCTAssertTrue(models.allSatisfy { !$0.provider.isEmpty && !$0.modelID.isEmpty })
        XCTAssertTrue(models.contains { $0.supportsText })
        XCTAssertTrue(models.contains { $0.supportsTranscription })
    }
}
