import AppKit
import SwiftUI

struct RootShellView: View {
    @ObservedObject var workspace: TaskWorkspaceModel
    @ObservedObject var navigation: AppNavigation
    @EnvironmentObject private var environment: AppEnvironment

    var body: some View {
        GeometryReader { geometry in
            let navigationVisible = geometry.size.width >= WFMetrics.navigationBreakpoint
            HStack(spacing: 0) {
                IconRailView(workspace: workspace, navigation: navigation)
                Divider()
                if navigationVisible {
                    NavigationColumnView(workspace: workspace, navigation: navigation)
                        .frame(width: WFMetrics.navigationWidth)
                    Divider()
                }
                if navigation.destination == .trash {
                    TaskTrashView(workspace: workspace)
                } else if navigation.destination.isNotes {
                    NotesWorkspaceView(notes: environment.notesWorkspace, navigation: navigation, tasks: workspace)
                } else if navigation.destination == .matrix || navigation.destination == .calendar {
                    PlanningWorkspaceView(workspace: workspace, matrix: navigation.destination == .matrix)
                        .id(navigation.destination)
                } else if navigation.destination.isTaskList {
                    TaskWorkspaceView(workspace: workspace,
                                      navigation: navigation,
                                      navigationVisible: navigationVisible)
                } else {
                    ModuleShellView(workspace: workspace, navigation: navigation,
                                    navigationVisible: navigationVisible)
                }
            }
            .background(WFColors.content)
        }
        .sheet(isPresented: $environment.commandPalettePresented) {
            CommandPaletteView(navigation: navigation)
                .environmentObject(environment)
        }
        .safeAreaInset(edge: .bottom) {
            if let error = environment.storageError {
                Text(error).font(.caption).foregroundStyle(.red).padding(8)
            }
        }
    }
}

private struct TaskWorkspaceView: View {
    @ObservedObject var workspace: TaskWorkspaceModel
    let navigation: AppNavigation
    let navigationVisible: Bool
    @State private var listWidth = WFMetrics.listPreferred
    @State private var dragOrigin: CGFloat?

    var body: some View {
        GeometryReader { geometry in
            let wide = geometry.size.width >= WFMetrics.splitMinimum
            let maximum = max(WFMetrics.listMinimum,
                              min(WFMetrics.listMaximum,
                                  geometry.size.width - WFMetrics.inspectorMinimum - WFMetrics.divider))
            let boundedWidth = min(max(listWidth, WFMetrics.listMinimum), maximum)
            if wide {
                HStack(spacing: 0) {
                    TaskListView(workspace: workspace, navigation: navigation,
                                 navigationVisible: navigationVisible)
                        .frame(width: boundedWidth)
                    Rectangle().fill(WFColors.border).frame(width: WFMetrics.divider)
                        .overlay {
                            Color.clear.frame(width: WFSpace.sm).contentShape(Rectangle())
                                .onHover { inside in
                                    if inside { NSCursor.resizeLeftRight.push() }
                                    else { NSCursor.pop() }
                                }
                                .gesture(DragGesture(minimumDistance: 1)
                                    .onChanged { value in
                                        if dragOrigin == nil { dragOrigin = boundedWidth }
                                        listWidth = min(max((dragOrigin ?? boundedWidth)
                                            + value.translation.width, WFMetrics.listMinimum), maximum)
                                    }
                                    .onEnded { _ in dragOrigin = nil })
                        }
                    TaskInspectorShell(workspace: workspace, showBack: false)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            } else if workspace.selectedTask != nil {
                TaskInspectorShell(workspace: workspace, showBack: true)
            } else {
                TaskListView(workspace: workspace, navigation: navigation,
                             navigationVisible: navigationVisible)
            }
        }
    }
}

private struct ModuleShellView: View {
    @ObservedObject var workspace: TaskWorkspaceModel
    @ObservedObject var navigation: AppNavigation
    let navigationVisible: Bool
    @State private var showNavigation = false

    var body: some View {
        VStack(alignment: .leading, spacing: WFSpace.xl) {
            HStack(spacing: WFSpace.md) {
                if !navigationVisible {
                    Button { showNavigation.toggle() } label: {
                        Image(systemName: "sidebar.left")
                    }.buttonStyle(.plain).help("显示导航")
                        .popover(isPresented: $showNavigation) {
                            NavigationColumnView(workspace: workspace, navigation: navigation) { showNavigation = false }
                                .frame(width: WFMetrics.navigationWidth, height: 260)
                        }
                }
                Label(navigation.destination.title, systemImage: navigation.destination.symbol)
                    .font(WFType.pageTitle)
            }
            Spacer()
            VStack(spacing: WFSpace.md) {
                Image(systemName: navigation.destination.symbol).font(.largeTitle)
                Text("这里还没有内容").font(WFType.body)
            }
            .foregroundStyle(WFColors.secondaryText)
            .frame(maxWidth: .infinity)
            Spacer()
        }
        .padding(WFSpace.xl)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(WFColors.content)
    }
}
