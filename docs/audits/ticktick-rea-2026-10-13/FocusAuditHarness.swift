import AppKit
import Combine
import Foundation

enum NativePreviewRepository {
    static var directory: URL { URL(fileURLWithPath: "/private/tmp/workfollow-rea-audit/unused") }
}

final class AuditClock {
    var now = Date(timeIntervalSince1970: 1_800_000_000)
    func advance(_ seconds: TimeInterval) { now = now.addingTimeInterval(seconds) }
}

@main
struct FocusAuditHarness {
    @MainActor
    static func main() {
        let base = URL(fileURLWithPath: "/private/tmp/workfollow-rea-audit/focus-harness-\(UUID().uuidString)")
        func store(_ clock: AuditClock, _ name: String) -> FocusStore {
            FocusStore(clock: { clock.now }, directory: base.appendingPathComponent(name))
        }
        func flush(_ store: FocusStore) {
            let done = DispatchSemaphore(value: 0)
            store.flush { error in
                if let error { print("flush-error=\(error.localizedDescription)") }
                done.signal()
            }
            _ = done.wait(timeout: .now() + 5)
        }

        let presetClock = AuditClock()
        let presetStore = store(presetClock, "preset")
        _ = presetStore.start(minutes: 25)
        _ = presetStore.addTimer(name: "深度工作", emoji: "📖", stopwatch: false, minutes: 50)
        presetStore.applyTimerPreset(presetStore.timers[0])
        let originalPlan = presetStore.phaseSeconds / 60
        presetClock.advance(25 * 60)
        presetStore.refresh()
        print("preset-change: original-plan=\(originalPlan), saved-minutes=\(presetStore.visibleRecords.first?.minutes ?? -1), phase=\(presetStore.phase)")

        let publicationClock = AuditClock()
        let publicationStore = store(publicationClock, "publication")
        _ = publicationStore.setStopwatchMode(true)
        _ = publicationStore.start()
        var publicationCount = 0
        let subscription = publicationStore.objectWillChange.sink { publicationCount += 1 }
        publicationClock.advance(90)
        publicationStore.refresh()
        print("stopwatch-refresh: elapsed=\(publicationStore.elapsedSeconds), remaining=\(publicationStore.remainingSeconds), change-events=\(publicationCount)")
        withExtendedLifetime(subscription) {}

        let overrideClock = AuditClock()
        let overrideStore = store(overrideClock, "override")
        _ = overrideStore.start(taskID: UUID(), stopwatch: true)
        print("explicit-stopwatch: preference=\(overrideStore.preferences.stopwatchMode), actual-no-end=\(overrideStore.sessionTiming?.projectedEndAt == nil), plan=\(overrideStore.phaseSeconds)")
        flush(overrideStore)
        let restored = FocusStore(clock: { overrideClock.now }, directory: base.appendingPathComponent("override"))
        print("restored-stopwatch: preference=\(restored.preferences.stopwatchMode), actual-no-end=\(restored.sessionTiming?.projectedEndAt == nil), phase=\(restored.phase)")

        let pauseClock = AuditClock()
        let pauseStore = store(pauseClock, "paused-end")
        _ = pauseStore.start(minutes: 25)
        pauseClock.advance(2 * 60)
        _ = pauseStore.pause()
        let shortRecord = pauseStore.giveUp()
        _ = pauseStore.start(minutes: 25)
        pauseClock.advance(10 * 60)
        _ = pauseStore.pause()
        let longRecord = pauseStore.giveUp()
        print("paused-end: 2-minute-record=\(shortRecord != nil), 10-minute-completed=\(longRecord?.completed ?? true), today-pomodoros=\(pauseStore.todayPomodoros), today-minutes=\(pauseStore.todayMinutes)")

        let finishClock = AuditClock()
        let finishStore = store(finishClock, "stopwatch-finish")
        _ = finishStore.setStopwatchMode(true)
        _ = finishStore.start()
        finishClock.advance(90)
        let stopwatchRecord = finishStore.finishEarly()
        print("stopwatch-finish: minutes=\(stopwatchRecord?.minutes ?? -1), completed=\(stopwatchRecord?.completed ?? false), tomato-count=\(finishStore.todayPomodoros), phase=\(finishStore.phase)")

        let manualClock = AuditClock()
        let manualStore = store(manualClock, "manual")
        _ = manualStore.addRecord(taskID: nil, startedAt: manualClock.now.addingTimeInterval(-3600), minutes: 60)
        print("manual-focus: minutes=\(manualStore.todayMinutes), tomato-count=\(manualStore.todayPomodoros)")

        let autoClock = AuditClock()
        let autoStore = store(autoClock, "auto")
        _ = autoStore.setAutoStartNextPomodoro(true)
        _ = autoStore.start(minutes: 5)
        autoClock.advance(5 * 60)
        autoStore.refresh()
        autoClock.advance(5 * 60)
        autoStore.refresh()
        print("unlinked-auto-start: enabled=\(autoStore.preferences.autoStartNextPomodoro), after-break=\(autoStore.phase)")

        print("bell-names: selected-raw-resolves=\(NSSound(named: FocusBell.crisp.rawValue) != nil), selected-system-name-resolves=\(NSSound(named: FocusBell.crisp.soundName!) != nil)")
    }
}
