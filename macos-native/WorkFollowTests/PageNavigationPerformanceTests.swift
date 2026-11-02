import AppKit
import SwiftUI
import XCTest
@testable import WorkFollow

@MainActor
final class PageNavigationPerformanceTests: XCTestCase {
    private func record(_ text: String) {
        FileHandle.standardOutput.write(Data((text + "\n").utf8))
    }

    func testModuleSwitchingWithFixedTasksAndNotes() throws {
        let now = Date(timeIntervalSince1970: 1_793_462_400)
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 8 * 3600)!
        let settings = PlanningSettingsStore.shared
        let previousCalendar = settings.calendar
        defer { settings.updateCalendar { $0 = previousCalendar } }
        settings.updateCalendar { $0 = CalendarPreferences() }
        let modes: [(String, NativeBackgroundTheme, WFAppearanceMaterial)] = [
            ("plain", .none, .classic), ("aurora", .auroraJelly, .classic), ("glass", .auroraJelly, .liquidGlass)
        ]
        for (mode, theme, material) in modes {
            let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
            let tasks = (0..<80).map { index in
                Task(id: UUID(), title: "虚构页面切换任务 \(index)",
                    document: NativeDocument(plainText: index.isMultiple(of: 2) ? "页面切换使用的虚构正文\n第二行正文" : ""),
                    list: .inbox, priority: index.isMultiple(of: 3) ? .high : .none,
                    schedule: TaskSchedule(dueAt: calendar.date(byAdding: .day, value: index % 14, to: now), hasTime: false),
                    childOrder: index, createdAt: now, updatedAt: now)
            }
            let text = (0..<80).map { "第\($0)段虚构资料：本周讨论产品设计与项目安排，记录决策、进度和后续工作。" }.joined(separator: "\n")
            let notes = (0..<12).map { Note(id: UUID(), title: "虚构项目笔记 \($0)", document: NativeDocument(plainText: text),
                folder: "项目资料", updatedAt: now.addingTimeInterval(Double(-$0))) }
            try NativePreviewRepository(directory: directory).save(.init(tasks: tasks, notes: notes))
            let environment = AppEnvironment(clock: { now }, calendar: calendar, directory: directory)
            environment.backgroundTheme = theme
            environment.backgroundAnimated = material == .classic
            environment.backgroundIntensity = .full
            environment.appearanceMaterial = material
            environment.companionEnabled = false
            environment.sidebarVisible = true
            environment.notesWorkspace.selectedID = notes[0].id
            environment.navigation.destination = .countdown
            let host = NSHostingView(rootView: RootShellView(workspace: environment.taskWorkspace, navigation: environment.navigation)
                .environmentObject(environment).environment(\.controlActiveState, .active).frame(width: 1280, height: 800))
            let window = InspectorPanelTestSupport.ownerWindow(for: host, width: 1280, height: 800)
            defer { window.contentView = nil; window.close() }
            let routes: [NativeDestination] = ProcessInfo.processInfo.environment["WORKFOLLOW_CORE_PAGE_ROUTES"] == "1"
                ? [.inbox, .notes, .calendar, .today]
                : [.inbox, .notes, .calendar, .matrix, .aiChat, .countdown, .summary, .meetings, .focus, .today]
            let passes = ProcessInfo.processInfo.environment["WORKFOLLOW_PROFILE_PAGE_NAVIGATION"] == "1" ? 30 : 3
            for pass in 0..<passes {
                for destination in routes {
                    NativeTaskOutline.Diagnostics.reset()
                    WorkspacePageCache.Diagnostics.reset()
                    let start = ProcessInfo.processInfo.systemUptime
                    environment.navigate(to: destination)
                    let routed = ProcessInfo.processInfo.systemUptime
                    host.layoutSubtreeIfNeeded()
                    let firstLayout = ProcessInfo.processInfo.systemUptime
                    RunLoop.main.run(until: Date().addingTimeInterval(0.001))
                    host.layoutSubtreeIfNeeded()
                    let settled = ProcessInfo.processInfo.systemUptime
                    window.displayIfNeeded()
                    let end = ProcessInfo.processInfo.systemUptime
                    record("MODULE_SWITCH mode=\(mode) pass=\(pass) page=\(destination.rawValue) route_ms=\((routed-start)*1000) layout_ms=\((firstLayout-routed)*1000) settle_ms=\((settled-firstLayout)*1000) draw_ms=\((end-settled)*1000) total_ms=\((end-start)*1000) hosts=\(WorkspacePageCache.Diagnostics.createdHosts) roots=\(WorkspacePageCache.Diagnostics.rootAssignments) attaches=\(WorkspacePageCache.Diagnostics.attachments) detaches=\(WorkspacePageCache.Diagnostics.detachments) show_ms=\(WorkspacePageCache.Diagnostics.showTime*1000) task_rows=\(NativeTaskOutline.Diagnostics.createdNativeRows)")
                    XCTAssertEqual(environment.navigation.destination, destination)
                }
            }
        }
    }
}
