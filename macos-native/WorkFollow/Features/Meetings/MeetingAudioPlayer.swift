import AVFoundation
import Combine

/// 会议录音回放：分段录音按 offset 拼成一条时间轴，一段放完自动接下一段。
@MainActor
final class MeetingAudioPlayer: ObservableObject {
    struct Track: Equatable {
        let url: URL
        let start: TimeInterval
        let duration: TimeInterval
        var end: TimeInterval { start + duration }
    }

    @Published private(set) var playing = false
    @Published private(set) var position: TimeInterval = 0
    @Published private(set) var duration: TimeInterval = 0
    @Published var error: String?

    private var player: AVAudioPlayer?
    private var timer: AnyCancellable?
    private var tracks: [Track] = []
    private var trackIndex = 0

    /// 单文件回放入口：时间轴从 0 开始。
    func play(url: URL, offset: TimeInterval) {
        play(tracks: [Track(url: url, start: 0, duration: 0)], from: offset)
    }

    func play(tracks nextTracks: [Track], from offset: TimeInterval) {
        let ordered = nextTracks.sorted { $0.start < $1.start }
        guard !ordered.isEmpty else { stop(); return }
        tracks = ordered
        duration = ordered.map(\.end).max() ?? 0
        guard let index = Self.trackIndex(containing: offset, in: ordered) else { stop(); return }
        load(index, at: max(0, offset - ordered[index].start), autoplay: true)
        startTimer()
    }

    func toggle() {
        guard let player else {
            guard !tracks.isEmpty else { return }
            play(tracks: tracks, from: position >= duration - 0.05 ? 0 : position)
            return
        }
        if player.isPlaying {
            player.pause()
        } else if player.currentTime >= player.duration - 0.05, trackIndex + 1 < tracks.count {
            load(trackIndex + 1, at: 0, autoplay: true)
        } else {
            player.play()
        }
        playing = self.player?.isPlaying ?? false
    }

    func seek(_ value: TimeInterval) {
        guard !tracks.isEmpty else { return }
        let wasPlaying = playing
        let target = min(max(0, value), max(duration, 0))
        guard let index = Self.trackIndex(containing: target, in: tracks) else { return }
        if index != trackIndex || player == nil {
            load(index, at: max(0, target - tracks[index].start), autoplay: wasPlaying)
        } else if let player {
            player.currentTime = min(max(0, target - tracks[index].start), player.duration)
            position = target
        }
    }

    func stop() {
        player?.stop()
        player = nil
        timer?.cancel()
        timer = nil
        playing = false
        duration = 0
        position = 0
        tracks = []
        trackIndex = 0
    }

    /// 时间轴落在哪一段：两段之间或首段之前回落到最近的已知起点。
    static func trackIndex(containing offset: TimeInterval, in tracks: [Track]) -> Int? {
        guard !tracks.isEmpty else { return nil }
        return tracks.lastIndex(where: { $0.start <= offset }) ?? tracks.startIndex
    }

    private func load(_ index: Int, at localOffset: TimeInterval, autoplay: Bool) {
        guard tracks.indices.contains(index) else { stop(); return }
        do {
            let next = try AVAudioPlayer(contentsOf: tracks[index].url)
            next.currentTime = min(max(0, localOffset), max(0, next.duration - 0.01))
            if autoplay { next.play() }
            player = next
            trackIndex = index
            playing = autoplay
            error = nil
            position = tracks[index].start + next.currentTime
            duration = max(tracks.map(\.end).max() ?? 0, tracks[index].start + next.duration)
        } catch {
            player = nil
            playing = false
            self.error = "无法播放这段录音：\(error.localizedDescription)"
        }
    }

    private func startTimer() {
        timer?.cancel()
        timer = Timer.publish(every: 0.25, on: .main, in: .common).autoconnect().sink { [weak self] _ in
            self?.tick()
        }
    }

    private func tick() {
        guard let player, tracks.indices.contains(trackIndex) else {
            timer?.cancel()
            timer = nil
            return
        }
        position = tracks[trackIndex].start + player.currentTime
        if player.isPlaying {
            playing = true
        } else if player.currentTime >= player.duration - 0.05 {
            if trackIndex + 1 < tracks.count {
                load(trackIndex + 1, at: 0, autoplay: true)
            } else {
                playing = false
                self.player = nil
                timer?.cancel()
                timer = nil
            }
        } else {
            playing = false
        }
    }
}
