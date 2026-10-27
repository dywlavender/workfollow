import AppKit
import SwiftUI
import XCTest
@testable import WorkFollow

@MainActor
final class AIModelSettingsInteractionTests: XCTestCase {
    private final class Probe {
        var triggers: [String: CGRect] = [:]
        var rows: [BusinessMenuRowFrame] = []
    }
    private func environment() throws -> AppEnvironment {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("ai-model-settings-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: root) }
        try NativePreviewRepository(directory: root).save(NativeWorkspaceSnapshot(tasks: [], notes: []))
        let environment = AppEnvironment(directory: root)
        environment.settingsSection = .ai
        environment.meetingStore.configuration.transcriptionModel = "ali-Pi/qwen-audio-3.1-asr-flash-streaming"
        environment.meetingStore.configuration.minutesModel = "A/text-alpha"
        return environment
    }
    private func host(environment: AppEnvironment, catalog: PiModelCatalog, probe: Probe, dark: Bool = false) -> NSWindow {
        let root = SettingsShellView(aiCatalog: catalog).environmentObject(environment)
            .preferredColorScheme(dark ? .dark : .light)
            .coordinateSpace(name: "business-menu")
            .onPreferenceChange(BusinessMenuTriggerFrames.self) { probe.triggers = $0 }
            .environment(\.popupContentObservation, { content in
                AnyView(content.coordinateSpace(name: "business-menu")
                    .onPreferenceChange(BusinessMenuRowFrames.self) { if !$0.isEmpty { probe.rows = $0 } })
            })
        let window = InspectorPanelTestSupport.ownerWindow(for: NSHostingView(rootView: root), width: 560, height: 520)
        window.appearance = NSAppearance(named: dark ? .darkAqua : .aqua)
        InspectorPanelTestSupport.settle(window)
        return window
    }
    private func screenshot(_ window: NSWindow, name: String) throws {
        let view = try XCTUnwrap(window.contentView)
        let bitmap = try XCTUnwrap(view.bitmapImageRepForCachingDisplay(in: view.bounds))
        view.cacheDisplay(in: view.bounds, to: bitmap)
        let data = try XCTUnwrap(bitmap.representation(using: .png, properties: [:]))
        try data.write(to: URL(fileURLWithPath: "/private/tmp/wf-native-ai-model-settings-20261026-\(name).png"))
    }

    func testRoleDropdownSelectionUpdatesOnlyItsScenarioAndCloses() throws {
        let environment = try environment(), probe = Probe()
        let catalog = PiModelCatalog { _ in [
            PiModelChoice(modelID: "text-alpha", provider: "A", name: "Text Alpha"),
            PiModelChoice(modelID: "text-beta", provider: "B", name: "Text Beta"),
            PiModelChoice(modelID: "qwen-audio-3.1-asr-flash-streaming", provider: "ali-Pi")
        ] }
        let window = host(environment: environment, catalog: catalog, probe: probe)
        defer { window.close() }
        try InspectorPanelTestSupport.waitUntil(timeout: 3) { catalog.models.count == 3 && !catalog.loading && probe.triggers["文字处理模型"] != nil }
        let frame = try XCTUnwrap(probe.triggers["文字处理模型"])
        try InspectorPanelTestSupport.click(frame, in: try XCTUnwrap(window.contentView), window: window)
        let menu = try InspectorPanelTestSupport.panel(title: "文字处理模型", below: window)
        XCTAssertEqual(probe.rows.count, 3, "默认选项与两个文字模型，不混入纯语音模型")
        try InspectorPanelTestSupport.click(try XCTUnwrap(probe.rows.last?.rect), in: try XCTUnwrap(menu.contentView), window: menu)
        XCTAssertEqual(environment.meetingStore.configuration.resolvedMinutesModel, "B/text-beta")
        XCTAssertEqual(environment.meetingStore.configuration.resolvedTranscriptionModel, "ali-Pi/qwen-audio-3.1-asr-flash-streaming")
        XCTAssertFalse(menu.isVisible)
        try screenshot(window, name: "light")
        let speech = try XCTUnwrap(probe.triggers["语音转写模型"])
        try InspectorPanelTestSupport.click(speech, in: try XCTUnwrap(window.contentView), window: window)
        let speechMenu = try InspectorPanelTestSupport.panel(title: "语音转写模型", below: window)
        XCTAssertEqual(probe.rows.count, 1)
        try InspectorPanelTestSupport.sendEscape(to: speechMenu)
        XCTAssertEqual(environment.meetingStore.configuration.resolvedMinutesModel, "B/text-beta")
    }

    func testReadFailureLeavesSavedModelsVisibleInDarkMode() throws {
        let environment = try environment(), probe = Probe()
        let catalog = PiModelCatalog { _ in throw PiModelCatalogError.invalidResponse }
        let window = host(environment: environment, catalog: catalog, probe: probe, dark: true)
        defer { window.close() }
        try InspectorPanelTestSupport.waitUntil(timeout: 3) { catalog.error != nil && !catalog.loading }
        XCTAssertEqual(environment.meetingStore.configuration.resolvedMinutesModel, "A/text-alpha")
        XCTAssertEqual(environment.meetingStore.configuration.resolvedTranscriptionModel, "ali-Pi/qwen-audio-3.1-asr-flash-streaming")
        try screenshot(window, name: "dark-error")
    }
}
