import SwiftUI

struct FocusRecordEditor: View {
    @ObservedObject var store: FocusStore
    let workspace: TaskWorkspaceModel?
    @State var draft: FocusRecordDraft
    @Environment(\.dismiss) private var dismiss
    @State private var error: String?
    @Environment(\.colorScheme) private var scheme
    private var theme: FocusTheme { FocusTheme(scheme) }

    var body: some View {
        VStack(spacing: 0) {
            DialogHeader(title: draft.isNew ? "补记专注" : "编辑专注记录")
            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    fieldRow("专注任务") {
                        BusinessPicker("关联任务", selection: $draft.taskID, options:
                            [BusinessChoice(nil, "不关联")] + candidates.map { task in
                                BusinessChoice(Optional(task.id), task.title.isEmpty ? "未命名任务" : task.title, symbol: "checklist")
                            }, width: PopupMetrics.relationPickerWidth).labelsHidden().accessibilityIdentifier("focus-record-task")
                    }
                    fieldRow("开始时间") {
                        DatePicker("开始", selection: $draft.startedAt, displayedComponents: [.date, .hourAndMinute])
                            .labelsHidden().datePickerStyle(.field)
                            .accessibilityIdentifier("focus-record-start")
                    }
                    fieldRow("结束时间") {
                        if draft.preservesLegacyTiming {
                            Text("未记录").foregroundStyle(theme.text3)
                        } else {
                            DatePicker("结束", selection: $draft.endedAt, in: ...store.currentTime,
                                displayedComponents: [.date, .hourAndMinute])
                                .labelsHidden().datePickerStyle(.field).accessibilityIdentifier("focus-record-end")
                        }
                    }
                    fieldRow("类型") {
                        HStack(spacing: 6) {
                            BusinessPicker("类型", selection: $draft.mode, options:
                                [BusinessChoice(FocusMode.pomodoro, "番茄计时"), BusinessChoice(.stopwatch, "正计时")]
                                + (draft.preservesLegacyTiming ? [BusinessChoice(.legacy, "历史专注")] : [])).labelsHidden().disabled(draft.preservesLegacyTiming)
                                .accessibilityIdentifier("focus-record-mode")
                            if draft.mode == .pomodoro {
                                TextField("0", value: $draft.creditedPomodoros, format: .number)
                                    .frame(width: 38).multilineTextAlignment(.center)
                                    .accessibilityIdentifier("focus-record-pomodoros")
                                Text("个番茄").font(.caption).foregroundStyle(theme.text2)
                            }
                        }
                    }
                    if draft.preservesLegacyTiming {
                        Stepper("时长 \(draft.durationMinutes) 分钟", value: $draft.durationMinutes, in: 1...1440)
                            .font(.caption).accessibilityIdentifier("focus-record-legacy-duration")
                    }
                    Text("专注笔记").font(.system(size: 13)).foregroundStyle(theme.text2)
                    TextEditor(text: $draft.note)
                        .font(.system(size: 13)).scrollContentBackground(.hidden).padding(6)
                        .frame(maxWidth: .infinity, minHeight: 68)
                        .background(theme.chipBackground, in: RoundedRectangle(cornerRadius: 6))
                        .overlay(RoundedRectangle(cornerRadius: 6).stroke(theme.hairline, lineWidth: 1))
                        .accessibilityIdentifier("focus-record-note")
                }.padding(PopupMetrics.formInset)
            }
            DialogFooter(cancelIdentifier: "focus-record-cancel", primaryIdentifier: "focus-record-save",
                         onCancel: { dismiss() }, onSubmit: {
                if store.saveRecordDraft(draft) { dismiss() }
                else { error = "开始应早于结束，结束应在此刻之前，番茄数不能为负。" }
            }) { Text(error ?? "").foregroundStyle(theme.warn) }
        }
        .frame(width: FocusLayoutMetrics.recordEditorWidth, height: FocusLayoutMetrics.recordEditorHeight)
        .background(theme.canvas).focusRenderAnchor(.recordEditor)
        .environment(\.calendar, store.presentationCalendar)
        .environment(\.timeZone, store.presentationCalendar.timeZone)
    }
    private func fieldRow<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        HStack(spacing: 10) {
            Text(title).font(.system(size: 13)).foregroundStyle(theme.text2).frame(width: 66, alignment: .leading)
            content().frame(maxWidth: .infinity, alignment: .leading)
        }.frame(minHeight: 26)
    }
    private var candidates: [Task] {
        (workspace?.allTasks ?? []).filter { !$0.isNoteTask && $0.deletedAt == nil && !$0.isAbandoned }
    }
}

struct FocusRecordDetail: View {
    @ObservedObject var store: FocusStore
    let recordID: UUID
    let workspace: TaskWorkspaceModel?
    let onSelectTask: ((UUID) -> Void)?
    @Environment(\.dismiss) private var dismiss
    @State private var draft: FocusRecordDraft?
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        let theme = FocusTheme(scheme)
        VStack(alignment: .leading, spacing: 18) {
            if let record = store.record(id: recordID) {
                HStack {
                    Text("专注记录").font(.title3.weight(.semibold))
                    Spacer()
                    Button("关闭") { dismiss() }.keyboardShortcut(.cancelAction)
                }
                Label(record.mode.title, systemImage: record.mode == .stopwatch ? "stopwatch" : "timer")
                    .font(.headline)
                Text(duration(record.activeSeconds)).font(.system(size: 36)).monospacedDigit()
                Text(FocusViewLogic.dateTimeLabel(for: record.startedAt, calendar: store.presentationCalendar))
                    .foregroundStyle(theme.text2)
                if let end = record.endedAt {
                    Text("结束 \(FocusViewLogic.dateTimeLabel(for: end, calendar: store.presentationCalendar))")
                        .foregroundStyle(theme.text2)
                } else { Text("结束时间未记录").foregroundStyle(theme.text3) }
                if let taskID = record.taskID {
                    Button {
                        onSelectTask?(taskID); dismiss()
                    } label: { Label(workspace?.task(for: taskID)?.title ?? "关联任务", systemImage: "link") }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("focus-record-open-task")
                } else { Text("未关联任务").foregroundStyle(theme.text3) }
                if let details = record.details, details.pausedSeconds > 0 {
                    Text("暂停 \(duration(details.pausedSeconds)) · \(details.pauseRanges.count) 段")
                        .font(.caption).foregroundStyle(theme.text2)
                }
                Divider()
                Text("专注笔记").font(.headline)
                ScrollView { Text(record.note ?? "暂无笔记").frame(maxWidth: .infinity, alignment: .leading) }
                    .frame(minHeight: 60, maxHeight: 180)
                HStack {
                    Button("删除记录", role: .destructive) { store.deleteRecord(recordID); dismiss() }
                    Spacer()
                    Button("编辑") { draft = FocusRecordDraft(record: record) }
                        .accessibilityIdentifier("focus-record-edit")
                }
            } else { Text("记录已删除"); Button("关闭") { dismiss() } }
        }
        .padding(24).frame(width: PopupMetrics.focusRecordWidth).background(theme.canvas)
        .focusRenderAnchor(.recordDetail)
        .sheet(item: $draft) { value in FocusRecordEditor(store: store, workspace: workspace, draft: value) }
    }
    private func duration(_ seconds: Int) -> String {
        seconds < 3600 ? "\(seconds / 60) 分 \(seconds % 60) 秒" : "\(seconds / 3600) 小时 \((seconds % 3600) / 60) 分"
    }
}
