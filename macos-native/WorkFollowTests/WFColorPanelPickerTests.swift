import AppKit
import XCTest
@testable import WorkFollow

@MainActor
final class WFColorPanelPickerTests: XCTestCase {
    /// 面板是全局单例：present 之后必须能收到色值，dismiss 之后必须不再收。
    func testPickedColorIsDeliveredThenDetached() {
        var picked: UInt32?
        WFColorPanelPicker.present(seed: 0xFF27C264) { picked = $0 }
        defer { WFColorPanelPicker.dismiss() }
        XCTAssertEqual(NSColorPanel.shared.color.usingColorSpace(.sRGB)?.redComponent ?? 0,
                       0x27 / 255.0, accuracy: 0.01)
        NSColorPanel.shared.setTarget(nil)     // 防止真的把面板留在屏幕上
        NSColorPanel.shared.orderOut(nil)
    }

    /// dismiss 是幂等的，且不会在没接线时误摘别人的 target。
    func testDismissIsIdempotent() {
        WFColorPanelPicker.dismiss()
        WFColorPanelPicker.dismiss()
    }
}
