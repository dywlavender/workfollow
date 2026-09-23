import AppKit
import SwiftUI

struct RootShellView: View {
    @ObservedObject var workspace: PreviewWorkspace
    @EnvironmentObject private var environment: AppEnvironment

    var body: some View {
        GeometryReader { geometry in
            let navigationVisible = geometry.size.width >= WFMetrics.navigationBreakpoint
            HStack(spacing: 0) {
                IconRailView(workspace: workspace)
                Divider()
                if navigationVisible {
                    NavigationColumnView(workspace: workspace)
                        .frame(width: WFMetrics.navigationWidth)
                    Divider()
                }
                if workspace.destination.isTaskList {
                    TaskWorkspaceView(workspace: workspace,
                                      navigationVisible: navigationVisible)
                } else {
                    ModuleShellView(workspace: workspace,
                                    navigationVisible: navigationVisible)
                }
            }
            .background(WFColors.content)
        }
        .sheet(isPresented: $environment.commandPalettePresented) {
            CommandPaletteView(workspace: workspace)
                .environmentObject(environment)
        }
    }
}

private struct TaskWorkspaceView: View {
    @ObservedObject var workspace: PreviewWorkspace
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
                    TaskListView(workspace: workspace, navigationVisible: navigationVisible)
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
                TaskListView(workspace: workspace, navigationVisible: navigationVisible)
            }
        }
    }
}

private struct ModuleShellView: View {
    @ObservedObject var workspace: PreviewWorkspace
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
                            NavigationColumnView(workspace: workspace) { showNavigation = false }
                                .frame(width: WFMetrics.navigationWidth, height: 260)
                        }
                }
                Label(workspace.destination.title, systemImage: workspace.destination.symbol)
                    .font(WFType.pageTitle)
            }
            Spacer()
            VStack(spacing: WFSpace.md) {
                Image(systemName: workspace.destination.symbol).font(.largeTitle)
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
