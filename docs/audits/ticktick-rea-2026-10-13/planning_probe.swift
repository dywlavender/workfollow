import Foundation
var calendar = Calendar(identifier: .gregorian)
calendar.timeZone = TimeZone(identifier: "Asia/Shanghai")!
calendar.firstWeekday = 1
func day(_ month: Int, _ value: Int, hour: Int = 0) -> Date {
    calendar.date(from: DateComponents(year: 2026, month: month, day: value, hour: hour))!
}
let now = day(10, 13, hour: 10)
func task(_ title: String, _ schedule: TaskSchedule, priority: TaskPriority = .high) -> Task {
    Task(id: UUID(), title: title, list: .inbox, priority: priority, schedule: schedule,
         parentID: nil, childOrder: 0, createdAt: now, updatedAt: now)
}
let deadlineOnly = task("明天截止，未安排", TaskSchedule(deadlineAt: day(10, 14)))
print("deadline-only quadrant:", PlanningProjection.quadrant(deadlineOnly, now: now, calendar: calendar))
let spanning = task("10/13–10/16", TaskSchedule(dueAt: day(10, 13), dueEndAt: day(10, 16)))
print("span on start day:", PlanningProjection.tasks(on: day(10, 13), from: [spanning], calendar: calendar).count)
print("span on next day:", PlanningProjection.tasks(on: day(10, 14), from: [spanning], calendar: calendar).count)
var recurring = task("每天 9 点", TaskSchedule(dueAt: day(10, 13, hour: 9), hasTime: true))
recurring.recurrence = .daily
print("daily recurring tomorrow:", PlanningProjection.tasks(on: day(10, 14), from: [recurring], calendar: calendar).count)
let late = task("下午 4 点", TaskSchedule(dueAt: day(10, 13, hour: 16), hasTime: true))
let early = task("上午 9 点", TaskSchedule(dueAt: day(10, 13, hour: 9), hasTime: true))
print("calendar order:", PlanningProjection.tasks(on: day(10, 13), from: [late, early], calendar: calendar).map(\.title))
print("last Thursday label:", MatrixProjection.dateLabel(for: day(10, 8), now: now, calendar: calendar) ?? "nil")
let spans = (1...5).map { task("跨天任务 \($0)", TaskSchedule(dueAt: day(10, 13), dueEndAt: day(10, 16))) }
let placed = CalendarSpans.lanes(for: PlanningProjection.weekDays(containing: now, calendar: calendar), tasks: spans, calendar: calendar)
print("five spans lanes:", placed.map(\.lane))
let lastBottom = 3 + 24 + 2 + (placed.last!.lane * 19) + 17
print("five span last bottom pt:", lastBottom)
