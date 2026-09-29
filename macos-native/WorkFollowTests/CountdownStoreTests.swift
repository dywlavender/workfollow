import XCTest
@testable import WorkFollow

/// `CountdownStore` 的增删改查、排序与持久化。
@MainActor
final class CountdownStoreTests: XCTestCase {
    private var calendar: Calendar {
        var value = Calendar(identifier: .gregorian)
        value.timeZone = TimeZone(secondsFromGMT: 8 * 3600)!
        return value
    }

    private var fixedNow: Date {
        calendar.date(from: DateComponents(year: 2026, month: 9, day: 29, hour: 10))!
    }

    /// 每个用例一个独立目录，避免互相看到对方的 countdowns.json。
    private func makeDirectory() -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("countdown-tests-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private func makeStore(directory: URL, now: Date? = nil) -> CountdownStore {
        CountdownStore(clock: { now ?? self.fixedNow }, calendar: calendar, directory: directory)
    }

    // MARK: 新建

    func testAddNormalizesAndAppends() {
        let store = makeStore(directory: makeDirectory())
        let event = store.add(name: "  春节  ", kind: .festival,
                              rule: .lunarYearly(month: 1, day: 1),
                              reminderOffsets: [0, 3 * 24 * 60, 999])
        XCTAssertEqual(event.name, "春节", "名称去首尾空白")
        XCTAssertEqual(event.reminderOffsets, [0, 3 * 24 * 60], "白名单外的提醒被丢掉")
        XCTAssertEqual(store.events.count, 1)
        XCTAssertEqual(event.sortOrder, 0)

        store.add(name: "生日", kind: .birthday, rule: .once(fixedNow))
        XCTAssertEqual(store.events.map(\.sortOrder), [0, 1], "新建追加到末尾")
    }

    /// 「显示岁数」只对生日有意义，别的类型即使传 true 也要落成 false。
    func testShowsAgeIsScopedToBirthdays() {
        let store = makeStore(directory: makeDirectory())
        let anniversary = store.add(name: "结婚纪念日", kind: .anniversary,
                                    rule: .once(fixedNow), showsAge: true)
        XCTAssertFalse(anniversary.showsAge)
        let birthday = store.add(name: "生日", kind: .birthday,
                                 rule: .once(fixedNow), showsAge: true)
        XCTAssertTrue(birthday.showsAge)
    }

    // MARK: 编辑

    func testUpdateKeepsIdentityArchiveStateAndSortOrder() {
        let store = makeStore(directory: makeDirectory())
        let event = store.add(name: "原名", kind: .countdown, rule: .once(fixedNow))
        store.add(name: "后面的", kind: .countdown, rule: .once(fixedNow))

        var edited = store.event(for: event.id)!
        edited.name = "  新名  "
        edited.kind = .birthday
        edited.rule = .solarYearly(month: 3, day: 1)
        edited.symbol = "不在白名单里"
        edited.colorIndex = 99
        edited.reminderOffsets = [0, 0, 999]
        edited.showsAge = true
        edited.sortOrder = 77          // 编辑面板不负责排序，应被忽略
        edited.archivedAt = fixedNow   // 也不负责归档，应被忽略
        store.update(edited)

        let saved = store.event(for: event.id)!
        XCTAssertEqual(saved.name, "新名")
        XCTAssertEqual(saved.kind, .birthday)
        XCTAssertEqual(saved.rule, .solarYearly(month: 3, day: 1))
        XCTAssertEqual(saved.symbol, CountdownKind.birthday.defaultSymbol, "白名单外回退默认符号")
        XCTAssertEqual(saved.colorIndex, 99 % CountdownEvent.paletteSize)
        XCTAssertEqual(saved.reminderOffsets, [0])
        XCTAssertTrue(saved.showsAge)
        XCTAssertEqual(saved.sortOrder, 0, "排序沿用原值")
        XCTAssertNil(saved.archivedAt, "归档状态沿用原值")
        XCTAssertEqual(saved.createdAt, event.createdAt)
    }

    func testUpdateIgnoresUnknownID() {
        let store = makeStore(directory: makeDirectory())
        let orphan = CountdownEvent(name: "不存在", rule: .once(fixedNow))
        store.update(orphan)
        XCTAssertTrue(store.events.isEmpty)
    }

    // MARK: 归档 / 删除 / 置顶

    func testArchiveAndRestoreMoveBetweenLists() {
        let store = makeStore(directory: makeDirectory())
        let event = store.add(name: "旧的", kind: .countdown, rule: .once(fixedNow))
        store.archive(event.id)
        XCTAssertTrue(store.events.isEmpty)
        XCTAssertEqual(store.archivedEvents.map(\.id), [event.id])
        XCTAssertNotNil(store.event(for: event.id), "归档只是移出列表，记录还在")

        store.restore(event.id)
        XCTAssertEqual(store.events.map(\.id), [event.id])
        XCTAssertTrue(store.archivedEvents.isEmpty)
    }

    func testHardDeleteRemovesTheRecordEntirely() {
        let store = makeStore(directory: makeDirectory())
        let event = store.add(name: "要删的", kind: .countdown, rule: .once(fixedNow))
        XCTAssertTrue(store.hardDelete(event.id))
        XCTAssertNil(store.event(for: event.id))
        XCTAssertFalse(store.hardDelete(event.id), "重复删除返回 false")
    }

    func testPinnedSortsFirstButKeepsRelativeOrder() {
        let store = makeStore(directory: makeDirectory())
        let first = store.add(name: "一", kind: .countdown, rule: .once(fixedNow))
        let second = store.add(name: "二", kind: .countdown, rule: .once(fixedNow))
        let third = store.add(name: "三", kind: .countdown, rule: .once(fixedNow))
        XCTAssertEqual(store.events.map(\.id), [first.id, second.id, third.id])

        store.togglePin(third.id)
        XCTAssertEqual(store.events.map(\.id), [third.id, first.id, second.id],
                       "置顶排最前，其余保持原序")

        store.togglePin(third.id)
        XCTAssertEqual(store.events.map(\.id), [first.id, second.id, third.id], "取消置顶回到原序")
    }

    func testMoveReordersAndRewritesSortOrder() {
        let store = makeStore(directory: makeDirectory())
        let first = store.add(name: "一", kind: .countdown, rule: .once(fixedNow))
        let second = store.add(name: "二", kind: .countdown, rule: .once(fixedNow))
        let third = store.add(name: "三", kind: .countdown, rule: .once(fixedNow))
        store.move(third.id, to: 0)
        XCTAssertEqual(store.events.map(\.id), [third.id, first.id, second.id])
        XCTAssertEqual(store.event(for: third.id)?.sortOrder, 0)
        XCTAssertEqual(store.event(for: first.id)?.sortOrder, 1)
    }

    func testSetStyleOnlyTouchesSymbolAndColour() {
        let store = makeStore(directory: makeDirectory())
        let event = store.add(name: "样式", kind: .countdown, rule: .once(fixedNow))
        store.setStyle(event.id, symbol: "gift", colorIndex: 3)
        XCTAssertEqual(store.event(for: event.id)?.symbol, "gift")
        XCTAssertEqual(store.event(for: event.id)?.colorIndex, 3)
        XCTAssertEqual(store.event(for: event.id)?.rule, .once(fixedNow), "日期不受影响")

        store.setStyle(event.id, symbol: "不存在", colorIndex: -1)
        XCTAssertEqual(store.event(for: event.id)?.symbol, CountdownKind.countdown.defaultSymbol)
        XCTAssertEqual(store.event(for: event.id)?.colorIndex, CountdownEvent.paletteSize - 1,
                       "负下标回绕")
    }

    func testSetNoteTrims() {
        let store = makeStore(directory: makeDirectory())
        let event = store.add(name: "备注", kind: .countdown, rule: .once(fixedNow))
        store.setNote(event.id, note: "  记一笔  ")
        XCTAssertEqual(store.event(for: event.id)?.note, "记一笔")
    }

    // MARK: 筛选

    func testFilteringByKind() {
        let store = makeStore(directory: makeDirectory())
        store.add(name: "纪念", kind: .anniversary, rule: .once(fixedNow))
        store.add(name: "倒数", kind: .countdown, rule: .once(fixedNow))
        store.add(name: "节日", kind: .festival, rule: .lunarYearly(month: 1, day: 1))
        store.add(name: "生日", kind: .birthday, rule: .once(fixedNow))

        XCTAssertEqual(store.events(matching: nil).count, 4, "「所有」含生日")
        XCTAssertEqual(store.events(matching: .anniversary).map(\.name), ["纪念"])
        XCTAssertEqual(store.events(matching: .festival).map(\.name), ["节日"])
        XCTAssertEqual(store.events(matching: .birthday).map(\.name), ["生日"])
    }

    // MARK: 跨天

    /// 定时器每分钟都会问一次，只有日界真的跨过才该重算（农历规则要向上扫一年）。
    func testRefreshOnlyBumpsWhenTheDayChanges() {
        let directory = makeDirectory()
        var now = fixedNow
        let store = CountdownStore(clock: { now }, calendar: calendar, directory: directory)
        let before = store.dateRevision
        store.refresh()
        XCTAssertEqual(store.dateRevision, before, "同一天不 bump")

        now = calendar.date(byAdding: .day, value: 1, to: fixedNow)!
        store.refresh()
        XCTAssertEqual(store.dateRevision, before + 1, "跨天 bump 一次")
    }

    // MARK: 持久化

    func testArchiveSurvivesAReload() throws {
        let directory = makeDirectory()
        let store = makeStore(directory: directory)
        let festival = store.add(name: "春节", kind: .festival,
                                 rule: .lunarYearly(month: 1, day: 1),
                                 reminderOffsets: [0, 7 * 24 * 60])
        store.add(name: "生日", kind: .birthday, rule: .once(fixedNow), showsAge: true)
        store.togglePin(festival.id)
        store.setNote(festival.id, note: "回家")
        flush(store)

        let reloaded = makeStore(directory: directory)
        XCTAssertEqual(reloaded.events.count, 2)
        let restored = try XCTUnwrap(reloaded.event(for: festival.id))
        XCTAssertEqual(restored.name, "春节")
        XCTAssertEqual(restored.rule, .lunarYearly(month: 1, day: 1))
        XCTAssertEqual(restored.reminderOffsets, [0, 7 * 24 * 60])
        XCTAssertEqual(restored.note, "回家")
        XCTAssertTrue(restored.pinned)
        XCTAssertEqual(reloaded.events.first?.id, festival.id, "置顶顺序也要活过重载")

        let birthday = try XCTUnwrap(reloaded.events.first { $0.kind == .birthday })
        XCTAssertTrue(birthday.showsAge)
        XCTAssertEqual(birthday.rule, .once(fixedNow))
    }

    func testArchiveStateSurvivesAReload() throws {
        let directory = makeDirectory()
        let store = makeStore(directory: directory)
        let event = store.add(name: "归档的", kind: .countdown, rule: .once(fixedNow))
        store.archive(event.id)
        flush(store)

        let reloaded = makeStore(directory: directory)
        XCTAssertTrue(reloaded.events.isEmpty)
        XCTAssertEqual(reloaded.archivedEvents.map(\.id), [event.id])
    }

    /// 生日往返不能丢掉出生年——丢了「显示岁数」就永远算不出来。
    func testBirthdayKeepsItsBirthYearAcrossAReload() throws {
        let directory = makeDirectory()
        let store = makeStore(directory: directory)
        let event = store.add(name: "生日", kind: .birthday,
                              rule: .birthday(month: 8, day: 20, birthYear: 2000),
                              showsAge: true)
        flush(store)

        let reloaded = makeStore(directory: directory)
        let saved = try XCTUnwrap(reloaded.event(for: event.id))
        XCTAssertEqual(saved.rule, .birthday(month: 8, day: 20, birthYear: 2000))
        XCTAssertEqual(saved.ageText(asOf: fixedNow, calendar: calendar), "26 岁")
    }

    /// 等防抖写入落盘（`JSONFileStore` 默认 0.4s 延迟）。
    private func flush(_ store: CountdownStore) {
        let done = expectation(description: "flush")
        store.flush { _ in done.fulfill() }
        wait(for: [done], timeout: 5)
    }
}
