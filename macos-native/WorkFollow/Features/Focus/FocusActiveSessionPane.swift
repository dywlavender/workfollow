import SwiftUI

/// 正在专注与已保存的完成记录共用右栏时间轴，笔记始终写回当前展示的那条记录。
struct FocusActiveSessionPane: View {
    @ObservedObject var store: FocusStore
    var workspace: TaskWorkspaceModel? = nil
    var onAssociate: (() -> Void)? = nil
    @Environment(\.colorScheme) private var colorScheme
    @State private var recordDraft: FocusRecordDraft?

    private var theme: FocusTheme { FocusTheme(colorScheme) }
    private var isCompleted: Bool { store.completionContext != nil }
    private var displayedPreset: FocusStore.TimerPreset? {
        let id = isCompleted ? store.completedRecord?.details?.presetID : store.currentSessionPresetID
        guard let id else { return nil }
        return store.timers.first { $0.id == id }
    }
    private var note: String { isCompleted ? store.completedSessionNote : store.currentSessionNote }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            sessionHeader.frame(height: FocusLayoutMetrics.timelineHeaderHeight)

            FocusTimelineView(store: store, theme: theme)
                .padding(.top, isCompleted ? FocusLayoutMetrics.completionTimelineHeaderGap
                         : FocusLayoutMetrics.timelineTopPadding)

            VStack(alignment: .leading, spacing: 8) {
                Text("专注笔记")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(theme.text)
                    .focusRenderAnchor(.activeFocusNoteHeader)

                ZStack(alignment: .topLeading) {
                    if note.isEmpty {
                        Text("记录你的想法...")
                            .font(.system(size: 14))
                            .foregroundStyle(theme.text3)
                            .padding(.horizontal, 9).padding(.top, 8)
                            .allowsHitTesting(false)
                    }
                    TextEditor(text: Binding(get: { note }, set: {
                        if isCompleted { store.updateCompletedSessionNote($0) }
                        else { store.updateCurrentSessionNote($0) }
                    }))
                    .font(.system(size: 14)).foregroundStyle(theme.text)
                    .scrollContentBackground(.hidden).background(.clear)
                    .accessibilityIdentifier(isCompleted ? "focus-completed-note-editor" : "focus-session-note-editor")
                }
                .frame(height: isCompleted ? FocusLayoutMetrics.completionNoteHeight : FocusLayoutMetrics.focusNoteHeight)
                .background(theme.chipBackground,
                            in: RoundedRectangle(cornerRadius: FocusLayoutMetrics.focusNoteRadius))
                .overlay(RoundedRectangle(cornerRadius: FocusLayoutMetrics.focusNoteRadius)
                    .stroke(theme.hairline, lineWidth: 1))
                .focusRenderAnchor(.activeFocusNote)
            }
            .padding(.top, isCompleted ? FocusLayoutMetrics.completionNoteTopGap : FocusLayoutMetrics.focusNoteTopGap)

            Spacer(minLength: 0)
        }
        .padding(.horizontal, isCompleted ? FocusLayoutMetrics.completionTimelineHorizontalPadding
                 : FocusLayoutMetrics.timelineHorizontalPadding)
        .padding(.top, isCompleted ? FocusLayoutMetrics.completionTimelineTop : FocusLayoutMetrics.timelineTopPadding)
        .padding(.bottom, FocusLayoutMetrics.timelineHorizontalPadding)
        .frame(minWidth: FocusLayoutMetrics.overviewPaneMinWidth, maxWidth: .infinity,
               maxHeight: .infinity, alignment: .topLeading)
        .background(theme.canvas)
        .onAppear { if isCompleted { store.prepareCompletedSessionNote() } }
        .onChange(of: store.completionContext?.recordID) { _, _ in store.prepareCompletedSessionNote() }
        .sheet(item: $recordDraft) { value in
            FocusRecordEditor(store: store, workspace: workspace, draft: value)
        }
    }

    private var sessionHeader: some View {
        HStack(spacing: 8) {
            if let preset = displayedPreset {
                Text(preset.emoji).font(.system(size: 18))
                    .frame(width: 30, height: 30).background(theme.avatarBackground, in: Circle())
                Text(preset.name)
                    .font(.system(size: isCompleted ? 14 : 18, weight: .semibold))
                    .foregroundStyle(theme.text).lineLimit(1)
            } else {
                FocusTomatoIcon(color: theme.accent).focusRenderAnchor(.activeSessionTomatoIcon)
                Text(sessionTitle).font(.system(size: 18, weight: .semibold)).foregroundStyle(theme.text)
            }
            Spacer()
            Button {
                if isCompleted, let record = store.completedRecord { recordDraft = FocusRecordDraft(record: record) }
                else { onAssociate?() }
            } label: {
                Image(systemName: "link").font(.system(size: 16, weight: .medium)).foregroundStyle(theme.text2)
            }
            .buttonStyle(.plain).help("任务关联")
            .accessibilityIdentifier(isCompleted ? "focus-completed-edit-record" : "focus-session-associate")
        }
    }

    private var sessionTitle: String {
        if isCompleted, let record = store.completedRecord {
            if let taskID = record.taskID, let task = workspace?.task(for: taskID) { return task.title }
            return record.mode.title
        }
        if let taskID = store.currentTaskID, let task = workspace?.task(for: taskID) { return task.title }
        return store.phase == .idle ? store.presentation.mode.title : store.currentMode.title
    }
}
