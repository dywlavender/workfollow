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
            let view = try waitForAction(identifier)
            let window = try XCTUnwrap(view.window)
            let frame = window.convertToScreen(view.convert(view.bounds, to: nil))
            try InspectorPanelTestSupport.click(screenFrame: frame, in: window)
        }
        func waitForAction(_ identifier: String, timeout: TimeInterval = 1) throws -> NSView {
            let deadline = Date().addingTimeInterval(timeout)
            while probe.actions[identifier]?.view?.window == nil && Date() < deadline { settle() }
            let view = try XCTUnwrap(probe.actions[identifier]?.view, "Missing production action anchor: " + identifier)
            XCTAssertNotNil(view.window, "Anchor is not attached to a window: " + identifier)
            return view
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

    func testSummaryCopyMenuOpensAboveFooterAndCopiesPlainText() throws {
        let fixture = Fixture(destination: .summary)
        defer {
            fixture.close()
            NSPasteboard.general.clearContents()
        }
        let environment = fixture.environment
        let context = environment.weeklyPlanning
        fixture.settle()
        let id = try XCTUnwrap(environment.taskWorkspace.createDraft(title: "摘要复制验收成果", list: "工作",
            schedule: .init(dueAt: context.weekStart), priority: .none, tags: [], reminder: nil,
            repeatFrequency: .never, selectCreatedTask: false).taskID)
        _ = environment.taskWorkspace.complete(id)
        fixture.settle()
        try fixture.click("summary.footer.更新摘要")
        try fixture.click("summary.preview.adopt")
        fixture.settle()

        NSPasteboard.general.clearContents()
        try fixture.click("summary.footer.复制")
        var menuItemView: NSView?
        let deadline = Date().addingTimeInterval(1.5)
        while Date() < deadline {
            menuItemView = fixture.probe.actions["summary.copy.plainText"]?.view
            if menuItemView?.window != nil { break }
            fixture.settle()
        }
        let menuItem = try XCTUnwrap(menuItemView, "Missing copy menu item")
        let popup = try XCTUnwrap(menuItem.window)
        let trigger = try XCTUnwrap(fixture.probe.actions["summary.footer.复制"]?.view)
        let triggerWindow = try XCTUnwrap(trigger.window)
        let triggerFrame = triggerWindow.convertToScreen(trigger.convert(trigger.bounds, to: nil))
        XCTAssertGreaterThan(popup.frame.midY, triggerFrame.midY, "复制菜单应向上展开")
        try fixture.screenshot("summary-copy-menu", view: try XCTUnwrap(popup.contentView))
        try fixture.screenshot("summary-footer-copy", view: fixture.window.contentView)

        try fixture.click("summary.copy.plainText")
        fixture.settle()
        let copied = try XCTUnwrap(NSPasteboard.general.string(forType: .string))
        XCTAssertTrue(copied.contains("摘要复制验收成果"))
        XCTAssertTrue(copied.contains("已完成"))
        XCTAssertTrue(copied.contains("• "))

        try fixture.click("summary.footer.保存为")
        var emailItemView: NSView?
        let emailDeadline = Date().addingTimeInterval(1.5)
        while Date() < emailDeadline {
            emailItemView = fixture.probe.actions["summary.export.email"]?.view
            if emailItemView?.window != nil { break }
            fixture.settle()
        }
        let emailItem = try XCTUnwrap(emailItemView, "Missing email export item")
        let saveMenu = try XCTUnwrap(emailItem.window)
        try fixture.screenshot("summary-save-menu", view: try XCTUnwrap(saveMenu.contentView))
        try InspectorPanelTestSupport.sendEscape(to: saveMenu)
        fixture.settle()
    }

    func testSummaryContentPopoverStylesAutoEnableAndKeepPanelOpen() throws {
        let fixture = Fixture(destination: .summary)
        defer { fixture.close() }
        let environment = fixture.environment
        let context = environment.weeklyPlanning
        fixture.settle()
        let id = try XCTUnwrap(environment.taskWorkspace.createDraft(title: "显示内容验收成果", list: "工作",
            schedule: .init(dueAt: context.weekStart), priority: .none, tags: [], reminder: nil,
            repeatFrequency: .never, selectCreatedTask: false).taskID)
        _ = environment.taskWorkspace.complete(id)
        fixture.settle()

        try fixture.click("summary.setting.content")
        _ = try fixture.waitForAction("summary.content.field.taskName", timeout: 2)
        let field = try XCTUnwrap(fixture.probe.actions["summary.content.field.taskName"]?.view)
        let popup = try XCTUnwrap(field.window)
        XCTAssertEqual(popup.frame.width, 252, accuracy: 0.5)
        XCTAssertNotNil(fixture.probe.actions["summary.content.field.detail"]?.view?.window,
                        "详细内容应作为固定槽位显示")

        try fixture.click("summary.content.style.completedTime")
        _ = try fixture.waitForAction("summary.content.style.completedTime.dateTime", timeout: 2)
        try fixture.screenshot("summary-content-style", view: try XCTUnwrap(popup.contentView))
        try fixture.click("summary.content.style.completedTime.dateTime")
        fixture.settle()
        XCTAssertNil(fixture.probe.actions["summary.content.style.completedTime.dateTime"]?.view?.window,
                     "选择样式后内嵌样式菜单应收起")
        XCTAssertNotNil(fixture.probe.actions["summary.content.field.taskName"]?.view?.window,
                        "选择完成时间样式后内容弹层应保持打开")

        // 所属清单默认未勾选；选择样式应当直接启用它，而不是只改样式。
        try fixture.click("summary.content.style.list")
        _ = try fixture.waitForAction("summary.content.style.list.listGroup", timeout: 2)
        try fixture.click("summary.content.style.list.listGroup")
        fixture.settle()
        XCTAssertNotNil(fixture.probe.actions["summary.content.field.taskName"]?.view?.window,
                        "选择所属清单样式后内容弹层应保持打开")
        try fixture.screenshot("summary-content-popover", view: try XCTUnwrap(popup.contentView))
        try fixture.screenshot("summary-content-config", view: fixture.window.contentView)

        try InspectorPanelTestSupport.sendEscape(to: popup)
        fixture.settle()
        try fixture.click("summary.options.preview")
        fixture.settle()
        try fixture.click("summary.preview.adopt")
        fixture.settle()
        try fixture.screenshot("summary-content-adopted", view: fixture.window.contentView)

        let scope = context.scopeID(workspace: environment.taskWorkspace)
        let entry = try XCTUnwrap(environment.summaryStore.weeklyEntry(weekKey: context.weekKey, scopeID: scope))
        let applied = try XCTUnwrap(entry.options)
        XCTAssertTrue(applied.content.contains(.list))
        XCTAssertEqual(applied.contentStyles.completedTime, .dateTime)
        XCTAssertEqual(applied.contentStyles.list, .listGroup)
        XCTAssertTrue(entry.document.plainText.contains("（工作）"))
        XCTAssertTrue(entry.document.plainText.contains("12:00]"),
                      "完成时间样式改为日期+时间后，前缀应带具体时间")
    }
}
