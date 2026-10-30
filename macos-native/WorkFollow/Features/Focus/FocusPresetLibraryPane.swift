import SwiftUI

/// 选中只浏览详情，独立播放按钮才启动；底部始终展示共享会话。
struct FocusPresetLibraryPane: View {
    @ObservedObject var store: FocusStore
    let workspace: TaskWorkspaceModel?
    let onAddTimer: () -> Void
    @Environment(\.colorScheme) private var scheme
    @State private var editingPreset: FocusStore.TimerPreset?
    @State private var recordDraft: FocusRecordDraft?
    @State private var archivingPreset: FocusStore.TimerPreset?
    private var theme: FocusTheme { FocusTheme(scheme) }
    private var presets: [FocusStore.TimerPreset] {
        store.presetLibrarySection == .active ? store.activeTimers : store.archivedTimers
    }

    var body: some View {
        VStack(spacing: 0) {
            libraryHeader
            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(Array(presets.enumerated()), id: \.element.id) { index, preset in
                        if index == 0 { presetRow(preset).focusRenderAnchor(.presetLibraryFirstRow) }
                        else { presetRow(preset) }
                    }
                    if presets.isEmpty {
                        Text(store.presetLibrarySection == .archived ? "暂无已归档的专注" : "点击 + 添加常用专注")
                            .font(.system(size: 13)).foregroundStyle(theme.text3)
                            .frame(maxWidth: .infinity).padding(.top, 45)
                    }
                }.padding(.horizontal, FocusLayoutMetrics.libraryListInset).padding(.top, 6)
            }
            compactTimerBar
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .focusRenderAnchor(.presetLibrary)
        .sheet(item: $editingPreset) { FocusPresetEditor(store: store, workspace: workspace, preset: $0) }
        .sheet(item: $recordDraft) { FocusRecordEditor(store: store, workspace: workspace, draft: $0) }
        .focusPresetArchiveConfirmation(store: store, preset: $archivingPreset)
    }

    private var libraryHeader: some View {
        ZStack {
            HStack(spacing: 6) {
                Text("番茄专注").font(.system(size: 18, weight: .semibold)).foregroundStyle(theme.text)
                Spacer()
                Button(action: onAddTimer) {
                    Image(systemName: "plus").font(.system(size: 17)).frame(width: 28, height: 28)
                }.buttonStyle(.plain).hoverTip("添加常用专注")
                    .accessibilityIdentifier("focus-library-add-preset")
                BusinessMenu {
                    Button("概览") { store.showLibraryOverview() }
                    Button("专注记录") { store.showRecords() }
                    Button("专注统计") { store.showStatistics() }
                    Divider()
                    Button("Mini 专注") { FocusPresentationWindows.showMini(store: store) }
                    Button("沉浸专注") { FocusPresentationWindows.showImmersive(store: store) }
                } label: {
                    Image(systemName: "ellipsis").font(.system(size: 16)).frame(width: 24, height: 28)
                }.fixedSize()
                    .hoverTip("更多专注操作")
                    .accessibilityIdentifier("focus-library-menu")
            }
            HStack(spacing: 2) {
                ForEach(FocusPresetLibrarySection.allCases, id: \.self) { section in
                    Button { store.setPresetLibrarySection(section) } label: {
                        Text(section.title).font(.system(size: 13, weight: section == store.presetLibrarySection ? .medium : .regular))
                            .foregroundStyle(section == store.presetLibrarySection ? theme.text : theme.text2)
                            .frame(width: 58, height: 26)
                            .background(section == store.presetLibrarySection ? theme.segmentActive : .clear, in: Capsule())
                    }.buttonStyle(.plain)
                        .accessibilityIdentifier("focus-library-section-\(section.rawValue)")
                }
            }.padding(3).background(theme.chipBackground, in: Capsule())
        }
        .padding(.horizontal, 20).frame(height: FocusLayoutMetrics.libraryHeaderHeight)
        .foregroundStyle(theme.text2)
    }

    private func presetRow(_ preset: FocusStore.TimerPreset) -> some View {
        HStack(spacing: 0) {
            Button { store.selectPresetForDetails(preset.id) } label: {
                HStack(spacing: 12) {
                    Text(preset.emoji).font(.system(size: 19))
                        .frame(width: FocusLayoutMetrics.libraryAvatarSize, height: FocusLayoutMetrics.libraryAvatarSize)
                        .background(theme.avatarBackground, in: Circle())
                    Text(preset.name).font(.system(size: 13, weight: .medium)).foregroundStyle(theme.text).lineLimit(1)
                    Spacer(minLength: 8)
                    if preset.archivedAt == nil {
                        Text(preset.stopwatch ? "正计时" : "\(preset.minutes)m")
                            .font(.system(size: 13)).foregroundStyle(theme.text3)
                    }
                }
                .contentShape(Rectangle()).frame(maxWidth: .infinity, maxHeight: .infinity)
            }.buttonStyle(.plain).accessibilityIdentifier("focus-library-select-\(preset.id.uuidString)")
            if preset.archivedAt == nil {
                Button { _ = store.startTimerPreset(preset.id) } label: {
                    Image(systemName: "play.fill").font(.system(size: 13)).frame(width: 28, height: 36)
                }
                .buttonStyle(.plain).foregroundStyle(theme.accent).disabled(!store.canStartTimerPreset)
                .hoverTip(store.canStartTimerPreset ? "开始此专注" : "当前会话尚未结束")
                .accessibilityIdentifier("focus-library-play-\(preset.id.uuidString)")
            }
        }
        .padding(.horizontal, 10).frame(height: FocusLayoutMetrics.libraryRowHeight)
        .rowHoverBackground(selected: store.browsedPresetID == preset.id,
                            cornerRadius: 13,
                            selectedFill: theme.chipBackground,
                            hoverFill: theme.chipBackground.opacity(0.55))
        .businessContextMenu {
            if preset.archivedAt == nil {
                Button("编辑") { editingPreset = preset }
                Button("添加记录") { addRecord(for: preset) }
                Button("归档") { archivingPreset = preset }
            } else {
                Button("恢复") { _ = store.restoreTimer(preset.id) }.disabled(store.activeTimers.count >= 12)
            }
            Button("删除", role: .destructive) { store.deleteTimer(preset.id) }
        }
    }

    private var compactTimerBar: some View {
        HStack(spacing: 10) {
            Button { store.showTimerWorkspace() } label: {
                HStack(spacing: 12) {
                    if store.presentation.mode == .stopwatch {
                        Image(systemName: "stopwatch.fill").font(.system(size: 22)).foregroundStyle(theme.accent)
                            .frame(width: 30)
                    } else {
                        FocusTomatoIcon(color: theme.accent).frame(width: 30)
                    }
                    VStack(alignment: .leading, spacing: 1) {
                        Text(compactTitle).font(.system(size: 12)).foregroundStyle(theme.text3).lineLimit(1)
                        Text(FocusViewLogic.clockText(store.presentation.displaySeconds))
                            .font(.system(size: 21)).monospacedDigit().foregroundStyle(theme.text)
                    }
                    Spacer(minLength: 0)
                }.contentShape(Rectangle())
            }.buttonStyle(.plain).help("展开计时页")
                .accessibilityIdentifier("focus-library-expand-timer")
            Button { if let action = primaryAction { _ = store.perform(action) } } label: {
                Image(systemName: primaryAction == .pause ? "pause.fill" : "play.fill")
                    .font(.system(size: 17)).foregroundStyle(theme.accent)
                    .frame(width: 36, height: 36).background(theme.accent.opacity(0.10), in: Circle())
            }.buttonStyle(.plain).hoverTip(primaryAction?.title ?? "开始", placement: .above)
                .accessibilityIdentifier("focus-library-timer-primary")
        }
        .padding(.horizontal, 20).frame(height: FocusLayoutMetrics.libraryTimerBarHeight)
        .overlay(alignment: .top) { Rectangle().fill(theme.hairline).frame(height: 1) }
        .focusRenderAnchor(.presetLibraryTimerBar)
    }

    private var primaryAction: FocusCommand? { store.presentation.availableActions.first }
    private var compactTitle: String {
        if let id = store.currentSessionPresetID ?? store.completedRecord?.details?.presetID,
           let preset = store.timers.first(where: { $0.id == id }) { return preset.name }
        if let id = store.currentTaskID, let task = workspace?.task(for: id) { return task.title }
        if store.phase == .idle && store.completionContext == nil { return "准备做什么？" }
        return store.presentation.phaseTitle
    }
    private func addRecord(for preset: FocusStore.TimerPreset) {
        var draft = FocusRecordDraft(now: store.currentTime, taskID: preset.taskID,
                                    mode: preset.stopwatch ? .stopwatch : .pomodoro, presetID: preset.id)
        if !preset.stopwatch {
            draft.startedAt = draft.endedAt.addingTimeInterval(TimeInterval(-preset.minutes * 60))
            draft.durationMinutes = preset.minutes
        }
        recordDraft = draft
    }
}

extension View {
    func focusPresetArchiveConfirmation(store: FocusStore,
                                        preset: Binding<FocusStore.TimerPreset?>) -> some View {
        alert("归档常用专注", isPresented: Binding(get: { preset.wrappedValue != nil },
                                              set: { if !$0 { preset.wrappedValue = nil } }),
              presenting: preset.wrappedValue) { value in
            Button("取消", role: .cancel) {}
            Button("归档") { store.archiveTimer(value.id) }
                .accessibilityIdentifier("focus-preset-archive-confirm")
        } message: { _ in
            Text("归档后将无法进行专注，是否确认归档？")
        }
    }
}
