import XCTest
@testable import WorkFollow

@MainActor
final class MeetingModelConfigurationTests: XCTestCase {
    func testLegacyHTTPConfigurationMigratesToStreamingAndIndependentMinutes() throws {
        let old = Data(#"{"executable":"/opt/homebrew/bin/pi","model":"ali-Pi/qwen-audio-3.1-asr-flash","audioExtension":""}"#.utf8)
        let configuration = try JSONDecoder().decode(MeetingPiConfiguration.self, from: old)
        XCTAssertEqual(configuration.resolvedTranscriptionModel, "ali-Pi/qwen-audio-3.1-asr-flash-streaming")
        XCTAssertEqual(configuration.resolvedMinutesModel, "")
        XCTAssertFalse(configuration.usesHTTPTranscription)
        XCTAssertEqual(configuration.model, "ali-Pi/qwen-audio-3.1-asr-flash")
        XCTAssertEqual(MeetingPiConfiguration().resolvedTranscriptionModel, MeetingPiConfiguration.defaultTranscriptionModel)
    }

    func testExplicitRolesRoundTripAndCustomAdapterPreservesLegacyModel() throws {
        var configuration = MeetingPiConfiguration()
        configuration.model = "ali-Pi/qwen-audio-3.1-asr-flash"
        configuration.audioExtension = "/custom/adapter.mjs"
        XCTAssertEqual(configuration.resolvedTranscriptionModel, configuration.model)
        configuration.audioExtension = ""
        configuration.transcriptionModel = "ali-Pi/qwen-audio-3.1-asr-flash\nignored"
        configuration.minutesModel = "  text-provider/text-model\nignored"
        let restored = try JSONDecoder().decode(MeetingPiConfiguration.self, from: JSONEncoder().encode(configuration))
        XCTAssertTrue(restored.usesHTTPTranscription)
        XCTAssertEqual(restored.forTranscription().resolvedModel, "ali-Pi/qwen-audio-3.1-asr-flash")
        XCTAssertEqual(restored.forMinutes().resolvedModel, "text-provider/text-model")
        XCTAssertFalse(restored.minutesUsesASR)
    }

    func testMinutesLaunchesTextModelWithoutAudioExtension() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("meeting-models-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let arguments = root.appendingPathComponent("arguments.txt")
        let executable = root.appendingPathComponent("pi-fixture")
        try """
        #!/bin/zsh
        print -rl -- "$@" > '\(arguments.path)'
        read -r input
        print -r -- '{"type":"message_end","message":{"role":"assistant","stopReason":"stop","content":[{"type":"text","text":"# 合成纪要"}]}}'
        print -r -- '{"type":"agent_settled"}'
        """.write(to: executable, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: executable.path)
        var configuration = MeetingPiConfiguration()
        configuration.executable = executable.path
        configuration.transcriptionModel = "ali-Pi/qwen-audio-3.1-asr-flash-streaming"
        configuration.minutesModel = "text-provider/text-model"
        let result = try await MeetingPiClient().updateMinutes(configuration: configuration, minutes: "",
            lines: [MeetingTranscriptLine(speaker: "未区分", text: "周五提交。", offset: 0)])
        XCTAssertEqual(result, "# 合成纪要")
        let received = try String(contentsOf: arguments, encoding: .utf8).split(separator: "\n").map(String.init)
        let modelFlag = try XCTUnwrap(received.firstIndex(of: "--model"))
        XCTAssertEqual(received[modelFlag + 1], "text-provider/text-model")
        XCTAssertTrue(received.contains("--no-context-files"))
        XCTAssertFalse(received.contains("--extension"))
        XCTAssertFalse(received.contains(configuration.resolvedTranscriptionModel))
    }

    func testASRMinutesSelectionFailsBeforeLaunchingPi() async throws {
        var configuration = MeetingPiConfiguration()
        configuration.executable = "/nonexistent-pi"
        configuration.minutesModel = MeetingPiConfiguration.defaultTranscriptionModel
        do {
            _ = try await MeetingPiClient().updateMinutes(configuration: configuration, minutes: "保留",
                lines: [MeetingTranscriptLine(speaker: "未区分", text: "周五提交。", offset: 0)])
            XCTFail("ASR cannot generate minutes")
        } catch {
            XCTAssertTrue(error.localizedDescription.contains("纪要模型需要支持文字生成"))
        }
    }
}
