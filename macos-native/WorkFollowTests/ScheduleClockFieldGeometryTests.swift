import AppKit
import SwiftUI
import XCTest
@testable import WorkFollow

/// 日期面板属性行的几何契约：放进 `PropertyRowCanvas` 值区域的编辑器
/// 必须**左对齐**且固定宽——防的是 2026-10-24 用户截图反馈的那类错位
/// （52pt 输入框在约 200pt 值区域里默认居中，与其它行「值紧跟图标」
/// 的画法错开）。这类问题读代码能推断、但容易漏，钉成测试后由 CI 把关。
@MainActor
final class ScheduleClockFieldGeometryTests: XCTestCase {
    private let rowWidth: CGFloat = 240

    /// 图标槽右缘的推导值（horizontalPadding + 图标 18 + 间距 8）：
    /// 第三条组合行测试用作「结束前缀之后」的基准。
    private var expectedLeading: CGFloat {
        ScheduleMetrics.propertyRowHorizontalPadding + 18 + 8
    }

    func testClockEditorHugsTheLeadingEdgeOfTheValueArea() throws {
        let canvas = try makeCanvasWithClockEditor()
        let field = try XCTUnwrap(firstTextField(in: canvas), "画布里应有一个时钟输入框")

        let frameInCanvas = field.convert(field.bounds, to: canvas)
        // 实测锚点 26 = 图标槽右缘（horizontalPadding + 18 + 8 = 28）
        // 再减 NSHostingView 的 2pt 内缩。契约钉的是「贴住值区域起点」，
        // 不是具体像素：容差 2pt，且整体必须落在行左三分之一内。
        XCTAssertEqual(frameInCanvas.minX, 26, accuracy: 2,
                       "时钟输入框必须左对齐到值区域起点（紧跟图标），不能在值区域里居中悬浮")
        XCTAssertLessThan(frameInCanvas.midX, rowWidth / 3,
                          "输入框整体应落在行左三分之一内")
    }

    func testClockEditorKeepsFixedWidthSoTheRowDoesNotJitter() throws {
        let canvas = try makeCanvasWithClockEditor()
        let field = try XCTUnwrap(firstTextField(in: canvas))

        // 52pt 的 SwiftUI 槽位 + NSTextField 自身边距，实测稳定在 56。
        // 契约的目的是「行内不跳动」：宽度必须钉死在一个固定值附近。
        let width = field.convert(field.bounds, to: canvas).width
        XCTAssertEqual(width, 56, accuracy: 2, "HH:mm 输入框固定宽度（约 56pt），行内不跳动")
    }

    /// 结束时间行是「结束 + 输入框」的组合，同样必须从值区域起点开始铺。
    func testEndTimeEditorGroupAlsoStartsAtTheValueArea() throws {
        let canvas = PropertyRowCanvas()
        canvas.frame = NSRect(x: 0, y: 0, width: rowWidth, height: ScheduleMetrics.rowHeight)
        canvas.setEditor(AnyView(
            HStack(spacing: 4) {
                Text("结束").font(WFType.body)
                LeadingScheduleClockField(text: .constant("17:45"), requestsFocus: false, onSubmit: {})
            }
        ))
        canvas.layoutSubtreeIfNeeded()
        settle()

        let field = try XCTUnwrap(firstTextField(in: canvas))
        let frameInCanvas = field.convert(field.bounds, to: canvas)
        // 「结束」前缀先占一段，输入框在其后，但仍必须落在行的左半侧。
        XCTAssertGreaterThan(frameInCanvas.minX, expectedLeading - 1,
                             "输入框应在「结束」前缀之后")
        XCTAssertLessThan(frameInCanvas.minX, expectedLeading + 60,
                          "「结束」前缀 + 输入框都应贴近值区域起点，不能整体被推到中间")
    }

    /// 聚焦时间输入框时不能出现系统焦点环，也不能整段选中（蓝底）。
    func testFocusedClockFieldHasNoFocusRingOrSelectionHighlight() throws {
        let host = NSHostingView(rootView: AnyView(
            LeadingScheduleClockField(text: .constant("09:00"), requestsFocus: true, onSubmit: {})
                .frame(width: rowWidth, height: ScheduleMetrics.rowHeight)
        ))
        let window = InspectorPanelTestSupport.ownerWindow(for: host, width: rowWidth, height: ScheduleMetrics.rowHeight)
        defer { window.close() }

        let field = try XCTUnwrap(firstTextField(in: host))
        XCTAssertEqual(field.focusRingType, .none, "时间输入框不应绘制蓝色焦点环")
        try InspectorPanelTestSupport.waitUntil("时间输入框应在下一拍拿到焦点") {
            window.firstResponder is NSTextView
        }
        let editor = try XCTUnwrap(field.currentEditor() as? NSTextView)
        XCTAssertEqual(editor.selectedRange.length, 0, "聚焦不能整段选中，否则会出现蓝色选中底色")
        XCTAssertEqual(editor.selectedRange.location, ("09:00" as NSString).length)
    }

    // MARK: 工具

    private func makeCanvasWithClockEditor() throws -> PropertyRowCanvas {
        let canvas = PropertyRowCanvas()
        canvas.frame = NSRect(x: 0, y: 0, width: rowWidth, height: ScheduleMetrics.rowHeight)
        canvas.setEditor(AnyView(
            LeadingScheduleClockField(text: .constant("09:00"), requestsFocus: false, onSubmit: {})
        ))
        canvas.layoutSubtreeIfNeeded()
        settle()
        return canvas
    }

    /// `NSHostingView` 布局走一拍 RunLoop 才落位。
    private func settle() {
        RunLoop.current.run(until: Date().addingTimeInterval(0.05))
    }

    private func firstTextField(in root: NSView) -> NSTextField? {
        if let field = root as? NSTextField { return field }
        for subview in root.subviews {
            if let field = firstTextField(in: subview) { return field }
        }
        return nil
    }
}
