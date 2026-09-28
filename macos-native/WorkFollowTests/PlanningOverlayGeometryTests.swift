import XCTest
@testable import WorkFollow

/// 锚定浮层的定位契约（Flutter `calculatePopoverGeometry` 的移植）。
///
/// 这几条用例问的是"弹框出现在哪里"：贴在锚框哪一侧、对齐到哪一条边、装不下时怎么
/// 翻转、夹在窗口安全边距里的位置。日历与四象限的编辑器与新建卡都靠它，改错一条
/// 就是弹框跑到别处去。
final class PlanningOverlayGeometryTests: XCTestCase {
    private let viewport = CGSize(width: 1200, height: 800)
    /// 一个在窗口左上区域的锚：x 100、y 100、宽 200、高 20。
    private let anchor = CGRect(x: 100, y: 100, width: 200, height: 20)
    private let editorSize = CGSize(width: 400, height: 356)

    // MARK: 贴在下方

    func testBottomCenterSitsSixPointsBelowTheAnchor() {
        // 锚框放在窗口中间，才看得出「居中」这一条：贴着窗口左缘的锚框会被安全边距
        // 夹住，那不是没对齐，是原版就夹。
        let centered = CGRect(x: 500, y: 100, width: 200, height: 20)
        let geometry = WFOverlayGeometryMath.compute(anchor: centered,
                                                     viewport: viewport,
                                                     desired: editorSize,
                                                     placement: .bottomCenter)
        XCTAssertEqual(geometry.side, .bottom)
        XCTAssertFalse(geometry.flipped)
        XCTAssertEqual(geometry.rect.height, 356)
        XCTAssertEqual(geometry.rect.width, 400)
        // 间距就是 `PopoverPlacement.gap`，不是"差不多贴着"。
        XCTAssertEqual(geometry.rect.minY, centered.maxY + 6)
        XCTAssertEqual(geometry.rect.midX, centered.midX)
    }

    func testLeftEdgeAnchorIsClampedAndLeavesTheSixPointGap() {
        let geometry = WFOverlayGeometryMath.compute(anchor: anchor,
                                                     viewport: viewport,
                                                     desired: editorSize,
                                                     placement: .bottomCenter)
        // 400 宽的卡片在窗口左缘居中会被推到安全边距上，但仍贴着锚框下方。
        XCTAssertEqual(geometry.rect.minX, WFPlanningOverlayMetrics.safeArea)
        XCTAssertEqual(geometry.rect.minY, anchor.maxY + 6)
    }

    func testBottomEndAlignsTheRightEdges() {
        // 锚框放到窗口右侧，右对齐才有位置可落。
        let right = CGRect(x: 900, y: 100, width: 200, height: 20)
        let geometry = WFOverlayGeometryMath.compute(anchor: right,
                                                     viewport: viewport,
                                                     desired: CGSize(width: 320, height: 212),
                                                     placement: .bottomEnd)
        XCTAssertEqual(geometry.side, .bottom)
        XCTAssertEqual(geometry.rect.maxX, right.maxX)
        XCTAssertEqual(geometry.rect.minY, right.maxY + 6)
    }

    // MARK: 装不下时翻转

    func testFlipsAboveWhenTheWindowHasNoRoomBelow() {
        let low = CGRect(x: 100, y: 600, width: 200, height: 20)
        let geometry = WFOverlayGeometryMath.compute(anchor: low,
                                                     viewport: viewport,
                                                     desired: editorSize,
                                                     placement: .bottomCenter)
        XCTAssertEqual(geometry.side, .top)
        XCTAssertTrue(geometry.flipped)
        // 翻到上方：面板底边在锚框上方 6pt。
        XCTAssertEqual(geometry.rect.maxY, low.minY - 6)
    }

    // MARK: 夹在安全边距里

    func testKeepsThePanelInsideTheSafeAreaForAnEdgeAnchor() {
        let corner = CGRect(x: 0, y: 0, width: 24, height: 20)
        let geometry = WFOverlayGeometryMath.compute(anchor: corner,
                                                     viewport: viewport,
                                                     desired: editorSize,
                                                     placement: .bottomCenter)
        XCTAssertEqual(geometry.rect.minX, WFPlanningOverlayMetrics.safeArea)
        XCTAssertEqual(geometry.rect.minY, corner.maxY + 6)
    }

    func testNarrowerWindowShrinksThePanelToTheSafeWidth() {
        let geometry = WFOverlayGeometryMath.compute(anchor: anchor,
                                                     viewport: CGSize(width: 320, height: 800),
                                                     desired: editorSize,
                                                     placement: .bottomCenter)
        XCTAssertEqual(geometry.rect.width, 320 - WFPlanningOverlayMetrics.safeArea * 2)
    }

    func testShorterWindowCapsThePanelHeight() {
        let geometry = WFOverlayGeometryMath.compute(anchor: anchor,
                                                     viewport: CGSize(width: 1200, height: 300),
                                                     desired: editorSize,
                                                     placement: .bottomCenter)
        XCTAssertEqual(geometry.rect.height, 300 - WFPlanningOverlayMetrics.safeArea * 2)
    }

    // MARK: 尺寸契约

    func testOverlaySizesMatchTheFlutterSurfaces() {
        // 编辑器 400×356（`TaskSurfaceMetrics.editorWidth` / `editorMinHeight`），
        // 新建卡 320×(42+1+126+1+42)。
        XCTAssertEqual(WFPlanningOverlayMetrics.editorWidth, 400)
        XCTAssertEqual(WFPlanningOverlayMetrics.editorHeight, 356)
        XCTAssertEqual(WFPlanningOverlayMetrics.composerWidth, 320)
        XCTAssertEqual(WFPlanningOverlayMetrics.composerHeight, 212)
    }
}
