import XCTest
@testable import WorkFollow

final class MeetingPiOwnershipTests: XCTestCase {
    func testNativeMeetingLayerDoesNotConnectToModelEndpoints() throws {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
        for relative in ["WorkFollow/Infrastructure/Meeting/MeetingPiClient.swift",
                         "WorkFollow/Infrastructure/Meeting/MeetingPiStreamingSession.swift",
                         "WorkFollow/Infrastructure/Meeting/MeetingRecorder.swift",
                         "WorkFollow/Features/Meetings/MeetingStore.swift"] {
            let text = try String(contentsOf: root.appendingPathComponent(relative), encoding: .utf8)
            for forbidden in ["URLSession", "webSocketTask", "maas.aliyuncs.com", "Authorization: Bearer"] {
                XCTAssertFalse(text.contains(forbidden), "Model transport must remain inside the AI backend: \(relative)")
            }
        }
        let client = try String(contentsOf: root.appendingPathComponent("WorkFollow/Infrastructure/Meeting/MeetingPiClient.swift"), encoding: .utf8)
        XCTAssertFalse(client.contains("Process()"), "Native AI callers must not launch engine processes")
    }

    /// 2026-10-07：设置框里粘成多行会让 Pi `Error: Model "…" not found` 直接退出，
    /// 而界面只报「Pi 调用失败，请检查 Pi 中的模型…」，把矛头指向 Pi 的配置。
    /// 两个拉起 Pi 的位置都必须走归一化后的值。
    func testPiModelArgumentUsesTheNormalizedValue() throws {
        var configuration = MeetingPiConfiguration()
        configuration.model = "qwen3.8-omni-flash-realtime\nqwen3.8-omni-flash-realtime\n"
        XCTAssertEqual(configuration.resolvedModel, "qwen3.8-omni-flash-realtime")
        // 用户输入本身不被偷偷改写，只在传给 Pi 时归一化。
        XCTAssertEqual(configuration.model, "qwen3.8-omni-flash-realtime\nqwen3.8-omni-flash-realtime\n")

        configuration.model = "   "
        XCTAssertEqual(configuration.resolvedModel, "", "全空白等同于留空，沿用 Pi 当前模型")

        configuration.minutesModel = " P/text \n重复值"
        configuration.transcriptionModel = " P/voice \n重复值"
        XCTAssertEqual(configuration.backendParameters(transcription: false)["model"] as? String, "P/text")
        XCTAssertEqual(configuration.backendParameters(transcription: true)["model"] as? String, "P/voice")
    }
}
