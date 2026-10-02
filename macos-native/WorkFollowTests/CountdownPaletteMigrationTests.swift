import SwiftUI
import XCTest
@testable import WorkFollow

/// 色板从 6 格扩到 12 格时，存量 `colorIndex` 的搬迁。
///
/// 这一组盯的是一件事：**用户已有的卡片不会集体换色**。下标是位置，位置变了颜色就变了，
/// 所以必须搬一次；而搬迁表一旦写错，表现是「颜色看着不对」，不会报错、不会崩，
/// 只能靠测试钉住。参照实现颜色行的实测见 `CountdownPaletteColors.swift` 的注释。
@MainActor
final class CountdownPaletteMigrationTests: XCTestCase {

    private var calendar: Calendar {
        var value = Calendar(identifier: .gregorian)
        value.timeZone = TimeZone(secondsFromGMT: 8 * 3600)!
        return value
    }

    private var fixedNow: Date {
        calendar.date(from: DateComponents(year: 2026, month: 10, day: 2, hour: 10))!
    }

    // MARK: 搬迁表本身

    /// 本机存量那两条记录的下标：春节 4（蓝）、小美 5（紫）。
    /// 搬到新色板后仍然要是蓝与紫——这正是这次改动的验收标准。
    func testTheTwoStoredIndicesKeepTheirColour() {
        XCTAssertEqual(CountdownPalette.remap(4), 0, "蓝 → 蓝")
        XCTAssertEqual(CountdownPalette.remap(5), 8, "紫 → 紫罗兰")
    }

    /// 老 6 格每一格都要落到新色板范围内、且互不撞车。
    ///
    /// 撞车 = 两个本来不同的颜色变成同一个，用户会看到两张不同颜色的卡片合并成一种。
    /// 这也是为什么表是「整体配一次」而不是逐格各取最近色（见 `CountdownPalette` 的注释）。
    func testLegacyRemapIsInjectiveAndInRange() {
        let targets = (0..<CountdownPalette.legacyRemap.count).map(CountdownPalette.remap)
        XCTAssertEqual(Set(targets).count, targets.count, "搬迁不能把两个老颜色映到同一格")
        for target in targets {
            XCTAssertTrue((0..<CountdownPalette.size).contains(target),
                          "搬迁结果 \(target) 越出 \(CountdownPalette.size) 格色板")
        }
    }

    /// 负数与越界按老色板格数回绕。存量文件与导入数据都可能带越界值。
    func testRemapWrapsNegativeAndOutOfRange() {
        XCTAssertEqual(CountdownPalette.remap(-1), CountdownPalette.remap(5))
        XCTAssertEqual(CountdownPalette.remap(10), CountdownPalette.remap(4))
        XCTAssertEqual(CountdownPalette.remap(99), CountdownPalette.remap(99 % 6))
    }

    // MARK: 四种类型的默认色

    /// 色板换序时 `CountdownKind.defaultColorIndex` **必须跟着一起改**，
    /// 否则四种类型的默认色会一起跑掉（改色板却忘了改默认值，是最容易漏的一处）。
    ///
    /// 判据不是「等于某个数」，而是「**新建的纪念日要和存量的纪念日同一个颜色**」：
    /// 老默认值经搬迁表落到的位置，就是新默认值该在的位置。
    func testKindDefaultsMatchWhatLegacyRecordsMigrateTo() {
        // 老色板 [红 0, 橙 1, 黄 2, 绿 3, 蓝 4, 紫 5] 下的旧默认值。
        let oldDefaults: [CountdownKind: Int] = [
            .anniversary: 1,  // 橙
            .countdown: 4,    // 蓝
            .festival: 0,     // 红
            .birthday: 5,     // 紫
        ]
        for (kind, old) in oldDefaults {
            XCTAssertEqual(kind.defaultColorIndex, CountdownPalette.remap(old),
                           "\(kind) 的新默认色与老记录搬迁后的落点不一致")
        }
    }

    // MARK: 载入迁移

    func testLegacyFileIsMigratedOnLoad() {
        let directory = makeDirectory()
        writeLegacyArchive([makeEvent(name: "春节", colorIndex: 4),
                            makeEvent(name: "小美", colorIndex: 5)], to: directory)

        let store = makeStore(directory: directory)
        XCTAssertEqual(store.events.map(\.colorIndex), [0, 8],
                       "老文件里的 4 / 5 要搬成 0 / 8")
        XCTAssertEqual(store.events.map(\.name), ["春节", "小美"], "搬迁不该动别的字段")
    }

    /// 已经搬过的文件不再动——否则每次启动都再搬一次，颜色会一路漂走。
    func testCurrentVersionFileIsNotTouched() {
        let directory = makeDirectory()
        writeArchive([makeEvent(name: "春节", colorIndex: 4)], version: 2, to: directory)

        let store = makeStore(directory: directory)
        XCTAssertEqual(store.events.map(\.colorIndex), [4], "版本 2 的文件原样读入")
    }

    /// 搬完要落盘并写上版本号。不写的话下次启动还会再搬一遍。
    func testMigrationIsPersistedWithTheNewVersion() throws {
        let directory = makeDirectory()
        writeLegacyArchive([makeEvent(name: "春节", colorIndex: 4)], to: directory)

        let store = makeStore(directory: directory)
        flush(store)

        let archive = try readArchive(from: directory)
        XCTAssertEqual(archive.paletteVersion, CountdownPalette.version, "版本号要写进文件")
        XCTAssertEqual(archive.events.map(\.colorIndex), [0])

        // 再载入一次：颜色不变（搬迁幂等，不是每次启动都往后再搬一格）。
        let reloaded = makeStore(directory: directory)
        XCTAssertEqual(reloaded.events.map(\.colorIndex), [0])
    }

    /// 空目录（首次启动）不该因为迁移而写出一个文件。
    func testNoFileMeansNoMigrationAndNoWrite() {
        let directory = makeDirectory()
        let store = makeStore(directory: directory)
        flush(store)
        XCTAssertFalse(FileManager.default.fileExists(
            atPath: directory.appendingPathComponent("countdowns.json").path),
                       "没有存量文件时不该凭空写一个")
        XCTAssertTrue(store.events.isEmpty)
    }

    // MARK: 前提校验

    /// **这条是上面几个用例的前提**：`paletteVersion` 为 nil 时不能把键写进 JSON。
    ///
    /// 若 `JSONEncoder` 真的把 `"paletteVersion": null` 写出来，那「老文件」就永远
    /// 造不出来了——上面的用例会变成自欺（解出来不是 nil，迁移根本不触发）。
    func testNilVersionIsOmittedFromJSON() throws {
        let data = try JSONEncoder().encode(
            CountdownStore.CountdownArchive(events: [], paletteVersion: nil))
        let json = String(decoding: data, as: UTF8.self)
        XCTAssertFalse(json.contains("paletteVersion"), "nil 版本不该写进文件：\(json)")
    }

    // MARK: 两份色板必须同宽

    /// Domain 的格数与界面侧色板的格数必须相等。两份定义在两个文件里（Domain 不引
    /// SwiftUI），靠这条绑住：改了色板不改 `CountdownPalette.size`（或反过来）会红。
    func testPaletteSizeMatchesTheViewSidePalette() {
        XCTAssertEqual(CountdownEvent.paletteSize, CountdownPalette.size)
        XCTAssertEqual(CountdownEvent.paletteSize, countdownPaletteColors.count,
                       "Domain 的格数与界面侧色板的格数必须相等")
    }

    // MARK: 夹具

    private func makeEvent(name: String, colorIndex: Int) -> CountdownEvent {
        CountdownEvent(name: name, kind: .festival,
                       rule: .lunarYearly(month: 1, day: 1),
                       colorIndex: colorIndex)
    }

    private func writeLegacyArchive(_ events: [CountdownEvent], to directory: URL) {
        writeArchive(events, version: nil, to: directory)
    }

    /// `version: nil` 走的是合成 `Codable` 的 `encodeIfPresent`，键会被省略，
    /// 这正是「老文件」的形状（见 `testNilVersionIsOmittedFromJSON`）。
    private func writeArchive(_ events: [CountdownEvent], version: Int?, to directory: URL) {
        let archive = CountdownStore.CountdownArchive(events: events, paletteVersion: version)
        do {
            let data = try JSONEncoder().encode(archive)
            try data.write(to: directory.appendingPathComponent("countdowns.json"))
        } catch {
            XCTFail("写夹具失败：\(error)")
        }
    }

    private func readArchive(from directory: URL) throws -> CountdownStore.CountdownArchive {
        let data = try Data(contentsOf: directory.appendingPathComponent("countdowns.json"))
        return try JSONDecoder().decode(CountdownStore.CountdownArchive.self, from: data)
    }

    /// 每个用例一个独立目录，避免互相看到对方的 countdowns.json。
    private func makeDirectory() -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("countdown-palette-tests-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private func makeStore(directory: URL) -> CountdownStore {
        CountdownStore(clock: { self.fixedNow }, calendar: calendar, directory: directory)
    }

    /// 等防抖写入落盘（`JSONFileStore` 默认 0.4s 延迟）。
    private func flush(_ store: CountdownStore) {
        let done = expectation(description: "flush")
        store.flush { _ in done.fulfill() }
        wait(for: [done], timeout: 5)
    }
}
