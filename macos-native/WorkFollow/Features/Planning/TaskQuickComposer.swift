import SwiftUI

/// 日历与四象限共用的小新建卡，逐项对齐 Flutter `widgets/task_add_surface.dart`
/// （`TaskAddSurface`）：宽 320、高 212 的三行卡——「日期 … 旗标」「正文」「清单 …
/// 更多」，两行之间各一条 1pt 分隔线，**没有确定/取消按钮**，回车即创建。
///
/// 它与任务列表的 `TaskComposer`（整张"新建任务"表单）不是一件事：原版里列表用
/// 快速输入行、这两页用这张小卡，本工程此前把两者合成了一个表单，这里按原版拆开。
///
/// 卡里只持有草稿；页面对"新任务落在哪一天、什么优先级"的决定通过
/// `fallbackSchedule` / `presetSchedule` / `presetPriority` 传进来——日历给的是被点
/// 那一天，四象限给的是象限默认值（对齐 `createTaskFromComposer` /
/// `createTaskInMatrixQuadrant`）。
struct TaskQuickComposer: View {
    @ObservedObject var workspace: TaskWorkspaceModel

    /// 用户没动日期时，页面替它决定的日程。
    let fallbackSchedule: TaskSchedule
    /// 打开时就带上的日程；nil 表示卡上显示「设置日期」。
    let presetSchedule: TaskSchedule?
    /// 打开时的优先级（四象限的象限默认值；日历为无）。
    let presetPriority: TaskPriority
    let requestClose: () -> Void

    @State private var title = ""
    @State private var listName = TaskList.inbox.name
    @State private var schedule: TaskSchedule
    /// 用户是否对日期做过决定。原版用它区分"页面给的日期"和"用户清空了日期"：
    /// 两者都不能再被 fallback 覆盖。
    @State private var overridden: Bool
    @State private var priority: TaskPriority
    @State private var reminder: Date?
    /// 面板里的多级提醒（0 = 准时，负数 = 提前多少分钟）。
    @State private var reminderOffsets: [Int] = []
    @State private var frequency: TaskRepeat = .never
    @State private var recurrenceRule: RecurrenceRule?
    @State private var datePage: TaskDatePopoverV2.Page?
    @FocusState private var titleFocused: Bool

    init(workspace: TaskWorkspaceModel,
         fallbackSchedule: TaskSchedule,
         presetSchedule: TaskSchedule?,
         presetPriority: TaskPriority,
         requestClose: @escaping () -> Void) {
        self.workspace = workspace
        self.fallbackSchedule = fallbackSchedule
        self.presetSchedule = presetSchedule
        self.presetPriority = presetPriority
        self.requestClose = requestClose
        _schedule = State(initialValue: presetSchedule ?? TaskSchedule())
        _overridden = State(initialValue: presetSchedule?.dueAt != nil)
        _priority = State(initialValue: presetPriority)
    }

    var body: some View {
        VStack(spacing: 0) {
            scheduleRow
            divider
            titleField
            divider
            listRow
        }
        .background(WFColors.overlay)
        .schedulePopover(isPresented: datePopoverBinding) {
            if let page = datePage {
                TaskDatePopoverV2(task: draftTask, workspace: workspace, initialPage: page,
                                  draftCommit: applyPlan) {
                    datePage = nil
                }
                .environment(\.calendar, workspace.calendar)
                .environment(\.timeZone, workspace.calendar.timeZone)
            }
        }
        .onAppear { titleFocused = true }
    }

    // MARK: 三行

    /// 第一行：日期胶囊（左）与优先级旗标（右），高 42、左右内边距 12。
    private var scheduleRow: some View {
        HStack(spacing: 0) {
            Button {
                datePage = .main
            } label: {
                HStack(spacing: WFSpace.sm) {
                    Image(systemName: "calendar")
                        .font(.system(size: 20))
                        .foregroundStyle(WFColors.overlaySecondaryText)
                    Text(scheduleLabel)
                        .font(.system(size: 14))
                        .foregroundStyle(schedule.dueAt == nil
                                         ? WFColors.overlayTertiaryText
                                         : WFColors.accent)
                }
                .padding(.horizontal, WFSpace.xs)
                .padding(.vertical, WFSpace.inline)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("设置日期")
            .scheduleTrigger()
            .accessibilityLabel("设置日期：\(scheduleLabel)")

            Spacer(minLength: 0)

            Menu {
                priorityItems
            } label: {
                Image(systemName: "flag")
                    .font(.system(size: 20))
                    .foregroundStyle(priorityColor)
                    .frame(width: WFCalendarMetrics.chipHeight, height: WFCalendarMetrics.chipHeight)
                    .contentShape(Rectangle())
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()
            .help("设置优先级")
            .accessibilityLabel("优先级：\(Self.priorityTitle(priority))")
        }
        .padding(.horizontal, WFSpace.md)
        .frame(height: WFPlanningOverlayMetrics.composerRowHeight)
    }

    /// 第二行：标题输入，高 126。原版是 4 行的输入框但回车即提交，所以这里是
    /// 单行输入铺在 126 高的槽位里，文字贴左上。
    private var titleField: some View {
        TextField("", text: $title, prompt: Text("准备做什么？")
            .foregroundStyle(WFColors.overlayTertiaryText))
            .textFieldStyle(.plain)
            .font(.system(size: 18))
            .foregroundStyle(WFColors.overlayText)
            .focused($titleFocused)
            .onSubmit(submit)
            .padding(.horizontal, WFSpace.lg)
            .padding(.vertical, WFSpace.relaxed)
            .frame(height: WFPlanningOverlayMetrics.composerBodyHeight, alignment: .topLeading)
            .accessibilityLabel("任务标题")
    }

    /// 第三行：清单胶囊（左）与更多（右），高 42、左右内边距 10。
    private var listRow: some View {
        HStack(spacing: 0) {
            Menu {
                ForEach(workspace.allListNames, id: \.self) { name in
                    Button {
                        listName = name
                    } label: {
                        if name == listName {
                            Label(name, systemImage: "checkmark")
                        } else {
                            Text(name)
                        }
                    }
                }
            } label: {
                HStack(spacing: WFSpace.sm) {
                    Image(systemName: "tray")
                        .font(.system(size: 20))
                        .foregroundStyle(WFColors.overlaySecondaryText)
                    Text(listName)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(WFColors.overlayText)
                }
                .padding(.horizontal, WFSpace.xs)
                .padding(.vertical, WFSpace.inline)
                .contentShape(Rectangle())
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()
            .help("移动到清单")
            .accessibilityLabel("清单：\(listName)")

            Spacer(minLength: 0)

            // 原版的「更多属性」只有提醒与重复两项，都是接着打开同一个日程面板的
            // 对应页（`_openMore` → `_pickReminder` / `_pickRepeat`）。
            Menu {
                Button("提醒") { datePage = .reminder }
                Button("重复") { datePage = .recurrence }
            } label: {
                Image(systemName: "ellipsis")
                    .font(.system(size: 20))
                    .foregroundStyle(WFColors.overlaySecondaryText)
                    .frame(width: WFCalendarMetrics.chipHeight, height: WFCalendarMetrics.chipHeight)
                    .contentShape(Rectangle())
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()
            .help("更多属性")
            .accessibilityLabel("更多属性")
        }
        .padding(.horizontal, WFSpace.cardInset)
        .frame(height: WFPlanningOverlayMetrics.composerRowHeight)
    }

    private var divider: some View {
        Rectangle()
            .fill(WFColors.border)
            .frame(height: WFMetrics.divider)
    }

    @ViewBuilder
    private var priorityItems: some View {
        ForEach([TaskPriority.none, .low, .medium, .high], id: \.self) { value in
            Button {
                priority = value
            } label: {
                if value == priority {
                    Label(Self.priorityTitle(value), systemImage: "checkmark")
                } else {
                    Text(Self.priorityTitle(value))
                }
            }
        }
    }

    // MARK: 草稿与提交

    /// 面板要在一个真实 `Task` 上工作（它按任务算重复与提醒），新建卡还没有任务，
    /// 所以照原版 `_scheduleTask()` 的做法现拼一个只用于展示的草稿任务。
    private var draftTask: Task {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let now = workspace.clock()
        return Task(id: Self.draftTaskID,
                    title: trimmed.isEmpty ? "准备做什么?" : trimmed,
                    recurrenceRule: recurrenceRule,
                    reminderAt: reminder,
                    reminderOffsets: reminderOffsets.isEmpty ? nil : reminderOffsets,
                    list: TaskList(name: listName),
                    priority: priority,
                    schedule: overridden ? schedule : fallbackSchedule,
                    parentID: nil,
                    childOrder: 0,
                    createdAt: now,
                    updatedAt: now)
    }

    private static let draftTaskID = UUID(uuidString: "00000000-0000-0000-0000-00000000ADD1")!

    private var scheduleLabel: String {
        guard overridden, let due = schedule.dueAt else { return "设置日期" }
        return TaskDateLabel.text(due, hasTime: schedule.hasTime,
                                  now: workspace.clock(), calendar: workspace.calendar)
    }

    /// 面板确定后把计划带回草稿：日程、提醒（单点 + 多级偏移）、重复一并保留，
    /// 提交时原样写进任务。
    private func applyPlan(_ plan: TaskDateDraftModel.CommitPlan) {
        schedule = plan.schedule
        overridden = true
        reminder = plan.reminder
        reminderOffsets = plan.reminderOffsets
        frequency = plan.frequency
        recurrenceRule = plan.recurrenceRule
    }

    private var datePopoverBinding: Binding<Bool> {
        Binding(get: { datePage != nil }, set: { if !$0 { datePage = nil } })
    }

    /// 回车提交：标题为空不创建（同原版 `_submit`）。
    private func submit() {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        workspace.createDraft(title: trimmed,
                              list: listName,
                              schedule: overridden ? schedule : fallbackSchedule,
                              priority: priority,
                              tags: [],
                              reminder: reminder,
                              reminderOffsets: reminderOffsets.isEmpty ? nil : reminderOffsets,
                              repeatFrequency: frequency,
                              recurrenceRule: recurrenceRule)
        requestClose()
    }

    private var priorityColor: Color {
        switch priority {
        case .high: WFColors.danger
        case .medium: WFColors.warning
        case .low: WFColors.accent
        case .none: WFColors.overlayTertiaryText
        }
    }

    static func priorityTitle(_ value: TaskPriority) -> String {
        switch value {
        case .none: "无优先级"
        case .low: "低优先级"
        case .medium: "中优先级"
        case .high: "高优先级"
        }
    }
}
