import XCTest
import Combine
import AppKit
import SwiftUI
@testable import WorkFollow

@MainActor
final class FocusReplicaFlowTests: XCTestCase {
    private let base = Date(timeIntervalSince1970: 1_800_000_000)
    private func directory() -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent("focus-replica-\(UUID().uuidString)")
    }
    private func flush(_ store: FocusStore) async {
        let done = expectation(description: "focus persisted")
        store.flush { error in XCTAssertNil(error); done.fulfill() }
        await fulfillment(of: [done], timeout: 5)
    }

    func testStopwatchPublishesTicksAndRestoresItsActualModeDespiteNextPreset() async {
        var now = base; let path = directory(); defer { try? FileManager.default.removeItem(at: path) }
        let store = FocusStore(clock: { now }, directory: path)
        XCTAssertTrue(store.start(stopwatch: true))
        var tickValues: [Int] = []
        let subscription = store.$elapsedSeconds.sink { tickValues.append($0) }
        now = base.addingTimeInterval(90); store.refresh()
        XCTAssertEqual(store.presentation.displaySeconds, 90)
        XCTAssertTrue(tickValues.contains(90))
        XCTAssertTrue(store.setStopwatchMode(false))
        XCTAssertTrue(store.setFocusMinutes(50))
        XCTAssertEqual(store.presentation.mode, .stopwatch)
        await flush(store)
        let restored = FocusStore(clock: { now }, directory: path)
        XCTAssertEqual(restored.presentation.mode, .stopwatch)
        XCTAssertEqual(restored.presentation.displaySeconds, 90)
        let record = restored.finishEarly()
        XCTAssertEqual(record?.activeSeconds, 90)
        XCTAssertEqual(record?.creditedPomodoros, 0)
        XCTAssertEqual(restored.phase, .idle)
        withExtendedLifetime(subscription) {}
    }

    func testNextPresetDoesNotChangeCurrentTargetAndExplicitAdjustmentDoes() {
        var now = base; let path = directory(); defer { try? FileManager.default.removeItem(at: path) }
        let store = FocusStore(clock: { now }, directory: path)
        XCTAssertTrue(store.start(minutes: 25))
        XCTAssertTrue(store.addTimer(name: "长写作", emoji: "📚", stopwatch: false, minutes: 50))
        store.applyTimerPreset(store.timers[0])
        XCTAssertEqual(store.phaseSeconds, 25 * 60)
        XCTAssertTrue(store.adjustCurrentTarget(byMinutes: 5))
        XCTAssertEqual(store.phaseSeconds, 30 * 60)
        now = base.addingTimeInterval(30 * 60 + 10); store.refresh()
        let record = store.records.first
        XCTAssertEqual(record?.activeSeconds, 30 * 60)
        XCTAssertEqual(record?.details?.targetSeconds, 30 * 60)
        XCTAssertEqual(record?.endedAt, base.addingTimeInterval(30 * 60))
        XCTAssertEqual(store.preferences.focusMinutes, 50)
        store.refresh()
        XCTAssertEqual(store.records.count, 1)
    }

    func testPauseSegmentsSurviveRestoreAndNeverCountTowardFocus() async {
        var now = base; let path = directory(); defer { try? FileManager.default.removeItem(at: path) }
        let store = FocusStore(clock: { now }, directory: path)
        XCTAssertTrue(store.start(stopwatch: true))
        now = base.addingTimeInterval(90); XCTAssertTrue(store.pause())
        await flush(store)
        now = base.addingTimeInterval(390)
        let restored = FocusStore(clock: { now }, directory: path)
        XCTAssertEqual(restored.elapsedSeconds, 90)
        XCTAssertTrue(restored.resume())
        now = base.addingTimeInterval(480); restored.refresh()
        let record = restored.finishEarly()
        XCTAssertEqual(record?.activeSeconds, 180)
        XCTAssertEqual(record?.details?.pausedSeconds, 300)
        XCTAssertEqual(record?.details?.pauseRanges.count, 1)
        XCTAssertEqual(restored.todayMinutes, 3)
        XCTAssertEqual(restored.todayPomodoros, 0)
    }

    func testManualYesterdayRecordEditingTaskTypeAndDateRefreshesAllAggregates() async throws {
        let path = directory(); defer { try? FileManager.default.removeItem(at: path) }
        let store = FocusStore(clock: { self.base }, directory: path)
        let a = UUID(), b = UUID()
        let yesterday = Calendar.current.date(byAdding: .day, value: -1, to: base)!
        var draft = FocusRecordDraft(now: base, taskID: a, mode: .stopwatch)
        draft.startedAt = yesterday.addingTimeInterval(-90); draft.endedAt = yesterday; draft.note = "昨日笔记"
        XCTAssertTrue(store.saveRecordDraft(draft))
        XCTAssertEqual(store.todayActiveSeconds, 0)
        XCTAssertEqual(store.allTimeActiveSeconds, 90)
        XCTAssertEqual(store.taskTotalActiveSeconds(taskID: a), 90)
        var edit = FocusRecordDraft(record: try XCTUnwrap(store.record(id: draft.id)))
        edit.startedAt = base.addingTimeInterval(-180); edit.endedAt = base; edit.taskID = b; edit.mode = .pomodoro; edit.creditedPomodoros = 1
        XCTAssertTrue(store.saveRecordDraft(edit))
        XCTAssertEqual(store.taskTotalActiveSeconds(taskID: a), 0)
        XCTAssertEqual(store.taskTotalActiveSeconds(taskID: b), 180)
        XCTAssertEqual(store.todayActiveSeconds, 180)
        XCTAssertEqual(store.todayPomodoros, 1)
        XCTAssertEqual(store.records.count, 1)
        XCTAssertEqual(store.records.first?.note, "昨日笔记")
        await flush(store)
        let restored = FocusStore(clock: { self.base }, directory: path)
        XCTAssertEqual(restored.allTimeActiveSeconds, 180)
        XCTAssertEqual(restored.records.first?.id, draft.id)
        restored.deleteRecord(draft.id)
        XCTAssertEqual(restored.allTimeActiveSeconds, 0)
        XCTAssertEqual(restored.todayPomodoros, 0)
    }

    func testCompletedRecordExtraTimeUpdatesSameIDAndExcludesInterveningBreak() throws {
        var now = base; let path = directory(); defer { try? FileManager.default.removeItem(at: path) }
        let store = FocusStore(clock: { now }, directory: path)
        XCTAssertTrue(store.start(minutes: 5))
        now = base.addingTimeInterval(300); store.refresh()
        let id = try XCTUnwrap(store.records.first?.id)
        now = base.addingTimeInterval(420)
        XCTAssertTrue(store.startCompletionExtraTime())
        now = base.addingTimeInterval(510); store.refresh()
        XCTAssertTrue(store.appendCompletionExtraTime())
        let record = try XCTUnwrap(store.record(id: id))
        XCTAssertEqual(record.activeSeconds, 390)
        XCTAssertEqual(record.details?.pausedSeconds, 120)
        XCTAssertEqual(record.endedAt, now)
        XCTAssertEqual(store.records.count, 1)
        XCTAssertEqual(store.allTimePomodoros, 1)
    }

    func testAutoBreakAndAutoNextAreIndependentAndLimitIncludesUnassociatedSessions() {
        var now = base; let path = directory(); defer { try? FileManager.default.removeItem(at: path) }
        let store = FocusStore(clock: { now }, directory: path)
        XCTAssertTrue(store.setAutoStartBreak(false))
        XCTAssertTrue(store.setAutoStartNextPomodoro(true))
        XCTAssertTrue(store.setAutomaticCycleLimit(2))
        XCTAssertTrue(store.start(minutes: 5))
        now = base.addingTimeInterval(300); store.refresh()
        XCTAssertEqual(store.phase, .idle); XCTAssertTrue(store.pendingBreak)
        XCTAssertTrue(store.startBreak())
        now = base.addingTimeInterval(600); store.refresh()
        XCTAssertEqual(store.phase, .focusing); XCTAssertNil(store.currentTaskID)
        now = base.addingTimeInterval(900); store.refresh()
        XCTAssertTrue(store.pendingBreak)
        XCTAssertTrue(store.skipBreak())
        XCTAssertEqual(store.phase, .idle)
        XCTAssertEqual(store.records.count, 2)
    }

    func testLegacyMinuteRowsRemainUnknownAndKeepTheirOriginalCredits() throws {
        let data = Data("{\"id\":\"11111111-1111-1111-1111-111111111111\",\"startedAt\":1234,\"minutes\":25,\"completed\":true,\"note\":\"旧笔记\"}".utf8)
        let record = try JSONDecoder().decode(PomodoroRecord.self, from: data)
        XCTAssertNil(record.details); XCTAssertNil(record.endedAt)
        XCTAssertEqual(record.mode, .legacy); XCTAssertEqual(record.source, .legacy)
        XCTAssertEqual(record.activeSeconds, 1500); XCTAssertEqual(record.creditedPomodoros, 1)
        let preferences = try JSONDecoder().decode(FocusPreferences.self, from: Data("{\"focusMinutes\":50,\"bellSound\":\"清脆\"}".utf8))
        XCTAssertEqual(preferences.normalized().bell, .crisp)
        XCTAssertEqual(preferences.normalized().bell.soundName, "Glass")
        XCTAssertNil(FocusBell.resolve("关闭").soundName)
        XCTAssertTrue(preferences.autoStartBreak)
    }
    func testNewManualRecordUsesExplicitPomodoroCountAndLegacyDateEditPreservesUnknownEnd() throws {
        let path = directory(); defer { try? FileManager.default.removeItem(at: path) }
        let yesterday = Calendar.current.date(byAdding: .day, value: -1, to: base)!
        let legacy = PomodoroRecord(id: UUID(), taskID: nil, startedAt: yesterday, minutes: 25, completed: true)
        try FileManager.default.createDirectory(at: path, withIntermediateDirectories: true)
        try JSONEncoder().encode(FocusStore.Archive(records: [legacy]))
            .write(to: path.appendingPathComponent("focus.json"))
        let store = FocusStore(clock: { self.base }, directory: path)
        var historical = FocusRecordDraft(record: legacy)
        historical.startedAt = base.addingTimeInterval(-3600); historical.note = "调整到今天"
        XCTAssertTrue(store.saveRecordDraft(historical))
        let saved = try XCTUnwrap(store.record(id: legacy.id))
        XCTAssertEqual(saved.startedAt, historical.startedAt)
        XCTAssertNil(saved.details); XCTAssertNil(saved.endedAt)
        XCTAssertEqual(saved.mode, .legacy); XCTAssertEqual(saved.creditedPomodoros, 1)
        XCTAssertEqual(store.todayPomodoros, 1); XCTAssertEqual(store.todayMinutes, 25)
        var manual = FocusRecordDraft(now: base)
        XCTAssertEqual(manual.creditedPomodoros, 0)
        XCTAssertTrue(store.saveRecordDraft(manual))
        XCTAssertEqual(store.allTimePomodoros, 1)
        manual.creditedPomodoros = 2; manual.isNew = false
        XCTAssertTrue(store.saveRecordDraft(manual))
        XCTAssertEqual(store.allTimePomodoros, 3)
        XCTAssertEqual(store.records.count, 2)
    }

    func testDurationCorrectionSurvivesNoteOnlyEditWithoutInventingPauseRanges() throws {
        var now = base; let path = directory(); defer { try? FileManager.default.removeItem(at: path) }
        let store = FocusStore(clock: { now }, directory: path)
        XCTAssertTrue(store.start(stopwatch: true))
        now = base.addingTimeInterval(90)
        let record = try XCTUnwrap(store.finishEarly())
        XCTAssertTrue(store.correctRecordDuration(record.id, seconds: 120))
        var draft = FocusRecordDraft(record: try XCTUnwrap(store.record(id: record.id)))
        draft.note = "补充结束总结"
        XCTAssertTrue(store.saveRecordDraft(draft))
        let saved = try XCTUnwrap(store.record(id: record.id))
        XCTAssertEqual(saved.activeSeconds, 120)
        XCTAssertEqual(saved.endedAt, now)
        XCTAssertEqual(saved.details?.durationCorrectionSeconds, 30)
        XCTAssertTrue(saved.details?.pauseRanges.isEmpty == true)
        XCTAssertEqual(saved.note, "补充结束总结")
        XCTAssertEqual(store.allTimeActiveSeconds, 120)
    }

    func testUnchangedCompletionDurationDraftPreservesExactSecondsWithoutHistoryMutation() throws {
        var now = base; let path = directory(); defer { try? FileManager.default.removeItem(at: path) }
        let store = FocusStore(clock: { now }, directory: path)
        XCTAssertTrue(store.start(stopwatch: true))
        now = base.addingTimeInterval(90)
        let record = try XCTUnwrap(store.finishEarly())
        let revision = store.historyRevision
        let draft = FocusRecordDurationDraft(record: record)
        XCTAssertEqual(draft.minutes, 2)

        XCTAssertTrue(store.saveRecordDurationDraft(draft))

        XCTAssertEqual(store.record(id: record.id), record)
        XCTAssertEqual(store.allTimeActiveSeconds, 90)
        XCTAssertEqual(store.todayActiveSeconds, 90)
        XCTAssertEqual(store.historyRevision, revision)
        XCTAssertNil(store.record(id: record.id)?.details?.durationCorrectionSeconds)
    }

    func testEditedCompletionDurationDraftAppliesEnteredMinutesToSameRecord() throws {
        var now = base; let path = directory(); defer { try? FileManager.default.removeItem(at: path) }
        let store = FocusStore(clock: { now }, directory: path)
        let taskID = UUID()
        XCTAssertTrue(store.start(taskID: taskID, stopwatch: true))
        now = base.addingTimeInterval(90)
        let record = try XCTUnwrap(store.finishEarly())
        let revision = store.historyRevision
        var draft = FocusRecordDurationDraft(record: record)
        draft.minutes = 3

        XCTAssertTrue(store.saveRecordDurationDraft(draft))

        let saved = try XCTUnwrap(store.record(id: record.id))
        XCTAssertEqual(saved.activeSeconds, 180)
        XCTAssertEqual(saved.minutes, 3)
        XCTAssertEqual(saved.endedAt, record.endedAt)
        XCTAssertEqual(saved.details?.durationCorrectionSeconds, 90)
        XCTAssertEqual(saved.creditedPomodoros, record.creditedPomodoros)
        XCTAssertEqual(store.taskTotalActiveSeconds(taskID: taskID), 180)
        XCTAssertEqual(store.allTimeActiveSeconds, 180)
        XCTAssertEqual(store.records.count, 1)
        XCTAssertEqual(store.historyRevision, revision + 1)
    }

    func testNaturalCompletionTracksPendingExtraWithoutSavingUntilOneExplicitAppend() throws {
        var now = base; let path = directory(); defer { try? FileManager.default.removeItem(at: path) }
        let store = FocusStore(clock: { now }, directory: path)
        XCTAssertTrue(store.setAutoStartBreak(false))
        XCTAssertTrue(store.start(minutes: 5))
        now = base.addingTimeInterval(300); store.refresh()
        let record = try XCTUnwrap(store.records.first)
        XCTAssertTrue(store.isTrackingPendingExtraTime)

        now = base.addingTimeInterval(316); store.refresh()
        XCTAssertEqual(store.availableExtraSeconds, 16)
        XCTAssertEqual(store.record(id: record.id)?.activeSeconds, 300)
        XCTAssertEqual(store.allTimeActiveSeconds, 300)
        XCTAssertEqual(store.allTimePomodoros, 1)
        XCTAssertTrue(store.appendCompletionExtraTime())

        let saved = try XCTUnwrap(store.record(id: record.id))
        XCTAssertEqual(saved.activeSeconds, 316)
        XCTAssertEqual(saved.endedAt, now)
        XCTAssertEqual(saved.creditedPomodoros, 1)
        XCTAssertEqual(store.presentation.displaySeconds, 300, "追加后的完成时长按已观察界面显示整分钟，原始秒数独立保留")
        XCTAssertFalse(store.isTrackingPendingExtraTime)
        now = base.addingTimeInterval(356); store.refresh()
        XCTAssertEqual(store.availableExtraSeconds, 0)
        XCTAssertFalse(store.appendCompletionExtraTime())
        XCTAssertEqual(store.record(id: record.id), saved)
        XCTAssertEqual(store.records.count, 1)
    }

    func testPendingExtraStopsOnStartingBreakOrExitingWithoutChangingRecord() throws {
        for startsBreak in [true, false] {
            var now = base; let path = directory(); defer { try? FileManager.default.removeItem(at: path) }
            let store = FocusStore(clock: { now }, directory: path)
            XCTAssertTrue(store.setAutoStartBreak(false))
            XCTAssertTrue(store.start(minutes: 5))
            now = base.addingTimeInterval(300); store.refresh()
            let record = try XCTUnwrap(store.records.first)
            now = base.addingTimeInterval(316); store.refresh()
            XCTAssertEqual(store.availableExtraSeconds, 16)

            if startsBreak { XCTAssertTrue(store.startBreak()) }
            else { store.dismissCompletion() }
            let stoppedExtra = store.availableExtraSeconds
            XCTAssertFalse(store.isTrackingPendingExtraTime)
            now = base.addingTimeInterval(356); store.refresh()

            XCTAssertEqual(store.availableExtraSeconds, stoppedExtra)
            XCTAssertFalse(store.appendCompletionExtraTime())
            XCTAssertEqual(store.record(id: record.id), record)
            XCTAssertEqual(store.allTimeActiveSeconds, 300)
            XCTAssertEqual(store.allTimePomodoros, 1)
            XCTAssertEqual(store.phase, startsBreak ? .breaking : .idle)
            if !startsBreak { XCTAssertFalse(store.pendingBreak); XCTAssertNil(store.completionContext) }
        }
    }

    func testPausedFocusStartsPendingExtraOnlyAfterItsResumedTarget() throws {
        var now = base; let path = directory(); defer { try? FileManager.default.removeItem(at: path) }
        let store = FocusStore(clock: { now }, directory: path)
        XCTAssertTrue(store.setAutoStartBreak(false))
        XCTAssertTrue(store.start(minutes: 5))
        now = base.addingTimeInterval(240); XCTAssertTrue(store.pause())
        now = base.addingTimeInterval(330); store.refresh()
        XCTAssertNil(store.completionContext)
        XCTAssertEqual(store.availableExtraSeconds, 0)
        XCTAssertTrue(store.resume())
        now = base.addingTimeInterval(390); store.refresh()
        let record = try XCTUnwrap(store.records.first)
        XCTAssertEqual(record.activeSeconds, 300)
        XCTAssertEqual(record.details?.pausedSeconds, 90)
        XCTAssertEqual(record.endedAt, now)
        now = base.addingTimeInterval(406); store.refresh()
        XCTAssertEqual(store.availableExtraSeconds, 16)
        XCTAssertTrue(store.appendCompletionExtraTime())
        let saved = try XCTUnwrap(store.record(id: record.id))
        XCTAssertEqual(saved.activeSeconds, 316)
        XCTAssertEqual(saved.details?.pausedSeconds, 90)
        XCTAssertEqual(saved.endedAt, now)
        XCTAssertEqual(store.records.count, 1)
    }

    func testCompletionMinuteDraftPreviewsAndSavesTheSelectedIntervalWithoutRoundingAnUnchangedRecord() throws {
        var now = base; let path = directory(); defer { try? FileManager.default.removeItem(at: path) }
        let store = FocusStore(clock: { now }, directory: path)
        XCTAssertTrue(store.setAutoStartBreak(false))
        XCTAssertTrue(store.start(minutes: 5))
        now = base.addingTimeInterval(300); store.refresh()
        let initial = try XCTUnwrap(store.completedRecord)
        now = base.addingTimeInterval(48 * 60 + 14); store.refresh()
        XCTAssertEqual(FocusRecordDurationDraft.completionMinuteRange(record: initial,
            pendingExtraSeconds: store.availableExtraSeconds), 5...48)
        XCTAssertTrue(store.appendCompletionExtraTime())
        let appended = try XCTUnwrap(store.completedRecord)
        XCTAssertEqual(appended.activeSeconds, 48 * 60 + 14)
        var draft = FocusRecordDurationDraft(record: appended, displayedMinutes: 48, alignsEndWithDuration: true)

        XCTAssertEqual(draft.previewEnd(startedAt: base), base.addingTimeInterval(48 * 60))
        XCTAssertTrue(store.saveRecordDurationDraft(draft))
        XCTAssertEqual(store.record(id: appended.id), appended, "Unchanged minute display must keep the saved seconds and interval")

        draft.minutes = 5
        XCTAssertEqual(draft.previewEnd(startedAt: base), base.addingTimeInterval(300))
        XCTAssertTrue(store.saveRecordDurationDraft(draft))
        let saved = try XCTUnwrap(store.record(id: appended.id))
        XCTAssertEqual(saved.activeSeconds, 300)
        XCTAssertEqual(saved.startedAt, base)
        XCTAssertEqual(saved.endedAt, base.addingTimeInterval(300))
        XCTAssertEqual(saved.creditedPomodoros, 1)
        XCTAssertEqual(store.allTimeActiveSeconds, 300)
        XCTAssertEqual(store.allTimePomodoros, 1)
        XCTAssertEqual(store.records.count, 1)
    }

    func testEarlyEndConfirmationCancelKeepsPausedSessionAndCanContinue() throws {
        var now = base; let path = directory(); defer { try? FileManager.default.removeItem(at: path) }
        let store = FocusStore(clock: { now }, directory: path)
        let taskID = UUID()
        XCTAssertTrue(store.start(taskID: taskID, minutes: 180))
        store.updateCurrentSessionNote("继续整理")
        now = base.addingTimeInterval(320); XCTAssertTrue(store.pause())
        let pausedTiming = store.sessionTiming

        XCTAssertTrue(store.perform(.end))
        let request = try XCTUnwrap(store.pendingEndConfirmation)
        XCTAssertEqual(request.activeSeconds, 320)
        XCTAssertFalse(store.perform(.end), "The same session keeps a single confirmation request")
        XCTAssertEqual(store.pendingEndConfirmation?.id, request.id)
        now = base.addingTimeInterval(920); store.refresh()
        XCTAssertTrue(store.resolveEndConfirmation(.cancel))

        XCTAssertNil(store.pendingEndConfirmation)
        XCTAssertEqual(store.phase, .pausedFocus)
        XCTAssertEqual(store.sessionTiming, pausedTiming)
        XCTAssertEqual(store.elapsedSeconds, 320)
        XCTAssertEqual(store.currentTaskID, taskID)
        XCTAssertEqual(store.currentSessionNote, "继续整理")
        XCTAssertTrue(store.records.isEmpty)
        XCTAssertTrue(store.perform(.resume))
        now = base.addingTimeInterval(950); store.refresh()
        XCTAssertEqual(store.phase, .focusing)
        XCTAssertEqual(store.elapsedSeconds, 350)
        XCTAssertEqual(store.remainingSeconds, 180 * 60 - 350)
    }

    func testEarlyEndConfirmationSaveKeepsSessionIdentityAndReturnsToOverviewWithoutBreak() throws {
        var now = base; let path = directory(); defer { try? FileManager.default.removeItem(at: path) }
        let store = FocusStore(clock: { now }, directory: path)
        let taskID = UUID()
        XCTAssertTrue(store.setAutoStartBreak(true))
        XCTAssertTrue(store.setAutoStartNextPomodoro(true))
        XCTAssertTrue(store.start(taskID: taskID, minutes: 180))
        store.updateCurrentSessionNote("保存本次进展")
        now = base.addingTimeInterval(320); XCTAssertTrue(store.pause())
        now = base.addingTimeInterval(380); store.refresh()
        XCTAssertTrue(store.perform(.end))
        let request = try XCTUnwrap(store.pendingEndConfirmation)
        XCTAssertTrue(store.records.isEmpty, "Requesting confirmation alone must not save")
        now = base.addingTimeInterval(400)

        XCTAssertTrue(store.resolveEndConfirmation(.save))

        let record = try XCTUnwrap(store.records.first)
        XCTAssertEqual(record.id, request.sessionID)
        XCTAssertEqual(record.activeSeconds, 320)
        XCTAssertEqual(record.details?.pausedSeconds, 80)
        XCTAssertEqual(record.details?.termination, .manuallyEnded)
        XCTAssertEqual(record.endedAt, now)
        XCTAssertEqual(record.note, "保存本次进展")
        XCTAssertEqual(record.taskID, taskID)
        XCTAssertEqual(record.creditedPomodoros, 1)
        XCTAssertEqual(store.allTimeActiveSeconds, 320)
        XCTAssertEqual(store.allTimePomodoros, 1)
        XCTAssertEqual(store.phase, .idle)
        XCTAssertFalse(store.pendingBreak)
        XCTAssertNil(store.completionContext)
        XCTAssertNil(store.pendingEndConfirmation)
        XCTAssertEqual(store.contentRoute, .automatic)
        XCTAssertEqual(store.preferences.lastTaskID, taskID)
        now = base.addingTimeInterval(1_000); store.refresh()
        XCTAssertEqual(store.phase, .idle)
        XCTAssertEqual(store.records.count, 1)
    }

    func testEarlyEndConfirmationDiscardReturnsToOverviewWithoutSaving() {
        var now = base; let path = directory(); defer { try? FileManager.default.removeItem(at: path) }
        let store = FocusStore(clock: { now }, directory: path)
        XCTAssertTrue(store.start(minutes: 180))
        store.updateCurrentSessionNote("放弃本次进展")
        now = base.addingTimeInterval(320); XCTAssertTrue(store.pause())
        XCTAssertTrue(store.perform(.end))

        XCTAssertTrue(store.resolveEndConfirmation(.discard))

        XCTAssertNil(store.pendingEndConfirmation)
        XCTAssertNil(store.completionContext)
        XCTAssertEqual(store.phase, .idle)
        XCTAssertFalse(store.pendingBreak)
        XCTAssertEqual(store.contentRoute, .automatic)
        XCTAssertEqual(store.currentSessionNote, "")
        XCTAssertTrue(store.records.isEmpty)
        XCTAssertEqual(store.allTimeActiveSeconds, 0)
        XCTAssertEqual(store.allTimePomodoros, 0)
    }

    func testShortPausedUserEndDiscardsPomodoroAndStillSavesExactStopwatchSeconds() throws {
        for stopwatch in [false, true] {
            var now = base; let path = directory(); defer { try? FileManager.default.removeItem(at: path) }
            let store = FocusStore(clock: { now }, directory: path)
            let taskID = UUID()
            XCTAssertTrue(store.start(taskID: taskID, minutes: 5, stopwatch: stopwatch))
            store.updateCurrentSessionNote("本次笔记")
            now = base.addingTimeInterval(15)
            XCTAssertTrue(store.perform(.pause))
            now = base.addingTimeInterval(615); store.refresh()
            XCTAssertEqual(store.elapsedSeconds, 15, "Paused wall time is excluded from the end threshold")
            if !stopwatch { store.showStatistics() }

            XCTAssertTrue(store.perform(.end))

            XCTAssertEqual(store.phase, .idle)
            XCTAssertFalse(store.pendingBreak)
            XCTAssertEqual(store.currentSessionNote, "")
            XCTAssertEqual(store.preferences.lastTaskID, taskID)
            XCTAssertEqual(store.allTimePomodoros, 0)
            if stopwatch {
                let record = try XCTUnwrap(store.completedRecord)
                XCTAssertEqual(record.mode, .stopwatch)
                XCTAssertEqual(record.activeSeconds, 15)
                XCTAssertEqual(record.details?.pausedSeconds, 600)
                XCTAssertEqual(record.endedAt, now)
                XCTAssertEqual(record.note, "本次笔记")
                XCTAssertEqual(store.allTimeActiveSeconds, 15)
                XCTAssertEqual(store.records.count, 1)
            } else {
                XCTAssertNil(store.completionContext)
                XCTAssertNil(store.completedRecord)
                XCTAssertEqual(store.contentRoute, .automatic)
                XCTAssertEqual(store.allTimeActiveSeconds, 0)
                XCTAssertEqual(store.todayActiveSeconds, 0)
                XCTAssertTrue(store.records.isEmpty)
            }
        }
    }

    func testCompletedNoteEditsUseTheSameRecordWithoutChangingTimingAndRestoreWithIt() async throws {
        var now = base; let path = directory(); defer { try? FileManager.default.removeItem(at: path) }
        let store = FocusStore(clock: { now }, directory: path)
        XCTAssertTrue(store.start(stopwatch: true))
        store.updateCurrentSessionNote("进行中的笔记")
        now = base.addingTimeInterval(90); XCTAssertTrue(store.pause())
        now = base.addingTimeInterval(120); XCTAssertTrue(store.resume())
        now = base.addingTimeInterval(210)
        let completed = try XCTUnwrap(store.finishEarly())
        let hydrated = store.hydratedRecordCount
        for _ in 0..<20 { _ = store.completedRecord; _ = store.displayedSessionTiming }
        XCTAssertEqual(store.hydratedRecordCount, hydrated, "Completion rendering must not decode history on every tick")

        store.updateCompletedSessionNote("完成后的笔记 ")
        XCTAssertEqual(store.completedSessionNote, "完成后的笔记 ", "Keep in-progress text input until it is committed")
        XCTAssertEqual(store.currentSessionNote, "")
        let saved = try XCTUnwrap(store.completedRecord)
        XCTAssertEqual(saved.id, completed.id)
        XCTAssertEqual(saved.details, completed.details)
        XCTAssertEqual(saved.startedAt, completed.startedAt)
        XCTAssertEqual(saved.note, "完成后的笔记")
        XCTAssertEqual(store.allTimeActiveSeconds, 180)
        XCTAssertEqual(store.allTimePomodoros, 0)
        await flush(store)

        let restored = FocusStore(clock: { now }, directory: path)
        restored.prepareCompletedSessionNote()
        XCTAssertEqual(restored.completedSessionNote, "完成后的笔记")
        XCTAssertEqual(restored.completedRecord, saved)
        XCTAssertEqual(restored.records.count, 1)
    }

}

@MainActor
final class FocusWindowAppearanceTests: XCTestCase {
    func testWindowAndSwiftUIAppearanceMapUserSelectionAndReturnToSystem() {
        let appearance = FocusWindowAppearance()
        XCTAssertNil(appearance.appKitName)
        XCTAssertNil(appearance.selection.colorScheme)
        appearance.update(.dark)
        XCTAssertEqual(appearance.appKitName, .darkAqua)
        XCTAssertEqual(appearance.selection.colorScheme, .dark)
        appearance.update(.light)
        XCTAssertEqual(appearance.appKitName, .aqua)
        XCTAssertEqual(appearance.selection.colorScheme, .light)
        appearance.update(.system)
        XCTAssertNil(appearance.appKitName)
        XCTAssertNil(appearance.selection.colorScheme)
    }
}
