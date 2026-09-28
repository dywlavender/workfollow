import SwiftUI

/// 一次新建请求：页面把「新任务默认落在哪一天、什么优先级」交给浮层里的新建卡，
/// 卡自己只持有草稿（对齐 Flutter `createTaskFromComposer` /
/// `createTaskInMatrixQuadrant` 的调用约定：页面给 fallback 与预置值）。
struct PlanningComposerRequest: Equatable {
    /// 用户没有动日期时用的日程。日历给被点那天的 0 点，四象限给象限默认日程。
    var fallback: TaskSchedule
    /// 打开时就带上的日程；nil 表示卡上显示「设置日期」（四象限的新建就是这一种）。
    var preset: TaskSchedule?
    /// 打开时的优先级：四象限用象限默认值，日历为无。
    var priority: TaskPriority
}

/// 日历与四象限共用的浮层宿主：把「正在新建什么 / 正在编辑哪个任务」变成贴着被点
/// 元素弹出的两个小面板，尺寸与呈现方式都按原版——
///
/// - 编辑器：`showTaskFloatingEditor` 的 **400 × 356**，挂在被点任务条/任务行的
///   下方居中。
/// - 新建卡：`showTaskEditorPopover` 的 **320 × 212**，挂在被点元素下方右缘对齐，
///   打开即聚焦标题（原版 `focusPolicy: searchField`）。
///
/// 内容与原版一样是**同一套**编辑面：编辑器就是任务页右侧详情栏那个
/// `TaskInspectorShell`（差在左上返回与 Esc 关浮层，即原版 `_isPopup` 的那一支），
/// 新建卡则与列表的快速输入行共用同一批零件（日期面板、优先级、清单）。
struct PlanningWorkspaceChrome: View {
    @ObservedObject var workspace: TaskWorkspaceModel

    /// 被点元素在页面坐标系里的矩形，由页面在点击时经 `PlanningAnchorProbe` 写进来。
    let anchor: PlanningAnchorRef

    @Binding var request: PlanningComposerRequest?
    @Binding var editingTaskID: UUID?

    /// 浮层是主窗口之外的第二层视图树（`NSHostingView` 那套已经不用了），但内容里
    /// 仍可能有 `@EnvironmentObject`（`TaskInspectorShell` 要 AppEnvironment），
    /// 所以照既有做法显式注入。
    @EnvironmentObject private var environment: AppEnvironment

    var body: some View {
        ZStack(alignment: .topLeading) {
            if let request {
                PlanningOverlayLayer(anchor: anchor,
                                     placement: .bottomEnd,
                                     size: CGSize(width: WFPlanningOverlayMetrics.composerWidth,
                                                  height: WFPlanningOverlayMetrics.composerHeight),
                                     onDismiss: closeComposer) {
                    TaskQuickComposer(workspace: workspace,
                                      fallbackSchedule: request.fallback,
                                      presetSchedule: request.preset,
                                      presetPriority: request.priority,
                                      requestClose: closeComposer)
                        .environmentObject(environment)
                }
            } else if editingTaskID != nil, workspace.selectedTask != nil {
                PlanningOverlayLayer(anchor: anchor,
                                     placement: .bottomCenter,
                                     size: CGSize(width: WFPlanningOverlayMetrics.editorWidth,
                                                  height: WFPlanningOverlayMetrics.editorHeight),
                                     onDismiss: closeEditor) {
                    TaskInspectorShell(workspace: workspace,
                                       showBack: true,
                                       onRequestClose: closeEditor)
                        .environmentObject(environment)
                }
            }
        }
        // 原版的浮层会跟着它的任务一起消失（`_closeWhenMissing`）：任务被删掉或不再
        // 被选中时，编辑器不该留在屏幕上一个已不存在的东西上。
        .onChange(of: workspace.selectedTaskID) { _, value in
            if value == nil, editingTaskID != nil { closeEditor() }
        }
    }

    private func closeComposer() {
        request = nil
        if workspace.selectedTaskID != nil { workspace.select(nil) }
    }

    private func closeEditor() {
        editingTaskID = nil
        if workspace.selectedTaskID != nil { workspace.select(nil) }
    }
}
