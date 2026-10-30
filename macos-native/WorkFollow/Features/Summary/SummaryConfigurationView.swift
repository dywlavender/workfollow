import Foundation
import SwiftUI
import UniformTypeIdentifiers

struct SummaryConfigurationView: View {
    @Binding var options: SummaryDocumentOptions
    @Binding var aiEnabled: Bool
    @Binding var aiOptions: SummaryAIOptions
    let range: SummaryDateRange
    let selectedLists: Set<String>
    let calendar: Calendar
    let now: Date
    let lists: [String]
    let listMetas: [TaskListMeta]
    let folders: [TaskListFolder]
    let tags: [String]
    let onSelectRange: (SummaryDateRange) -> Void
    let onSelectLists: (Set<String>) -> Void
    let templates: [TaskTemplate]
    let aiRunning: Bool
    let canGenerate: Bool
    let aiError: String?
    let onTemplate: (TaskTemplate?) -> Void
    let onSaveTemplate: () -> Void
    let onGenerateAI: () -> Void
    var onCancelAI: () -> Void = {}
    var onConfigureAI: () -> Void = {}
    @State private var activePopover: Control?

    enum Control: String {
        case date, list, status, more, grouping, content, aiLength, aiStyle
        var width: CGFloat {
            switch self {
            case .date: SummaryPopoverMetrics.dateWidth
            case .list: SummaryPopoverMetrics.listWidth
            case .status: SummaryPopoverMetrics.statusWidth
            case .more: SummaryPopoverMetrics.moreWidth
            case .grouping: SummaryPopoverMetrics.groupingWidth
            case .content: SummaryPopoverMetrics.contentWidth
            case .aiLength, .aiStyle: SummaryPopoverMetrics.aiOptionWidth
            }
        }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 26) {
                templateSection
                section("筛选") {
                    control("日期", value: dateLabel, kind: .date)
                    control("清单", value: listLabel, kind: .list)
                    control("状态", value: options.filter.status.rawValue, kind: .status)
                    control("更多", value: moreLabel, kind: .more)
                }
                section("显示设置") {
                    control("分组", value: options.grouping.rawValue, kind: .grouping)
                    control("显示内容", value: "\(options.content.count)项", kind: .content)
                }
                HStack {
                    Text("下一周期任务").font(WFType.sectionSemibold)
                    Spacer()
                    Toggle("下一周期任务", isOn: $options.includesNextWeek)
                        .toggleStyle(.switch).labelsHidden().controlSize(.mini)
                        .help("带入下一天、周、月或相同长度的下一段日期中已安排的任务")
                }
                aiSection
            }
            .padding(24).frame(maxWidth: .infinity, alignment: .leading)
        }
        .compactScrollbars()
        .tint(WFColors.summaryAction)
    }

    private func control(_ title: String, value: String, kind: Control) -> some View {
        SummarySettingControl(title: title, value: value,
            isPresented: Binding(get: { activePopover == kind }, set: { activePopover = $0 ? kind : nil }),
            width: kind.width, anchor: "summary.setting." + kind.rawValue) {
            popover(kind).tint(WFColors.summaryAction)
        }
    }

    @ViewBuilder private func popover(_ kind: Control) -> some View {
        switch kind {
        case .date:
            SummaryDatePopover(range: range, now: now, calendar: calendar) {
                onSelectRange($0); activePopover = nil
            } onCancel: { activePopover = nil }
        case .list:
            SummaryListPopover(selected: selectedLists, lists: lists, metas: listMetas, folders: folders) {
                onSelectLists($0); activePopover = nil
            } onCancel: { activePopover = nil }
        case .status:
            SummaryStatusPopover(status: options.filter.status) {
                options.filter.status = $0; activePopover = nil
            } onCancel: { activePopover = nil }
        case .more:
            SummaryMorePopover(filter: options.filter, tags: tags) {
                options.filter = $0; activePopover = nil
            } onCancel: { activePopover = nil }
        case .grouping:
            VStack(spacing: 2) {
                ForEach(SummaryGrouping.allCases, id: \.self) { grouping in
                    SummaryChoiceRow(title: grouping.rawValue, selected: options.grouping == grouping) {
                        options.grouping = grouping; activePopover = nil
                    }
                    .disabled(!grouping.isAvailable)
                    .help(grouping.isAvailable ? grouping.rawValue : "指派人分组需要协作成员，当前不可用。")
                }
            }.padding(SummaryPopoverMetrics.contentPadding)
                .frame(width: SummaryPopoverMetrics.groupingWidth)
        case .content:
            SummaryContentPopover(options: $options)
        case .aiLength:
            VStack(spacing: 2) {
                ForEach(SummaryAIOptions.Length.allCases, id: \.self) { length in
                    SummaryChoiceRow(title: length.rawValue, selected: aiOptions.length == length) {
                        aiOptions.length = length; activePopover = nil
                    }
                }
            }.padding(SummaryPopoverMetrics.contentPadding)
                .frame(width: SummaryPopoverMetrics.aiOptionWidth)
        case .aiStyle:
            VStack(spacing: 2) {
                ForEach(SummaryAIOptions.Style.allCases, id: \.self) { style in
                    SummaryChoiceRow(title: style.rawValue, selected: aiOptions.style == style) {
                        aiOptions.style = style; activePopover = nil
                    }
                }
            }.padding(SummaryPopoverMetrics.contentPadding)
                .frame(width: SummaryPopoverMetrics.aiOptionWidth)
        }
    }

    private var listLabel: String {
        if selectedLists.isEmpty { return "所有" }
        if selectedLists.count == 1 { return selectedLists.first! }
        return "\(selectedLists.count)个清单"
    }
    private var moreLabel: String {
        let values = [options.filter.tagName.map { "#" + $0 }, options.filter.priority.map(\.title)].compactMap { $0 }
        return values.isEmpty ? "无" : values.joined(separator: "、")
    }
    private var dateLabel: String {
        if let preset = SummaryDateRange.Preset.allCases.first(where: { SummaryDateRange.preset($0, now: now, calendar: calendar) == range }) {
            return preset.rawValue + "（" + range.title(calendar: calendar) + "）"
        }
        return (range.kind == .custom ? "自定义（" : "") + range.title(calendar: calendar) + (range.kind == .custom ? "）" : "")
    }

    private var templateSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("模板").font(WFType.sectionSemibold)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    Button { onTemplate(nil) } label: { templateLabel("标准摘要") }.help("套用标准摘要配置")
                    ForEach(templates) { template in
                        Button { onTemplate(template) } label: { templateLabel(template.name) }.help("套用模板：" + template.name)
                    }
                    Button(action: onSaveTemplate) {
                        Image(systemName: "plus").font(.system(size: 16, weight: .light))
                            .foregroundStyle(WFColors.secondaryText).frame(width: 30, height: 30)
                            .background(WFColors.panelFill, in: Circle())
                    }.hoverTip("将当前筛选与显示配置存为模板").accessibilityLabel("添加摘要模板")
                }.buttonStyle(.borderless).padding(.vertical, 1)
            }
        }
    }
    private func templateLabel(_ text: String) -> some View {
        Text(text).font(WFType.supporting).foregroundStyle(WFColors.secondaryText)
            .lineLimit(1).frame(maxWidth: 132).padding(.horizontal, 14).frame(height: 30)
            .background(WFColors.panelFill, in: Capsule())
    }
    private var aiSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 8) {
                Text("内容优化").font(WFType.sectionSemibold)
                Text("AI").font(.system(size: 9, weight: .medium)).foregroundStyle(WFColors.summaryAction)
                    .padding(.horizontal, 3).padding(.vertical, 1)
                    .overlay { RoundedRectangle(cornerRadius: 2).stroke(WFColors.summaryAction.opacity(0.65), lineWidth: 0.8) }
                Spacer()
                Toggle("内容优化", isOn: $aiEnabled).toggleStyle(.switch).labelsHidden().controlSize(.mini)
            }
            if aiEnabled {
                Text("按当前任务重新组织摘要，先预览再采用。")
                    .font(WFType.supporting).foregroundStyle(WFColors.secondaryText).fixedSize(horizontal: false, vertical: true)
                VStack(spacing: 0) {
                    control("长度", value: aiOptions.length.rawValue, kind: .aiLength)
                    aiRowDivider
                    control("语言风格", value: aiOptions.style.rawValue, kind: .aiStyle)
                    aiRowDivider
                    aiTextRow("职业", placeholder: "可选，如产品经理", text: $aiOptions.profession)
                    aiRowDivider
                    aiTextRow("补充要求", placeholder: "可选，如不要用第一人称", text: $aiOptions.hint)
                }.background(WFColors.panelFill, in: RoundedRectangle(cornerRadius: 8))
                if let aiError {
                    Text(aiError).font(WFType.supporting).foregroundStyle(WFColors.danger).fixedSize(horizontal: false, vertical: true)
                    Button("AI 接入设置…", action: onConfigureAI).buttonStyle(.borderless)
                }
                if aiRunning { Button("取消生成", action: onCancelAI).buttonStyle(.borderless) }
                Button(action: onGenerateAI) {
                    HStack(spacing: 8) {
                        if aiRunning { ProgressView().controlSize(.small).tint(.white) }
                        Text(aiRunning ? "正在整理…" : "AI 优化").font(WFType.body)
                    }.foregroundStyle(.white).frame(maxWidth: .infinity).frame(height: 38)
                        .background(WFColors.summaryAction, in: RoundedRectangle(cornerRadius: 8))
                        .contentShape(RoundedRectangle(cornerRadius: 8))
                }.buttonStyle(.plain).disabled(aiRunning || !canGenerate)
                    .opacity(canGenerate ? 1 : 0.45)
            }
        }
    }
    private var aiRowDivider: some View {
        Divider().overlay(WFColors.border).padding(.leading, 16)
    }
    private func aiTextRow(_ title: String, placeholder: String, text: Binding<String>) -> some View {
        HStack(spacing: 8) {
            Text(title).font(WFType.body).foregroundStyle(WFColors.text)
            Spacer(minLength: 8)
            TextField(placeholder, text: text).textFieldStyle(.plain)
                .multilineTextAlignment(.trailing).font(WFType.body)
                .foregroundStyle(WFColors.secondaryText).frame(maxWidth: 190)
                .accessibilityLabel(title)
        }.padding(.horizontal, 16).frame(height: 38)
    }
    private func section<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title).font(WFType.sectionSemibold)
            VStack(spacing: 0, content: content).background(WFColors.panelFill, in: RoundedRectangle(cornerRadius: 8))
        }
    }
}

/// The value button is the presentation anchor; its label and row are not.
struct SummarySettingControl<Content: View>: View {
    let title: String
    let value: String
    @Binding var isPresented: Bool
    let width: CGFloat
    var anchor = ""
    @ViewBuilder let content: () -> Content
    @State private var hovered = false

    var body: some View {
        HStack(spacing: 8) {
            Text(title).font(WFType.body).foregroundStyle(WFColors.text)
            Spacer(minLength: 8)
            Button { isPresented.toggle() } label: {
                HStack(spacing: 8) {
                    Text(value).font(WFType.body).foregroundStyle(WFColors.secondaryText)
                        .lineLimit(1).truncationMode(.middle)
                    Image(systemName: "chevron.up.chevron.down").font(.system(size: 9))
                        .foregroundStyle(WFColors.tertiaryText)
                }
                .padding(.horizontal, 6).frame(height: 28)
                .background(isPresented || hovered ? WFColors.border.opacity(0.5) : .clear,
                            in: RoundedRectangle(cornerRadius: 6))
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain).accessibilityLabel(title + "：" + value)
            .workflowActionAnchor(anchor)
            .onHover { hovered = $0 }
            .background {
                AnchoredPropertyPanel(isPresented: $isPresented, width: width,
                    placement: .dropdown, focusPolicy: .panelWindow, title: "摘要：" + title, content: content)
            }
        }
        .padding(.horizontal, 16).frame(height: 38)
    }
}

#if DEBUG
struct SummaryChoiceFrames: PreferenceKey {
    static let defaultValue: [String: CGRect] = [:]
    static func reduce(value: inout [String: CGRect], nextValue: () -> [String: CGRect]) {
        value.merge(nextValue(), uniquingKeysWith: { _, latest in latest })
    }
}
#endif

/// 摘要弹层统一的勾选样式，与 BusinessMenu 的菜单勾一致。
struct SummaryCheckmark: View {
    let selected: Bool
    var body: some View {
        Image(systemName: "checkmark")
            .font(.system(size: 12, weight: .semibold))
            .foregroundStyle(WFColors.accent)
            .frame(width: 16)
            .opacity(selected ? 1 : 0)
    }
}

struct SummaryChoiceRow: View {
    let title: String
    let selected: Bool
    var symbol: String? = nil
    var emoji: String? = nil
    var checkOnLeft = false
    let action: () -> Void
    @Environment(\.isEnabled) private var isEnabled
    @State private var hovered = false
    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                if checkOnLeft { SummaryCheckmark(selected: selected) }
                if let emoji { Text(emoji).frame(width: 18) }
                else if let symbol { Image(systemName: symbol).frame(width: 18) }
                Text(title).lineLimit(2).multilineTextAlignment(.leading)
                    .frame(maxWidth: .infinity, alignment: .leading)
                if !checkOnLeft { SummaryCheckmark(selected: selected) }
            }
            .font(WFType.body).foregroundStyle(selected ? WFColors.accent : WFColors.text)
            .padding(.horizontal, 10)
            .frame(maxWidth: .infinity, minHeight: SummaryPopoverMetrics.rowHeight, alignment: .leading)
            .background(hovered && isEnabled ? WFColors.hover : Color.clear,
                        in: RoundedRectangle(cornerRadius: PopupMetrics.buttonCornerRadius))
            .contentShape(Rectangle())
        }.buttonStyle(.plain).onHover { hovered = $0 }.opacity(isEnabled ? 1 : 0.4)
            .transaction { $0.animation = nil }
            .accessibilityLabel(title).accessibilityValue(selected ? "已选中" : "未选中")
            .background {
                #if DEBUG
                GeometryReader { geometry in
                    Color.clear.preference(key: SummaryChoiceFrames.self,
                        value: [title: geometry.frame(in: .named("summary-choices"))])
                }
                #endif
            }
    }
}

struct SummaryPopoverActions: View {
    var canApply = true
    let onCancel: () -> Void
    let onApply: () -> Void
    var body: some View {
        PopupActionBar {
            PopupActionButton(title: "取消", action: onCancel)
                .keyboardShortcut(.cancelAction)
            PopupActionButton(title: "确定", primary: true, tint: WFColors.summaryAction, action: onApply)
                .keyboardShortcut(.defaultAction).disabled(!canApply)
        }
    }
}

struct SummaryDatePopover: View {
    let range: SummaryDateRange
    let now: Date
    let calendar: Calendar
    let onApply: (SummaryDateRange) -> Void
    let onCancel: () -> Void
    @State private var custom = false
    @State private var start: Date
    @State private var last: Date
    init(range: SummaryDateRange, now: Date, calendar: Calendar,
         onApply: @escaping (SummaryDateRange) -> Void, onCancel: @escaping () -> Void) {
        self.range = range; self.now = now; self.calendar = calendar; self.onApply = onApply; self.onCancel = onCancel
        _start = State(initialValue: range.start); _last = State(initialValue: range.lastDay(calendar: calendar))
    }
    var body: some View {
        VStack(spacing: 0) {
            if custom {
                VStack(alignment: .leading, spacing: 18) {
                    Text("自定义日期范围").font(WFType.sectionSemibold)
                    DatePicker("开始日期", selection: $start, displayedComponents: .date).datePickerStyle(.field)
                    DatePicker("结束日期", selection: $last, displayedComponents: .date).datePickerStyle(.field)
                    if last < calendar.startOfDay(for: start) {
                        Text("结束日期不能早于开始日期").font(WFType.supporting).foregroundStyle(WFColors.danger)
                    }
                }.padding(18)
                SummaryPopoverActions(canApply: selectedCustom != nil, onCancel: onCancel) {
                    if let selectedCustom { onApply(selectedCustom) }
                }
            } else {
                VStack(spacing: 2) {
                    ForEach(SummaryDateRange.Preset.allCases, id: \.self) { preset in
                        let value = SummaryDateRange.preset(preset, now: now, calendar: calendar)
                        SummaryChoiceRow(title: label(preset, value), selected: value == range) { onApply(value) }
                    }
                    SummaryChoiceRow(title: "自定义", selected: range.kind == .custom) { custom = true }
                }.padding(SummaryPopoverMetrics.contentPadding)
            }
        }.frame(width: SummaryPopoverMetrics.dateWidth).environment(\.calendar, calendar).environment(\.timeZone, calendar.timeZone)
    }
    private var selectedCustom: SummaryDateRange? { .custom(start: start, through: last, calendar: calendar) }
    private func label(_ preset: SummaryDateRange.Preset, _ value: SummaryDateRange) -> String {
        value.kind == .week ? preset.rawValue + "（" + value.title(calendar: calendar) + "）" : preset.rawValue
    }
}

struct SummaryStatusPopover: View {
    let onApply: (SummaryFilter.Status) -> Void
    let onCancel: () -> Void
    @State private var draft: SummaryFilter.Status
    init(status: SummaryFilter.Status, onApply: @escaping (SummaryFilter.Status) -> Void, onCancel: @escaping () -> Void) {
        self.onApply = onApply; self.onCancel = onCancel; _draft = State(initialValue: status)
    }
    var body: some View {
        VStack(spacing: 0) {
            VStack(spacing: 2) {
                ForEach(SummaryFilter.Status.allCases, id: \.self) { status in
                    SummaryChoiceRow(title: status.rawValue, selected: draft == status) { draft = status }
                        .help(status == .inProgress ? "已有子任务、检查项进展或专注记录。" : status.rawValue)
                }
            }.padding(SummaryPopoverMetrics.contentPadding)
            SummaryPopoverActions(onCancel: onCancel) { onApply(draft) }
        }.frame(width: SummaryPopoverMetrics.statusWidth)
    }
}

struct SummaryMorePopover: View {
    let tags: [String]
    let onApply: (SummaryFilter) -> Void
    let onCancel: () -> Void
    @State private var draft: SummaryFilter
    init(filter: SummaryFilter, tags: [String], onApply: @escaping (SummaryFilter) -> Void, onCancel: @escaping () -> Void) {
        self.tags = tags; self.onApply = onApply; self.onCancel = onCancel; _draft = State(initialValue: filter)
    }
    var body: some View {
        VStack(spacing: 0) {
            VStack(spacing: 18) {
                HStack {
                    Text("标签"); Spacer()
                    BusinessPicker("标签", selection: $draft.tagName, options:
                        [BusinessChoice(nil, "所有标签")] + tags.map { BusinessChoice(Optional($0), "#" + $0, symbol: "tag") })
                        .labelsHidden().frame(width: 176)
                }
                HStack {
                    Text("优先级"); Spacer()
                    BusinessPicker("优先级", selection: $draft.priority, options:
                        [BusinessChoice(nil, "所有优先级")] + TaskPriority.menuOrder.map { BusinessChoice(Optional($0), $0.title, symbol: "flag", color: $0.menuColor) })
                        .labelsHidden().frame(width: 176)
                }
            }.font(WFType.body).padding(18)
            SummaryPopoverActions(onCancel: onCancel) { onApply(draft) }
        }.frame(width: SummaryPopoverMetrics.moreWidth)
    }
}

struct SummaryListPopover: View {
    let lists: [String]
    let metas: [TaskListMeta]
    let folders: [TaskListFolder]
    let onApply: (Set<String>) -> Void
    let onCancel: () -> Void
    @State private var draft: Set<String>
    @State private var all: Bool
    @State private var expanded = true
    @State private var query = ""
    @State private var contentHeight: CGFloat?
    init(selected: Set<String>, lists: [String], metas: [TaskListMeta], folders: [TaskListFolder],
         onApply: @escaping (Set<String>) -> Void, onCancel: @escaping () -> Void) {
        self.lists = lists; self.metas = metas; self.folders = folders; self.onApply = onApply; self.onCancel = onCancel
        _draft = State(initialValue: selected); _all = State(initialValue: selected.isEmpty)
    }
    var body: some View {
        VStack(spacing: 0) {
            if lists.count > 7 {
                TextField("搜索清单", text: $query).textFieldStyle(.roundedBorder).padding(12)
            }
            ScrollView {
                VStack(spacing: 2) {
                    SummaryChoiceRow(title: "所有", selected: all, symbol: "tray.full") { all = true; draft = [] }
                    Divider().padding(.vertical, 5)
                    DisclosureGroup("所有清单", isExpanded: $expanded) {
                        if matches(TaskList.inbox.name) { listRow(TaskList.inbox.name) }
                        ForEach(topLevel, id: \.self) { listRow($0) }
                        ForEach(visibleFolders, id: \.name) { folder in
                            DisclosureGroup {
                                ForEach(members(folder.name), id: \.self) { listRow($0) }
                            } label: {
                                HStack {
                                    Label(folder.name, systemImage: "folder")
                                    Spacer()
                                    Button { toggleFolder(folder.name) } label: {
                                        Image(systemName: !all && Set(members(folder.name)).isSubset(of: draft) ? "checkmark.square.fill" : "square")
                                    }.buttonStyle(.plain).hoverTip("选择文件夹“\(folder.name)”下的清单")
                                        .accessibilityLabel("选择文件夹“\(folder.name)”下的清单")
                                }.font(WFType.body).padding(.vertical, 8)
                            }.padding(.leading, 8)
                        }
                    }.padding(.horizontal, 10).padding(.bottom, 6)
                }.padding(SummaryPopoverMetrics.contentPadding).fixedSize(horizontal: false, vertical: true)
                    .background(GeometryReader { geometry in
                        Color.clear
                            .onAppear { updateContentHeight(geometry.size.height) }
                            .onChange(of: geometry.size.height) { _, height in updateContentHeight(height) }
                    })
                    .compactScrollbars()
            }
            .frame(height: min(contentHeight ?? estimatedHeight, SummaryPopoverMetrics.maximumListHeight))
            SummaryPopoverActions(canApply: all || !draft.isEmpty, onCancel: onCancel) { onApply(all ? [] : draft) }
        }.frame(width: SummaryPopoverMetrics.listWidth)
    }
    private func updateContentHeight(_ height: CGFloat) {
        if height > 0 && abs(height - (contentHeight ?? 0)) > 0.5 { contentHeight = height }
    }
    private var estimatedHeight: CGFloat {
        80 + (expanded ? CGFloat(topLevel.count + visibleFolders.count + (matches(TaskList.inbox.name) ? 1 : 0)) * SummaryPopoverMetrics.rowHeight : 0)
    }
    private func matches(_ name: String) -> Bool { query.isEmpty || name.localizedCaseInsensitiveContains(query) }
    private var topLevel: [String] {
        lists.filter { name in name != TaskList.inbox.name && matches(name) && metas.first { $0.name == name }?.folderName == nil }
    }
    private var visibleFolders: [TaskListFolder] {
        let names = Set(metas.compactMap(\.folderName))
        let extra = names.subtracting(folders.map(\.name)).map { TaskListFolder(name: $0) }
        return (folders + extra).sorted { ($0.sortOrder, $0.name) < ($1.sortOrder, $1.name) }.filter { !members($0.name).isEmpty }
    }
    private func members(_ folder: String) -> [String] {
        lists.filter { name in matches(name) && metas.first { $0.name == name }?.folderName == folder }
    }
    private func toggleFolder(_ folder: String) {
        let names = Set(members(folder))
        if !all && names.isSubset(of: draft) { draft.subtract(names) } else { draft.formUnion(names) }
        all = false
    }
    private func listRow(_ name: String) -> some View {
        let meta = metas.first { $0.name == name }
        return SummaryChoiceRow(title: name, selected: !all && draft.contains(name),
            symbol: name == TaskList.inbox.name ? "tray" : "line.3.horizontal", emoji: meta?.icon) {
            all = false
            if !draft.insert(name).inserted { draft.remove(name) }
        }.padding(.leading, 8)
    }
}

/// 标题与详细内容固定，辅助信息可排序；显示选项与正文的层级一致。
struct SummaryContentPopover: View {
    @Binding var options: SummaryDocumentOptions
    @State private var expandedStyle: SummaryContentField?
    @State private var dragging: SummaryContentField?
    @State private var dropTarget: SummaryContentField?
    @State private var hoveredField: SummaryContentField?
    @State private var hoveredStyleChoice: String?

    private var metadataOrder: Binding<[SummaryContentField]> {
        Binding(get: { options.contentOrder.filter { $0 != .taskName } },
                set: { options.contentOrder = [.taskName] + $0 })
    }

    var body: some View {
        VStack(spacing: 2) {
            row(.taskName)
            row(.completedTime)
            ForEach(metadataOrder.wrappedValue, id: \.self) { field in
                row(field)
            }
            row(.detail)
        }
        .padding(SummaryPopoverMetrics.contentPadding)
        .onDisappear {
            expandedStyle = nil
            dragging = nil
            dropTarget = nil
            hoveredField = nil
            hoveredStyleChoice = nil
        }
    }

    @ViewBuilder
    private func row(_ field: SummaryContentField) -> some View {
        VStack(spacing: 2) {
            if field.isInline && field != .taskName {
                surface(field)
                    .onDrop(of: [UTType.text], delegate: SummaryContentDropDelegate(
                        target: field, order: metadataOrder,
                        dragging: $dragging, dropTarget: $dropTarget))
                    .contextMenu {
                        Button("上移") { moveMetadata(field, by: -1) }
                            .disabled(index(of: field) == 0)
                        Button("下移") { moveMetadata(field, by: 1) }
                            .disabled(index(of: field) >= metadataOrder.wrappedValue.count - 1)
                    }
            } else {
                surface(field)
            }
            if expandedStyle == field {
                styleChoices(for: field)
            }
        }
    }

    private func surface(_ field: SummaryContentField) -> some View {
        HStack(spacing: 6) {
            handle(field)
            toggle(field)
            styleControl(field)
        }
        .padding(.horizontal, 6)
        .frame(height: SummaryPopoverMetrics.rowHeight)
        .background((hoveredField == field || dropTarget == field) ? WFColors.hover : .clear,
                    in: RoundedRectangle(cornerRadius: 6))
        .contentShape(Rectangle())
        .onHover { inside in
            if inside { hoveredField = field }
            else if hoveredField == field { hoveredField = nil }
        }
        .accessibilityElement(children: .contain)
    }

    @ViewBuilder
    private func handle(_ field: SummaryContentField) -> some View {
        if field.isInline && field != .taskName {
            Image(systemName: "line.3.horizontal")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(WFColors.tertiaryText)
                .frame(width: 14, height: 28)
                .contentShape(Rectangle())
                .onDrag {
                    dragging = field
                    return NSItemProvider(object: field.rawValue as NSString)
                }
                .hoverTip("拖动调整顺序")
                .accessibilityLabel("调整\(field.rawValue)顺序")
        } else {
            Color.clear.frame(width: 14, height: 28)
        }
    }

    private func toggle(_ field: SummaryContentField) -> some View {
        Button { toggleField(field) } label: {
            HStack(spacing: 8) {
                SummaryCheckmark(selected: options.content.contains(field))
                Text(field.rawValue)
                    .font(WFType.body)
                    .foregroundStyle(options.content.contains(field) ? WFColors.accent : WFColors.text)
                    .lineLimit(1)
                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("显示内容：\(field.rawValue)")
        .accessibilityValue(options.content.contains(field) ? "已选中" : "未选中")
        .workflowActionAnchor("summary.content.field." + field.anchor)
    }

    @ViewBuilder
    private func styleControl(_ field: SummaryContentField) -> some View {
        if let label = options.contentStyles.styleLabel(for: field) {
            Button { expandedStyle = expandedStyle == field ? nil : field } label: {
                HStack(spacing: 4) {
                    Text(label)
                        .font(WFType.supporting)
                        .foregroundStyle(WFColors.secondaryText)
                        .lineLimit(1)
                    Image(systemName: "chevron.down")
                        .font(.system(size: 8, weight: .semibold))
                        .foregroundStyle(WFColors.tertiaryText)
                }
                .padding(.horizontal, 6)
                .frame(height: 28)
                .background(expandedStyle == field ? WFColors.border.opacity(0.5) : .clear,
                            in: RoundedRectangle(cornerRadius: 6))
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("\(field.rawValue)样式：\(label)")
            .workflowActionAnchor("summary.content.style." + field.anchor)
        }
    }

    private func styleChoices(for field: SummaryContentField) -> some View {
        VStack(spacing: 2) {
            ForEach(choices(for: field)) { choice in
                Button(action: choice.apply) {
                    HStack(spacing: 8) {
                        SummaryCheckmark(selected: choice.selected)
                        Text(choice.title)
                            .font(WFType.supporting)
                            .foregroundStyle(WFColors.text)
                        Spacer(minLength: 0)
                    }
                    .padding(.horizontal, 10)
                    .frame(height: SummaryPopoverMetrics.styleRowHeight)
                    .background(hoveredStyleChoice == choice.id ? WFColors.hover : .clear,
                                in: RoundedRectangle(cornerRadius: 5))
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .onHover { inside in
                    if inside { hoveredStyleChoice = choice.id }
                    else if hoveredStyleChoice == choice.id { hoveredStyleChoice = nil }
                }
                .accessibilityLabel(choice.title)
                .accessibilityValue(choice.selected ? "已选中" : "未选中")
                .workflowActionAnchor("summary.content.style.\(field.anchor).\(choice.id)")
            }
        }
        .padding(.leading, 38)
    }

    private struct StyleChoice: Identifiable {
        let id: String
        let title: String
        let selected: Bool
        let apply: () -> Void
    }

    private func choices(for field: SummaryContentField) -> [StyleChoice] {
        switch field {
        case .completedTime:
            return SummaryDateStyle.allCases.map { style in
                StyleChoice(id: style.anchor, title: style.rawValue,
                            selected: options.contentStyles.completedTime == style) {
                    apply(style, to: field)
                }
            }
        case .taskTime:
            return SummaryDateStyle.allCases.map { style in
                StyleChoice(id: style.anchor, title: style.rawValue,
                            selected: options.contentStyles.taskTime == style) {
                    apply(style, to: field)
                }
            }
        case .list:
            return SummaryListStyle.allCases.map { style in
                StyleChoice(id: style.anchor, title: style.rawValue,
                            selected: options.contentStyles.list == style) {
                    options.contentStyles.list = style
                    enable(field)
                }
            }
        case .detail:
            return SummaryDetailStyle.allCases.map { style in
                StyleChoice(id: style.anchor, title: style.rawValue,
                            selected: options.contentStyles.detail == style) {
                    options.contentStyles.detail = style
                    enable(field)
                }
            }
        default:
            return []
        }
    }

    private func apply(_ style: SummaryDateStyle, to field: SummaryContentField) {
        options.contentStyles.setDateStyle(style, for: field)
        enable(field)
    }

    private func enable(_ field: SummaryContentField) {
        options.content.insert(field)
        expandedStyle = nil
    }

    private func toggleField(_ field: SummaryContentField) {
        if !options.content.insert(field).inserted { options.content.remove(field) }
        if !options.content.contains(field), expandedStyle == field { expandedStyle = nil }
    }

    private func index(of field: SummaryContentField) -> Int {
        metadataOrder.wrappedValue.firstIndex(of: field) ?? 0
    }
    private func moveMetadata(_ field: SummaryContentField, by offset: Int) {
        var order = metadataOrder.wrappedValue
        guard let from = order.firstIndex(of: field) else { return }
        let to = min(max(0, from + offset), order.count - 1)
        guard to != from else { return }
        order.remove(at: from); order.insert(field, at: to); metadataOrder.wrappedValue = order
    }
}

private struct SummaryContentDropDelegate: DropDelegate {
    let target: SummaryContentField
    @Binding var order: [SummaryContentField]
    @Binding var dragging: SummaryContentField?
    @Binding var dropTarget: SummaryContentField?

    func dropEntered(info: DropInfo) {
        guard dragging != nil else { return }
        dropTarget = target
    }

    func dropExited(info: DropInfo) {
        if dropTarget == target { dropTarget = nil }
    }

    func dropUpdated(info: DropInfo) -> DropProposal? {
        DropProposal(operation: .move)
    }

    func performDrop(info: DropInfo) -> Bool {
        defer {
            dragging = nil
            dropTarget = nil
        }
        guard let dragging, dragging != target,
              let from = order.firstIndex(of: dragging),
              let to = order.firstIndex(of: target) else { return false }
        let moved = order.remove(at: from)
        order.insert(moved, at: to)
        return true
    }
}
