import AppKit
import SwiftUI

struct TaskTemplateGalleryView: View {
    @ObservedObject var templateStore: TemplateStore
    var apply: (TaskTemplate) -> UUID?
    var title: String
    var kind: TemplateKind
    var builtIns: [TaskTemplate]
    var onDismiss: () -> Void
    var onApplied: ((UUID) -> Void)? = nil

    @State private var searchText: String
    @State private var showingManagement = false
    @State private var visibleScreenSize: CGSize?
    @State private var applicationGate = TaskTemplateApplyGate()

    private static let preferredSize = CGSize(width: 720, height: 520)

    init(templateStore: TemplateStore,
         apply: @escaping (TaskTemplate) -> UUID?,
         title: String,
         kind: TemplateKind = .task,
         builtIns: [TaskTemplate] = BuiltInTaskTemplates.all,
         onDismiss: @escaping () -> Void,
         onApplied: ((UUID) -> Void)? = nil,
         initialSearchText: String = "") {
        self.templateStore = templateStore
        self.apply = apply
        self.title = title
        self.kind = kind
        self.builtIns = builtIns
        self.onDismiss = onDismiss
        self.onApplied = onApplied
        _searchText = State(initialValue: initialSearchText)
    }

    /// 任务侧入口：把 workspace 的 createFromTemplate 包装成注入的 apply 闭包，
    /// 保留原有 `workspace:` 调用方式（UI 渲染测试依赖该签名）。
    init(workspace: TaskWorkspaceModel,
         templateStore: TemplateStore,
         onDismiss: @escaping () -> Void,
         onApplied: ((UUID) -> Void)? = nil,
         initialSearchText: String = "") {
        self.init(templateStore: templateStore,
                  apply: { TemplateApplier.apply($0, to: workspace) },
                  title: "任务模板",
                  onDismiss: onDismiss,
                  onApplied: onApplied,
                  initialSearchText: initialSearchText)
    }

    private var contentSize: CGSize {
        guard let visibleScreenSize else { return Self.preferredSize }
        return CGSize(
            width: min(Self.preferredSize.width, max(1, visibleScreenSize.width - 40)),
            height: min(Self.preferredSize.height, max(1, visibleScreenSize.height - 40))
        )
    }

    private var templates: [TaskTemplateCatalogItem] {
        TaskTemplateCatalog.items(userTemplates: templateStore.templates,
                                  builtIns: builtIns, kind: kind, query: searchText)
    }

    var body: some View {
        ZStack {
            if showingManagement && templateStore.templates.contains(where: { $0.templateKind == kind }) {
                TemplateManagementView(templateStore: templateStore, kind: kind) {
                    showingManagement = false
                }
            } else {
                gallery
                if showingManagement {
                    Color.black.opacity(0.12)
                        .overlay {
                            TemplateEducationView(kind: kind) {
                                showingManagement = false
                            }
                            .background {
                                GeometryReader { proxy in
                                    Color.clear.preference(
                                        key: TaskTemplateGalleryControlFramesKey.self,
                                        value: ["education": proxy.frame(in: .named("task-template-gallery"))]
                                    )
                                }
                            }
                        }
                        .zIndex(1)
                }
            }
        }
        .frame(width: contentSize.width, height: contentSize.height)
        .workfollowPopupSurface()
        .overlay(alignment: .topTrailing) {
            GalleryWindowScreenReader { size in
                guard visibleScreenSize != size else { return }
                visibleScreenSize = size
            }
            .frame(width: 0, height: 0)
            .accessibilityHidden(true)
        }
        .coordinateSpace(name: "task-template-gallery")
        .background(PopupEscapeRouter(depth: 1, onEscape: dismissTopLayer))
        .onExitCommand(perform: dismissTopLayer)
    }

    private func dismissTopLayer() {
        if showingManagement { showingManagement = false }
        else { onDismiss() }
    }

    private var gallery: some View {
        VStack(spacing: 0) {
            header

            ScrollView {
                if templates.isEmpty {
                    emptyResults
                        .frame(maxWidth: .infinity, minHeight: 360)
                } else {
                    LazyVGrid(columns: Array(
                        repeating: GridItem(.flexible(), spacing: 12, alignment: .top), count: 3
                    ), alignment: .center, spacing: 12) {
                        ForEach(templates, id: \.template.id) { item in
                            Button {
                                guard applicationGate.begin() else { return }
                                guard let taskID = apply(item.template) else {
                                    applicationGate.finish(succeeded: false)
                                    return
                                }
                                applicationGate.finish(succeeded: true)
                                onApplied?(taskID)
                                onDismiss()
                            } label: {
                                TaskTemplateCard(item: item)
                                    .background {
                                        GeometryReader { proxy in
                                            Color.clear.preference(
                                                key: TaskTemplateGalleryFramesKey.self,
                                                value: [item.template.id: proxy.frame(in: .named("task-template-gallery"))]
                                            )
                                        }
                                    }
                            }
                            .buttonStyle(.plain)
                            .accessibilityIdentifier("task-template-card-\(item.template.id.uuidString)")
                        }
                    }
                    .padding(.horizontal, 2)
                    .padding(.vertical, 2)
                }
            }
            .compactScrollbars()
            .scrollIndicators(.visible)
            .padding(.top, 18)

            Button("管理模板") {
                showingManagement = true
            }
            .font(WFType.listTitleMedium)
            .foregroundStyle(WFColors.accent)
            .buttonStyle(.plain)
            .accessibilityIdentifier("task-template-management")
            .background {
                GeometryReader { proxy in
                    Color.clear.preference(
                        key: TaskTemplateGalleryControlFramesKey.self,
                        value: ["management": proxy.frame(in: .named("task-template-gallery"))]
                    )
                }
            }
            .padding(.top, 18)
        }
        .padding(.horizontal, 24)
        .padding(.top, 18)
        .padding(.bottom, 20)
        .workfollowPopupSurface()
    }

    private var header: some View {
        let slotWidth = min(190, max(132, contentSize.width * 0.28))
        // 右侧 = 搜索框 + 关闭钮；左槽位补上同样的宽度，标题保持光学居中。
        let closeSlot: CGFloat = 30
        return HStack(spacing: 0) {
            Color.clear.frame(width: slotWidth + closeSlot, height: 40)
            Spacer(minLength: 0)
            Text(title)
                .font(WFType.detailTitle)
                .lineLimit(1)
                .fixedSize()
            Spacer(minLength: 0)
            searchField.frame(width: slotWidth)
            closeButton
                .frame(width: closeSlot, height: 40)
        }
        .frame(height: 34)
    }

    /// 弹层没有标题栏，此前只能靠 Esc 或选完模板关闭；补一个显式关闭钮。
    private var closeButton: some View {
        Button {
            onDismiss()
        } label: {
            Image(systemName: "xmark")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(WFColors.secondaryText)
                .frame(width: 26, height: 26)
                .background(WFColors.content, in: Circle())
                .overlay(Circle().stroke(WFColors.border))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .hoverTip("关闭")
        .accessibilityLabel("关闭")
        .accessibilityIdentifier("task-template-close")
    }

    private var searchField: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 16))
                .foregroundStyle(WFColors.tertiaryText)
                .accessibilityHidden(true)
            TextField("搜索", text: $searchText)
                .textFieldStyle(.plain)
                .font(WFType.body)
                .accessibilityIdentifier("task-template-search")
        }
        .padding(.horizontal, 14)
        .frame(height: 32)
        .background(WFColors.content)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(WFColors.borderStrong, lineWidth: 1)
        }
    }

    private var emptyResults: some View {
        VStack(spacing: WFSpace.sm) {
            Image(systemName: searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                  ? "doc.text.image" : "magnifyingglass")
                .font(.system(size: 27))
                .foregroundStyle(WFColors.tertiaryText)
            Text(searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                 ? "暂无模板" : "没有匹配的模板")
                .font(WFType.body)
                .foregroundStyle(WFColors.secondaryText)
        }
    }
}

private struct GalleryWindowScreenReader: NSViewRepresentable {
    var onScreenSize: (CGSize) -> Void

    func makeNSView(context: Context) -> ScreenProbe {
        let view = ScreenProbe()
        view.onScreenSize = onScreenSize
        return view
    }

    func updateNSView(_ view: ScreenProbe, context: Context) {
        view.onScreenSize = onScreenSize
        view.reportScreenSize()
    }

    final class ScreenProbe: NSView {
        var onScreenSize: ((CGSize) -> Void)?

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            reportScreenSize()
        }

        override func viewDidChangeBackingProperties() {
            super.viewDidChangeBackingProperties()
            reportScreenSize()
        }

        func reportScreenSize() {
            guard let size = window?.screen?.visibleFrame.size else { return }
            DispatchQueue.main.async { [weak self] in
                self?.onScreenSize?(size)
            }
        }
    }
}

struct TaskTemplateGalleryFramesKey: PreferenceKey {
    static var defaultValue: [UUID: CGRect] = [:]

    static func reduce(value: inout [UUID: CGRect], nextValue: () -> [UUID: CGRect]) {
        value.merge(nextValue(), uniquingKeysWith: { _, newer in newer })
    }
}

struct TaskTemplateGalleryControlFramesKey: PreferenceKey {
    static var defaultValue: [String: CGRect] = [:]

    static func reduce(value: inout [String: CGRect], nextValue: () -> [String: CGRect]) {
        value.merge(nextValue(), uniquingKeysWith: { _, newer in newer })
    }
}

private final class TaskTemplateApplyGate {
    private var isApplying = false
    private var hasApplied = false

    func begin() -> Bool {
        guard !isApplying, !hasApplied else { return false }
        isApplying = true
        return true
    }

    func finish(succeeded: Bool) {
        isApplying = false
        if succeeded { hasApplied = true }
    }
}
