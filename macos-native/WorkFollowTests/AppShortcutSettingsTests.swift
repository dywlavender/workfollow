import AppKit
import XCTest
@testable import WorkFollow

@MainActor
final class AppShortcutSettingsTests: XCTestCase {
    func testRecordedChordPersistsAndRejectsConflict() throws {
        let name = "WorkFollow.ShortcutTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: name))
        defer { defaults.removePersistentDomain(forName: name) }
        let store = AppShortcutStore(defaults: defaults)
        let key = try XCTUnwrap(NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [.command, .shift],
            timestamp: 0, windowNumber: 0,
            context: nil, characters: "K", charactersIgnoringModifiers: "K", isARepeat: false, keyCode: 40))
        let recorded = try XCTUnwrap(AppShortcutChord(event: key))
        XCTAssertEqual(recorded.label, "⇧⌘K")
        try store.set(recorded, for: .quickOpen)

        XCTAssertTrue(AppShortcutStore(defaults: defaults).chord(for: .quickOpen).sameKeys(as: recorded))
        XCTAssertThrowsError(try store.set(recorded, for: .newTask)) { error in
            guard case AppShortcutError.occupied(.quickOpen) = error else {
                return XCTFail("应提示与快速打开冲突")
            }
        }
        XCTAssertTrue(store.isDefault(.newTask))
        try store.restoreDefaults()
        XCTAssertTrue(AppShortcutStore(defaults: defaults).isDefault(.quickOpen))
    }
}
