import AppKit
import SwiftUI

/// 摘要工作区（对齐滴答“摘要”概念）：默认进入“周回顾”——从任务数据自动
/// 生成本周 已完成 / 已放弃 / 未完成 清单，并保留一段可编辑的“本周小结”
/// （防抖保存进 SummaryStore，dayKey 用本周一日期，与手记复用同一存储）。
/// 原有的每日手记模式原样保留，可在左栏分段控件中切换。
///
/// `init(store:)` 保持原签名供壳层使用；此时没有任务数据，周回顾主栏显示
/// 接入提示。`init(store:workspace:)` 供主线注入任务数据。
struct SummaryWorkspaceView: View {
    @ObservedObject var store: SummaryStore
    let workspace: TaskWorkspaceModel?

    private enum Mode: Hashable { case weekly, journal }

    @State private var mode: Mode = .weekly
    // 周回顾
    @State private var selectedWeekStart = SummaryReviewBuilder.weekStart(of: Date(), calendar: .current)
    @State private var weeklyDraft = ""
    @State private var weeklySaveTask: _Concurrency.Task<Void, Never>?
    @State private var copied = false
    @State private var copyResetTask: _Concurrency.Task<Void, Never>?
    // 手记（每日一篇）
    @State private var monthAnchor = Date()
    @State private var selectedDayKey = SummaryStore.dayKey(Date(), calendar: .current)
    @State private var draft = ""
    @State private var saveTask: _Concurrency.Task<Void, Never>?
    @State private var saveError: String?
    @State private var narrowShowsList = false

    private static let prompts = [
        "今天最有成就感的一件事",
        "明天最重要的一件事",
        "今天学到的最重要的一点",
        "今天遇到的挑战与解决思路",
        "值得记住的一个瞬间",
        "明天想做出的一个改变",
    ]
    private static let weekdayNames = ["日", "一", "二", "三", "四", "五", "六"]
    private var calendar: Calendar { workspace?.calendar ?? .current }

    init(store: SummaryStore) {
        self.init(store: store, workspace: nil)
    }

    init(store: SummaryStore, workspace: TaskWorkspaceModel?) {
        self.store = store
        self.workspace = workspace
    }

    /// Review builder wired to the injected task workspace when available.
    private var reviewBuilder: SummaryReviewBuilder {
        SummaryReviewBuilder(clock: workspace?.clock ?? Date.init, calendar: calendar)
    }

    private func weeklyDayKey(_ weekStart: Date) -> String {
        SummaryStore.dayKey(weekStart, calendar: calendar)
    }

    var body: some View {
        GeometryReader { geometry in
            let narrow = geometry.size.width < 640
            let showList = !narrow || narrowShowsList
            let showEditor = !narrow || !narrowShowsList
            HStack(spacing: 0) {
                if showList {
                    leftColumn(narrow: narrow)
                        .frame(width: 280)
                    if showEditor { Divider() }
                }
                if showEditor {
                    mainColumn(narrow: narrow)
                }
            }
        }
        .background(WFColors.content)
        .onAppear { loadDraft(); loadWeeklyDraft() }
        .onDisappear {
            finishPendingSave()
            finishWeeklySave()
            copyResetTask?.cancel()
        }
        .onChange(of: mode) { _, _ in
            finishPendingSave()
            finishWeeklySave()
            saveError = nil
        }
        .onChange(of: selectedDayKey) { oldKey, _ in
            // Keep the outgoing day's pending edit before switching.
            finishPendingSave(dayKey: oldKey)
            saveError = nil
            loadDraft()
        }
        .onChange(of: draft) { _, _ in scheduleSave() }
        .onChange(of: selectedWeekStart) { oldStart, _ in
            finishWeeklySave(weekStart: oldStart)
            saveError = nil
            loadWeeklyDraft()
        }
        .onChange(of: weeklyDraft) { _, _ in scheduleWeeklySave() }
    }

    // MARK: Left column

    private func leftColumn(narrow: Bool) -> some View {
        VStack(alignment: .leading, spacing: WFSpace.md) {
            Text("摘要").font(WFType.pageTitle)
            Picker("视角", selection: $mode) {
                Text("周回顾").tag(Mode.weekly)
                Text("手记").tag(Mode.journal)
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            if mode == .weekly {
                weekList(dismissList: narrow)
            } else {
                dayList(dismissList: narrow)
            }
        }
        .padding(WFSpace.xl)
    }

    // MARK: Weekly review list

    private func weekList(dismissList: Bool) -> some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: WFSpace.xs) {
                let weeks = reviewBuilder.availableWeeks(for: workspace?.allTasks ?? [])
                ForEach(weeks, id: \.weekStart) { week in
                    weekRow(week, dismissList: dismissList)
                }
            }
        }
    }

    private func weekRow(_ week: WeeklyReviewSummary, dismissList: Bool) -> some View {
        Button {
            selectedWeekStart = week.weekStart
            if dismissList { narrowShowsList = false }
        } label: {
            VStack(alignment: .leading, spacing: WFSpace.xs) {
                Text(week.isCurrent ? "本周（\(week.weekTitle)）" : week.weekTitle)
                    .font(WFType.listTitle)
                    .foregroundStyle(WFColors.text)
                Text(week.isCurrent && week.completedCount == 0 ? "暂无内容" : "已完成 \(week.completedCount) 条")
                    .font(WFType.supporting)
                    .foregroundStyle(WFColors.secondaryText)
                    .lineLimit(1)
            }
            .padding(WFSpace.md)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                selectedWeekStart == week.weekStart ? WFColors.selection : .clear,
                in: RoundedRectangle(cornerRadius: WFMetrics.corner)
            )
        }
        .buttonStyle(.plain)
    }

    // MARK: Weekly review pane

    private func weeklyPane(narrow: Bool) -> some View {
        let review = reviewBuilder.review(for: workspace?.allTasks ?? [], weekOf: selectedWeekStart)
        return VStack(alignment: .leading, spacing: WFSpace.md) {
            HStack(spacing: WFSpace.sm) {
                if narrow {
                    Button { narrowShowsList = true } label: { Image(systemName: "sidebar.left") }
                        .help("查看周列表")
                }
                Text(review.weekTitle).font(WFType.detailTitle)
                Spacer()
                if workspace != nil {
                    Button {
                        copyReview(review)
                    } label: {
                        Label(copied ? "已复制" : "复制",
                              systemImage: copied ? "checkmark" : "doc.on.doc")
                    }
                }
            }
            .buttonStyle(.borderless)
            ScrollView {
                VStack(alignment: .leading, spacing: WFSpace.xl) {
                    if workspace != nil {
                        reviewSection("已完成", items: review.completed, showsDatePrefix: true)
                        reviewSection("已放弃", items: review.abandoned, showsDatePrefix: true)
                        reviewSection("未完成", items: review.uncompleted, showsDatePrefix: false)
                        if review.isEmpty {
                            Text("本周还没有任务记录")
                                .font(WFType.supporting)
                                .foregroundStyle(WFColors.tertiaryText)
                        }
                    } else {
                        VStack(alignment: .leading, spacing: WFSpace.sm) {
                            Text("接入任务数据后可自动生成周回顾")
                                .font(WFType.body)
                                .foregroundStyle(WFColors.secondaryText)
                            Text("届时这里会按周汇总已完成、已放弃与未完成的任务；本周小结仍会照常保存。")
                                .font(WFType.supporting)
                                .foregroundStyle(WFColors.tertiaryText)
                        }
                    }
                    Divider()
                    weeklyNoteSection
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(WFSpace.xl)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    /// TickTick-style plain rows: gray date prefix + title, list name on the
    /// right. No cards — the pane stays a single white page.
    private func reviewSection(_ title: String, items: [ReviewItem], showsDatePrefix: Bool) -> some View {
        VStack(alignment: .leading, spacing: WFSpace.sm) {
            Text(title)
                .font(WFType.section)
                .foregroundStyle(WFColors.secondaryText)
            if items.isEmpty {
                Text("暂无")
                    .font(WFType.supporting)
                    .foregroundStyle(WFColors.tertiaryText)
            } else {
                ForEach(Array(items.enumerated()), id: \.offset) { _, item in
                    HStack(spacing: WFSpace.sm) {
                        if showsDatePrefix && !item.datePrefix.isEmpty {
                            Text(item.datePrefix)
                                .font(WFType.supporting)
                                .foregroundStyle(WFColors.secondaryText)
                        }
                        Text(item.title)
                            .font(WFType.body)
                            .foregroundStyle(WFColors.text)
                            .lineLimit(1)
                        Spacer(minLength: 0)
                        Text(item.listName)
                            .font(WFType.supporting)
                            .foregroundStyle(WFColors.secondaryText)
                            .lineLimit(1)
                    }
                }
            }
        }
    }

    /// 手写小结：与每日手记共用 SummaryStore，dayKey 为本周一日期。
    private var weeklyNoteSection: some View {
        let dayKey = weeklyDayKey(selectedWeekStart)
        return VStack(alignment: .leading, spacing: WFSpace.sm) {
            Text("本周小结")
                .font(WFType.section)
                .foregroundStyle(WFColors.secondaryText)
            ZStack(alignment: .topLeading) {
                TextEditor(text: $weeklyDraft)
                    .font(WFType.body)
                    .frame(minHeight: 120)
                if store.entry(for: dayKey) == nil && weeklyDraft.isEmpty {
                    Text("写几句本周的回顾与想法吧")
                        .font(WFType.body)
                        .foregroundStyle(WFColors.tertiaryText)
                        .padding(.top, WFSpace.sm)
                        .padding(.leading, WFSpace.xs)
                        .allowsHitTesting(false)
                }
            }
            .frame(height: 150)
            if let saveError {
                Label(saveError, systemImage: "exclamationmark.triangle.fill")
                    .font(WFType.supporting)
                    .foregroundStyle(.red)
            } else if let entry = store.entry(for: dayKey) {
                Text("已于 \(entry.updatedAt.formatted(date: .omitted, time: .shortened)) 保存")
                    .font(WFType.supporting)
                    .foregroundStyle(WFColors.secondaryText)
            }
        }
    }

    private func copyReview(_ review: WeeklyReview) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(reviewBuilder.plainText(for: review), forType: .string)
        copied = true
        copyResetTask?.cancel()
        copyResetTask = _Concurrency.Task {
            try? await _Concurrency.Task.sleep(for: .seconds(1.5))
            guard !_Concurrency.Task.isCancelled else { return }
            copied = false
        }
    }

    // MARK: Journal (每日手记, 原样保留)

    private func dayList(dismissList: Bool) -> some View {
        VStack(alignment: .leading, spacing: WFSpace.md) {
            HStack(spacing: WFSpace.sm) {
                Button {
                    moveMonth(-1)
                } label: { Image(systemName: "chevron.left") }
                    .help("上一个月")
                Text(monthTitle).font(WFType.section)
                Button {
                    moveMonth(1)
                } label: { Image(systemName: "chevron.right") }
                    .help("下一个月")
                Spacer()
                Button("回到今天") { goToday() }
            }
            .buttonStyle(.borderless)
            ScrollView {
                LazyVStack(alignment: .leading, spacing: WFSpace.xs) {
                    let days = store.entries(inMonth: monthAnchor, calendar: calendar)
                    if days.isEmpty {
                        Text("本月暂无摘要")
                            .font(WFType.supporting)
                            .foregroundStyle(WFColors.secondaryText)
                            .padding(.vertical, WFSpace.lg)
                    }
                    ForEach(days) { day in
                        dayRow(day, dismissList: dismissList)
                    }
                }
            }
        }
    }

    private func dayRow(_ day: DailySummary, dismissList: Bool) -> some View {
        Button {
            selectedDayKey = day.dayKey
            if dismissList { narrowShowsList = false }
        } label: {
            VStack(alignment: .leading, spacing: WFSpace.xs) {
                Text(dayTitle(day.dayKey))
                    .font(WFType.listTitle)
                    .foregroundStyle(WFColors.text)
                Text(firstLine(of: day.content))
                    .font(WFType.supporting)
                    .foregroundStyle(WFColors.secondaryText)
                    .lineLimit(1)
            }
            .padding(WFSpace.md)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                selectedDayKey == day.dayKey ? WFColors.selection : .clear,
                in: RoundedRectangle(cornerRadius: WFMetrics.corner)
            )
        }
        .buttonStyle(.plain)
    }

    private func editor(showsListButton: Bool) -> some View {
        VStack(alignment: .leading, spacing: WFSpace.md) {
            HStack(spacing: WFSpace.sm) {
                if showsListButton {
                    Button { narrowShowsList = true } label: { Image(systemName: "sidebar.left") }
                        .help("查看日期列表")
                }
                Text(dayTitle(selectedDayKey)).font(WFType.detailTitle)
            }
            .buttonStyle(.borderless)
            Text(prompt(for: selectedDayKey))
                .font(WFType.supporting)
                .foregroundStyle(WFColors.tertiaryText)
            ZStack(alignment: .topLeading) {
                TextEditor(text: $draft).font(WFType.body)
                if store.entry(for: selectedDayKey) == nil && draft.isEmpty {
                    Text("还没有摘要，写下这一天的记录吧")
                        .font(WFType.body)
                        .foregroundStyle(WFColors.tertiaryText)
                        .padding(.top, WFSpace.sm)
                        .padding(.leading, WFSpace.xs)
                        .allowsHitTesting(false)
                }
            }
            if let saveError {
                Label(saveError, systemImage: "exclamationmark.triangle.fill")
                    .font(WFType.supporting)
                    .foregroundStyle(.red)
            } else if let entry = store.entry(for: selectedDayKey) {
                Text("已于 \(entry.updatedAt.formatted(date: .omitted, time: .shortened)) 保存")
                    .font(WFType.supporting)
                    .foregroundStyle(WFColors.secondaryText)
            }
        }
        .padding(WFSpace.xl)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    // MARK: Main column switch

    @ViewBuilder
    private func mainColumn(narrow: Bool) -> some View {
        if mode == .weekly {
            weeklyPane(narrow: narrow)
        } else {
            editor(showsListButton: narrow)
        }
    }

    // MARK: Display helpers

    private var monthTitle: String {
        let parts = calendar.dateComponents([.year, .month], from: monthAnchor)
        return "\(parts.year ?? 0)年\(parts.month ?? 0)月"
    }

    private func dayTitle(_ dayKey: String) -> String {
        guard let date = SummaryStore.date(fromDayKey: dayKey, calendar: calendar) else { return dayKey }
        let parts = calendar.dateComponents([.month, .day, .weekday], from: date)
        let weekday = Self.weekdayNames[(parts.weekday ?? 1) - 1]
        return "\(parts.month ?? 0)月\(parts.day ?? 0)日 周\(weekday)"
    }

    private func firstLine(of content: String) -> String {
        content.components(separatedBy: .newlines).first ?? content
    }

    /// Fixed prompt pool rotated by the day of the selected date.
    private func prompt(for dayKey: String) -> String {
        guard let date = SummaryStore.date(fromDayKey: dayKey, calendar: calendar) else {
            return Self.prompts[0]
        }
        let index = (calendar.ordinality(of: .day, in: .year, for: date) ?? 0) % Self.prompts.count
        return Self.prompts[index]
    }

    // MARK: Navigation

    private func moveMonth(_ offset: Int) {
        monthAnchor = calendar.date(byAdding: .month, value: offset, to: monthAnchor) ?? monthAnchor
    }

    private func goToday() {
        monthAnchor = Date()
        selectedDayKey = SummaryStore.dayKey(Date(), calendar: calendar)
    }

    // MARK: Autosave (view-driven debounce; the store keeps no timers)

    private func loadDraft() {
        draft = store.entry(for: selectedDayKey)?.content ?? ""
    }

    private func loadWeeklyDraft() {
        weeklyDraft = store.entry(for: weeklyDayKey(selectedWeekStart))?.content ?? ""
    }

    private func scheduleSave() {
        let dayKey = selectedDayKey
        let content = draft
        saveTask?.cancel()
        saveTask = _Concurrency.Task {
            try? await _Concurrency.Task.sleep(for: .seconds(0.5))
            guard !_Concurrency.Task.isCancelled else { return }
            performSave(content: content, dayKey: dayKey)
        }
    }

    private func scheduleWeeklySave() {
        let dayKey = weeklyDayKey(selectedWeekStart)
        let content = weeklyDraft
        weeklySaveTask?.cancel()
        weeklySaveTask = _Concurrency.Task {
            try? await _Concurrency.Task.sleep(for: .seconds(0.5))
            guard !_Concurrency.Task.isCancelled else { return }
            performSave(content: content, dayKey: dayKey)
        }
    }

    /// Saves any pending edit immediately (day switch or view disappearing).
    private func finishPendingSave(dayKey: String? = nil) {
        let target = dayKey ?? selectedDayKey
        saveTask?.cancel()
        saveTask = nil
        performSave(content: draft, dayKey: target)
    }

    /// Saves any pending weekly note immediately (week switch, mode switch or
    /// view disappearing).
    private func finishWeeklySave(weekStart: Date? = nil) {
        let target = weeklyDayKey(weekStart ?? selectedWeekStart)
        weeklySaveTask?.cancel()
        weeklySaveTask = nil
        performSave(content: weeklyDraft, dayKey: target)
    }

    private func performSave(content: String, dayKey: String) {
        let trimmed = content.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            guard store.entry(for: dayKey) != nil else { return }
        } else if let existing = store.entry(for: dayKey), existing.content == trimmed {
            return  // Nothing changed; skip the redundant write and status refresh.
        }
        store.save(content: content, dayKey: dayKey)
        store.flush { error in
            _Concurrency.Task { @MainActor in
                saveError = error.map { "摘要保存失败：\($0.localizedDescription)" }
            }
        }
    }
}
