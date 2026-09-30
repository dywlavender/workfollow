import AppKit
import SwiftUI
import XCTest
@testable import WorkFollow

@MainActor
final class FocusTaskPickerRenderTests: XCTestCase {
    private enum RenderState: String, CaseIterable {
        case todayWithOverdue
        case searchResult
        case scopePicker
        case selectedTask
        case darkMode
    }

    func testTaskPickerAndScopePickerRenderContractsInRealPopoverWindows() throws {
        for state in RenderState.allCases {
            let rendered = try render(state)
            let picker = rendered.pickerWindow
            XCTAssertEqual(picker.frame.width, FocusTaskPickerMetrics.width + 26, accuracy: 1.5,
                           "Picker popover frame changed in \(state.rawValue)")
            XCTAssertEqual(picker.frame.height, FocusTaskPickerMetrics.height + 26, accuracy: 1.5,
                           "Picker popover frame changed in \(state.rawValue)")
            XCTAssertTrue(rendered.screenshots.allSatisfy { FileManager.default.fileExists(atPath: $0.path) })
            XCTAssertTrue(rendered.searchFocused,
                          "Opening the picker must focus its search field in \(state.rawValue)")
            XCTAssertTrue(rendered.screenVisibleFrame.insetBy(dx: -1, dy: -1).contains(picker.frame),
                          "Picker popover is clipped by the visible screen in \(state.rawValue)")

            if state == .todayWithOverdue || state == .searchResult || state == .selectedTask {
                let frames = rendered.layoutFrames
                let search = try XCTUnwrap(frames["search"])
                let scope = try XCTUnwrap(frames["scope"])
                XCTAssertEqual(search.height, FocusTaskPickerMetrics.searchHeight, accuracy: 0.5)
                XCTAssertEqual(scope.height, FocusTaskPickerMetrics.scopeRowHeight, accuracy: 0.5)
                let task = try XCTUnwrap(rendered.firstTask)
                XCTAssertEqual(task.height, FocusTaskPickerMetrics.taskRowHeight, accuracy: 0.5)
                if let date = frames["date-\(rendered.firstTaskID.uuidString)"] {
                    XCTAssertEqual(task.maxX - date.maxX, 8, accuracy: 1,
                                   "Task date must align to the row's trailing inset")
                } else {
                    XCTFail("The first task's date was not included in the render layout")
                }
            }

            if state == .scopePicker {
                let scopeWindow = try XCTUnwrap(rendered.scopeWindow)
                XCTAssertEqual(scopeWindow.frame.width, FocusTaskPickerMetrics.scopeWidth + 26,
                               accuracy: 1.5)
                let expectedScopeContentHeight = 4 * FocusTaskPickerMetrics.scopeRowHeightCompact
                    + 9 + 2 * FocusTaskPickerMetrics.scopeRowHeightCompact + 16
                XCTAssertEqual(scopeWindow.frame.height, expectedScopeContentHeight + 26,
                               accuracy: 1.5)
                XCTAssertTrue(rendered.screenVisibleFrame.insetBy(dx: -1, dy: -1).contains(scopeWindow.frame),
                              "Scope popover is clipped by the visible screen")

                let scopeRow = try XCTUnwrap(rendered.layoutFrames["scope"])
                let chromeInset = (picker.frame.height - FocusTaskPickerMetrics.height) / 2
                let scopeRowScreenY = picker.frame.minY + chromeInset
                    + FocusTaskPickerMetrics.height - scopeRow.midY
                XCTAssertEqual(scopeWindow.frame.minY, scopeRowScreenY + scopeRow.height / 2,
                               accuracy: 1.5,
                               "Second-level popover edge must align with the Scope row; row=\(scopeRow), picker=\(picker.frame), scopeWindow=\(scopeWindow.frame), expectedCenterY=\(scopeRowScreenY)")

                XCTAssertEqual(rendered.screenshots.count, 2)
            }
        }
    }

    private func render(_ state: RenderState) throws -> RenderedPicker {
        let fixture = makeFixture()
        let session = FocusTaskPickerSession(
            linkedTaskID: state == .selectedTask ? fixture.todayTask.id : nil
        )

        var layoutFrames: [String: CGRect] = [:]
        let colorScheme: ColorScheme = state == .darkMode ? .dark : .light
        let appearance: NSAppearance.Name = state == .darkMode ? .darkAqua : .aqua
        let root = FocusTaskPickerPopoverHost(
            workspace: fixture.workspace,
            session: session,
            onLayout: { layoutFrames = $0 }
        )
        .preferredColorScheme(colorScheme)

        let size = NSSize(width: 760, height: 620)
        let visibleFrame = NSScreen.main?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
        let origin = NSPoint(x: visibleFrame.midX - size.width / 2,
                             y: visibleFrame.midY - size.height / 2)
        let priorWindows = Set(NSApp.windows.map(\.windowNumber))
        let rootWindow = NSWindow(contentRect: NSRect(origin: origin, size: size),
                                  styleMask: [.borderless], backing: .buffered, defer: false)
        rootWindow.isReleasedWhenClosed = false
        rootWindow.appearance = NSAppearance(named: appearance)
        rootWindow.backgroundColor = .clear
        rootWindow.hasShadow = false
        rootWindow.contentView = NSHostingView(rootView: root)
        rootWindow.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        flushWindow(rootWindow)
        session.present()
        if state == .searchResult { session.query = "季度" }
        flushWindow(rootWindow)

        var popovers = waitForPopoverWindows(excluding: priorWindows, rootWindow: rootWindow)
        let pickerWindow = try XCTUnwrap(popovers.first {
            $0.className.contains("PopoverWindow")
                && abs($0.frame.width - (FocusTaskPickerMetrics.width + 26)) < 4
        }, "The real task-picker popover window did not appear")
        let searchFocused = pickerWindow.firstResponder is NSTextView
        if state == .scopePicker {
            session.presentScopePicker()
            flushWindow(pickerWindow)
            popovers = waitForPopoverWindows(excluding: priorWindows, rootWindow: rootWindow)
        }
        let scopeWindow = state == .scopePicker ? popovers.first {
            $0 !== pickerWindow && $0.isVisible
                && abs($0.frame.width - (FocusTaskPickerMetrics.scopeWidth + 26)) < 4
        } : nil
        flushWindow(pickerWindow)

        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("focus-task-picker-render", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        var screenshots = [try capture(pickerWindow, named: state.rawValue, in: directory)]
        if let scopeWindow {
            screenshots.append(try capture(scopeWindow, named: "\(state.rawValue)-scope", in: directory))
        }

        let firstTask = state == .searchResult ? fixture.todayTask : fixture.overdueTask
        let result = RenderedPicker(
            pickerWindow: pickerWindow,
            scopeWindow: scopeWindow,
            layoutFrames: layoutFrames,
            firstTask: layoutFrames["task-\(firstTask.id.uuidString)"],
            firstTaskID: firstTask.id,
            screenshots: screenshots,
            searchFocused: searchFocused,
            screenVisibleFrame: pickerWindow.screen?.visibleFrame ?? visibleFrame
        )

        session.dismiss()
        for popup in popovers { popup.orderOut(nil) }
        rootWindow.orderOut(nil)
        return result
    }

    private func waitForPopoverWindows(excluding priorWindows: Set<Int>,
                                       rootWindow: NSWindow) -> [NSWindow] {
        let deadline = Date().addingTimeInterval(2)
        var candidates: [NSWindow] = []
        repeat {
            RunLoop.current.run(until: Date().addingTimeInterval(0.05))
            candidates = NSApp.windows.filter {
                $0 !== rootWindow && $0.isVisible && !priorWindows.contains($0.windowNumber)
            }
            if candidates.contains(where: {
                $0.className.contains("PopoverWindow")
                    && abs($0.frame.width - (FocusTaskPickerMetrics.width + 26)) < 4
            }) { break }
        } while Date() < deadline
        return candidates
    }

    private func flushWindow(_ window: NSWindow) {
        window.contentView?.layoutSubtreeIfNeeded()
        window.displayIfNeeded()
        RunLoop.current.run(until: Date().addingTimeInterval(0.15))
        window.contentView?.layoutSubtreeIfNeeded()
        window.displayIfNeeded()
    }

    private func capture(_ window: NSWindow, named name: String, in directory: URL) throws -> URL {
        guard let contentView = window.contentView,
              let bitmap = contentView.bitmapImageRepForCachingDisplay(in: contentView.bounds) else {
            throw NSError(domain: "FocusTaskPickerRender", code: 1,
                          userInfo: [NSLocalizedDescriptionKey: "Window content could not be rendered to a bitmap"])
        }
        contentView.cacheDisplay(in: contentView.bounds, to: bitmap)
        let png = try XCTUnwrap(bitmap.representation(using: .png, properties: [:]))
        let url = directory.appendingPathComponent("\(name).png")
        try png.write(to: url)
        return url
    }

    private func makeFixture() -> (workspace: TaskWorkspaceModel, overdueTask: Task, todayTask: Task) {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let now = calendar.date(from: DateComponents(year: 2026, month: 9, day: 30, hour: 12))!
        let overdue = makeTask("昨天到期", date: calendar.date(from: DateComponents(year: 2026, month: 9, day: 29, hour: 9))!, now: now)
        let today = makeTask("准备季度评审", date: now, now: now)
        let tomorrow = makeTask("明日计划", date: calendar.date(from: DateComponents(year: 2026, month: 10, day: 1, hour: 9))!, now: now)
        let workspace = TaskWorkspaceModel(clock: { now }, calendar: calendar,
                                           seedDemoData: false,
                                           initialTasks: [overdue, today, tomorrow],
                                           initialLists: ["工作", "学习"])
        return (workspace, overdue, today)
    }

    private func makeTask(_ title: String, date: Date, now: Date) -> Task {
        Task(id: UUID(), title: title, list: .inbox, priority: .none,
             schedule: TaskSchedule(dueAt: date), parentID: nil, childOrder: 0,
             createdAt: now, updatedAt: now)
    }

    private struct RenderedPicker {
        let pickerWindow: NSWindow
        let scopeWindow: NSWindow?
        let layoutFrames: [String: CGRect]
        let firstTask: CGRect?
        let firstTaskID: UUID
        let screenshots: [URL]
        let searchFocused: Bool
        let screenVisibleFrame: CGRect
    }
}

private struct FocusTaskPickerPopoverHost: View {
    @ObservedObject var workspace: TaskWorkspaceModel
    @ObservedObject var session: FocusTaskPickerSession
    let onLayout: ([String: CGRect]) -> Void

    var body: some View {
        Button("选择专注任务") {}
            .frame(width: 220, height: 46)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .popover(isPresented: session.presentationBinding, arrowEdge: .trailing) {
                FocusTaskPickerPopover(
                    workspace: workspace,
                    selectedTaskID: session.linkedTaskID,
                    scope: $session.scope,
                    query: $session.query,
                    isScopePickerPresented: session.scopePickerBinding,
                    onSelectScope: { session.selectScope($0) },
                    onSelectTask: { session.selectTask($0.id) },
                    onClearTask: { session.selectTask(nil) },
                    onDismiss: { session.handleEscape() }
                )
                .onPreferenceChange(FocusTaskPickerLayoutPreferenceKey.self, perform: onLayout)
            }
    }
}
