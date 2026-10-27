import AppKit
import SwiftUI
import XCTest
@testable import WorkFollow

@MainActor
final class UXWorkflowSurfaceTests: XCTestCase {
    private final class WeakView {
        weak var view: NSView?
        init(_ view: NSView) { self.view = view }
    }
    private final class Probe { var actions: [String: WeakView] = [:] }
    @MainActor private final class Fixture {
        let probe: Probe
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("ux-window-" + UUID().uuidString)
        let environment: AppEnvironment
        let host: NSHostingView<AnyView>
        let window: NSWindow
        init(destination: NativeDestination) {
            let probe = Probe(); self.probe = probe
            var calendar = Calendar(identifier: .gregorian)
            calendar.timeZone = TimeZone(secondsFromGMT: 28800)!
            let now = calendar.date(from: DateComponents(year: 2026, month: 10, day: 21, hour: 12))!
            environment = AppEnvironment(clock: { now }, calendar: calendar, directory: directory)
            environment.navigation.destination = destination
            let observation: (String, NSView) -> Void = { [weak probe] name, view in probe?.actions[name] = WeakView(view) }
            host = NSHostingView(rootView: AnyView(RootShellView(workspace: environment.taskWorkspace,
                navigation: environment.navigation).environmentObject(environment)
                .environment(\.workflowActionObservation, observation)
                .environment(\.popupContentObservation, { content in AnyView(content.environment(\.workflowActionObservation, observation)) })))
            window = InspectorPanelTestSupport.ownerWindow(for: host, width: 1280, height: 800)
        }
        func click(_ identifier: String) throws {
            let deadline = Date().addingTimeInterval(1)
            while probe.actions[identifier]?.view?.window == nil && Date() < deadline { settle() }
            let view = try XCTUnwrap(probe.actions[identifier]?.view, "Missing production action anchor: " + identifier)
            let window = try XCTUnwrap(view.window)
            let frame = window.convertToScreen(view.convert(view.bounds, to: nil))
            try InspectorPanelTestSupport.click(screenFrame: frame, in: window)
        }
        func settle() { InspectorPanelTestSupport.settle(window) }
        func close() {
            window.attachedSheet.map { window.endSheet($0) }
            window.contentView = nil; window.close()
            try? FileManager.default.removeItem(at: directory)
        }
        func screenshot(_ name: String, view: NSView? = nil) throws {
            let view = view ?? host
            view.layoutSubtreeIfNeeded()
            let bitmap = try XCTUnwrap(view.bitmapImageRepForCachingDisplay(in: view.bounds))
            view.cacheDisplay(in: view.bounds, to: bitmap)
            try XCTUnwrap(bitmap.representation(using: .png, properties: [:]))
                .write(to: URL(fileURLWithPath: "/private/tmp/ux-flow-" + name + ".png"))
        }
    }

    func testFullSearchOpensResultBeyondQuickLimitAndReturnsToRetainedResults() throws {
        let fixture = Fixture(destination: .today)
        defer { fixture.close() }
        let environment = fixture.environment
        var ids: [UUID] = []
        for index in 0..<18 {
            ids.append(try XCTUnwrap(environment.taskWorkspace.createDraft(title: "验收搜索第\(index)项", list: "工作",
                schedule: .init(), priority: .none, tags: [], reminder: nil, repeatFrequency: .never,
                selectCreatedTask: false).taskID))
        }
        environment.searchSession.query = "验收搜索"
        environment.searchSession.showAll = true
        environment.searchSession.content = .tasks
        environment.commandPalettePresented = true
        fixture.settle()
        let sheet = try XCTUnwrap(fixture.window.attachedSheet)
        environment.searchSession.selectedIndex = 17; fixture.settle()
        try fixture.screenshot("search-results", view: try XCTUnwrap(sheet.contentView))
        try fixture.click("search.task-" + ids[17].uuidString)
        fixture.settle()
        XCTAssertEqual(environment.taskWorkspace.selectedTaskID, ids[17])
        try fixture.click("feedback.destination")
        fixture.settle()
        XCTAssertTrue(environment.commandPalettePresented)
        XCTAssertEqual(environment.searchSession.query, "验收搜索")
        XCTAssertEqual(environment.searchSession.selectedIndex, 17)
    }

    func testSummaryPreviewAdoptionAndUndoThroughNativeButtons() throws {
        let fixture = Fixture(destination: .summary)
        defer { fixture.close() }
        let environment = fixture.environment
        let context = environment.weeklyPlanning
        fixture.settle()
        let scope = context.scopeID(workspace: environment.taskWorkspace)
        let original = try XCTUnwrap(environment.summaryStore.weeklyEntry(weekKey: context.weekKey, scopeID: scope)?.document)
        let id = try XCTUnwrap(environment.taskWorkspace.createDraft(title: "摘要按钮验收成果", list: "工作",
            schedule: .init(dueAt: context.weekStart), priority: .none, tags: [], reminder: nil,
            repeatFrequency: .never, selectCreatedTask: false).taskID)
        _ = environment.taskWorkspace.complete(id)
        fixture.settle()
        try fixture.click("summary.footer.更新摘要")
        let sheet = try XCTUnwrap(fixture.window.attachedSheet)
        try fixture.screenshot("summary-comparison", view: try XCTUnwrap(sheet.contentView))
        try fixture.click("summary.preview.adopt")
        fixture.settle()
        let updated = try XCTUnwrap(environment.summaryStore.weeklyEntry(weekKey: context.weekKey, scopeID: scope)?.document)
        XCTAssertTrue(updated.plainText.contains("摘要按钮验收成果"))
        try fixture.click("summary.footer.撤销采用")
        fixture.settle()
        XCTAssertEqual(environment.summaryStore.weeklyEntry(weekKey: context.weekKey, scopeID: scope)?.document, original)
    }
}
