import Foundation
import XCTest
@testable import WorkFollow

@MainActor
final class LayoutPersistenceTests: XCTestCase {
    private func makeDefaults() throws -> (UserDefaults, String) {
        let suite = "WorkFollow.LayoutPersistence.\(UUID())"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defaults.removePersistentDomain(forName: suite)
        return (defaults, suite)
    }

    func testTaskListPaneWidthLoadsPersistsAndClamps() throws {
        let (defaults, suite) = try makeDefaults()
        defer { defaults.removePersistentDomain(forName: suite) }

        let model = TaskWorkspaceModel(seedDemoData: false, layoutDefaults: defaults)
        XCTAssertEqual(model.taskListPaneWidth, WFMetrics.listPreferred)
        model.setTaskListPaneWidth(412)
        XCTAssertEqual(defaults.double(forKey: "workspace.taskListPaneWidth"), 412)

        let reopened = TaskWorkspaceModel(seedDemoData: false, layoutDefaults: defaults)
        XCTAssertEqual(reopened.taskListPaneWidth, 412)

        defaults.set(9_000.0, forKey: "workspace.taskListPaneWidth")
        let clamped = TaskWorkspaceModel(seedDemoData: false, layoutDefaults: defaults)
        XCTAssertEqual(clamped.taskListPaneWidth, WFMetrics.listMaximum)
    }

    func testNotesAIPaneVisibilityLoadsAndPersists() throws {
        let (defaults, suite) = try makeDefaults()
        defer { defaults.removePersistentDomain(forName: suite) }

        let model = NotesWorkspaceModel(layoutDefaults: defaults)
        XCTAssertFalse(model.aiPaneVisible)
        model.aiPaneVisible = true
        XCTAssertTrue(defaults.bool(forKey: "notes.ai.paneVisible"))
        XCTAssertTrue(NotesWorkspaceModel(layoutDefaults: defaults).aiPaneVisible)
    }

    func testEnvironmentSidebarAndNotesFolderPanePersist() throws {
        let (defaults, suite) = try makeDefaults()
        defer { defaults.removePersistentDomain(forName: suite) }

        let environment = AppEnvironment(layoutPreferences: defaults)
        XCTAssertTrue(environment.sidebarVisible)
        XCTAssertFalse(environment.notesFolderPaneHidden)
        environment.sidebarVisible = false
        environment.notesFolderPaneHidden = true
        XCTAssertFalse(defaults.bool(forKey: "workspace.sidebarVisible"))
        XCTAssertTrue(defaults.bool(forKey: "notes.folderPaneHidden"))

        let reopened = AppEnvironment(layoutPreferences: defaults)
        XCTAssertFalse(reopened.sidebarVisible)
        XCTAssertTrue(reopened.notesFolderPaneHidden)
    }
}
