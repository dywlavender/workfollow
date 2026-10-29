import AppKit
import SwiftUI
import XCTest
@testable import WorkFollow

@MainActor
final class MemoryAIModelCredentials: AIModelCredentials {
    var values: [UUID: String] = [:]
    func read(_ id: UUID) throws -> String? { values[id] }
    func write(_ value: String?, for id: UUID) throws { values[id] = value?.isEmpty == false ? value : nil }
}

@MainActor
final class AIModelSettingsTests: XCTestCase {
    private func directory() throws -> URL {
        let path = FileManager.default.temporaryDirectory.appendingPathComponent("ai-settings-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: path, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: path) }
        return path
    }
    private func profile(_ model: String = "fixture-model", protocolKind: AIModelProtocol = .openAIChat) -> AIModelProfile {
        var value = AIModelProfile(); value.protocolKind = protocolKind
        value.model = model; value.baseURL = protocolKind.defaultURL
        return value
    }

    func testSavedModelsReloadAndKeysStayOutOfTheSettingsFile() throws {
        let root = try directory(), keys = MemoryAIModelCredentials()
        let store = AIModelStore(directory: root, credentials: keys)
        XCTAssertEqual(store.engine, .pi)
        let first = try store.save(profile("first"), key: "private-test-key-one")
        let second = try store.save(profile("second", protocolKind: .openAIResponses), key: "private-test-key-two")
        let restored = AIModelStore(directory: root, credentials: keys)
        XCTAssertEqual(restored.profiles.count, 2)
        XCTAssertEqual(try restored.request()?.profile.id, second.id)
        XCTAssertEqual(try restored.request()?.key, "private-test-key-two")
        try restored.select(first.id)
        XCTAssertEqual(try restored.request()?.key, "private-test-key-one")
        let raw = try String(contentsOf: root.appendingPathComponent("ai-models.json"), encoding: .utf8)
        XCTAssertFalse(raw.contains("private-test-key"))
        XCTAssertFalse(raw.contains("ai_api_key"))
        try restored.usePi(); XCTAssertNil(try restored.request())
        try restored.select(second.id)
        try restored.delete(second.id)
        XCTAssertNil(keys.values[second.id])
        XCTAssertEqual(try restored.request()?.profile.id, first.id)
    }

    func testFailedSaveRestoresThePreviousCredentialAndModel() throws {
        let root = try directory(), keys = MemoryAIModelCredentials()
        let original = AIModelStore(directory: root, credentials: keys)
        let saved = try original.save(profile(), key: "previous-test-key")
        let failing = AIModelStore(directory: root, credentials: keys, writeFile: { _, _ in
            throw CocoaError(.fileWriteNoPermission)
        })
        var updated = saved; updated.model = "other-model"
        XCTAssertThrowsError(try failing.save(updated, key: "replacement-test-key"))
        XCTAssertEqual(try failing.request()?.key, "previous-test-key")
        XCTAssertEqual(try failing.request()?.profile.model, "fixture-model")
    }

    func testValidationSupportsKeylessLocalCompatibleServices() throws {
        var local = profile(); local.baseURL = "http://localhost:11434/v1"
        XCTAssertNoThrow(try local.validated(key: ""))
        local.protocolKind = .openAIResponses
        XCTAssertNoThrow(try local.validated(key: ""))
        local.protocolKind = .gemini
        XCTAssertThrowsError(try local.validated(key: ""))
        var invalid = profile(); invalid.baseURL = "https://proxy.example/v1?api_key=wrong-place"
        XCTAssertThrowsError(try invalid.validated(key: "test-key"))
        invalid = profile(); invalid.contextWindow = 2048
        XCTAssertThrowsError(try invalid.validated(key: "test-key"))
    }

    func testSavedMetadataWithAMissingKeyDoesNotSilentlyFallBackToPi() throws {
        let root = try directory(), keys = MemoryAIModelCredentials()
        let store = AIModelStore(directory: root, credentials: keys)
        let value = try store.save(profile(), key: "test-key")
        keys.values.removeValue(forKey: value.id)
        XCTAssertThrowsError(try store.request())
        XCTAssertEqual(store.engine, .langchain)
    }

    func testOnlyOpenAIProtocolsAreSelectableAndOlderProfilesRemainReadable() throws {
        XCTAssertEqual(AIModelProtocol.allCases, [.openAIChat, .openAIResponses])
        let root = try directory(), keys = MemoryAIModelCredentials()
        let value = profile(protocolKind: .anthropic)
        let old: [String: Any] = ["engine": "langchain", "profiles": [try JSONSerialization.jsonObject(with: JSONEncoder().encode(value))], "selectedID": value.id.uuidString]
        try JSONSerialization.data(withJSONObject: old).write(to: root.appendingPathComponent("ai-models.json"))
        keys.values[value.id] = "fixture-key"
        let store = AIModelStore(directory: root, credentials: keys)
        XCTAssertEqual(store.profiles.first?.protocolKind, .anthropic)
        XCTAssertNil(store.loadError)
        XCTAssertThrowsError(try store.request())
    }

    func testAllProtocolsReachTextAndMinutesRequests() async throws {
        let root = try directory()
        let script = root.appendingPathComponent("backend.py")
        try #"""
        import json, pathlib, sys
        root = pathlib.Path(__file__).parent
        print('{"ready":1}',flush=True)
        for line in sys.stdin:
            request=json.loads(line)
            if 'id' not in request: continue
            (root/'request.json').write_text(json.dumps(request))
            print(json.dumps({'id':request['id'],'result':{'text':'合成结果','success':True}}),flush=True)
        """#.write(to: script, atomically: true, encoding: .utf8)
        let backend = AIBackendBridge(root: root, launch: { _ in (URL(fileURLWithPath: "/usr/bin/python3"), ["-u", script.path]) })
        defer { backend.shutdown() }
        let store = AIModelStore(directory: root, credentials: MemoryAIModelCredentials())
        for kind in AIModelProtocol.allCases {
            let value = try store.save(profile(protocolKind: kind), key: "test-only-key")
            var text = SummaryPiOptimizer(); text.backend = backend; text.textModel = try store.request()
            _ = try await text.optimize(text: "任务事实", options: SummaryAIOptions())
            let record = try XCTUnwrap(try JSONSerialization.jsonObject(with: Data(contentsOf: root.appendingPathComponent("request.json"))) as? [String: Any])
            let params = try XCTUnwrap(record["params"] as? [String: Any])
            XCTAssertEqual(params["engine"] as? String, "langchain")
            let config = try XCTUnwrap(params["configuration"] as? [String: Any])
            XCTAssertEqual(config["ai_protocol"] as? String, kind.rawValue)
            XCTAssertEqual(config["ai_model"] as? String, value.model)
            var legacy = MeetingPiConfiguration(); legacy.minutesModel = MeetingPiConfiguration.defaultTranscriptionModel
            let meeting = MeetingPiClient(backend: backend, textModel: { try store.request() })
            _ = try await meeting.updateMinutes(configuration: legacy, minutes: "",
                lines: [MeetingTranscriptLine(speaker: "A", text: "周五交付", offset: 0)])
            let request = try XCTUnwrap(try JSONSerialization.jsonObject(with: Data(contentsOf: root.appendingPathComponent("request.json"))) as? [String: Any])
            XCTAssertEqual(request["method"] as? String, "meeting.minutes")
        }
        try store.usePi()
        let before = store.profiles
        try await store.test(profile(), key: "test-key", backend: backend)
        XCTAssertEqual(store.engine, .pi)
        XCTAssertEqual(store.profiles, before, "测试连接不应保存或激活输入中的模型")
    }

    func testSettingsFormSavesAnEditedModelAndKeepsTheKeyMasked() throws {
        let root = try directory(), keys = MemoryAIModelCredentials()
        let models = AIModelStore(directory: root, credentials: keys)
        let saved = try models.save(profile(), key: "test-only-key")
        let catalog = PiModelCatalog { _ in [] }
        var saveFrame = CGRect.zero
        let view = SettingsAIModelsView(store: MeetingStore(directory: root, automaticallyUpdate: false), models: models, catalog: catalog)
            .frame(width: 560, height: 520)
            .onPreferenceChange(AIModelSaveFrameKey.self) { saveFrame = $0 }
        let host = NSHostingView(rootView: AnyView(view))
        let window = InspectorPanelTestSupport.ownerWindow(for: host, width: 560, height: 520)
        defer { window.contentView = nil; window.close() }
        InspectorPanelTestSupport.settle(window)
        func fields(_ view: NSView) -> [NSTextField] {
            (view as? NSTextField).map { [$0] } ?? view.subviews.flatMap(fields)
        }
        let name = try XCTUnwrap(fields(host).first { $0.stringValue == saved.model })
        XCTAssertTrue(fields(host).contains { $0 is NSSecureTextField })
        XCTAssertTrue(window.makeFirstResponder(name))
        let editor = try XCTUnwrap(name.currentEditor())
        editor.selectAll(nil)
        editor.insertText("fixture-updated")
        window.makeFirstResponder(nil)
        InspectorPanelTestSupport.settle(window)
        XCTAssertFalse(saveFrame.isEmpty)
        XCTAssertTrue(host.bounds.contains(saveFrame), "保存按钮应在设置窗口内")
        try InspectorPanelTestSupport.click(saveFrame, in: host, window: window)
        XCTAssertEqual(models.profiles.first?.model, "fixture-updated")
        XCTAssertEqual(try models.key(for: saved.id), "test-only-key")
        if let bitmap = host.bitmapImageRepForCachingDisplay(in: host.bounds) {
            host.cacheDisplay(in: host.bounds, to: bitmap)
            try bitmap.representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: "/private/tmp/workfollow-ai-model-settings.png"))
        }
    }
}
