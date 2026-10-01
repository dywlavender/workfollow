import AppKit
import SwiftUI

struct TaskTemplateGalleryView: View {
    @ObservedObject var workspace: TaskWorkspaceModel
    @ObservedObject var templateStore: TemplateStore
    var onDismiss: () -> Void
    var onApplied: ((UUID) -> Void)? = nil

    @State private var searchText: String
    @State private var showingManagement = false
    @State private var visibleScreenSize: CGSize?
    @State private var applicationGate = TaskTemplateApplyGate()

    private static let preferredSize = CGSize(width: 720, height: 520)

    init(workspace: TaskWorkspaceModel,
         templateStore: TemplateStore,
         onDismiss: @escaping () -> Void,
         onApplied: ((UUID) -> Void)? = nil,
         initialSearchText: String = "") {
        self.workspace = workspace
        self.templateStore = templateStore
        self.onDismiss = onDismiss
        self.onApplied = onApplied
        _searchText = State(initialValue: initialSearchText)
    }

    private var contentSize: CGSize {
        guard let visibleScreenSize else { return Self.preferredSize }
        return CGSize(
            width: min(Self.preferredSize.width, max(1, visibleScreenSize.width - 40)),
            height: min(Self.preferredSize.height, max(1, visibleScreenSize.height - 40))
        )
    }

    private var templates: [TaskTemplateCatalogItem] {
        TaskTemplateCatalog.items(userTemplates: templateStore.templates, query: searchText)
    }

    var body: some View {
        ZStack {
            if showingManagement && !templateStore.templates.isEmpty {
                TemplateManagementView(templateStore: templateStore) {
                    showingManagement = false
                }
            } else {
                gallery
                if showingManagement {
                    Color.black.opacity(0.12)
                        .overlay {
                            TemplateEducationView {
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
        .background(WFColors.content)
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
                                guard let taskID = TemplateApplier.apply(item.template, to: workspace) else {
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
            .scrollIndicators(.visible)
            .padding(.top, 18)

            Button("管理模板") {
                showingManagement = true
            }
            .font(.system(size: 14, weight: .medium))
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
        .background(WFColors.content)
    }

    private var header: some View {
        let slotWidth = min(190, max(132, contentSize.width * 0.28))
        return HStack(spacing: 0) {
            Color.clear.frame(width: slotWidth, height: 40)
            Spacer(minLength: 0)
            Text("任务模板")
                .font(.system(size: 18, weight: .semibold))
                .lineLimit(1)
                .fixedSize()
            Spacer(minLength: 0)
            searchField.frame(width: slotWidth)
        }
        .frame(height: 34)
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
