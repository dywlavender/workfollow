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
    /// 面板里的多级提醒（0 = 准时，负数 = 提前多少分钟）。空数组 = 未设。
    var reminderOffsets: [Int] = []
    var repeatFrequency: TaskRepeat
    var recurrenceRule: RecurrenceRule?

    var schedule: TaskSchedule {
        TaskSchedule(dueAt: dueAt, hasTime: hasTime, dueEndAt: dueEndAt)
    }

    /// 交给动作层的形状：空数组表示"没有多级提醒"，而不是"清空"。
    var reminderOffsetsOrNil: [Int]? {
        reminderOffsets.isEmpty ? nil : reminderOffsets
    }

    init(dueAt: Date? = nil, dueEndAt: Date? = nil, hasTime: Bool = false,
         reminderAt: Date? = nil, reminderOffsets: [Int] = [],
         repeatFrequency: TaskRepeat = .never, recurrenceRule: RecurrenceRule? = nil) {
        self.dueAt = dueAt
        self.dueEndAt = dueAt == nil ? nil : dueEndAt
        self.hasTime = dueAt != nil && hasTime
        self.reminderAt = reminderAt
        self.reminderOffsets = reminderOffsets
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

    /// 直接由面板产出的 `SchedulePlan` 构造，宿主不再逐字段手抄
    /// （手抄就是丢字段的地方：`dueEndAt` / `reminderOffsets` / `rule.month` 都丢过）。
    init(_ plan: SchedulePlan) {
        self.init(dueAt: plan.schedule.dueAt,
                  dueEndAt: plan.schedule.dueEndAt,
                  hasTime: plan.schedule.hasTime,
                  reminderAt: plan.reminder,
                  reminderOffsets: plan.reminderOffsets,
                  repeatFrequency: plan.frequency,
                  recurrenceRule: plan.recurrenceRule)
    }
}
