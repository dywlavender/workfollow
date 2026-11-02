import AppKit
import SwiftUI
import XCTest
@testable import WorkFollow

@MainActor
final class TaskListSwitchPerformanceTests: XCTestCase {
    private func record(_ line: String) { FileHandle.standardOutput.write(Data((line + "\n").utf8)) }

    func testCustomListsAndSmartListsThroughFullShell() throws {
        NativeTaskOutline.Diagnostics.usesNativeRows = ProcessInfo.processInfo.environment["WORKFOLLOW_REFERENCE_TASK_ROWS"] != "1"
        defer { NativeTaskOutline.Diagnostics.usesNativeRows = true }
        let now = Date(timeIntervalSince1970: 1_793_410_000)
        let names = ["虚构工作", "虚构学习", "虚构个人"]
        let profiling = ProcessInfo.processInfo.environment["WORKFOLLOW_PROFILE_LIST_SWITCH"] == "1"
        let modes: [(String, NativeBackgroundTheme)] = profiling ? [("plain", .none)] : [("plain", .none), ("aurora", .auroraJelly)]
        for (mode, theme) in modes {
            let directory = FileManager.default.temporaryDirectory.appendingPathComponent("wf-list-switch-" + UUID().uuidString)
            let tasks = (0..<60).map { index in
                Task(id: UUID(), title: "虚构任务 \(index)",
                     document: NativeDocument(plainText: "虚构预览 \(index)"),
                     list: index < 15 ? .inbox : TaskList(name: names[(index - 15) / 15]),
                     priority: .none, schedule: TaskSchedule(dueAt: now),
                     childOrder: index, createdAt: now, updatedAt: now)
            }
            try NativePreviewRepository(directory: directory).save(.init(tasks: tasks, notes: []))
            let environment = AppEnvironment(clock: { now }, directory: directory)
            environment.backgroundTheme = theme
            environment.backgroundAnimated = true
            environment.backgroundIntensity = .full
            environment.appearanceMaterial = .classic
            environment.companionEnabled = false
            let workspace = environment.taskWorkspace
            let navigation = environment.navigation
            navigation.destination = .inbox
            let host = NSHostingView(rootView: RootShellView(workspace: workspace, navigation: navigation)
                .environmentObject(environment).frame(width: 1280, height: 800))
            let window = InspectorPanelTestSupport.ownerWindow(for: host, width: 1280, height: 800)
            defer { window.close(); window.contentView = nil }

            for pass in 0..<(profiling ? 40 : 3) {
                for name in names {
                    NativeTaskOutline.Diagnostics.reset()
                    let projections = workspace.projectionBuildCount
                    let start = ProcessInfo.processInfo.systemUptime
                    navigation.openTaskList(name, in: workspace)
                    let routed = ProcessInfo.processInfo.systemUptime
                    host.layoutSubtreeIfNeeded()
                    let laidOut = ProcessInfo.processInfo.systemUptime
                    RunLoop.main.run(until: Date().addingTimeInterval(0.001))
                    host.layoutSubtreeIfNeeded()
                    let settled = ProcessInfo.processInfo.systemUptime
                    window.displayIfNeeded()
                    let end = ProcessInfo.processInfo.systemUptime
                    record("LIST_SWITCH mode=\(mode) pass=\(pass) list=\(name) route_ms=\((routed-start)*1000) layout_ms=\((laidOut-routed)*1000) settle_ms=\((settled-laidOut)*1000) draw_ms=\((end-settled)*1000) total_ms=\((end-start)*1000) hosting_views=\(NativeTaskOutline.Diagnostics.createdHostingViews) native_rows=\(NativeTaskOutline.Diagnostics.createdNativeRows) cells=\(NativeTaskOutline.Diagnostics.createdCells) configs=\(NativeTaskOutline.Diagnostics.configurations) update_ms=\(NativeTaskOutline.Diagnostics.updateTime*1000) reload_ms=\(NativeTaskOutline.Diagnostics.reloadTime*1000) sizing_ms=\(NativeTaskOutline.Diagnostics.sizingTime*1000) sizing_calls=\(NativeTaskOutline.Diagnostics.sizingCalls) row_layout_ms=\(NativeTaskOutline.Diagnostics.rowLayoutTime*1000) projections=\(workspace.projectionBuildCount-projections)")
                    XCTAssertEqual(NativeTaskOutline.Diagnostics.containers, 0)
                    XCTAssertEqual(workspace.activeList, name)
                }
                for destination: NativeDestination in [.today, .inbox] {
                    NativeTaskOutline.Diagnostics.reset()
                    let start = ProcessInfo.processInfo.systemUptime
                    environment.navigate(to: destination)
                    host.layoutSubtreeIfNeeded()
                    RunLoop.main.run(until: Date().addingTimeInterval(0.001))
                    host.layoutSubtreeIfNeeded()
                    window.displayIfNeeded()
                    record("LIST_SMART mode=\(mode) pass=\(pass) destination=\(destination.rawValue) total_ms=\((ProcessInfo.processInfo.systemUptime-start)*1000) hosting_views=\(NativeTaskOutline.Diagnostics.createdHostingViews) native_rows=\(NativeTaskOutline.Diagnostics.createdNativeRows) cells=\(NativeTaskOutline.Diagnostics.createdCells) configs=\(NativeTaskOutline.Diagnostics.configurations) reload_ms=\(NativeTaskOutline.Diagnostics.reloadTime*1000) sizing_ms=\(NativeTaskOutline.Diagnostics.sizingTime*1000)")
                }
                // Also cover closing an existing inspector while changing scope.
                workspace.select(tasks[0].id)
                InspectorPanelTestSupport.settle(window)
            }
        }
    }
}
