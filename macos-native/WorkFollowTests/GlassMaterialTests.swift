import XCTest
@testable import WorkFollow

final class GlassMaterialTests: XCTestCase {
    func testOnlyLiquidGlassCanActivateGlassSurface() {
        XCTAssertFalse(WFGlassSupport.isActive(.classic, reduceTransparency: false))
        XCTAssertFalse(WFGlassSupport.isActive(.liquidGlass, reduceTransparency: true))
        if #available(macOS 26.0, *) {
            XCTAssertTrue(WFGlassSupport.isActive(.liquidGlass, reduceTransparency: false))
        } else {
            XCTAssertFalse(WFGlassSupport.isActive(.liquidGlass, reduceTransparency: false))
        }
    }

    func testMaterialChoicesStayStableForPersistence() {
        XCTAssertEqual(WFAppearanceMaterial.allCases, [.classic, .liquidGlass])
        XCTAssertEqual(WFAppearanceMaterial.classic.rawValue, "classic")
        XCTAssertEqual(WFAppearanceMaterial.liquidGlass.rawValue, "liquidGlass")
        XCTAssertEqual(WFAppearanceMaterial(rawValue: "liquidGlass"), .liquidGlass)
    }
}
