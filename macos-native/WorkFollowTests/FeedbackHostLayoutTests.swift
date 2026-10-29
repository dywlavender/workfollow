import AppKit
import SwiftUI
import XCTest
@testable import WorkFollow

/// 结果 HUD 是根视图的悬浮层：出现时不能让页面（中栏/检查器）重新排版。
@MainActor
final class FeedbackHostLayoutTests: XCTestCase {
    private func outline(in view: NSView) -> NSView? {
        if view is NSOutlineView { return view }
        return view.subviews.lazy.compactMap { self.outline(in: $0) }.first
    }

    func testCompletionHUDFloatsWithoutReflowingWorkspace() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("feedback-host-layout-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: directory) }
        let environment = AppEnvironment(directory: directory)
        let workspace = environment.taskWorkspace
        _ = workspace.createTask(title: "完成提示不顶页面", in: .inbox)
        environment.navigation.destination = .inbox
        var hudFrames: [CGRect] = []
        let host = NSHostingView(rootView: RootShellView(workspace: workspace,
                                                         navigation: environment.navigation)
            .environmentObject(environment)
            .frame(width: 1280, height: 800)
            .coordinateSpace(name: FeedbackHUDRenderFrames.coordinateSpace)
            .onPreferenceChange(FeedbackHUDRenderFrames.self) { hudFrames = $0 })
        let window = InspectorPanelTestSupport.ownerWindow(for: host, width: 1280, height: 800)
        defer {
            environment.feedback.dismiss()
            window.close()
        }
        InspectorPanelTestSupport.settle(window)

        let list = try XCTUnwrap(outline(in: host), "Task list outline did not render")
        let before = list.convert(list.bounds, to: nil)

        environment.feedback.show(FeedbackEvent(kind: .completion, message: "任务已完成"))
        XCTAssertNotNil(environment.feedback.presentation)
        InspectorPanelTestSupport.settle(window)

        let after = list.convert(list.bounds, to: nil)
        XCTAssertEqual(after.minY, before.minY, accuracy: 0.5,
                       "完成提示出现后列表底边不应被顶高")
        XCTAssertEqual(after.height, before.height, accuracy: 0.5,
                       "完成提示出现后列表高度不应回流")

        // HUD 必须真的浮在窗口内、底部居中，而不是挤在布局流里。
        let hud = try XCTUnwrap(hudFrames.last, "HUD did not render while feedback was presented")
        XCTAssertLessThan(hud.width, 600, "HUD 只应占卡片宽度，不能是整窗宽的空带")
        XCTAssertEqual(hud.midX, 640, accuracy: 4, "HUD 应在窗口水平居中")
        XCTAssertEqual(hud.height, 40, accuracy: 2, "HUD 高度应是卡片高度")
        XCTAssertEqual(hud.maxY, 800 - WFSpace.lg, accuracy: 2,
                       "HUD 应浮在窗口底部之上，而不是把内容顶上去")

        environment.feedback.dismiss()
        InspectorPanelTestSupport.settle(window)
        XCTAssertTrue(hudFrames.isEmpty, "HUD 收起后不应留下布局占位")
    }
}
