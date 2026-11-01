import AppKit
import SwiftUI

struct RootShellView: View {
    // The shell routes the model to independently observing features; its
    // layout depends on navigation/window geometry, not task mutations.
    let workspace: TaskWorkspaceModel
    @ObservedObject var navigation: AppNavigation
    @EnvironmentObject private var environment: AppEnvironment
    @Environment(\.mainWindowRailInset) private var railInset
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    #if DEBUG
    @Environment(\.popupContentObservation) private var popupObservation
    @Environment(\.workflowActionObservation) private var workflowObservation
    #endif
    @StateObject private var pageCache = WorkspacePageCache()
    @StateObject private var selectionMemory = WorkspaceSelectionMemory()
    private var pageKey: String {
        if navigation.destination.isNotes { return "notes" }
        if TaskWorkspaceModel.scope(for: navigation.destination) != nil { return "tasks" }
        return navigation.destination.rawValue
    }

    private func pageContent(destination: NativeDestination, navigationVisible: Bool,
                             windowWidth: CGFloat) -> AnyView {
        switch destination {
        case .focus:
            return AnyView(FocusWorkspaceView(store: environment.focusStore, workspace: workspace,
                onSelectRecordTask: { id in environment.openTask(id) }))
        case .trash: return AnyView(TaskTrashView(workspace: workspace))
        case .summary: return AnyView(SummaryWorkspaceView(store: environment.summaryStore, workspace: workspace,
                                                          context: environment.weeklyPlanning))
        case .countdown: return AnyView(CountdownWorkspaceView(store: environment.countdownStore))
        case .meetings: return AnyView(MeetingWorkspaceView(store: environment.meetingStore))
        case .aiChat: return AnyView(AIChatWorkspaceView(store: environment.aiChat))
        case .notes, .notesTrash:
            return AnyView(NotesWorkspaceView(notes: environment.notesWorkspace, navigation: pageCache.navigation(for: "notes", appNavigation: navigation, belongsToPage: { $0.isNotes }),
                                             tasks: workspace, navigationVisible: navigationVisible,
                                             windowWidth: windowWidth))
        case .calendar: return AnyView(CalendarWorkspaceView(workspace: workspace, systemCalendar: environment.systemCalendar))
        case .matrix: return AnyView(MatrixWorkspaceView(workspace: workspace))
        default:
            return AnyView(TaskWorkspaceView(workspace: workspace,
                                             navigation: pageCache.navigation(for: "tasks",
                                                appNavigation: navigation,
                                                belongsToPage: { TaskWorkspaceModel.scope(for: $0) != nil }),
                                             navigationVisible: navigationVisible))
        }
    }

    private func hostedPage(destination: NativeDestination, navigationVisible: Bool,
                            windowWidth: CGFloat) -> AnyView {
        let content = pageContent(destination: destination, navigationVisible: navigationVisible,
                                  windowWidth: windowWidth)
            .environmentObject(environment)
            .environment(\.taskFocusStore, environment.focusStore)
            .environment(\.mainWindowRailInset, railInset)
            .environment(\.colorScheme, colorScheme)
            .environment(\.workfollowBackgroundTheme, environment.backgroundTheme)
            .environment(\.workfollowBackgroundIntensity, environment.backgroundIntensity)
            .environment(\.workfollowMaterial, environment.appearanceMaterial)
            .environment(\.workfollowPageCanvasActive, environment.backgroundTheme.isThemed)
            .disabled(environment.storageNeedsReload)
            .hidesSystemFocusEffect()
        #if DEBUG
        return AnyView(content.environment(\.popupContentObservation, popupObservation).environment(\.workflowActionObservation, workflowObservation).tint(WFColors.accent))
        #else
        return AnyView(content.tint(WFColors.accent))
        #endif
    }

    /// 缓存页只在"页面结构可能变化"时重设 rootView；切换清单/智能清单时
    /// 目标页的这组值不变，SwiftUI 可沿用已有图，只做挂载与布局。
    ///
    /// 不含 destination：同一 pageKey 的页面结构相同，页面内部的跳转由各页
    /// 自己的 navigation bridge 推送（SwiftUI 观察得到），不必重建整页。
    private func pageContentSignature(navigationVisible: Bool,
                                      windowWidth: CGFloat) -> String {
        var parts = [
            navigationVisible ? "1" : "0",
            "\(Int(windowWidth.rounded()))",
            "\(Int(railInset.rounded()))",
            environment.storageNeedsReload ? "1" : "0",
            String(describing: colorScheme),
            environment.backgroundTheme.rawValue,
            environment.backgroundIntensity.rawValue,
            environment.appearanceMaterial.rawValue
        ]
        #if DEBUG
        parts.append(popupObservation == nil ? "0" : "1")
        parts.append(workflowObservation == nil ? "0" : "1")
        #endif
        return parts.joined(separator: "|")
    }

    var body: some View {
        GeometryReader { geometry in
            // 笔记页 AI 右扩时，壳层宽度按扩展前计算，导航列不会因为窗口变宽而突然出现。
            let shellWidth = environment.notesAIFrozenWindowWidth ?? geometry.size.width
            let navigationVisible = shellWidth >= WFMetrics.navigationBreakpoint
            let destination = navigation.destination
            let notesFolderSuppressed = destination.isNotes
                && (environment.notesFolderPaneHidden || environment.notesFolderPaneAutoHidden)
            let showsNavigationColumn = navigationVisible && environment.sidebarVisible
                && !notesFolderSuppressed
                && destination != .calendar && destination != .matrix
                && destination != .countdown && destination != .meetings
                && destination != .focus && destination != .aiChat
            let glassActive = WFGlassSupport.isActive(
                environment.appearanceMaterial,
                reduceTransparency: reduceTransparency || WFGlassSupport.systemReduceTransparency)
            let leadingWidth = WFMetrics.railWidth
                + (showsNavigationColumn ? WFMetrics.navigationWidth : 0)
            HStack(spacing: 0) {
                IconRailView(workspace: workspace, navigation: navigation,
                             onNavigate: environment.navigate,
                             onOpenQuickOpen: { environment.commandPalettePresented = true },
                             sync: environment.systemReminders,
                             onRetrySync: environment.retryRemindersSync,
                             onOpenSyncSettings: { environment.settingsSection = .appleSync })
                    .overlay(alignment: .trailing) { ShellColumnSeparator() }
                // 这些模块自己带页面内导航（或只有一个入口），不再给二级导航列。
                if showsNavigationColumn {
                    NavigationColumnView(workspace: workspace, navigation: navigation,
                                         filterStore: environment.filterStore)
                        .frame(width: WFMetrics.navigationWidth)
                        .overlay(alignment: .trailing) { ShellColumnSeparator() }
                }
                WorkspacePageHost(cache: pageCache, pageKey: pageKey,
                                  contentSignature: pageContentSignature(
                                    navigationVisible: navigationVisible,
                                    windowWidth: geometry.size.width),
                                  // 任务列之间切换只做显隐；离开任务模块仍卸载，
                                  // 保留笔记/会议等页面的 onDisappear 清理。
                                  keepsMounted: TaskWorkspaceModel.scope(for: destination) != nil,
                                  content: hostedPage(destination: destination,
                                                      navigationVisible: navigationVisible,
                                                      windowWidth: geometry.size.width))
            }
            // 小伙伴蹲在图标栏的空白下半段：那里只有底部三个按钮，竖排留白最多，
            // 不压中栏/正文，也不为它改列表或导航列的布局。矮窗口直接不出现。
            .overlay(alignment: .bottomLeading) {
                if environment.companionEnabled, geometry.size.height >= 600 {
                    CompanionPerchView(director: environment.companion,
                                       character: environment.companionCharacter)
                        .padding(.leading, (WFMetrics.railWidth - CompanionLayout.perchMascotSize) / 2)
                        .padding(.bottom, CompanionLayout.railBottomReserve)
                        .transition(.opacity)
                }
            }
            .background {
                ZStack {
                    if environment.backgroundTheme.isThemed {
                        WorkFollowBackgroundView(theme: environment.backgroundTheme,
                                                 intensity: environment.backgroundIntensity,
                                                 animated: false, layer: .base)
                    } else if glassActive {
                        // 玻璃模式且无主题：图标栏与导航列让出底色，
                        // 但先压一层内容色底衬，桌面只淡淡透出，避免过透影响可读性。
                        HStack(spacing: 0) {
                            WFColors.content.opacity(0.70)
                                .frame(width: leadingWidth)
                            WFColors.content
                        }
                    } else {
                        WFColors.content
                    }
                    // 整窗一层连续画布：页面与各栏在主题开启时都不再各自铺底，
                    // 多栏页面的列边界因此没有深浅台阶。
                    WorkfollowPageCanvas(theme: environment.backgroundTheme,
                                         intensity: environment.backgroundIntensity,
                                         leadingWidth: leadingWidth)
                    // 动效单独叠在底纱之上：底纱只压底图，气泡/云朵/极光带
                    // 不再一起被洗成近白。
                    if environment.backgroundTheme.isThemed {
                        WorkFollowBackgroundView(theme: environment.backgroundTheme,
                                                 intensity: environment.backgroundIntensity,
                                                 animated: environment.backgroundAnimated,
                                                 layer: .motion)
                            .opacity(NativeBackgroundMotion.opacity(
                                for: colorScheme, intensity: environment.backgroundIntensity))
                    }
                }
            }
            .environment(\.workfollowBackgroundTheme, environment.backgroundTheme)
            .environment(\.workfollowBackgroundIntensity, environment.backgroundIntensity)
            .environment(\.workfollowMaterial, environment.appearanceMaterial)
            .environment(\.workfollowPageCanvasActive, environment.backgroundTheme.isThemed)
            .disabled(environment.storageNeedsReload)
            .onAppear {
                selectionMemory.connect(workspace: workspace, notes: environment.notesWorkspace, navigation: navigation)
            }
            .onChange(of: navigation.destination) { _, _ in
                navigation.taskSelectionToPreserveOnNextNavigation = nil
                workspace.clearBulkSelection()
            }
        }
        .ignoresSafeArea(.container, edges: .top)
        .sheet(isPresented: $environment.commandPalettePresented) {
            CommandPaletteView(navigation: navigation, session: environment.searchSession, workspace: workspace, notes: environment.notesWorkspace)
                .environmentObject(environment)
        }
        .sheet(isPresented: $environment.welcomeGuideWelcomePresented) {
            WelcomeGuideWelcomeView(
                onStart: {
                    environment.welcomeGuideWelcomePresented = false
                    environment.openWelcomeGuide()
                },
                onSkip: { environment.welcomeGuideWelcomePresented = false })
        }
        // HUD 浮在最外层：作为 overlay 不参与布局，出现/消失时中栏与检查器
        // 的高度不回流；底部状态条仍用 safeAreaInset 占位，避免提示盖住重试入口。
        .overlay(alignment: .bottom) {
            FeedbackHostView(center: environment.feedback)
        }
        .safeAreaInset(edge: .bottom) {
            VStack(spacing: 0) {
                if let error = environment.storageError {
                    // 保存失败不是"看一眼就好"：重试成功后提示自己消失。
                    HStack(spacing: 8) {
                        Text(error).font(.caption).foregroundStyle(WFColors.danger)
                        Button("重试") { environment.retryStorage() }
                            .buttonStyle(.link)
                            .font(.caption)
                    }
                    .padding(8)
                }
                if environment.storageNeedsReload {
                    Text("数据已更新，请重新打开应用以加载。")
                        .font(.caption).foregroundStyle(.secondary).padding(8)
                }
            }
        }
        .hidesSystemFocusEffect()
        // 放在最外层：根级 sheet（命令面板、欢迎页）也要继承主题，弹层才有底色。
        .environment(\.workfollowBackgroundTheme, environment.backgroundTheme)
        .environment(\.workfollowBackgroundIntensity, environment.backgroundIntensity)
        .environment(\.workfollowMaterial, environment.appearanceMaterial)
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
            // 焦点页保留原来的占位 Divider：它的渲染基准按含 1pt 分隔线的布局标定，
            // 本次只把任务页的列起点对齐滴答，不对焦点页重标定。
            Divider()
            FocusWorkspaceView(store: store, workspace: workspace,
                               onSelectRecordTask: onSelectRecordTask)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}

/// 外壳列分隔线：覆盖在列的右边缘绘制，**不参与布局**。
///
/// 原来用 `Divider()` 在 `HStack` 里占 1pt，两处叠加后列表列从 276pt 起，
/// 滴答同窗口实测为 274pt（`AXScrollArea @274,137 358x751`，列表 outline 的
/// 1pt 边框压在导航列最后一像素上）。改成 overlay 后列宽分配与滴答一致，
/// 线仍然可见、不可命中。
private struct ShellColumnSeparator: View {
    @Environment(\.workfollowMaterial) private var material
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    var body: some View {
        if WFGlassSupport.isActive(material,
                                   reduceTransparency: reduceTransparency || WFGlassSupport.systemReduceTransparency) {
            Color.clear.frame(width: WFMetrics.divider)
        } else {
            Rectangle()
                .fill(Color(nsColor: .separatorColor))
                .frame(width: WFMetrics.divider)
                .frame(maxHeight: .infinity)
                .allowsHitTesting(false)
        }
    }
}

private struct TaskWorkspaceView: View {
    @TaskLayoutObserved var workspace: TaskWorkspaceModel
    @ObservedObject var navigation: AppNavigation
    let navigationVisible: Bool
    @EnvironmentObject private var environment: AppEnvironment
    @Environment(\.colorScheme) private var colorScheme
    @State private var dragOrigin: CGFloat?
    @AppStorage(TaskDetailLayout.defaultsKey) private var detailLayoutRaw =
        TaskDetailLayout.sidePeek.rawValue

    private var detailLayout: TaskDetailLayout {
        TaskDetailLayout(rawValue: detailLayoutRaw) ?? .sidePeek
    }

    /// 视图偏好的键（与 TaskListView 同一套派生，真值源唯一）。
    private var preferenceKey: String {
        TaskViewScopeKey.key(destination: navigation.destination,
                             activeList: workspace.activeList, activeTag: workspace.activeTag,
                             activeFilterID: workspace.activeFilter?.id)
    }

    var body: some View {
        GeometryReader { geometry in
            let wide = geometry.size.width >= WFMetrics.splitMinimum
            // 看板/时间线是**宽视图**：滴答里它们占满内容区，不该被"列表列"的上限
            // （listMaximum = 470）夹住——实测截图里那会让时间线只剩左边一条窄栏。
            let modes = TaskListViewMode.availableOptions(destination: navigation.destination,
                activeList: workspace.activeList, activeTag: workspace.activeTag,
                activeFilterID: workspace.activeFilter?.id)
            let wideView = environment.viewPreferences.viewMode(for: preferenceKey, availableModes: modes) != .list
            let layout = TaskWorkspaceLayout(availableWidth: geometry.size.width,
                preferredListWidth: workspace.taskListPaneWidth, wideView: wideView,
                hasSelection: workspace.selectedTaskID != nil, hasBulkSelection: !workspace.bulkSelection.isEmpty)
            let maximum = layout.maximumListWidth
            let boundedWidth = layout.listWidth
            if wide {
                HStack(spacing: 0) {
                    TaskListView(workspace: workspace, navigation: navigation,
                                 navigationVisible: navigationVisible)
                        // 保持同一个列表宿主，只改宽度，保留输入草稿与滚动位置。
                        .frame(width: boundedWidth)
                    if layout.showsInspector {
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
                            TaskInspectorShell(workspace: workspace, showBack: false, allowsClosing: true,
                                               commentStore: environment.taskCommentStore)
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
                if detailLayout == .popup {
                    // 窄窗口选「弹窗」：列表留在原位，详情以带阴影的浮层出现。
                    ZStack(alignment: .topTrailing) {
                        TaskListView(workspace: workspace, navigation: navigation,
                                     navigationVisible: navigationVisible)
                        TaskInspectorShell(workspace: workspace, showBack: false,
                                           allowsClosing: true,
                                           commentStore: environment.taskCommentStore)
                            .frame(width: min(420, max(320, geometry.size.width - 64)),
                                   height: max(280, geometry.size.height - 32))
                            .background {
                                WFGlassSurface(shape: RoundedRectangle(cornerRadius: 12),
                                               fallback: environment.backgroundTheme.popupFillOrFallback(
                                                WFColors.content, for: colorScheme))
                            }
                            .overlay {
                                RoundedRectangle(cornerRadius: 12)
                                    .stroke(WFColors.border, lineWidth: 1)
                                    .allowsHitTesting(false)
                            }
                            .shadow(color: .black.opacity(0.18), radius: 18, y: 6)
                            .padding(.vertical, 16)
                            .padding(.trailing, 16)
                    }
                } else {
                    // 「侧边栏」：详情贴右边缘停靠，列表仍从左侧露出来（不撑满整个内容区）。
                    ZStack(alignment: .topTrailing) {
                        TaskListView(workspace: workspace, navigation: navigation,
                                     navigationVisible: navigationVisible)
                        TaskInspectorShell(workspace: workspace, showBack: false,
                                           allowsClosing: true,
                                           commentStore: environment.taskCommentStore)
                            .frame(width: min(440, max(320, geometry.size.width * 0.72)),
                                   height: geometry.size.height)
                            // 详情盖在列表上：必须自己带不透明底色，整窗画布生效后
                            // 页面铺底已经让出，没有这层会透出后面的列表。
                            .background(environment.backgroundTheme.popupFillOrFallback(
                                WFColors.content, for: colorScheme))
                            .overlay(alignment: .leading) {
                                Rectangle().fill(WFColors.border).frame(width: 1)
                            }
                    }
                }
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
                    }.buttonStyle(.plain).hoverTip("显示导航")
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
        .workfollowPageSurface(0.90)
    }
}
