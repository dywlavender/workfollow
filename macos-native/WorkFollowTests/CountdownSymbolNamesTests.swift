import XCTest
@testable import WorkFollow

/// `CountdownSymbolNames`（视图层的名字表）与 `CountdownEvent.symbolOptions`
/// （域模型的图标清单）是两份必须同步的表。
///
/// 分开是刻意的——`symbol` 是持久化字段，名字纯属展示，不该进数据模型。但分开
/// 就有漂移风险：图标加了一个而名字忘了加，界面会**静默**回退成显示英文符号名
/// （`name(for:)` 的兜底），没人会注意到。所以用测试把它们钉在一起。
final class CountdownSymbolNamesTests: XCTestCase {

    /// 每个可选图标都必须有名字。
    func testEverySymbolHasAName() {
        let missing = CountdownEvent.symbolOptions.filter { CountdownSymbolNames.all[$0] == nil }
        XCTAssertTrue(missing.isEmpty, "这些图标没有中文名：\(missing)")
    }

    /// 反过来：名字表里不能留下已经不在图标清单里的项（删图标或改名后的残留）。
    func testNoNamesForUnknownSymbols() {
        let known = Set(CountdownEvent.symbolOptions)
        let stale = CountdownSymbolNames.all.keys.filter { !known.contains($0) }.sorted()
        XCTAssertTrue(stale.isEmpty, "名字表里有已不在 symbolOptions 的项：\(stale)")
    }

    /// 名字要短、要是汉字。
    ///
    /// 长度不是审美偏好而是布局约束：最窄的一处格子是样式弹窗的 6 列 × 34pt，
    /// 在 `WFType.caption`（11pt）下 2 个汉字约 22pt 放得下，3 个字约 33pt 就顶满
    /// 34pt 了（`lineLimit(1)` 会把它截断）。
    func testNamesAreShortChinese() {
        for (symbol, name) in CountdownSymbolNames.all {
            XCTAssertFalse(name.isEmpty, "\(symbol) 的名字是空的")
            XCTAssertLessThanOrEqual(name.count, 2,
                                     "\(symbol) 的名字「\(name)」超过 2 个字，窄格里会被截断")
            let allHan = name.unicodeScalars.allSatisfy { (0x4E00...0x9FFF).contains($0.value) }
            XCTAssertTrue(allHan, "\(symbol) 的名字「\(name)」不是汉字")
        }
    }

    /// 兜底：查不到的符号返回它自己，而不是空串——宁可显示英文，也不要留白。
    func testUnknownSymbolFallsBackToItself() {
        XCTAssertEqual(CountdownSymbolNames.name(for: "some.unknown.symbol"), "some.unknown.symbol")
    }
}
