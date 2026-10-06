import XCTest
@testable import WorkFollow

final class MeetingPiOwnershipTests: XCTestCase {
    func testNativeMeetingLayerDoesNotConnectToModelEndpoints() throws {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
        for relative in ["WorkFollow/Infrastructure/Meeting/MeetingPiClient.swift",
                         "WorkFollow/Infrastructure/Meeting/MeetingRecorder.swift",
                         "WorkFollow/Features/Meetings/MeetingStore.swift"] {
            let text = try String(contentsOf: root.appendingPathComponent(relative), encoding: .utf8)
            for forbidden in ["URLSession", "webSocketTask", "maas.aliyuncs.com", "Authorization: Bearer"] {
                XCTAssertFalse(text.contains(forbidden), "Model transport must remain inside Pi: \(relative)")
            }
        }
        let client = try String(contentsOf: root.appendingPathComponent("WorkFollow/Infrastructure/Meeting/MeetingPiClient.swift"), encoding: .utf8)
        XCTAssertTrue(client.contains("\"--extension\", configuration.resolvedAudioExtension"))
        XCTAssertTrue(client.contains("\"--no-session\""))
        XCTAssertTrue(client.contains("/wf-meeting-audio"))
        XCTAssertTrue(client.contains("/wf-meeting-minutes"))
    }
}
