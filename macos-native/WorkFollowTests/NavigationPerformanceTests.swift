import AppKit
import SwiftUI
import XCTest
@testable import WorkFollow

@MainActor
final class NavigationPerformanceTests: XCTestCase {
    func testFirstTaskPageWithFixedFixtures() throws {
        let now = Date(timeIntervalSince1970: 1_791_324_000)
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        for count in [43, 200] {
            let tasks = (0..<count).map { index in
                Task(id: UUID(uuidString: String(format: "00000000-0000-0000-0000-%012d", index + 1))!, title: "Fixture task \(index)",
                     document: NativeDocument(plainText: index.isMultiple(of: 2) ? "Preview\nBody" : ""),
                     list: .inbox, priority: .none, schedule: TaskSchedule(),
                     childOrder: index, createdAt: now, updatedAt: now)
            }
            let environment = AppEnvironment(clock: { now }, calendar: calendar)
            let workspace = TaskWorkspaceModel(clock: { now }, calendar: calendar,
                                               seedDemoData: false, initialTasks: tasks)
            let navigation = AppNavigation(destination: .today)
            let host = NSHostingView(rootView: RootShellView(workspace: workspace, navigation: navigation)
                .environmentObject(environment).frame(width: 1280, height: 800))
            let window = InspectorPanelTestSupport.ownerWindow(for: host, width: 1280, height: 800)
            defer { window.close() }
            for pass in 0..<3 {
                NativeTaskOutline.Diagnostics.reset()
                let projectionCount = workspace.projectionBuildCount
                let start = ProcessInfo.processInfo.systemUptime
                navigation.destination = .inbox
                host.layoutSubtreeIfNeeded()
                let firstLayout = ProcessInfo.processInfo.systemUptime
                RunLoop.main.run(until: Date().addingTimeInterval(0.005))
                host.layoutSubtreeIfNeeded()
                let end = ProcessInfo.processInfo.systemUptime
                print("FIRST_TASK_PAGE count=\(count) pass=\(pass) layout_ms=\((firstLayout-start)*1000) total_ms=\((end-start)*1000) containers=\(NativeTaskOutline.Diagnostics.containers) cells=\(NativeTaskOutline.Diagnostics.createdCells) configure=\(NativeTaskOutline.Diagnostics.configurations) configure_ms=\(NativeTaskOutline.Diagnostics.configurationTime*1000) update_ms=\(NativeTaskOutline.Diagnostics.updateTime*1000) reload_ms=\(NativeTaskOutline.Diagnostics.reloadTime*1000) sizing_ms=\(NativeTaskOutline.Diagnostics.sizingTime*1000) sizing_calls=\(NativeTaskOutline.Diagnostics.sizingCalls) row_layout_ms=\(NativeTaskOutline.Diagnostics.rowLayoutTime*1000) projections=\(workspace.projectionBuildCount-projectionCount)")
                XCTAssertEqual(workspace.allTasks.count, count)
                if pass == 0 {
                    XCTAssertEqual(NativeTaskOutline.Diagnostics.containers, 1)
                    XCTAssertGreaterThan(NativeTaskOutline.Diagnostics.createdCells, 0)
                    XCTAssertLessThan(NativeTaskOutline.Diagnostics.createdCells, count,
                                      "The initial viewport must not instantiate every task")
                } else {
                    XCTAssertEqual(NativeTaskOutline.Diagnostics.createdCells, 0)
                    XCTAssertEqual(workspace.projectionBuildCount, projectionCount)
                }
                navigation.destination = .today
                InspectorPanelTestSupport.settle(window)
            }
        }
    }

    func testCollapsedParentProgressUpdatesWithoutReplacingItsRow() throws {
        let environment = AppEnvironment()
        let workspace = TaskWorkspaceModel(seedDemoData: false)
        let parentID = try XCTUnwrap(workspace.createTask(title: "Parent", in: .inbox).taskID)
        let childID = try XCTUnwrap(workspace.createChild(parentID, title: "Child").taskID)
        workspace.toggleExpanded(parentID)
        let navigation = AppNavigation(destination: .inbox)
        let host = NSHostingView(rootView: RootShellView(workspace: workspace, navigation: navigation)
            .environmentObject(environment).frame(width: 1280, height: 800))
        let window = InspectorPanelTestSupport.ownerWindow(for: host, width: 1280, height: 800)
        defer { window.close() }
        func title(_ view: NSView) -> TaskRowTitleField.Field? {
            if let field = view as? TaskRowTitleField.Field, field.stringValue == "Parent" { return field }
            return view.subviews.lazy.compactMap { title($0) }.first
        }
        XCTAssertEqual(workspace.subtaskProgress(for: parentID), "0/1")
        let original = try XCTUnwrap(title(host))
        var ancestor: NSView? = original
        while ancestor != nil && !(ancestor is NativeTaskOutline.Cell) { ancestor = ancestor?.superview }
        let cell = try XCTUnwrap(ancestor as? NativeTaskOutline.Cell)
        let initialConfigurations = cell.configurationCount
        _ = workspace.complete(childID, in: .inbox)
        InspectorPanelTestSupport.settle(window)
        XCTAssertEqual(workspace.subtaskProgress(for: parentID), "1/1")
        XCTAssertGreaterThan(cell.configurationCount, initialConfigurations,
                             "A hidden child's completion must refresh its unchanged parent")
        let completedConfigurations = cell.configurationCount
        XCTAssertTrue(title(host) === original)
        workspace.undo()
        InspectorPanelTestSupport.settle(window)
        XCTAssertEqual(workspace.subtaskProgress(for: parentID), "0/1")
        XCTAssertGreaterThan(cell.configurationCount, completedConfigurations)
        XCTAssertTrue(title(host) === original)
    }

    func testScopedNavigationFreezesWhileHiddenAndForwardsPageLinks() {
        let app = AppNavigation(destination: .today)
        let bridge = WorkspaceNavigationBridge(appNavigation: app, belongsToPage: { $0 == .today })
        app.destination = .calendar
        XCTAssertEqual(bridge.navigation.destination, .today)
        app.destination = .today
        bridge.navigation.destination = .countdown
        XCTAssertEqual(app.destination, .countdown)
        app.destination = .today
        XCTAssertEqual(bridge.navigation.destination, .today)
    }

    func testTaskDataChangedWhileHiddenAppearsOnReturn() throws {
        let environment = AppEnvironment()
        let workspace = TaskWorkspaceModel(seedDemoData: false)
        _ = workspace.createTask(title: "Existing", in: .inbox)
        let navigation = AppNavigation(destination: .inbox)
        let host = NSHostingView(rootView: RootShellView(workspace: workspace, navigation: navigation)
            .environmentObject(environment).frame(width: 1280, height: 800))
        let window = InspectorPanelTestSupport.ownerWindow(for: host, width: 1280, height: 800)
        defer { window.close() }
        navigation.destination = .notes
        InspectorPanelTestSupport.settle(window)
        _ = workspace.createTask(title: "Created while hidden", in: .inbox)
        navigation.destination = .inbox
        InspectorPanelTestSupport.settle(window)
        func containsTitle(_ view: NSView) -> Bool {
            if let field = view as? TaskRowTitleField.Field, field.stringValue == "Created while hidden" { return true }
            return view.subviews.contains { containsTitle($0) }
        }
        XCTAssertTrue(containsTitle(host))
    }

    private struct LifecycleProbe: View {
        @State private var identity = UUID()
        let onAppear: (UUID) -> Void
        let onDisappear: () -> Void
        var body: some View {
            Text("Page").onAppear { onAppear(identity) }.onDisappear(perform: onDisappear)
        }
    }

    func testRetainedPagesKeepStateAndDeliverAppearanceEvents() {
        let cache = WorkspacePageCache()
        let container = WorkspacePageHost.Container()
        let window = InspectorPanelTestSupport.ownerWindow(for: container)
        defer { window.close() }
        var identities: [UUID] = []
        var exits = 0
        func content() -> AnyView {
            AnyView(LifecycleProbe(onAppear: { identities.append($0) }, onDisappear: { exits += 1 }))
        }
        let first = cache.host(for: "first", content: content())
        container.show(first)
        InspectorPanelTestSupport.settle(window)
        XCTAssertEqual(identities.count, 1)
        container.show(cache.host(for: "second", content: AnyView(Text("Other page"))))
        InspectorPanelTestSupport.settle(window)
        XCTAssertEqual(exits, 1, "Leaving a cached page must still deliver save/cleanup callbacks")
        let returned = cache.host(for: "first", content: content())
        container.show(returned)
        InspectorPanelTestSupport.settle(window)
        XCTAssertTrue(first === returned)
        XCTAssertEqual(identities.count, 2)
        XCTAssertEqual(identities.first, identities.last, "Returning must retain SwiftUI page state")
        XCTAssertEqual(container.subviews.count, 1)
    }

    func testTaskListContainerSurvivesScopeAndModuleSwitches() throws {
        let environment = AppEnvironment()
        environment.navigation.destination = .inbox
        let host = NSHostingView(rootView: RootShellView(workspace: environment.taskWorkspace,
            navigation: environment.navigation).environmentObject(environment)
            .frame(width: 1280, height: 800))
        let window = InspectorPanelTestSupport.ownerWindow(for: host, width: 1280, height: 800)
        defer { window.close() }
        func outline(in view: NSView) -> NSOutlineView? {
            if let outline = view as? NativeTaskOutline.OutlineView { return outline }
            return view.subviews.lazy.compactMap { outline(in: $0) }.first
        }
        let original = try XCTUnwrap(outline(in: host))
        var visited: [NativeDestination: NSOutlineView] = [.inbox: original]
        for destination: NativeDestination in [.today, .tomorrow, .notes, .inbox] {
            environment.navigate(to: destination)
            InspectorPanelTestSupport.settle(window)
            if destination.isTaskList {
                let current = try XCTUnwrap(outline(in: host))
                if let previous = visited[destination] {
                    XCTAssertTrue(current === previous, "Container replaced on \(destination.rawValue)")
                } else {
                    visited[destination] = current
                }
            } else {
                XCTAssertNil(outline(in: host))
            }
        }
    }

    func testPageNavigationLayoutProbe() {
        let environment = AppEnvironment()
        let host = NSHostingView(rootView: RootShellView(workspace: environment.taskWorkspace,
            navigation: environment.navigation).environmentObject(environment)
            .frame(width: 1280, height: 800))
        let window = InspectorPanelTestSupport.ownerWindow(for: host, width: 1280, height: 800)
        defer { window.close() }
        let destinations: [NativeDestination] = [.inbox, .notes, .calendar, .matrix,
                                                .countdown, .summary, .meetings, .focus, .today]
        for pass in 0..<3 {
            for destination in destinations {
                let start = ProcessInfo.processInfo.systemUptime
                environment.navigate(to: destination)
                let routed = ProcessInfo.processInfo.systemUptime
                host.layoutSubtreeIfNeeded()
                let laidOut = ProcessInfo.processInfo.systemUptime
                RunLoop.main.run(until: Date().addingTimeInterval(0.005))
                host.layoutSubtreeIfNeeded()
                let finished = ProcessInfo.processInfo.systemUptime
                print("PAGE_LAYOUT destination=\(destination.rawValue) pass=\(pass) route_ms=\((routed-start)*1000) layout_ms=\((laidOut-routed)*1000) settle_ms=\((finished-laidOut)*1000) total_ms=\((finished-start)*1000)")
                XCTAssertEqual(environment.navigation.destination, destination)
            }
        }
    }
}
