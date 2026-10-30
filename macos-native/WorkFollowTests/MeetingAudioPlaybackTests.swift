import XCTest
@testable import WorkFollow

final class MeetingAudioPlaybackTests: XCTestCase {
    @MainActor
    func testTrackIndexFallsBackToNearestEarlierStart() {
        let tracks = [
            MeetingAudioPlayer.Track(url: URL(fileURLWithPath: "/tmp/a"), start: 0, duration: 60),
            MeetingAudioPlayer.Track(url: URL(fileURLWithPath: "/tmp/b"), start: 60, duration: 30),
            MeetingAudioPlayer.Track(url: URL(fileURLWithPath: "/tmp/c"), start: 120, duration: 10)
        ]
        XCTAssertEqual(MeetingAudioPlayer.trackIndex(containing: 0, in: tracks), 0)
        XCTAssertEqual(MeetingAudioPlayer.trackIndex(containing: 59, in: tracks), 0)
        XCTAssertEqual(MeetingAudioPlayer.trackIndex(containing: 60, in: tracks), 1)
        XCTAssertEqual(MeetingAudioPlayer.trackIndex(containing: 125, in: tracks), 2)
        XCTAssertEqual(MeetingAudioPlayer.trackIndex(containing: 999, in: tracks), 2)
        XCTAssertNil(MeetingAudioPlayer.trackIndex(containing: 0, in: []))
    }

    @MainActor
    func testRecordingPlaylistStartsAtContainingChunkAndSkipsMissingFiles() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("MeetingPlayback-\(UUID())", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        var meeting = MeetingRecord()
        let chunks = [0.0, 60, 120].map { offset in
            MeetingAudioChunk(filename: "meeting-audio/\(meeting.id.uuidString)/\(UUID()).caf",
                              offset: offset, duration: 60)
        }
        // 中间一段文件缺失：回放清单跳过它，但保留后面一段在时间轴上的位置。
        for chunk in [chunks[0], chunks[2]] {
            let url = root.appendingPathComponent(chunk.filename)
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(),
                                                    withIntermediateDirectories: true)
            try Data([0]).write(to: url)
        }
        meeting.audio = chunks
        struct Snapshot: Encodable {
            let meetings: [MeetingRecord]
            let configuration: MeetingPiConfiguration
        }
        try JSONEncoder().encode(Snapshot(meetings: [meeting], configuration: MeetingPiConfiguration()))
            .write(to: root.appendingPathComponent("meetings.json"))
        let store = MeetingStore(directory: root, automaticallyUpdate: false)
        let selected = try XCTUnwrap(store.selected)

        let fromMiddle = store.recordingPlaylist(for: selected, offset: 75)
        XCTAssertEqual(fromMiddle.map(\.start), [120])
        XCTAssertEqual(fromMiddle.first?.duration, 60)

        let fromStart = store.recordingPlaylist(for: selected, offset: 0)
        XCTAssertEqual(fromStart.map(\.start), [0, 120])

        let beyondEnd = store.recordingPlaylist(for: selected, offset: 999)
        XCTAssertEqual(beyondEnd.map(\.start), [120])
    }
}
