import AppKit
import SwiftUI

/// 摘要只负责回顾与产出；计划动作在日历周视图里完成，这里不再提供计划页。
/// 正文是当前任务事实的实时投影：任务、筛选或显示设置变化都会重建，
/// 默认摘要不落盘，手写内容会在下一次重建时被覆盖（对齐滴答）。
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
    @State private var aiEnabled = false
    @State private var aiOptions = SummaryAIOptions()
    @State private var showsConfiguration = false
    @State private var configurationDismissAction: (() -> Void)?
    @State private var showsSaveTemplate = false
    @State private var templateName = ""
    @StateObject private var editorHandle = DocumentEditorHandle()
    @State private var document = NativeDocument.empty
    @State private var editorID = UUID()
    @State private var preview: DraftPreview?
    @State private var showsSources = false
    @State private var selectedCarry: Set<UUID> = []
    @State private var aiRunning = false
    @State private var aiError: String?
    @State private var aiJob: _Concurrency.Task<Void, Never>?
    @State private var aiGeneration = UUID()
    @State private var selectedDraftSections: Set<Int> = []
    @State private var copied = false
    @State private var copyFeedbackTask: _Concurrency.Task<Void, Never>?
    @State private var reloadTask: _Concurrency.Task<Void, Never>?
    @State private var journalMode = false
    @State private var journalDay: Date
    @State private var journalText = ""
    @State private var loadedJournalKey: String?

    private struct Selection: Equatable {
        let listNames: Set<String>
        let range: SummaryDateRange
    }
    private struct DraftPreview: Identifiable {
        let id = UUID()
        let title: String
        let selection: Selection
        let document: NativeDocument
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
    private var options: SummaryDocumentOptions { store.options }
    private var optionsBinding: Binding<SummaryDocumentOptions> {
        Binding(get: { store.options }, set: { store.updateOptions($0) })
    }
    private var selection: Selection {
        Selection(listNames: selectedLists, range: range)
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
            range: range, listNames: selectedLists, listFolders: listFolders, listMetas: workspace.listMetas)
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
        .onAppear { reloadDocument(); loadJournal() }
        .onDisappear {
            cancelAI()
            copyFeedbackTask?.cancel()
            reloadTask?.cancel()
            saveJournal()
        }
        .onChange(of: selection) { _, _ in
            cancelAI(); preview = nil
            guard environment.navigation.destination == .summary else { return }
            selectedCarry = []
            aiError = nil
            reloadDocument()
        }
        .onChange(of: options) { _, _ in
            guard environment.navigation.destination == .summary else { return }
            scheduleReload()
        }
        .onChange(of: context.weekStart) { _, _ in
            if environment.navigation.destination != .summary { rangeOverride = nil }
        }
        .onChange(of: context.listName) { _, _ in
            if environment.navigation.destination != .summary { listOverride = nil }
        }
        .onReceive(environment.focusStore.$historyRevision.dropFirst()) { _ in
            refreshFocus()
            scheduleReload()
        }
        .onReceive(workspace.$revision.dropFirst()) { _ in
            scheduleReload()
        }
        #if DEBUG
        // 录制引导演示时直接走真实复制路径，避免在非前台测试宿主里展开菜单。
        .onReceive(NotificationCenter.default.publisher(for: .guideTourCopySummary)) { _ in
            copySummary(as: .markdown)
        }
        #endif
        .onChange(of: environment.navigation.destination) { _, destination in
            if destination == .summary { reloadDocument() } else { cancelAI(); preview = nil }
        }
        .onChange(of: journalMode) { _, _ in
            cancelAI()
            saveJournal()
            if !journalMode { reloadDocument() }
        }
        .onChange(of: aiEnabled) { _, enabled in if !enabled { cancelAI() } }
        .onChange(of: journalDay) { _, _ in saveJournal(); loadJournal() }
        .onChange(of: journalText) { _, _ in saveJournal() }
        .onChange(of: document) { _, _ in
            copied = false
            copyFeedbackTask?.cancel()
        }
        .sheet(item: $preview) { draft in previewSheet(draft) }
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
                DialogCloseFooter { showsConfiguration = false }
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
        SummaryConfigurationView(options: optionsBinding, aiEnabled: $aiEnabled, aiOptions: $aiOptions,
            range: range, selectedLists: selectedLists, calendar: workspace.calendar, now: workspace.clock(),
            lists: [TaskList.inbox.name] + workspace.orderedListNames, listMetas: workspace.listMetas, folders: workspace.listFolders,
            tags: workspace.orderedTags.map(\.name),
            onSelectRange: selectRange, onSelectLists: selectLists,
            templates: templateStore.templates.filter(\.isSummaryTemplate),
            aiRunning: aiRunning, canGenerate: !document.isEmpty, aiError: aiError,
            onTemplate: { template in
                cancelAI()
                store.updateOptions(template?.summaryOptions ?? .standard)
            }, onSaveTemplate: { afterConfiguration { beginSaveTemplate() } },
            onGenerateAI: { afterConfiguration { startAI() } },
            onCancelAI: cancelAI, onConfigureAI: { afterConfiguration { openAISettings() } })
    }

    private func pageHeader(showsInspector: Bool) -> some View {
        HStack(spacing: 12) {
            Button { environment.toggleSidebar() } label: { Image(systemName: "sidebar.left") }
                .hoverTip("显示或隐藏侧栏").accessibilityLabel("显示或隐藏侧栏")
            Text(journalMode ? "每日手记" : "摘要").font(WFType.detailTitle).foregroundStyle(WFColors.text)
            Spacer()
            if !journalMode {
                if !showsInspector {
                    Button { showsConfiguration = true } label: { Image(systemName: "slider.horizontal.3") }
                        .hoverTip("筛选与显示设置").accessibilityLabel("筛选与显示设置")
                }
                Button { reloadDocument() } label: { Image(systemName: "arrow.clockwise") }
                    .hoverTip("刷新摘要").accessibilityLabel("刷新摘要")
            }
            BusinessMenu {
                Button(journalMode ? "周回顾" : "每日手记") { journalMode.toggle() }
                if !journalMode {
                    Divider()
                    Button("打印") { TaskPrintService.printDocument(title: "摘要 " + range.title(calendar: workspace.calendar), body: document.plainText) }
                }
            } label: { Image(systemName: "ellipsis.circle") }
                .fixedSize()
                .hoverTip("摘要更多操作")
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
                DocumentEditor(documentID: editorID, document: document,
                    onDocumentChange: { document = $0 }, onEscape: { .keepInspector },
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
                Spacer(minLength: 0)
                BusinessMenu(title: "保存为", prefersAbove: true) {
                    Button { saveSummary(as: .pdf) } label: {
                        SummaryMenuLabel(title: "PDF", badge: .pdf)
                    }
                    .disabled(document.isEmpty)
                    .workflowActionAnchor("summary.export.pdf")
                    Button { saveSummary(as: .image) } label: {
                        SummaryMenuLabel(title: "图片", badge: .png)
                    }
                    .disabled(document.isEmpty)
                    .workflowActionAnchor("summary.export.image")
                    Button { emailSummary() } label: {
                        SummaryMenuLabel(title: "发送邮件", badge: .mail)
                    }
                    .disabled(document.isEmpty)
                    .workflowActionAnchor("summary.export.email")
                } label: {
                    if compact {
                        Image(systemName: "square.and.arrow.down").frame(width: 22, height: 24)
                    } else {
                        Label("保存为", systemImage: "square.and.arrow.down").font(WFType.supporting)
                    }
                }
                .hoverTip(compact ? "保存为" : "", placement: .above)
                .accessibilityLabel("保存为")
                .workflowActionAnchor("summary.footer.保存为")
                BusinessMenu(title: "复制", prefersAbove: true) {
                    ForEach(SummaryCopyFormat.allCases, id: \.self) { format in
                        Button { copySummary(as: format) } label: {
                            SummaryMenuLabel(title: format.menuTitle, badge: format.menuBadge)
                        }
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
                .hoverTip(compact ? "复制" : "", placement: .above)
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
        }.hoverTip(compact ? title : "", placement: .above).accessibilityLabel(title).workflowActionAnchor("summary.footer." + title)
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

    private var exportBaseName: String {
        SummaryExportService.baseName(for: range, calendar: workspace.calendar)
    }

    private func emailSummary() {
        editorHandle.prepareForDocumentChange()
        guard let draft = SummaryMailDraft.make(subject: exportBaseName, document: document) else {
            environment.feedback.show(FeedbackEvent(kind: .error,
                message: SummaryExportError.emptyDocument.localizedDescription))
            return
        }
        guard let service = NSSharingService(named: .composeEmail),
              service.canPerform(withItems: [draft.body]) else {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(draft.plainText, forType: .string)
            environment.feedback.show(FeedbackEvent(kind: .error,
                message: "没有可用的邮件应用，摘要已复制到剪贴板"))
            return
        }
        service.subject = draft.subject
        service.perform(withItems: [draft.body])
    }

    private func saveSummary(as format: SummaryExportFormat) {
        editorHandle.prepareForDocumentChange()
        let exportDocument = document
        let baseName = exportBaseName
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
            DialogFooter(primaryTitle: "采用所选",
                canSubmit: draft.selection == selection && !selectedDraftSections.isEmpty,
                primaryIdentifier: "summary.preview.adopt",
                onCancel: { preview = nil }, onSubmit: {
                    guard draft.selection == selection else { preview = nil; return }
                    let next = review.applying(selectedDraftSections)
                    let previousDocument = document
                    let accepted = editorHandle.replaceDocument(next, commit: { updated in
                        document = updated
                    }, inverseCommit: { _ in
                        // TextKit may coalesce adjacent runs; restore the
                        // structured blocks together with the replayed text.
                        document = previousDocument
                    })
                    if accepted {
                        preview = nil
                        DispatchQueue.main.async { editorHandle.focusEditor() }
                    }
                }) { Text("\(selectedDraftSections.count) 处改动") }
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
        let original = document
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
            optimizer.textModel = try environment.aiModels.request()
            let text = try await optimizer.optimize(text: original.plainText, options: request)
            try _Concurrency.Task.checkCancellation()
            guard aiGeneration == generation, target == selection, !journalMode,
                  environment.navigation.destination == .summary else { return }
            guard document == original else {
                aiError = "正文已按最新任务更新，请按当前内容重新生成。"
                return
            }
            preview = DraftPreview(title: "AI 草稿预览", selection: target,
                document: WeeklyReportBuilder.aiDocument(text: text, title: title))
        } catch is CancellationError { }
        catch { if aiGeneration == generation && target == selection { aiError = error.localizedDescription } }
    }

    /// 滴答的摘要正文是任务事实的实时投影：重建会丢弃手写改动并清空撤销历史。
    private func reloadDocument() {
        guard !journalMode else { return }
        reloadTask?.cancel(); reloadTask = nil
        refreshFocus()
        if range.kind == .week { workspace.captureWeekPlan(weekOf: range.start) }
        let next = builder.document(for: report, options: options, now: workspace.clock())
        guard next != document else { return }
        preview = nil
        editorHandle.prepareForDocumentChange()
        document = next
        editorID = UUID()
        copied = false
        copyFeedbackTask?.cancel()
    }

    private func scheduleReload() {
        guard !journalMode, environment.navigation.destination == .summary else { return }
        reloadTask?.cancel()
        reloadTask = _Concurrency.Task { @MainActor in
            try? await _Concurrency.Task.sleep(for: .milliseconds(120))
            guard !_Concurrency.Task.isCancelled else { return }
            reloadDocument()
        }
    }

    private func refreshFocus() {
        focusRecords = environment.focusStore.summarySnapshot(in: range)
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

/// 摘要底栏菜单的格式徽标，对齐滴答的彩色文件图标。
private struct SummaryMenuLabel: View {
    enum Badge {
        case file(String, Color)
        case symbol(String, Color)

        static let pdf = Self.file("PDF", Color(red: 0.93, green: 0.26, blue: 0.24))
        static let png = Self.file("PNG", Color(red: 0.98, green: 0.70, blue: 0.20))
        static let markdown = Self.file("M↓", Color(red: 0.18, green: 0.20, blue: 0.26))
        static let richText = Self.file("R", Color(red: 0.93, green: 0.26, blue: 0.24))
        static let plainText = Self.file("T", Color(red: 0.24, green: 0.74, blue: 0.48))
        static let mail = Self.symbol("envelope.fill", Color(red: 0.23, green: 0.51, blue: 0.96))
    }

    let title: String
    let badge: Badge

    var body: some View {
        HStack(spacing: 8) {
            switch badge {
            case let .file(text, color):
                Text(text)
                    .font(.system(size: text.count > 2 ? 6.5 : text.count == 2 ? 8.5 : 10, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(width: 20, height: 20)
                    .background(color, in: RoundedRectangle(cornerRadius: 4))
            case let .symbol(name, color):
                Image(systemName: name)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(color)
                    .frame(width: 20, height: 20)
            }
            Text(title)
        }
    }
}

private extension SummaryCopyFormat {
    var menuBadge: SummaryMenuLabel.Badge {
        switch self {
        case .markdown: .markdown
        case .richText: .richText
        case .plainText: .plainText
        }
    }
}
