import SwiftUI

struct CommandPaletteView: View {
    @ObservedObject var navigation: AppNavigation
    @EnvironmentObject private var environment: AppEnvironment
    @State private var query = ""
    @State private var selectedIndex = 0
    @FocusState private var focused: Bool

    private var entries: [CommandPaletteEntry] {
        CommandPaletteProjection.entries(
            query: query,
            tasks: environment.taskWorkspace.allTasks,
            notes: environment.notesWorkspace.notes,
            creationList: environment.taskWorkspace.activeList ?? TaskList.inbox.name,
            schedulesForToday: navigation.destination == .today,
            now: environment.taskWorkspace.clock(),
            calendar: environment.taskWorkspace.calendar)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: WFSpace.md) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(WFColors.secondaryText)
                TextField("搜索任务、笔记或命令…", text: $query)
                    .textFieldStyle(.plain)
                    .focused($focused)
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

            Divider()

            ScrollView {
                LazyVStack(spacing: WFSpace.xs) {
                    ForEach(Array(entries.enumerated()), id: \.element.id) { index, entry in
                        Button { run(entry) } label: {
                            HStack(spacing: WFSpace.md) {
                                Image(systemName: entry.symbol)
                                    .frame(width: WFMetrics.icon)
                                    .foregroundStyle(entry.kind == .createTask
                                                     ? WFColors.accent : WFColors.secondaryText)
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(entry.title)
                                        .fontWeight(entry.kind == .createTask ? .semibold : .regular)
                                        .lineLimit(1)
                                    Text(entry.subtitle).font(WFType.supporting)
                                        .foregroundStyle(WFColors.secondaryText).lineLimit(1)
                                }
                                Spacer(minLength: 0)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, WFSpace.md)
                            .padding(.vertical, WFSpace.sm)
                            .background(index == selectedIndex ? WFColors.selection : .clear,
                                        in: RoundedRectangle(cornerRadius: WFMetrics.corner))
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .padding(.horizontal, WFSpace.sm)
                    }
                }
                .padding(.vertical, WFSpace.sm)
            }

            Divider()

            // 底部快捷键提示条（Flutter 命令面板对齐）。
            HStack(spacing: WFSpace.sm) {
                Text("↑↓ 选择 · ↵ 执行 · esc 关闭")
                    .font(WFType.supporting)
                    .foregroundStyle(WFColors.secondaryText)
                Spacer(minLength: 0)
                Text("打勾命令面板")
                    .font(WFType.supporting)
                    .fontWeight(.semibold)
                    .foregroundStyle(WFColors.secondaryText)
            }
            .padding(.horizontal, WFSpace.lg)
            .padding(.vertical, WFSpace.sm)
            .background(WFColors.canvas)
        }
        .frame(minWidth: 320, idealWidth: 500, maxWidth: 560,
               minHeight: 300, idealHeight: 420, maxHeight: 520)
        .onAppear { focused = true }
        .onChange(of: query) { _, _ in selectedIndex = 0 }
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

    private func run(_ entry: CommandPaletteEntry) {
        switch entry.action {
        case let .createTask(title):
            guard CommandPaletteProjection.createTask(
                title, workspace: environment.taskWorkspace, navigation: navigation).taskID != nil else { return }
        case let .openTask(id):
            guard CommandPaletteProjection.openTask(
                id, workspace: environment.taskWorkspace, navigation: navigation) else { return }
        case let .openNote(id):
            guard CommandPaletteProjection.openNote(
                id, workspace: environment.notesWorkspace,
                taskWorkspace: environment.taskWorkspace, navigation: navigation) else { return }
        case let .navigate(destination):
            environment.navigate(to: destination)
        case .toggleAppearance:
            environment.appearance = CommandPaletteProjection.nextAppearance(after: environment.appearance)
        }
        environment.commandPalettePresented = false
    }
}
