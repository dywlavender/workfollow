import XCTest
@testable import WorkFollow

/// Opt-in installed-Pi integration. This tests RPC/extension transport with an
/// explicitly synthetic extension; it never calls a model or uploads audio.
final class MeetingPiBridgeIntegrationTests: XCTestCase {
    func testInstalledPiDispatchesAudioCommandAndReturnsStructuredNotification() async throws {
        guard ProcessInfo.processInfo.environment["MEETING_PI_INTEGRATION"] == "1",
              FileManager.default.isExecutableFile(atPath: "/opt/homebrew/bin/pi") else {
            throw XCTSkip("Enable MEETING_PI_INTEGRATION=1 with Pi installed to verify the transport")
        }
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("meeting-pi-transport-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let extensionFile = root.appendingPathComponent("transport-fixture.ts")
        let source = """
        export default function(pi) {
          pi.registerCommand('wf-meeting-audio', {
            description: 'Synthetic RPC transport fixture, not a speech recognizer',
            handler: async (args, ctx) => {
              const input = JSON.parse(args);
              if (input.version !== 2 || input.offset !== 15 || input.file ||
                  input.audio !== 'AQIDBA==' || input.sampleRate !== 16000 || input.format !== 'pcm16') {
                throw new Error('Bad meeting command');
              }
              ctx.ui.notify('WF_MEETING_RESULT ' + JSON.stringify({
                version: 1, segments: [{text: 'synthetic protocol payload', start: 2}]
              }), 'info');
            }
          });
        }
        """
        try source.write(to: extensionFile, atomically: true, encoding: .utf8)
        var configuration = MeetingPiConfiguration()
        configuration.audioExtension = extensionFile.path
        let lines = try await MeetingPiClient().transcribe(configuration: configuration,
            packet: MeetingAudioPacket(pcm: Data([1, 2, 3, 4]), offset: 15), speakers: [])
        XCTAssertEqual(lines.map(\.text), ["synthetic protocol payload"])
        XCTAssertEqual(lines.map(\.offset), [17])
        XCTAssertEqual(lines.map(\.speaker), ["未区分"])
    }
}
