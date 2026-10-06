import AppKit
import SwiftUI

struct RootShellView: View {
    // The shell routes the model to independently observing features; its
    // layout depends on navigation/window geometry, not task mutations.
    let workspace: TaskWorkspaceModel
    @ObservedObject var navigation: AppNavigation
    @EnvironmentObject private var environment: AppEnvironment

    var body: some View {
        GeometryReader { geometry in
            let navigationVisible = geometry.size.width >= WFMetrics.navigationBreakpoint
            Group {
                if navigation.destination == .focus {
                    FocusWorkspaceShellView(
                        workspace: workspace,
                        navigation: navigation,
                        store: environment.focusStore,
                        onNavigate: environment.navigate,
                        onOpenQuickOpen: { environment.commandPalettePresented = true },
                        onSelectRecordTask: { id in
                            workspace.select(id)
                            navigation.destination = .allTasks
                        })
                } else {
                    HStack(spacing: 0) {
                        IconRailView(workspace: workspace, navigation: navigation,
                                     onNavigate: environment.navigate,
                                     onOpenQuickOpen: { environment.commandPalettePresented = true })
                        Divider()
                        if navigationVisible, environment.sidebarVisible,
                           navigation.destination != .calendar, navigation.destination != .matrix,
                           navigation.destination != .countdown {
                            NavigationColumnView(workspace: workspace, navigation: navigation,
                                                 filterStore: environment.filterStore)
                                .frame(width: WFMetrics.navigationWidth)
                            Divider()
                        }
                        if navigation.destination == .trash {
                            TaskTrashView(workspace: workspace)
                        } else if navigation.destination == .summary {
                            SummaryWorkspaceView(store: environment.summaryStore, workspace: workspace)
                        } else if navigation.destination == .countdown {
                            CountdownWorkspaceView(store: environment.countdownStore)
                        } else if navigation.destination.isNotes {
                            NotesWorkspaceView(notes: environment.notesWorkspace, navigation: navigation, tasks: workspace,
                                               navigationVisible: navigationVisible)
                        } else if navigation.destination == .calendar {
                            CalendarWorkspaceView(workspace: workspace)
                                .id(navigation.destination)
                        } else if navigation.destination == .matrix {
                            MatrixWorkspaceView(workspace: workspace)
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
                }
            }
            .background(WFColors.content)
            .onChange(of: navigation.destination) { _, destination in
                let routedTaskID = navigation.taskSelectionToPreserveOnNextNavigation
                navigation.taskSelectionToPreserveOnNextNavigation = nil
                if routedTaskID != workspace.selectedTaskID { workspace.select(nil) }
                workspace.clearBulkSelection()

                if !destination.isNotes {
                    environment.notesWorkspace.selectedID = nil
                } else if let selected = environment.notesWorkspace.selected,
                          (selected.deletedAt != nil) != (destination == .notesTrash) {
                    environment.notesWorkspace.selectedID = nil
                }
            }
        }
        .ignoresSafeArea(.container, edges: .top)
        .sheet(isPresented: $environment.commandPalettePresented) {
            CommandPaletteView(navigation: navigation)
                .environmentObject(environment)
        }
        .safeAreaInset(edge: .bottom) {
            // 反馈 HUD 挂载在底部居中：空场不占布局，有内容时也不遮挡点击。
            VStack(spacing: 0) {
                FeedbackHostView(center: environment.feedback)
                if let error = environment.storageError {
                    Text(error).font(.caption).foregroundStyle(.red).padding(8)
                }
            }
        }
    }
}

/// Reusable production shell for Focus; also provides a stable host for render contracts.
struct FocusWorkspaceShellView: View {
    @ObservedObject var workspace: TaskWorkspaceModel
    @ObservedObject var navigation: AppNavigation
    @ObservedObject var store: FocusStore
    let onNavigate: (NativeDestination) -> Void
    let onOpenQuickOpen: () -> Void
    let onSelectRecordTask: (UUID) -> Void

    var body: some View {
        HStack(spacing: 0) {
            IconRailView(workspace: workspace, navigation: navigation,
                         onNavigate: onNavigate, onOpenQuickOpen: onOpenQuickOpen)
            Divider()
            FocusWorkspaceView(store: store, workspace: workspace,
                               onSelectRecordTask: onSelectRecordTask)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}

private struct TaskWorkspaceView: View {
    @ObservedObject var workspace: TaskWorkspaceModel
    @ObservedObject var navigation: AppNavigation
    let navigationVisible: Bool
    @EnvironmentObject private var environment: AppEnvironment
    @State private var dragOrigin: CGFloat?

    /// 视图偏好的键（与 TaskListView 同一套派生，真值源唯一）。
    private var preferenceKey: String {
        TaskViewScopeKey.key(destination: navigation.destination,
                             activeList: workspace.activeList, activeTag: workspace.activeTag)
    }

    var body: some View {
        GeometryReader { geometry in
            let wide = geometry.size.width >= WFMetrics.splitMinimum
            // 看板/时间线是**宽视图**：滴答里它们占满内容区，不该被"列表列"的上限
            // （listMaximum = 470）夹住——实测截图里那会让时间线只剩左边一条窄栏。
            let wideView = environment.viewPreferences.viewMode(for: preferenceKey) != .list
            // 宽视图下详情面板**按需出现**：没选中任务时（本来只显示空态插画）
            // 整块让给时间线/看板。
            let showsInspector = !wideView || workspace.selectedTaskID != nil
            let reserved = showsInspector ? WFMetrics.inspectorMinimum + WFMetrics.divider : 0
            let maximum = max(WFMetrics.listMinimum,
                              min(wideView ? geometry.size.width : WFMetrics.listMaximum,
                                  geometry.size.width - reserved))
            let boundedWidth = min(max(workspace.taskListPaneWidth, WFMetrics.listMinimum), maximum)
            if wide {
                HStack(spacing: 0) {
                    TaskListView(workspace: workspace, navigation: navigation,
                                 navigationVisible: navigationVisible)
                        // 宽视图吃满剩余宽度；列表模式沿用用户拖拽的宽度。
                        .frame(width: wideView ? maximum : boundedWidth)
                    if showsInspector {
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
                                            workspace.setTaskListPaneWidth(min(max((dragOrigin ?? boundedWidth)
                                                + value.translation.width, WFMetrics.listMinimum), maximum))
                                        }
                                        .onEnded { _ in dragOrigin = nil })
                            }
                        // 右栏是选中状态的纯投影：批量选中非空 → 批量面板；否则详情。
                        if workspace.bulkSelection.isEmpty {
                            TaskInspectorShell(workspace: workspace, showBack: false)
                                .frame(maxWidth: .infinity, maxHeight: .infinity)
                        } else {
                            TaskBatchPanelView(workspace: workspace)
                                .frame(maxWidth: .infinity, maxHeight: .infinity)
                        }
                    }
                }
            } else if !workspace.bulkSelection.isEmpty {
                TaskBatchPanelView(workspace: workspace)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
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
    @EnvironmentObject private var environment: AppEnvironment

    var body: some View {
        VStack(alignment: .leading, spacing: WFSpace.xl) {
            HStack(spacing: WFSpace.md) {
                if !navigationVisible {
                    Button { showNavigation.toggle() } label: {
                        Image(systemName: "sidebar.left")
                    }.buttonStyle(.plain).help("显示导航")
                        .background(AnchoredPropertyPanel(isPresented: $showNavigation,
                                                          width: WFMetrics.navigationWidth) {
                            NavigationColumnView(workspace: workspace, navigation: navigation,
                                                 filterStore: environment.filterStore,
                                                 onNavigate: { showNavigation = false })
                                .frame(width: WFMetrics.navigationWidth, height: 260)
                        })
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
