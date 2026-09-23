import SwiftUI

struct IconRailView: View {
    @ObservedObject var workspace: PreviewWorkspace
    @ObservedObject var navigation: AppNavigation
    @EnvironmentObject private var environment: AppEnvironment
    @Environment(\.openSettings) private var openSettings

    var body: some View {
        VStack(spacing: WFSpace.md) {
            railButton(.today, symbol: "checklist", title: "任务",
                       selected: navigation.destination.isTaskList)
            railButton(.notes, symbol: "text.alignleft", title: "笔记",
                       selected: navigation.destination.isNotes)
            railButton(.calendar, symbol: "calendar", title: "日历",
                       selected: navigation.destination == .calendar)
            railButton(.matrix, symbol: "square.grid.2x2", title: "四象限",
                       selected: navigation.destination == .matrix)
            Spacer()
            Button { environment.commandPalettePresented = true } label: {
                Image(systemName: "magnifyingglass")
                    .frame(width: WFMetrics.controlHeight, height: WFMetrics.controlHeight)
            }.help("快速打开（⌘K）").accessibilityLabel("快速打开")
            Button { openSettings() } label: {
                Image(systemName: "slider.horizontal.3")
                    .frame(width: WFMetrics.controlHeight, height: WFMetrics.controlHeight)
            }.help("设置（⌘,）").accessibilityLabel("设置")
        }
        .font(.system(size: WFMetrics.icon))
        .buttonStyle(.plain)
        .foregroundStyle(WFColors.secondaryText)
        .padding(.vertical, WFSpace.lg)
        .frame(width: WFMetrics.railWidth)
        .background(WFColors.canvas)
    }

    private func railButton(_ destination: NativeDestination, symbol: String,
                            title: String, selected: Bool) -> some View {
        Button { environment.navigate(to: destination) } label: {
            Image(systemName: symbol)
                .foregroundStyle(selected ? WFColors.accent : WFColors.secondaryText)
                .frame(width: WFMetrics.controlHeight, height: WFMetrics.controlHeight)
                .background(selected ? WFColors.selection : .clear,
                            in: RoundedRectangle(cornerRadius: WFMetrics.corner))
        }.help(title).accessibilityLabel(title)
    }
}

struct NavigationColumnView: View {
    @ObservedObject var workspace: PreviewWorkspace
    @ObservedObject var navigation: AppNavigation
    @EnvironmentObject private var environment: AppEnvironment
    var onNavigate: () -> Void = {}

    private var destinations: [NativeDestination] {
        if navigation.destination.isNotes { return [.notes, .notesTrash] }
        if navigation.destination == .calendar { return [.calendar] }
        if navigation.destination == .matrix { return [.matrix] }
        return [.today, .inbox, .completed, .trash]
    }

    var body: some View {
        VStack(alignment: .leading, spacing: WFSpace.xs) {
            Text(navigation.destination.isNotes ? "笔记" : "工作空间")
                .font(WFType.supporting).foregroundStyle(WFColors.secondaryText)
                .padding(.horizontal, WFSpace.sm).padding(.bottom, WFSpace.sm)
            ForEach(destinations) { destination in
                Button {
                    environment.navigate(to: destination)
                    onNavigate()
                } label: {
                    HStack(spacing: WFSpace.md) {
                        Image(systemName: destination.symbol).frame(width: WFMetrics.icon)
                        Text(destination.title)
                        Spacer(minLength: WFSpace.xs)
                        let count = workspace.projectedTasks(for: destination).count
                        if count > 0 {
                            Text("\(count)").font(WFType.supporting)
                                .foregroundStyle(WFColors.secondaryText)
                        }
                    }
                    .font(WFType.navigation)
                    .foregroundStyle(navigation.destination == destination
                                     ? WFColors.accent : WFColors.text)
                    .padding(.horizontal, WFSpace.sm)
                    .frame(height: WFMetrics.controlHeight)
                    .background(navigation.destination == destination
                                ? WFColors.selection : .clear,
                                in: RoundedRectangle(cornerRadius: WFMetrics.corner))
                    .contentShape(Rectangle())
                }.buttonStyle(.plain)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, WFSpace.sm)
        .padding(.vertical, WFSpace.xl)
        .frame(maxHeight: .infinity)
        .background(WFColors.content)
    }
}
