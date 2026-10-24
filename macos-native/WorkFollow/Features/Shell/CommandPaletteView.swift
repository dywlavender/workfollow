import SwiftUI

struct CommandPaletteView: View {
    @ObservedObject var navigation: AppNavigation
    @EnvironmentObject private var environment: AppEnvironment
    @ObservedObject var session: WorkspaceSearchSession
    private var query: String { session.query }
    private var selectedIndex: Int {
        get { session.selectedIndex }
        nonmutating set { session.selectedIndex = newValue }
    }
    @FocusState private var focused: Bool

    private var entries: [CommandPaletteEntry] {
        session.entries(workspace: environment.taskWorkspace, notes: environment.notesWorkspace.notes,
                        destination: navigation.destination)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: WFSpace.md) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(WFColors.secondaryText)
                TextField("搜索任务、笔记或命令…", text: $session.query)
                    .textFieldStyle(.plain)
                    .focused($focused)
                    .onKeyPress(keys: [.return], phases: .down) { key in
                        guard key.modifiers.contains(.command) else { return .ignored }
                        createFromQuery()
                        return .handled
                    }
                    .onSubmit(runSelected)
                    .onKeyPress(.downArrow) { moveSelection(1) }
                    .onKeyPress(.upArrow) { moveSelection(-1) }
                    .onKeyPress(.escape) {
                        environment.commandPalettePresented = false
                        return .handled
                    }
                Button("取消") { environment.commandPalettePresented = false }
                    .keyboardShortcut(.cancelAction)
            }
            .padding(WFSpace.lg)

            if session.showAll { filters }
            Divider()

            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: WFSpace.xs) {
                        if entries.isEmpty {
                            Text("没有符合条件的结果").font(WFType.body).foregroundStyle(WFColors.secondaryText).padding(24)
                        }
                        ForEach(Array(entries.enumerated()), id: \.element.id) { index, entry in
                            Button { run(entry) } label: {
                                HStack(spacing: WFSpace.md) {
                                    Image(systemName: entry.symbol)
                                        .frame(width: WFMetrics.icon)
                                        .foregroundStyle(entry.kind == .createTask
                                                         ? WFColors.accent : WFColors.secondaryText)
                                    VStack(alignment: .leading, spacing: 3) {
                                        highlighted(entry.title)
                                            .fontWeight(entry.kind == .createTask ? .semibold : .regular)
                                            .lineLimit(1)
                                        Text(entry.subtitle).font(WFType.supporting)
                                            .foregroundStyle(WFColors.secondaryText).lineLimit(1)
                                        if let snippet = entry.snippet {
                                            highlighted(snippet).font(WFType.supporting)
                                                .foregroundStyle(WFColors.secondaryText).lineLimit(2)
                                        }
                                    }
                                    Spacer(minLength: 0)
                                    if entry.kind == .createTask {
                                        Text("⌘↵").font(WFType.supporting)
                                            .foregroundStyle(WFColors.secondaryText)
                                    }
                                }
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.horizontal, WFSpace.md)
                                .padding(.vertical, WFSpace.sm)
                                .background(index == selectedIndex ? WFColors.selection : .clear,
                                            in: RoundedRectangle(cornerRadius: WFMetrics.corner))
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain).workflowActionAnchor("search." + entry.id)
                            .padding(.horizontal, WFSpace.sm)
                        }
                    }
                    .padding(.vertical, WFSpace.sm)
                }
                .onChange(of: selectedIndex) { _, index in
                    if entries.indices.contains(index) { proxy.scrollTo(entries[index].id) }
                }
                .onChange(of: query) { _, _ in
                    if let first = entries.first { proxy.scrollTo(first.id, anchor: .top) }
                }
            }

            Divider()

            HStack {
                Button(session.showAll ? "返回快捷搜索" : "查看全部结果") {
                    session.showAll.toggle(); selectedIndex = 0
                }.buttonStyle(.borderless)
                Spacer()
                if session.showAll {
                    Text("\(entries.count) 条结果").font(WFType.supporting).foregroundStyle(WFColors.secondaryText)
                }
            }.padding(.horizontal, WFSpace.lg).padding(.vertical, WFSpace.sm)
            // 底部快捷键提示条（Flutter 命令面板对齐）。
            HStack(spacing: WFSpace.sm) {
                Text("↑↓ 选择 · ↵ 打开 · ⌘↵ 新建 · esc 关闭")
                    .font(WFType.supporting)
                    .foregroundStyle(WFColors.secondaryText)
                Spacer(minLength: 0)
                Text("WorkFollow")
                    .font(WFType.supporting)
                    .fontWeight(.semibold)
                    .foregroundStyle(WFColors.secondaryText)
            }
            .padding(.horizontal, WFSpace.lg)
            .padding(.vertical, WFSpace.sm)
            .background(WFColors.canvas)
        }
        .background(WFColors.content)
        .frame(width: session.showAll ? 700 : 540, height: session.showAll ? 580 : 420)
        .onAppear { focused = true }
        .onChange(of: query) { _, _ in selectedIndex = 0 }
        .onChange(of: session.content) { _, _ in selectedIndex = 0 }
        .onChange(of: session.status) { _, _ in selectedIndex = 0 }
        .onChange(of: session.list) { _, _ in selectedIndex = 0 }
    }

    private var filters: some View {
        HStack {
            BusinessMenu(session.content.rawValue) {
                BusinessMenuChoices(selection: $session.content, options: WorkspaceSearchSession.Content.allCases.map {
                    BusinessChoice($0, $0.rawValue)
                })
            }
            if session.content != .notes {
                BusinessMenu(session.list ?? "所有清单") {
                    BusinessMenuChoices(selection: $session.list, options:
                        [BusinessChoice<String?>(nil, "所有清单")] + environment.taskWorkspace.availableListNames.map {
                            BusinessChoice<String?>($0, $0)
                        })
                }
                BusinessMenu(session.status.rawValue) {
                    BusinessMenuChoices(selection: $session.status, options: WorkspaceSearchSession.Status.allCases.map {
                        BusinessChoice($0, $0.rawValue)
                    })
                }
            }
            Spacer()
        }.buttonStyle(.borderless).padding(.horizontal, WFSpace.lg).padding(.bottom, WFSpace.sm)
    }

    private func moveSelection(_ offset: Int) -> KeyPress.Result {
        guard !entries.isEmpty else { return .ignored }
        selectedIndex = (selectedIndex + offset + entries.count) % entries.count
        return .handled
    }

    private func runSelected() {
        guard entries.indices.contains(selectedIndex) else { return }
        run(entries[selectedIndex])
    }

    private func createFromQuery() {
        let values = CommandPaletteProjection.entries(query: query, tasks: [], notes: [],
            creationList: environment.taskWorkspace.activeList ?? TaskList.inbox.name,
            schedulesForToday: navigation.destination == .today)
        guard let entry = values.first(where: { $0.kind == .createTask }) else { return }
        run(entry)
    }

    private func highlighted(_ value: String) -> Text {
        let query = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return Text(value) }
        var text = Text("")
        var start = value.startIndex
        while let range = value.range(of: query, options: .caseInsensitive, range: start..<value.endIndex) {
            text = text + Text(String(value[start..<range.lowerBound]))
                + Text(String(value[range])).bold().foregroundColor(WFColors.accent)
            start = range.upperBound
        }
        return text + Text(String(value[start...]))
    }

    private func run(_ entry: CommandPaletteEntry) {
        session.open(entry, environment: environment, navigation: navigation)
    }
}
