import XCTest
@testable import WorkFollow

@MainActor
final class FocusDurationInteractionTests: XCTestCase {
    func testOpeningCopiesSavedPreferenceAndConfirmPersistsValidDraft() {
        let store = makeStore()
        XCTAssertTrue(store.setFocusMinutes(30))
        let session = FocusDurationEditorSession()

        session.present(currentMinutes: store.preferences.focusMinutes)

        XCTAssertTrue(session.isPresented)
        XCTAssertEqual(session.draftText, "30")
        session.draftText = "180"
        XCTAssertTrue(session.confirm(apply: store.setFocusMinutes))
        XCTAssertEqual(store.preferences.focusMinutes, 180)
        XCTAssertFalse(session.isPresented)
    }

    func testInvalidDurationsAreRejectedWithoutChangingSavedPreference() {
        let store = makeStore()
        let session = FocusDurationEditorSession()
        session.present(currentMinutes: store.preferences.focusMinutes)

        for invalidValue in ["4", "181", "not a number"] {
            session.draftText = invalidValue
            XCTAssertFalse(session.canConfirm, "\(invalidValue) should be invalid")
            XCTAssertFalse(session.confirm(apply: store.setFocusMinutes))
            XCTAssertEqual(store.preferences.focusMinutes, 25)
            XCTAssertTrue(session.isPresented, "Invalid input should keep the editor open")
        }
    }

    func testCancelDoesNotChangeSavedFocusDuration() {
        let store = makeStore()
        let session = FocusDurationEditorSession()
        session.present(currentMinutes: store.preferences.focusMinutes)
        session.draftText = "60"

        session.cancel()

        XCTAssertEqual(store.preferences.focusMinutes, 25)
        XCTAssertFalse(session.isPresented)
    }

    func testDurationCanOnlyBeEditedForIdleCountdownMode() {
        XCTAssertTrue(FocusDurationEditorSession.canEditDuration(phase: .idle,
                                                                 stopwatchMode: false))
        XCTAssertFalse(FocusDurationEditorSession.canEditDuration(phase: .idle,
                                                                  stopwatchMode: true))
        XCTAssertFalse(FocusDurationEditorSession.canEditDuration(phase: .focusing,
                                                                  stopwatchMode: false))
        XCTAssertFalse(FocusDurationEditorSession.canEditDuration(phase: .pausedFocus,
                                                                  stopwatchMode: false))
        XCTAssertFalse(FocusDurationEditorSession.canEditDuration(phase: .breaking,
                                                                  stopwatchMode: false))
        XCTAssertFalse(FocusDurationEditorSession.canEditDuration(phase: .pausedBreak,
                                                                  stopwatchMode: false))
    }

    private func makeStore() -> FocusStore {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("focus-duration-tests-\(UUID().uuidString)",
                                   isDirectory: true)
        return FocusStore(clock: Date.init, directory: directory)
    }
}
