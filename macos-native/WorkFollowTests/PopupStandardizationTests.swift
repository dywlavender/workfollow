import AppKit
import SwiftUI
import XCTest
@testable import WorkFollow

@MainActor
final class PopupStandardizationTests: XCTestCase {
    func testSummaryStatusCancelDiscardsTheDraftAndConfirmationUsesOnlyTheCurrentChoice() throws {
        var applied: SummaryFilter.Status?
        var cancellations = 0
        var choices: [String: CGRect] = [:]
        var actions: [DialogActionAnchor: CGRect] = [:]
        func open() -> NSWindow {
            let host = NSHostingView(rootView: SummaryStatusPopover(status: .all,
                onApply: { applied = $0 }, onCancel: { cancellations += 1 }).background(WFColors.content)
                .coordinateSpace(name: "summary-choices").coordinateSpace(name: "dialog-render")
                .onPreferenceChange(SummaryChoiceFrames.self) { choices = $0 }
                .onPreferenceChange(DialogActionFrames.self) { actions = $0 })
            return InspectorPanelTestSupport.ownerWindow(for: host, width: 188, height: 236)
        }
        func click(_ frame: CGRect?, in window: NSWindow) throws {
            try InspectorPanelTestSupport.click(try XCTUnwrap(frame),
                in: try XCTUnwrap(window.contentView), window: window)
        }
        let cancelled = open()
        try click(choices["已完成"], in: cancelled)
        XCTAssertNil(applied)
        try click(actions[.cancel], in: cancelled)
        XCTAssertEqual(cancellations, 1)
        XCTAssertNil(applied)
        cancelled.close()
        let reopened = open()
        try click(actions[.primary], in: reopened)
        XCTAssertEqual(applied, .all, "取消的选择不能泄漏到重开的筛选器")
        reopened.close()
        let confirmed = open()
        defer { confirmed.close() }
        try click(choices["进行中"], in: confirmed)
        XCTAssertEqual(applied, .all)
        try click(actions[.primary], in: confirmed)
        XCTAssertEqual(applied, .inProgress)
    }

    func testInspectorRootsRequireClickAnchorToTheirButtonsAndCloseWhenTargetChanges() throws {
        let workspace = TaskWorkspaceModel(seedDemoData: false)
        let first = try XCTUnwrap(workspace.createTask(title: "第一条", in: .inbox).taskID)
        let second = try XCTUnwrap(workspace.createTask(title: "第二条", in: .inbox).taskID)
        _ = workspace.setDocument(first, NativeDocument(plainText: "有正文的信息卡"))
        workspace.select(first)
        var frames: [InspectorRenderAnchor: CGRect] = [:]
        let host = InspectorPanelTestSupport.inspectorHost(workspace: workspace, onFrames: { frames = $0 })
        let window = InspectorPanelTestSupport.ownerWindow(for: host)
        defer { window.close() }
        let kind = try button("任务类型", in: host)
        let info = try button("笔记信息", in: host)
        let priority = try button("优先级：", in: host)
        for button in [kind, info, priority] {
            let event = try XCTUnwrap(NSEvent.enterExitEvent(with: .mouseEntered, location: .zero,
                modifierFlags: [], timestamp: 0, windowNumber: window.windowNumber, context: nil,
                eventNumber: 0, trackingNumber: 0, userData: nil))
            button.mouseEntered(with: event)
        }
        InspectorPanelTestSupport.settle(window, duration: 0.3)
        XCTAssertTrue(InspectorPanelTestSupport.visibleWindows(below: window).isEmpty,
                      "扫过根图标只显示悬停反馈")

        kind.performClick(nil)
        InspectorPanelTestSupport.settle(window)
        let kindPanel = try InspectorPanelTestSupport.panel(title: "任务类型", below: window)
        let kindRect = screenRect(try XCTUnwrap(frames[.kind]), host: host, window: window)
        XCTAssertEqual(kindRect.width, 24, accuracy: 0.5)
        XCTAssertEqual(kindRect.height, WFMetrics.controlHeight, accuracy: 0.5)
        XCTAssertEqual(kindPanel.frame.maxX, kindRect.maxX, accuracy: 0.5)
        XCTAssertEqual(kindPanel.frame.maxY, kindRect.minY - 4, accuracy: 0.5)
        // 任务类型菜单 176 → 144：实测三项内容只到 108pt，176 是被优先级菜单
        // 拖着走的（见 PopupMetrics.taskMenuWidth 注释）。
        XCTAssertEqual(kindPanel.frame.width, PopupMetrics.taskMenuWidth, accuracy: 0.5)

        // Accessibility/keyboard actions have no outside mouse-down to clean up.
        info.performClick(nil)
        InspectorPanelTestSupport.settle(window)
        XCTAssertFalse(kindPanel.isVisible)
        let infoPanel = try InspectorPanelTestSupport.panel(title: "笔记信息", below: window)
        let infoRect = screenRect(try XCTUnwrap(frames[.noteInfo]), host: host, window: window)
        XCTAssertEqual(infoPanel.frame.maxX, infoRect.maxX, accuracy: 0.5)
        XCTAssertEqual(infoPanel.frame.maxY, infoRect.minY - 4, accuracy: 0.5)
        info.performClick(nil)
        InspectorPanelTestSupport.settle(window)
        XCTAssertFalse(infoPanel.isVisible, "再次点击同一入口关闭")

        priority.performClick(nil)
        InspectorPanelTestSupport.settle(window)
        let priorityPanel = try InspectorPanelTestSupport.panel(title: "优先级", below: window)
        try InspectorPanelTestSupport.sendEscape(to: priorityPanel)
        XCTAssertFalse(priorityPanel.isVisible)
        XCTAssertEqual(workspace.selectedTaskID, first)
        priority.performClick(nil)
        InspectorPanelTestSupport.settle(window)
        workspace.select(second)
        InspectorPanelTestSupport.settle(window, duration: 0.3)
        XCTAssertTrue(InspectorPanelTestSupport.visibleWindows(below: window).isEmpty)
        XCTAssertEqual(workspace.selectedTaskID, second)
    }

    private final class ContentProbe: ObservableObject { @Published var expanded = false }
    private struct ChangingContent: View {
        @ObservedObject var probe: ContentProbe
        var body: some View { Text("状态信息").frame(height: probe.expanded ? 220 : 100) }
    }

    func testContentDrivenHeightWorksForControlAndSideCardsWithoutResizingOwner() throws {
        typealias Adapter = AnchoredPropertyPanel<AnyView>
        let owner = InspectorPanelTestSupport.ownerWindow(for: NSView(), width: 800, height: 650)
        let baseline = owner.frame
        defer { owner.close() }
        for placement: AnchoredPropertyPanelPlacement in [.verticalInOwner, .submenu] {
            let probe = ContentProbe()
            let anchor = Adapter.AnchorView(frame: CGRect(x: 20, y: 440, width: 28, height: 28))
            owner.contentView!.addSubview(anchor)
            let coordinator = Adapter.Coordinator()
            coordinator.anchor = anchor
            coordinator.width = 260
            coordinator.placement = placement
            coordinator.presented = true
            coordinator.root = AnyView(ChangingContent(probe: probe))
            coordinator.update()
            InspectorPanelTestSupport.settle(owner)
            let panel = try XCTUnwrap(coordinator.panel)
            XCTAssertEqual(panel.contentMinSize, .zero, "内容高度不能反向写入窗口最小尺寸")
            XCTAssertEqual(panel.frame.height, 100, accuracy: 0.5)
            probe.expanded = true
            InspectorPanelTestSupport.settle(owner)
            XCTAssertTrue(coordinator.panel === panel)
            XCTAssertEqual(panel.frame.height, 220, accuracy: 0.5)
            XCTAssertEqual(panel.contentMinSize, .zero)
            probe.expanded = false
            InspectorPanelTestSupport.settle(owner)
            XCTAssertEqual(panel.frame.height, 100, accuracy: 0.5)
            XCTAssertEqual(owner.frame, baseline)
            coordinator.close()
            anchor.removeFromSuperview()
        }
    }

    private func screenRect(_ frame: CGRect, host: NSView, window: NSWindow) -> CGRect {
        let local = CGRect(x: frame.minX, y: host.isFlipped ? frame.minY : host.bounds.height - frame.maxY,
                           width: frame.width, height: frame.height)
        return window.convertToScreen(host.convert(local, to: nil))
    }

    private func button(_ label: String, in view: NSView) throws -> NSButton {
        func find(_ view: NSView) -> NSButton? {
            if let button = view as? NSButton, button.accessibilityLabel()?.hasPrefix(label) == true { return button }
            return view.subviews.lazy.compactMap(find).first
        }
        return try XCTUnwrap(find(view), "Missing button: \(label)")
    }
}
