import Foundation

/// 快速添加条上「日期 / 提醒 / 重复」这组属性的草稿值。
///
/// 列表快速添加条（`TaskListView.quickAddBar`）、全局快速添加面板
/// （`GlobalQuickAddComposer`）与新建任务对话框（`TaskManagementViews`）共用它，
/// 把「解析结果」和「用户在日程面板里改过的值」投影成同一个形状。
///
/// 原本它与已废弃的 `QuickAddSchedulePopover` 同处一个文件；那个视图已无调用点
/// （日程面板统一走 `TaskDatePopoverV2`），所以这里把仍在使用的草稿类型单独留下。
struct QuickAddScheduleDraft: Equatable {
    var dueAt: Date?
    var dueEndAt: Date?
    var hasTime: Bool
    var reminderAt: Date?
    var repeatFrequency: TaskRepeat
    var recurrenceRule: RecurrenceRule?

    var schedule: TaskSchedule {
        TaskSchedule(dueAt: dueAt, hasTime: hasTime, dueEndAt: dueEndAt)
    }

    init(dueAt: Date? = nil, dueEndAt: Date? = nil, hasTime: Bool = false,
         reminderAt: Date? = nil,
         repeatFrequency: TaskRepeat = .never, recurrenceRule: RecurrenceRule? = nil) {
        self.dueAt = dueAt
        self.dueEndAt = dueAt == nil ? nil : dueEndAt
        self.hasTime = dueAt != nil && hasTime
        self.reminderAt = reminderAt
        self.repeatFrequency = repeatFrequency
        self.recurrenceRule = recurrenceRule
    }

    init(parsed: QuickAddParseResult, defaultDueAt: Date?) {
        self.init(dueAt: parsed.dueAt ?? defaultDueAt,
                  hasTime: parsed.hasTime,
                  reminderAt: parsed.reminderAt,
                  repeatFrequency: parsed.recurrence,
                  recurrenceRule: parsed.recurrenceRule)
    }
}
