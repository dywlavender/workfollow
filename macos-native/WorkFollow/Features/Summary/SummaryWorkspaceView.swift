import AppKit
import SwiftUI

/// 摘要只负责回顾与产出；计划动作在日历周视图里完成，这里不再提供计划页。
/// Saved reports are snapshots; changing tasks or filters never silently replaces an edited document.
struct SummaryWorkspaceView: View {
    @ObservedObject var store: SummaryStore
    @ObservedObject var workspace: TaskWorkspaceModel
    @ObservedObject var context: WeeklyPlanningContext
    @EnvironmentObject private var environment: AppEnvironment
    @Environment(\.openSettings) private var openSettings
    @ObservedObject private var templateStore = TemplateStore.shared
    @State private var rangeOverride: SummaryDateRange?
    @State private var listOverride: Set<String>?
    @State private var focusRecords: [PomodoroRecord] = []
    @State private var focusedTaskIDs: Set<UUID> = []
    @State private var options = SummaryDocumentOptions.standard
    @State private var appliedOptions = SummaryDocumentOptions.standard
    @State private var aiEnabled = false
    @State private var aiOptions = SummaryAIOptions()
    @State private var showsConfiguration = false
    @State private var configurationDismissAction: (() -> Void)?
    @State private var showsSaveTemplate = false
    @State private var templateName = ""
    @StateObject private var editorHandle = DocumentEditorHandle()
    @State private var document = NativeDocument.empty
    @State private var editorID = UUID()
    @State private var loadedSelection: Selection?
    @State private var preview: DraftPreview?
    @State private var showsHistory = false
    @State private var showsSources = false
    @State private var selectedCarry: Set<UUID> = []
    @State private var aiRunning = false
    @State private var aiError: String?
    @State private var aiJob: _Concurrency.Task<Void, Never>?
    @State private var aiGeneration = UUID()
    @State private var selectedDraftSections: Set<Int> = []
    @State private var adoptedDocument: NativeDocument?
    @State private var adoptionAvailable = false
    @State private var copied = false
    @State private var copyFeedbackTask: _Concurrency.Task<Void, Never>?
    @State private var journalMode = false
    @State private var journalDay: Date
    @State private var journalText = ""
    @State private var loadedJournalKey: String?

    private struct Selection: Equatable {
        let weekKey: String
        let scopeID: String
        let listName: String?
        let listNames: Set<String>
        let range: SummaryDateRange
    }
    private struct DraftPreview: Identifiable {
        let id = UUID()
        let title: String
        let selection: Selection
        let document: NativeDocument
        let options: SummaryDocumentOptions
    }

    init(store: SummaryStore, workspace: TaskWorkspaceModel? = nil, context: WeeklyPlanningContext? = nil) {
        let model = workspace ?? TaskWorkspaceModel(seedDemoData: false)
        self.store = store
        self.workspace = model
        self.context = context ?? WeeklyPlanningContext(clock: model.clock, calendar: model.calendar)
        _journalDay = State(initialValue: model.clock())
    }

    private var range: SummaryDateRange { rangeOverride ?? .week(containing: context.weekStart, calendar: workspace.calendar) }
    private var selectedLists: Set<String> { listOverride ?? context.listName.map { Set([$0]) } ?? [] }
    private var selection: Selection {
        let lists = selectedLists
        let scope: String
        if lists.isEmpty { scope = "all" }
        else if lists.count == 1 { scope = workspace.listReferenceID(for: lists.first!).uuidString }
        else { scope = "lists:" + lists.map { workspace.listReferenceID(for: $0).uuidString }.sorted().joined(separator: ",") }
        return Selection(weekKey: range.storageKey(calendar: workspace.calendar), scopeID: scope,
            listName: lists.count == 1 ? lists.first : nil, listNames: lists, range: range)
    }
    private func selectRange(_ value: SummaryDateRange) {
        if value.kind == .week { rangeOverride = nil; context.weekStart = value.start }
        else { rangeOverride = value }
    }
    private func selectLists(_ names: Set<String>) {
        if names.count <= 1 { listOverride = nil; context.listName = names.first }
        else { listOverride = names }
    }
    private func openPlan(at date: Date) {
        saveWeekly()
        context.weekStart = SummaryReviewBuilder.weekStart(of: date, calendar: workspace.calendar)
        context.listName = selectedLists.count == 1 ? selectedLists.first : nil
        rangeOverride = nil; listOverride = nil
        showsSources = false
        // 先放置一次性定位请求，再切页：日历可能被页面缓存复用，
        // 依赖 onChange 消费请求而不是重新初始化。
        environment.navigation.calendarRevealRequest = context.weekStart
        environment.navigation.destination = .calendar
    }
    private var builder: WeeklyReportBuilder { WeeklyReportBuilder(calendar: workspace.calendar) }
    private var listFolders: [String: String] {
        var result: [String: String] = [:]
        for meta in workspace.listMetas {
            if let folder = meta.folderName, !folder.isEmpty { result[meta.name] = folder }
        }
        return result
    }
    private var report: WeeklyReport {
        return builder.report(tasks: workspace.tasksInActiveLists, weekOf: range.start,
            filter: options.filter, tagDirectory: workspace.taskTags, focusRecords: focusRecords,
            range: range, listNames: selectedLists, startedTaskIDs: focusedTaskIDs,
            listFolders: listFolders)
    }
    private var linkProfile: DocumentProfile {
        DocumentProfile(onOpenLink: { target in
            guard let url = URL(string: target), let resource = NativeResourceLink(url: url) else { return false }
            return NativeResourceLinkRouter.open(resource, tasks: workspace,
                notes: environment.notesWorkspace, navigation: environment.navigation, meetings: environment.meetingStore)
        })
    }

    var body: some View {
        GeometryReader { geometry in
            let inspectorWidth = min(440, max(300, geometry.size.width * 0.355))
            let showsInspector = !journalMode && geometry.size.width >= 900
            HStack(spacing: 0) {
                VStack(spacing: 0) {
                    pageHeader(showsInspector: showsInspector)
                    if journalMode { journalPane }
                    else { weeklyEditor(compact: geometry.size.width - (showsInspector ? inspectorWidth : 0) < 600) }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                if showsInspector {
                    Divider()
                    configuration.frame(width: inspectorWidth)
                }
            }
        }
        .background(WFColors.content)
        .onAppear { loadWeekly(); loadJournal() }
        .onDisappear {
            cancelAI()
            copyFeedbackTask?.cancel()
            saveWeekly()
            saveJournal()
        }
        .onChange(of: selection) { _, _ in
            cancelAI(); adoptionAvailable = false
            guard environment.navigation.destination == .summary else { return }
            editorHandle.prepareForDocumentChange()
            saveWeekly()
            selectedCarry = []
            aiError = nil
            loadWeekly()
        }
        .onChange(of: context.weekStart) { _, _ in
            if environment.navigation.destination != .summary { rangeOverride = nil }
        }
        .onChange(of: context.listName) { _, _ in
            if environment.navigation.destination != .summary { listOverride = nil }
        }
        .onReceive(environment.focusStore.$historyRevision.dropFirst()) { _ in
            DispatchQueue.main.async { refreshFocus() }
        }
        #if DEBUG
        // 录制引导演示时直接走真实复制路径，避免在非前台测试宿主里展开菜单。
        .onReceive(NotificationCenter.default.publisher(for: .guideTourCopySummary)) { _ in
            copySummary(as: .markdown)
        }
        #endif
        .onChange(of: environment.navigation.destination) { _, destination in
            if destination != .summary { cancelAI() }
        }
        .onChange(of: journalMode) { _, _ in cancelAI(); saveWeekly(); saveJournal() }
        .onChange(of: aiEnabled) { _, enabled in if !enabled { cancelAI() } }
        .onChange(of: journalDay) { _, _ in saveJournal(); loadJournal() }
        .onChange(of: journalText) { _, _ in saveJournal() }
        .onChange(of: document) { _, updated in
            copied = false
            copyFeedbackTask?.cancel()
            if adoptedDocument != updated { adoptionAvailable = false }
        }
        .sheet(item: $preview) { draft in previewSheet(draft) }
        .sheet(isPresented: $showsHistory) { historySheet }
        .sheet(isPresented: $showsSources) {
            VStack(spacing: 0) {
                DialogHeader(title: "任务与结转")
                Divider()
                sources(report: report)
                DialogCloseFooter { showsSources = false }
            }.frame(width: 380, height: 560)
        }
        .sheet(isPresented: $showsConfiguration, onDismiss: {
            let action = configurationDismissAction
            configurationDismissAction = nil
            action?()
        }) {
            VStack(spacing: 0) {
                DialogHeader(title: "摘要设置")
                Divider()
                configuration
                if options != appliedOptions {
                    DialogFooter(cancelTitle: "完成", primaryTitle: "预览更新",
                                 onCancel: { showsConfiguration = false },
                                 onSubmit: { afterConfiguration { showLatestDraft() } }) { EmptyView() }
                } else {
                    DialogCloseFooter { showsConfiguration = false }
                }
            }.frame(width: 400, height: 690)
        }
        .alert("存为摘要模板", isPresented: $showsSaveTemplate) {
            TextField("模板名称", text: $templateName)
            Button("取消", role: .cancel) {}
            Button(templateStore.contains(name: templateName) ? "替换同名模板" : "保存") {
                templateStore.saveSummaryTemplate(name: templateName, options: options, forceReplace: true)
            }.disabled(templateName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        } message: {
            Text("保存当前筛选与显示配置；再次套用时按当时任务重新生成正文。")
        }
    }

    private var configuration: some View {
        SummaryConfigurationView(options: $options, aiEnabled: $aiEnabled, aiOptions: $aiOptions,
            range: range, selectedLists: selectedLists, calendar: workspace.calendar, now: workspace.clock(),
            lists: [TaskList.inbox.name] + workspace.orderedListNames, listMetas: workspace.listMetas, folders: workspace.listFolders,
            tags: workspace.orderedTags.map(\.name),
            onSelectRange: selectRange, onSelectLists: selectLists,
            templates: templateStore.templates.filter(\.isSummaryTemplate),
            aiRunning: aiRunning, canGenerate: !document.isEmpty, aiError: aiError,
            onTemplate: { template in
                cancelAI()
                options = template?.summaryOptions ?? .standard
                afterConfiguration { showLatestDraft() }
            }, onSaveTemplate: { afterConfiguration { beginSaveTemplate() } },
            onGenerateAI: { afterConfiguration { startAI() } },
            onCancelAI: cancelAI, onConfigureAI: { afterConfiguration { openAISettings() } })
    }

    private func pageHeader(showsInspector: Bool) -> some View {
        HStack(spacing: 12) {
            Button { environment.toggleSidebar() } label: { Image(systemName: "sidebar.left") }
                .help("显示或隐藏侧栏").accessibilityLabel("显示或隐藏侧栏")
            Text(journalMode ? "每日手记" : "摘要").font(WFType.detailTitle).foregroundStyle(WFColors.text)
            Spacer()
            if !journalMode {
                if !showsInspector {
                    Button { showsConfiguration = true } label: { Image(systemName: "slider.horizontal.3") }
                        .help("筛选与显示设置").accessibilityLabel("筛选与显示设置")
                }
                Button { showsHistory = true } label: { Image(systemName: "doc.text") }
                    .help("已保存的摘要").accessibilityLabel("已保存的摘要")
            }
            BusinessMenu {
                Button(journalMode ? "周回顾" : "每日手记") { journalMode.toggle() }
                if !journalMode {
                    Divider()
                    Button("打印") { TaskPrintService.printDocument(title: "摘要 " + range.title(calendar: workspace.calendar), body: document.plainText) }
                }
            } label: { Image(systemName: "ellipsis.circle") }
                .fixedSize()
                .accessibilityLabel("摘要更多操作")
        }
        .buttonStyle(.borderless).foregroundStyle(WFColors.secondaryText)
        .padding(.horizontal, 22).frame(height: 52)
    }

    private func weeklyEditor(compact: Bool) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            if aiRunning {
                HStack {
                    ProgressView().controlSize(.small)
                    Text("AI 正在整理草稿…").font(WFType.supporting)
                    Spacer()
                    Button("取消生成", action: cancelAI).buttonStyle(.borderless)
                }
            } else if let aiError {
                HStack {
                    Text(aiError).font(WFType.supporting).foregroundStyle(WFColors.danger).lineLimit(2)
                    Spacer()
                    Button("AI 模型设置…", action: openAISettings).buttonStyle(.borderless)
                }
            }
            VStack(spacing: 0) {
                DocumentFormatToolbarView(handle: editorHandle, maxWidth: .infinity, embedded: true)
                    .padding(.horizontal, 10)
                Divider().overlay(WFColors.border)
                if options != appliedOptions {
                    HStack(spacing: 10) {
                        Text("筛选或显示设置已更改").font(WFType.supporting).foregroundStyle(WFColors.secondaryText)
                        Spacer(minLength: 4)
                        Button("还原") { options = appliedOptions }
                        Button("预览更新") { showLatestDraft() }
                            .workflowActionAnchor("summary.options.preview")
                    }
                    .buttonStyle(.borderless).font(WFType.supporting)
                    .padding(.horizontal, 16).padding(.vertical, 9)
                    .background(WFColors.panelFill)
                }
                DocumentEditor(documentID: editorID, document: document,
                    onDocumentChange: { updated in document = updated; saveWeekly(updated) }, onEscape: { .keepInspector },
                    onEditingChanged: { _ in }, profile: linkProfile, handle: editorHandle)
                    .padding(.horizontal, 12).padding(.vertical, 14)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            }
            .background(WFColors.content, in: RoundedRectangle(cornerRadius: 8))
            .overlay { RoundedRectangle(cornerRadius: 8).stroke(WFColors.border, lineWidth: 1) }
            if let error = store.lastError { Text(error).font(WFType.supporting).foregroundStyle(WFColors.danger) }
            HStack(spacing: 16) {
                footerAction("在日历中查看", symbol: "calendar", compact: compact) { openPlan(at: range.start) }
                footerAction("任务与结转", symbol: "checklist", compact: compact) { showsSources = true }
                footerAction("更新摘要", symbol: "arrow.clockwise", compact: compact) { showLatestDraft() }
                if adoptionAvailable {
                    footerAction("撤销采用", symbol: "arrow.uturn.backward", compact: compact) {
                        editorHandle.textView?.undo(nil)
                    }
                }
                Spacer(minLength: 0)
                BusinessMenu(title: "保存为", prefersAbove: true) {
                    ForEach(SummaryExportFormat.allCases, id: \.self) { format in
                        Button(format.menuTitle) { saveSummary(as: format) }
                    }
                    Divider().padding(.vertical, 4)
                    Button("发送邮件") { emailSummary() }
                        .disabled(document.isEmpty)
                        .workflowActionAnchor("summary.export.email")
                } label: {
                    if compact {
                        Image(systemName: "square.and.arrow.down").frame(width: 22, height: 24)
                    } else {
                        Label("保存为", systemImage: "square.and.arrow.down").font(WFType.supporting)
                    }
                }
                .help("保存为")
                .accessibilityLabel("保存为")
                .workflowActionAnchor("summary.footer.保存为")
                BusinessMenu(title: "复制", prefersAbove: true) {
                    ForEach(SummaryCopyFormat.allCases, id: \.self) { format in
                        Button(format.menuTitle) { copySummary(as: format) }
                            .disabled(document.isEmpty)
                            .workflowActionAnchor("summary.copy." + format.anchor)
                    }
                } label: {
                    if compact {
                        Image(systemName: copied ? "checkmark" : "doc.on.clipboard")
                            .frame(width: 22, height: 24)
                    } else {
                        Label(copied ? "已复制" : "复制",
                              systemImage: copied ? "checkmark" : "doc.on.clipboard")
                            .font(WFType.supporting)
                    }
                }
                .help("复制")
                .accessibilityLabel("复制")
                .workflowActionAnchor("summary.footer.复制")
                .guideTourAnchor("summary.footer.复制")
            }
            .buttonStyle(.borderless).foregroundStyle(WFColors.secondaryText).frame(height: 30)
        }
        .padding(.horizontal, 20).padding(.top, 8).padding(.bottom, 12)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func footerAction(_ title: String, symbol: String, compact: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            if compact { Image(systemName: symbol).frame(width: 22, height: 24) }
            else { Label(title, systemImage: symbol).font(WFType.supporting) }
        }.help(title).accessibilityLabel(title).workflowActionAnchor("summary.footer." + title)
            .guideTourAnchor("summary.footer." + title)
    }

    private func beginSaveTemplate() {
        showsConfiguration = false
        templateName = "摘要模板"
        showsSaveTemplate = true
    }

    private func copySummary(as format: SummaryCopyFormat) {
        editorHandle.prepareForDocumentChange()
        do {
            try SummaryCopyService.copy(document, format: format)
            markCopied()
        } catch {
            environment.feedback.show(FeedbackEvent(kind: .error,
                message: error.localizedDescription))
        }
    }

    private func markCopied() {
        copyFeedbackTask?.cancel()
        copied = true
        copyFeedbackTask = _Concurrency.Task { @MainActor in
            try? await _Concurrency.Task.sleep(for: .seconds(1.5))
            guard !_Concurrency.Task.isCancelled else { return }
            copied = false
        }
    }

    private func emailSummary() {
        editorHandle.prepareForDocumentChange()
        let scope = selection.listName.map { $0 + " " } ?? ""
        let subject = "摘要 " + scope + range.title(calendar: workspace.calendar)
        guard let draft = SummaryMailDraft.make(
            subject: subject,
            body: SummaryExportService.plainText(document)
        ) else {
            environment.feedback.show(FeedbackEvent(kind: .error,
                message: SummaryExportError.emptyDocument.localizedDescription))
            return
        }
        if draft.copiesBodyToPasteboard {
            copyMailBody(draft.body)
        }
        guard let url = draft.url, NSWorkspace.shared.open(url) else {
            copyMailBody(draft.body)
            environment.feedback.show(FeedbackEvent(kind: .error,
                message: "没有可用的邮件应用，摘要已复制到剪贴板"))
            return
        }
        if draft.copiesBodyToPasteboard {
            environment.feedback.show(FeedbackEvent(kind: .info,
                message: "内容较长，已复制到剪贴板，请粘贴到邮件"))
        }
    }

    private func copyMailBody(_ body: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(body, forType: .string)
    }

    private func saveSummary(as format: SummaryExportFormat) {
        editorHandle.prepareForDocumentChange()
        let exportDocument = document
        let scope = selection.listName.map { $0 + " " } ?? ""
        let baseName = "摘要 " + scope + range.title(calendar: workspace.calendar)
        let panel = NSSavePanel()
        panel.title = "保存摘要"
        panel.prompt = "保存"
        panel.canCreateDirectories = true
        panel.allowedContentTypes = [format.contentType]
        panel.nameFieldStringValue = format.suggestedFileName(for: baseName)
        panel.begin { response in
            guard response == .OK, let url = panel.url else { return }
            _Concurrency.Task { @MainActor in
                do {
                    let data = try SummaryExportService.data(for: exportDocument, format: format)
                    try data.write(to: url, options: .atomic)
                    environment.feedback.show(FeedbackEvent(kind: .success,
                        message: "已导出 " + url.lastPathComponent))
                } catch {
                    let message = (error as? SummaryExportError) == .imageTooLong
                        ? error.localizedDescription
                        : "导出失败：" + error.localizedDescription
                    environment.feedback.show(FeedbackEvent(kind: .error, message: message))
                }
            }
        }
    }

    private func afterConfiguration(_ action: @escaping () -> Void) {
        if showsConfiguration {
            configurationDismissAction = action
            showsConfiguration = false
        } else { action() }
    }

    private func sources(report: WeeklyReport) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                VStack(alignment: .leading, spacing: 9) {
                    Text(range.kind == .week ? "本周成果" : "本期成果").font(WFType.section)
                    if report.completed.isEmpty && report.progress.isEmpty {
                        Text("暂无完成记录").font(WFType.supporting).foregroundStyle(WFColors.tertiaryText)
                    }
                    ForEach(report.completed) { task in sourceRow(task) }
                    ForEach(report.progress) { progress in
                        VStack(alignment: .leading, spacing: 4) {
                            sourceRow(progress.task)
                            Text("本期推进 \(progress.completedChildren.count) 个子任务")
                                .font(WFType.supporting).foregroundStyle(WFColors.tertiaryText)
                        }
                    }
                }
                VStack(alignment: .leading, spacing: 9) {
                    HStack {
                        Text("待推进").font(WFType.section)
                        Spacer()
                        if !report.pending.isEmpty {
                            Button(selectedCarry.count == report.pending.count ? "取消全选" : "全选") {
                                selectedCarry = selectedCarry.count == report.pending.count ? [] : Set(report.pending.map(\.id))
                            }.font(WFType.supporting)
                        }
                    }
                    if report.pending.isEmpty { Text("没有待结转任务").font(WFType.supporting).foregroundStyle(WFColors.tertiaryText) }
                    ForEach(report.pending) { task in
                        HStack(alignment: .top, spacing: 8) {
                            Toggle("选择 \(task.title)", isOn: Binding(get: { selectedCarry.contains(task.id) }, set: { selected in
                                if selected { selectedCarry.insert(task.id) } else { selectedCarry.remove(task.id) }
                            })).labelsHidden().toggleStyle(.checkbox)
                            sourceRow(task)
                        }
                    }
                    if range.kind == .week && !report.pending.isEmpty {
                        Button("结转所选到下周") {
                            _ = workspace.planTasks(selectedCarry.intersection(Set(report.pending.map(\.id))), weekOf: context.nextWeek)
                            selectedCarry = []
                        }.disabled(selectedCarry.isEmpty).buttonStyle(.bordered)
                        Text("保留原任务和提醒，支持撤销。")
                            .font(WFType.supporting).foregroundStyle(WFColors.tertiaryText)
                    }
                }
                if !report.carried.isEmpty {
                    VStack(alignment: .leading, spacing: 9) {
                        Text("已结转 \(report.carried.count)").font(WFType.section)
                        ForEach(report.carried) { move in sourceRow(move.task) }
                    }
                }
                if !report.abandoned.isEmpty || !report.rescheduled.isEmpty {
                    VStack(alignment: .leading, spacing: 9) {
                        Text("其他调整").font(WFType.section)
                        ForEach(report.abandoned) { task in
                            VStack(alignment: .leading, spacing: 3) {
                                sourceRow(task)
                                Text("已放弃").font(WFType.supporting).foregroundStyle(WFColors.tertiaryText)
                            }
                        }
                        ForEach(report.rescheduled) { task in sourceRow(task) }
                    }
                }
                VStack(alignment: .leading, spacing: 9) {
                    Text("下一周期任务").font(WFType.section)
                    ForEach(report.nextWeek) { task in sourceRow(task) }
                    Button("打开下一周期计划") { openPlan(at: range.next(calendar: workspace.calendar).start) }
                        .font(WFType.supporting)
                }
                DisclosureGroup("专注投入") {
                    Text("本期记录 \(report.focusSeconds / 60) 分钟，仅作为投入参考。")
                        .font(WFType.supporting).foregroundStyle(WFColors.secondaryText).padding(.top, 8)
                }.font(WFType.supporting).foregroundStyle(WFColors.secondaryText)
            }
            .buttonStyle(.borderless).frame(maxWidth: .infinity, alignment: .leading).padding(20)
        }
    }

    private func sourceRow(_ task: Task) -> some View {
        Button { showsSources = false; environment.openTask(task.id) } label: {
            Text(task.title).font(WFType.supporting).foregroundStyle(WFColors.text)
                .multilineTextAlignment(.leading).frame(maxWidth: .infinity, alignment: .leading)
                .padding(.vertical, 3).padding(.horizontal, 6)
                .contentShape(Rectangle())
                .rowHoverBackground(cornerRadius: 6)
        }.help("打开原任务")
    }

    private var journalPane: some View {
        VStack(alignment: .leading, spacing: 16) {
            DatePicker("日期", selection: $journalDay, displayedComponents: .date).datePickerStyle(.field)
            TextEditor(text: $journalText).font(WFType.body)
        }.padding(24)
    }

    private var historySheet: some View {
        VStack(spacing: 0) {
            DialogHeader(title: "已保存的摘要")
            Divider()
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 12) {
                    ForEach(store.weeklyEntries) { entry in
                        Button {
                            saveWeekly()
                            selectLists(Set(entry.listNames ?? entry.listName.map { [$0] } ?? []))
                            if let savedRange = entry.range { selectRange(savedRange) }
                            else if let start = SummaryStore.date(fromDayKey: entry.weekKey, calendar: workspace.calendar) {
                                selectRange(.week(containing: start, calendar: workspace.calendar))
                            }
                            showsHistory = false
                        } label: {
                            VStack(alignment: .leading, spacing: 5) {
                                Text((entry.range?.title(calendar: workspace.calendar) ?? entry.weekKey) + " · " +
                                    (entry.listNames?.isEmpty == false ? entry.listNames!.joined(separator: "、") : entry.listName ?? "所有清单"))
                                Text(entry.document.plainText.replacingOccurrences(of: "\n", with: " "))
                                    .font(WFType.supporting).foregroundStyle(WFColors.secondaryText).lineLimit(2)
                            }.frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.vertical, 6).padding(.horizontal, 8)
                                .contentShape(Rectangle())
                                .rowHoverBackground(cornerRadius: 8)
                        }
                    }
                }.padding(PopupMetrics.formInset)
            }
            DialogCloseFooter { showsHistory = false }
        }.buttonStyle(.borderless).frame(width: 540, height: 460)
    }

    private func previewSheet(_ draft: DraftPreview) -> some View {
        let review = SummaryDraftReview(original: document, candidate: draft.document)
        return VStack(spacing: 0) {
            DialogHeader(title: draft.title)
            Divider()
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text("选择要采用的段落，未选内容保留原文。任务依据可从“任务与结转”核对。")
                        .font(WFType.supporting).foregroundStyle(WFColors.secondaryText)
                    Spacer()
                    Button("全选改动") { selectedDraftSections = review.changedIDs }.buttonStyle(.borderless)
                }
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        ForEach(review.sections) { section in
                            VStack(alignment: .leading, spacing: 8) {
                                if section.changed {
                                    Toggle(section.title, isOn: Binding(get: { selectedDraftSections.contains(section.id) }, set: { selected in
                                        if selected { selectedDraftSections.insert(section.id) } else { selectedDraftSections.remove(section.id) }
                                    })).toggleStyle(.checkbox).font(WFType.section)
                                    HStack(alignment: .top, spacing: 16) {
                                        previewColumn("原文", blocks: section.before)
                                        previewColumn("草稿", blocks: section.after)
                                    }
                                } else {
                                    Text(section.title + " · 保留原文").font(WFType.supporting).foregroundStyle(WFColors.secondaryText)
                                }
                            }.padding(12).frame(maxWidth: .infinity, alignment: .leading)
                                .background(WFColors.panelFill, in: RoundedRectangle(cornerRadius: 8))
                        }
                    }
                }
            }.padding(PopupMetrics.formInset)
            DialogFooter(primaryTitle: "采用所选", canSubmit: draft.selection == selection &&
                (review.changedIDs.isEmpty ? draft.options != appliedOptions : !selectedDraftSections.isEmpty),
                primaryIdentifier: "summary.preview.adopt",
                onCancel: { preview = nil }, onSubmit: {
                    guard draft.selection == selection else { preview = nil; return }
                    if review.changedIDs.isEmpty {
                        options = draft.options; appliedOptions = draft.options
                        saveWeekly(); preview = nil
                        return
                    }
                    let next = review.applying(selectedDraftSections)
                    let previousDocument = document
                    let previousOptions = appliedOptions
                    let nextOptions = selectedDraftSections == review.changedIDs ? draft.options : appliedOptions
                    let accepted = editorHandle.replaceDocument(next, commit: { updated in
                        document = updated; options = nextOptions; appliedOptions = nextOptions
                        adoptedDocument = updated; adoptionAvailable = true; saveWeekly(updated)
                    }, inverseCommit: { _ in
                        // TextKit may coalesce adjacent runs. Restore the saved
                        // structured blocks together with the replayed text.
                        document = previousDocument; options = previousOptions; appliedOptions = previousOptions
                        adoptionAvailable = false; saveWeekly(previousDocument)
                    })
                    if accepted {
                        preview = nil
                        DispatchQueue.main.async { editorHandle.focusEditor() }
                    }
                }) { Text(review.changedIDs.isEmpty ? "应用配置" : "\(selectedDraftSections.count) 处改动") }
        }.background(WFColors.content).frame(width: 700, height: 590)
            .onAppear { selectedDraftSections = review.changedIDs }
    }

    private func previewColumn(_ title: String, blocks: [DocumentBlock]) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(WFType.supporting).foregroundStyle(WFColors.secondaryText)
            Text(blocks.isEmpty ? "（空）" : blocks.map(\.plainText).joined(separator: "\n"))
                .font(WFType.body).textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading)
        }.frame(maxWidth: .infinity, alignment: .leading)
    }

    private func openAISettings() {
        environment.settingsSection = .ai
        openSettings()
    }

    private func showLatestDraft() {
        editorHandle.prepareForDocumentChange()
        preview = DraftPreview(title: "最新任务摘要预览", selection: selection,
                               document: builder.document(for: report, options: options, preserving: document), options: options)
    }

    private func cancelAI() {
        aiGeneration = UUID()
        aiJob?.cancel(); aiJob = nil; aiRunning = false
    }
    private func startAI() {
        cancelAI()
        let generation = UUID(); aiGeneration = generation
        aiJob = _Concurrency.Task { await generateAI(generation: generation) }
    }
    private func generateAI(generation: UUID) async {
        editorHandle.prepareForDocumentChange()
        let target = selection
        let requestedOptions = options
        let original = document
        let source = builder.document(for: report, options: requestedOptions, preserving: document)
        let title = range.title(calendar: workspace.calendar)
        var request = aiOptions
        request.weeklyStructure = false
        request.isWeeklyPeriod = range.kind == .week
        aiRunning = true; aiError = nil
        defer { if aiGeneration == generation { aiRunning = false; aiJob = nil } }
        do {
            var optimizer = SummaryPiOptimizer()
            optimizer.executable = environment.meetingStore.configuration.executable
            optimizer.model = environment.meetingStore.configuration.resolvedMinutesModel
            let text = try await optimizer.optimize(text: source.plainText, options: request)
            try _Concurrency.Task.checkCancellation()
            guard aiGeneration == generation, target == selection, !journalMode,
                  environment.navigation.destination == .summary else { return }
            guard requestedOptions == options, document == original else {
                aiError = "正文或筛选已更改，请按当前内容重新生成。"
                return
            }
            preview = DraftPreview(title: "AI 草稿预览", selection: target,
                document: WeeklyReportBuilder.aiDocument(text: text, title: title), options: requestedOptions)
        } catch is CancellationError { }
        catch { if aiGeneration == generation && target == selection { aiError = error.localizedDescription } }
    }

    private func loadWeekly() {
        refreshFocus()
        if range.kind == .week {
            workspace.captureWeekPlan(weekOf: range.start)
            if selectedLists.isEmpty { store.migrateLegacyWeekly(weekStart: range.start, calendar: workspace.calendar) }
        }
        let target = selection
        loadedSelection = target
        let saved = store.weeklyEntry(weekKey: target.weekKey, scopeID: target.scopeID)
        // Keep combined conditions when opening a new scope; an existing
        // archive restores the recipe actually applied to that document.
        options = saved?.options ?? (saved == nil ? options : .standard)
        appliedOptions = options
        document = saved?.document ?? builder.document(for: report, options: options)
        editorID = UUID(); copied = false; copyFeedbackTask?.cancel()
        saveWeekly()
    }

    private func refreshFocus() {
        let snapshot = environment.focusStore.summarySnapshot(in: range)
        focusRecords = snapshot.records
        focusedTaskIDs = snapshot.startedTaskIDs
    }

    private func saveWeekly(_ updated: NativeDocument? = nil) {
        guard let target = loadedSelection else { return }
        store.saveWeekly(document: updated ?? document, weekKey: target.weekKey, scopeID: target.scopeID, listName: target.listName, options: appliedOptions,
            range: target.range, listNames: target.listNames.sorted())
    }

    private func loadJournal() {
        let key = SummaryStore.dayKey(journalDay, calendar: workspace.calendar)
        loadedJournalKey = key
        journalText = store.entry(for: key)?.content ?? ""
    }
    private func saveJournal() {
        guard let key = loadedJournalKey else { return }
        if store.entry(for: key)?.content != journalText { store.save(content: journalText, dayKey: key) }
    }
}
