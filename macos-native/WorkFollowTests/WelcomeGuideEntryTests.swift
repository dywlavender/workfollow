import XCTest
@testable import WorkFollow

@MainActor
final class WelcomeGuideEntryTests: XCTestCase {
    private var directory: URL!
    private var defaults: UserDefaults!
    private var suiteName: String!

    override func setUp() async throws {
        try await super.setUp()
        suiteName = "welcome-guide-entry-\(UUID().uuidString)"
        defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("welcome-guide-entry-\(UUID().uuidString)")
    }

    override func tearDown() async throws {
        defaults.removePersistentDomain(forName: suiteName)
        try? FileManager.default.removeItem(at: directory)
        try await super.tearDown()
    }

    func testFirstLaunchSeedsGuideAndPresentsWelcomeOnce() {
        let environment = AppEnvironment(directory: directory)

        XCTAssertEqual(environment.ensureWelcomeGuideIfNeeded(defaults: defaults, allowInTests: true), .seeded)
        XCTAssertTrue(environment.welcomeGuideWelcomePresented)
        XCTAssertTrue(environment.taskWorkspace.listNames.contains(WelcomeGuide.listName))
        XCTAssertEqual(environment.taskWorkspace.allTasks.filter { $0.guideAction != nil }.count,
                       WelcomeGuide.items.count)

        environment.welcomeGuideWelcomePresented = false
        XCTAssertEqual(environment.ensureWelcomeGuideIfNeeded(defaults: defaults, allowInTests: true), .none)
        XCTAssertFalse(environment.welcomeGuideWelcomePresented)
    }

    func testExistingTasksSeedGuideWithoutWelcomeSheet() throws {
        let workspace = TaskWorkspaceModel(seedDemoData: false, initialTasks: [])
        _ = workspace.createTask(title: "已有任务", in: .inbox)
        try NativePreviewRepository(directory: directory).save(
            NativeWorkspaceSnapshot(tasks: workspace.allTasks, notes: []))

        let environment = AppEnvironment(directory: directory)

        XCTAssertEqual(environment.ensureWelcomeGuideIfNeeded(defaults: defaults, allowInTests: true), .seeded)
        XCTAssertFalse(environment.welcomeGuideWelcomePresented)
        XCTAssertTrue(environment.taskWorkspace.listNames.contains(WelcomeGuide.listName))
    }

    func testXCTestHostNeverSeedsUnlessExplicitlyAllowed() {
        let environment = AppEnvironment(directory: directory)

        XCTAssertEqual(environment.ensureWelcomeGuideIfNeeded(defaults: defaults), .none)
        XCTAssertFalse(environment.welcomeGuideWelcomePresented)
        XCTAssertFalse(environment.taskWorkspace.listNames.contains(WelcomeGuide.listName))
    }
}
