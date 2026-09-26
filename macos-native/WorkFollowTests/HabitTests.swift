import XCTest
@testable import WorkFollow

@MainActor
final class HabitTests: XCTestCase {
    private let calendar: Calendar = {
        var value = Calendar(identifier: .gregorian)
        value.timeZone = TimeZone(secondsFromGMT: 0)!
        return value
    }()
    private var now = Date(timeIntervalSince1970: 1_800_000_000)

    // MARK: Helpers

    private func makeStore() -> HabitStore {
        HabitStore(clock: { self.now }, directory: FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString))
    }

    private func date(_ year: Int, _ month: Int, _ day: Int) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: day))!
    }

    /// 以 `asOf`（2026-09-26，周六）为基准偏移 `offset` 天的日键。
    private func dayKey(from asOf: Date, offset: Int) -> String {
        Habit.dayKey(calendar.date(byAdding: .day, value: offset, to: asOf)!, calendar: calendar)
    }

    private func record(_ habit: Habit, _ dayKey: String) -> HabitCheckIn {
        HabitCheckIn(habitID: habit.id, dayKey: dayKey, createdAt: now)
    }

    // MARK: 计划日判定

    func testEmptyScheduleMeansEveryDayAndWeekdaysMatch() {
        let daily = Habit(name: "每天", createdAt: now)
        for weekday in 1...7 {
            XCTAssertTrue(daily.isScheduled(onWeekday: weekday))
        }

        let mondays = Habit(name: "周一", scheduleDays: [2], createdAt: now)
        XCTAssertTrue(mondays.isScheduled(onWeekday: 2))
        XCTAssertFalse(mondays.isScheduled(onWeekday: 1))
        XCTAssertTrue(mondays.isScheduled(on: date(2026, 9, 21), calendar: calendar))  // 周一
        XCTAssertFalse(mondays.isScheduled(on: date(2026, 9, 26), calendar: calendar))  // 周六
        XCTAssertFalse(mondays.isScheduled(on: date(2026, 9, 27), calendar: calendar))  // 周日
    }

    func testNormalizedScheduleDaysKeepsValidWeekdaysOnly() {
        XCTAssertEqual(Habit.normalizedScheduleDays([8, 0, -1, 3, 3, 1]), [1, 3])
        XCTAssertEqual(Habit.normalizedScheduleDays([]), [])
    }

    // MARK: 连续天数

    func testCurrentStreakStartsFromYesterdayWhenTodayUnchecked() {
        let habit = Habit(name: "阅读", createdAt: now)
        let asOf = date(2026, 9, 26)  // 周六
        let yesterday = record(habit, dayKey(from: asOf, offset: -1))
        let dayBefore = record(habit, dayKey(from: asOf, offset: -2))

        // 今天未打卡不打断：从昨天起算连续两天。
        XCTAssertEqual(habit.currentStreak(asOf: asOf, checkIns: [yesterday, dayBefore], calendar: calendar), 2)
        // 今天已打卡则计入。
        let today = record(habit, dayKey(from: asOf, offset: 0))
        XCTAssertEqual(
            habit.currentStreak(asOf: asOf, checkIns: [today, yesterday, dayBefore], calendar: calendar), 3)
        // 今天打卡但昨天断签，只算今天。
        XCTAssertEqual(habit.currentStreak(asOf: asOf, checkIns: [today], calendar: calendar), 1)
        // 昨天断签归零（即使更早有天打卡）。
        XCTAssertEqual(habit.currentStreak(asOf: asOf, checkIns: [dayBefore], calendar: calendar), 0)
        // 习惯自己的打卡之外的数据不参与统计。
        let other = Habit(name: "其他", createdAt: now)
        let stranger = record(other, dayKey(from: asOf, offset: -1))
        XCTAssertEqual(habit.currentStreak(asOf: asOf, checkIns: [stranger], calendar: calendar), 0)
    }

    func testCurrentStreakSkipsUnscheduledDaysWithoutBreaking() {
        let habit = Habit(name: "周五特训", scheduleDays: [6], createdAt: now)  // 仅周五
        let asOf = date(2026, 9, 26)  // 周六；9-25 与 9-18 都是周五
        let lastFriday = record(habit, dayKey(from: asOf, offset: -1))
        let earlierFriday = record(habit, dayKey(from: asOf, offset: -8))
        // 中间的周六到周四均为非计划日，不打断连续。
        XCTAssertEqual(
            habit.currentStreak(asOf: asOf, checkIns: [lastFriday, earlierFriday], calendar: calendar), 2)
        // 再往前最近的周五未打卡则截止。
        let anotherFriday = record(habit, dayKey(from: asOf, offset: -15))
        XCTAssertEqual(
            habit.currentStreak(asOf: asOf, checkIns: [lastFriday, earlierFriday, anotherFriday],
                                calendar: calendar), 3)
    }

    // MARK: 打卡率

    func testCheckInRateCountsOnlyScheduledDaysWithinRange() {
        let daily = Habit(name: "每天", createdAt: now)
        let from = date(2026, 9, 21)
        let to = date(2026, 9, 30)  // 10 天区间
        let fiveDays = [21, 22, 23, 26, 27].map {
            record(daily, Habit.dayKey(date(2026, 9, $0), calendar: calendar))
        }
        XCTAssertEqual(daily.checkInRate(from: from, to: to, checkIns: fiveDays, calendar: calendar), 0.5, accuracy: 0.0001)
        // 单日区间且当天已打卡 = 100%；区间外打卡不计入。
        XCTAssertEqual(daily.checkInRate(from: from, to: from, checkIns: fiveDays, calendar: calendar), 1, accuracy: 0.0001)
        // 无计划日的区间返回 0。
        let mondays = Habit(name: "周一", scheduleDays: [2], createdAt: now)
        let tuesdayToSunday = (22...27).map { record(mondays, Habit.dayKey(date(2026, 9, $0), calendar: calendar)) }
        XCTAssertEqual(
            mondays.checkInRate(from: date(2026, 9, 22), to: date(2026, 9, 27), checkIns: tuesdayToSunday, calendar: calendar), 0, accuracy: 0.0001)
        // 计划日之外的打卡不抬高比例。
        let offDay = record(mondays, Habit.dayKey(date(2026, 9, 22), calendar: calendar))  // 周二
        XCTAssertEqual(
            mondays.checkInRate(from: from, to: date(2026, 9, 27), checkIns: [offDay], calendar: calendar), 0, accuracy: 0.0001)
        // 单个计划日已打卡 = 100%。
        let monday = record(mondays, Habit.dayKey(date(2026, 9, 21), calendar: calendar))
        XCTAssertEqual(
            mondays.checkInRate(from: from, to: date(2026, 9, 27), checkIns: [monday, offDay], calendar: calendar), 1, accuracy: 0.0001)
        // 起止颠倒返回 0。
        XCTAssertEqual(daily.checkInRate(from: to, to: from, checkIns: fiveDays, calendar: calendar), 0, accuracy: 0.0001)
    }

    // MARK: 日键

    func testDayKeyFormatIsZeroPaddedAndParsesBack() {
        XCTAssertEqual(Habit.dayKey(date(2026, 9, 5), calendar: calendar), "2026-09-05")
        XCTAssertEqual(HabitStore.dayKey(date(2026, 12, 31), calendar: calendar), "2026-12-31")
        XCTAssertEqual(Habit.date(fromDayKey: "2026-09-05", calendar: calendar),
                       calendar.startOfDay(for: date(2026, 9, 5)))
        XCTAssertNil(Habit.date(fromDayKey: "not-a-day", calendar: calendar))
    }

    // MARK: 打卡与心得

    func testStoreCheckInIsIdempotentAndNoteUpdates() {
        let store = makeStore()
        let habit = store.add(name: "喝水")
        let key = store.todayKey

        XCTAssertTrue(store.checkIn(habit.id, dayKey: key))
        XCTAssertFalse(store.checkIn(habit.id, dayKey: key))  // 重复打卡幂等
        XCTAssertEqual(store.checkIns.count, 1)

        XCTAssertTrue(store.checkIn(habit.id, dayKey: key, note: "多喝了一杯"))
        XCTAssertEqual(store.checkInRecord(habitID: habit.id, dayKey: key)?.note, "多喝了一杯")
        XCTAssertEqual(store.checkIns.count, 1)

        // 圆环翻转：取消后再取消无副作用。
        store.toggleCheckIn(habit.id, dayKey: key)
        XCTAssertNil(store.checkInRecord(habitID: habit.id, dayKey: key))
        XCTAssertFalse(store.uncheck(habit.id, dayKey: key))
        XCTAssertEqual(store.checkIns.count, 0)

        // 心得保存：未打卡的日期会创建打卡记录。
        store.saveNote(habit.id, dayKey: key, note: "补记心得")
        XCTAssertEqual(store.checkInRecord(habitID: habit.id, dayKey: key)?.note, "补记心得")
        // 空白心得清空内容但保留打卡；再次保存无变化不写入。
        store.saveNote(habit.id, dayKey: key, note: "  \n ")
        XCTAssertEqual(store.checkInRecord(habitID: habit.id, dayKey: key)?.note, "")
        XCTAssertEqual(store.checkIns.count, 1)
        store.saveNote(habit.id, dayKey: key, note: "")
        XCTAssertEqual(store.checkIns.count, 1)
    }

    // MARK: 归档与删除

    func testArchivedHabitLeavesTodaysListAndHardDeleteOnlyWorksWhenArchived() {
        let store = makeStore()
        let first = store.add(name: "晨跑")
        let second = store.add(name: "冥想")
        XCTAssertEqual(store.todaysHabits.map(\.id), [first.id, second.id])

        store.checkIn(first.id, dayKey: store.todayKey)
        store.archive(first.id)
        XCTAssertFalse(store.todaysHabits.contains { $0.id == first.id })
        XCTAssertEqual(store.habits.map(\.id), [second.id])
        XCTAssertEqual(store.archivedHabits.map(\.id), [first.id])
        XCTAssertEqual(store.habitsIncludingArchived.map(\.id), [first.id, second.id])

        // 未归档不允许彻底删除。
        XCTAssertFalse(store.hardDelete(second.id))
        XCTAssertEqual(store.habitsIncludingArchived.count, 2)

        // 恢复后回到今日列表（每日习惯）。
        store.restore(first.id)
        XCTAssertEqual(store.todaysHabits.map(\.id), [first.id, second.id])

        store.archive(first.id)
        XCTAssertTrue(store.hardDelete(first.id))
        XCTAssertEqual(store.habitsIncludingArchived.map(\.id), [second.id])
        XCTAssertTrue(store.checkIns.isEmpty)  // 打卡记录一并删除
        XCTAssertFalse(store.hardDelete(first.id))  // 已不存在
    }

    // MARK: 字段归一化、排序与更新

    func testAddNormalizesFieldsAndAssignsIncreasingSortOrder() {
        let store = makeStore()
        let first = store.add(name: "  跑步  ", symbol: "not-in-whitelist", colorIndex: 99, scheduleDays: [2, 2, 99])
        XCTAssertEqual(first.name, "跑步")
        XCTAssertEqual(first.symbol, Habit.symbolOptions[0])
        XCTAssertEqual(first.colorIndex, 3)  // 99 回绕到色板第 4 位
        XCTAssertEqual(first.scheduleDays, [2])
        XCTAssertEqual(first.sortOrder, 0)

        let second = store.add(name: "阅读")
        XCTAssertGreaterThan(second.sortOrder, first.sortOrder)
        XCTAssertEqual(store.habits.map(\.name), ["跑步", "阅读"])

        store.move(second.id, to: 0)
        XCTAssertEqual(store.habits.map(\.id), [second.id, first.id])
        XCTAssertEqual(store.habits.map(\.sortOrder), [0, 1])
    }

    func testUpdateChangesFieldsButKeepsIdentityAndCheckIns() throws {
        let store = makeStore()
        let habit = store.add(name: "旧名字")
        store.checkIn(habit.id, dayKey: store.todayKey, note: "记录")

        store.update(habit.id, name: "  新名字  ", symbol: "figure.run", colorIndex: 2, scheduleDays: [1, 7])
        let updated = try XCTUnwrap(store.habits.first)
        XCTAssertEqual(updated.id, habit.id)
        XCTAssertEqual(updated.name, "新名字")
        XCTAssertEqual(updated.symbol, "figure.run")
        XCTAssertEqual(updated.colorIndex, 2)
        XCTAssertEqual(updated.scheduleDays, [1, 7])
        XCTAssertEqual(updated.createdAt, habit.createdAt)
        XCTAssertEqual(store.checkIns(for: habit.id).first?.note, "记录")

        // 白名单之外的符号与非法 weekday 被忽略/过滤。
        store.update(habit.id, symbol: "not-in-whitelist", scheduleDays: [42])
        XCTAssertEqual(try XCTUnwrap(store.habits.first).symbol, "figure.run")
        XCTAssertEqual(try XCTUnwrap(store.habits.first).scheduleDays, [])

        // 更新不存在的习惯无副作用。
        store.update(UUID(), name: "ghost")
        XCTAssertEqual(store.habits.count, 1)
    }

    // MARK: 持久化

    func testFlushPersistsArchiveForTheNextStoreInstance() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
        let store = HabitStore(clock: { self.now }, directory: directory)
        let habit = store.add(name: "持久化习惯", symbol: "drop", colorIndex: 4, scheduleDays: [2])
        store.checkIn(habit.id, dayKey: "2026-09-25", note: "有心得")
        store.archive(habit.id)

        let done = expectation(description: "flush")
        store.flush { error in
            XCTAssertNil(error)
            done.fulfill()
        }
        await fulfillment(of: [done], timeout: 5)

        let reloaded = HabitStore(clock: { self.now }, directory: directory)
        let archived = try XCTUnwrap(reloaded.archivedHabits.first)
        XCTAssertEqual(archived.name, "持久化习惯")
        XCTAssertEqual(archived.symbol, "drop")
        XCTAssertEqual(archived.colorIndex, 4)
        XCTAssertEqual(archived.scheduleDays, [2])
        XCTAssertNotNil(archived.archivedAt)
        XCTAssertTrue(reloaded.todaysHabits.isEmpty)  // 已归档不出现在今日列表
        XCTAssertEqual(reloaded.checkIns(for: habit.id).first?.note, "有心得")
    }
}
