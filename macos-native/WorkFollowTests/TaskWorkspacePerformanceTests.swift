import AppKit
import SwiftUI
import XCTest
@testable import WorkFollow

@MainActor
final class TaskWorkspacePerformanceTests: XCTestCase {
    func testFixedTaskFixtureNavigationSelectionAndThemeIdle() throws {
        let now = Date(timeIntervalSince1970: 1_793_410_000)
        let modes: [(String, NativeBackgroundTheme)] = [
            ("plain", .none), ("mint_motion", .mintCloud), ("aurora_motion", .auroraJelly)
        ]
        for (name, theme) in modes {
            let directory = FileManager.default.temporaryDirectory.appendingPathComponent("wf-workspace-perf-" + UUID().uuidString)
            let tasks = (0..<58).map { index in
                Task(id: UUID(), title: "虚构任务 \(index)",
                     document: NativeDocument(plainText: "这是虚构的性能测试内容 \(index)。"),
                     list: .inbox, priority: .none, schedule: TaskSchedule(dueAt: now),
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
            navigation.destination = .allTasks
            let host = NSHostingView(rootView: RootShellView(workspace: workspace, navigation: navigation)
                .environmentObject(environment).environment(\.controlActiveState, .active)
                .frame(width: 1280, height: 800))
            let window = InspectorPanelTestSupport.ownerWindow(for: host, width: 1280, height: 800)
            defer { window.close(); window.contentView = nil }
            let routes: [(String, NativeDestination)] = [
                ("first", .inbox), ("first", .today), ("warm", .inbox), ("warm", .today),
                ("first", .tomorrow), ("warm", .allTasks), ("warm_four", .inbox)
            ]
            for (phase, destination) in routes {
                NativeTaskOutline.Diagnostics.reset()
                let start = ProcessInfo.processInfo.systemUptime
                environment.navigate(to: destination)
                host.layoutSubtreeIfNeeded()
                RunLoop.main.run(until: Date().addingTimeInterval(0.001))
                host.layoutSubtreeIfNeeded()
                window.displayIfNeeded()
                print("WORKSPACE_NAV mode=\(name) phase=\(phase) destination=\(destination.rawValue) total_ms=\((ProcessInfo.processInfo.systemUptime-start)*1000) containers=\(NativeTaskOutline.Diagnostics.containers) cells=\(NativeTaskOutline.Diagnostics.createdCells)")
                XCTAssertEqual(NativeTaskOutline.Diagnostics.containers, 0)
            }
            workspace.select(tasks[0].id)
            InspectorPanelTestSupport.settle(window)
            let revision = workspace.revision
            let projections = workspace.projectionBuildCount
            var samples: [Double] = []
            for index in 0..<30 {
                let start = ProcessInfo.processInfo.systemUptime
                workspace.select(tasks[(index+1)%2].id)
                host.layoutSubtreeIfNeeded()
                RunLoop.main.run(until: Date().addingTimeInterval(0.001))
                host.layoutSubtreeIfNeeded()
                window.displayIfNeeded()
                samples.append((ProcessInfo.processInfo.systemUptime-start)*1000)
            }
            samples.sort()
            print("WORKSPACE_SELECT mode=\(name) p50_ms=\(samples[15]) p95_ms=\(samples[28]) revisions=\(workspace.revision-revision) projections=\(workspace.projectionBuildCount-projections)")
            XCTAssertEqual(workspace.revision, revision)
            XCTAssertEqual(workspace.projectionBuildCount, projections)
            func cpuTime() -> Double {
                var usage = rusage(); getrusage(RUSAGE_SELF, &usage)
                return Double(usage.ru_utime.tv_sec + usage.ru_stime.tv_sec)
                    + Double(usage.ru_utime.tv_usec + usage.ru_stime.tv_usec) / 1_000_000
            }
            // Let the normal save debounce finish before measuring idle work.
            RunLoop.main.run(until: Date().addingTimeInterval(0.5))
            let renders = BackgroundArtworkCache.renderCount
            let cpu = cpuTime()
            RunLoop.main.run(until: Date().addingTimeInterval(1.0))
            print("WORKSPACE_IDLE mode=\(name) cpu_ms=\((cpuTime()-cpu)*1000) artwork_renders=\(BackgroundArtworkCache.renderCount-renders)")
            XCTAssertEqual(BackgroundArtworkCache.renderCount, renders)
        }
    }
}
