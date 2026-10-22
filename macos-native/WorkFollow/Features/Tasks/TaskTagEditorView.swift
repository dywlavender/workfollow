import SwiftUI

/// The shipped tag editor declares name, color and parent controls together.
/// Keep them in one local draft; only confirmation reaches the domain action.
struct TaskTagEditorView: View {
    @ObservedObject var workspace: TaskWorkspaceModel
    let tagID: UUID?
    let onSaved: (UUID?) -> Void
    let onDismiss: () -> Void
    @State private var name: String
    @State private var color: UInt32?
    @State private var parentID: UUID?
    @State private var invalid = false
    @FocusState private var nameFocused: Bool

    init(workspace: TaskWorkspaceModel, tag: TaskTag?, parentID: UUID?,
         onSaved: @escaping (UUID?) -> Void = { _ in }, onDismiss: @escaping () -> Void) {
        self.workspace = workspace; self.tagID = tag?.id
        self.onSaved = onSaved; self.onDismiss = onDismiss
        _name = State(initialValue: tag?.name ?? "")
        _color = State(initialValue: tag?.colorARGB)
        _parentID = State(initialValue: tag?.parentID ?? parentID)
    }

    private var parents: [TaskTag] {
        workspace.orderedTags.filter { tag in
            guard let tagID else { return true }
            return tag.id != tagID && !workspace.tagAncestors(tag.id).contains(tagID)
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: WFSpace.lg) {
            Text(tagID == nil ? "新建标签" : "编辑标签").font(WFType.detailTitle)
            HStack {
                fieldLabel("名称")
                TextField("标签名称", text: $name).textFieldStyle(.roundedBorder)
                    .focused($nameFocused)
                    .accessibilityIdentifier("tag.editor.name")
            }
            HStack(alignment: .top) {
                fieldLabel("颜色").padding(.top, 4)
                TaskTagColorGrid(color: $color)
            }
            HStack {
                fieldLabel("父标签")
                BusinessPicker("父标签", selection: $parentID, options:
                    [BusinessChoice(nil, "无")] + parents.map { tag in
                        BusinessChoice(Optional(tag.id), String(repeating: "  ", count: workspace.tagDepth(tag.name)) + tag.name,
                                       symbol: "tag", color: workspace.tagColor(tag.name))
                    })
                .labelsHidden().accessibilityIdentifier("tag.editor.parent")
            }
            if invalid {
                Text("名称为空、已存在，或父标签不可用")
                    .font(WFType.supporting).foregroundStyle(.red)
            }
            Divider()
            HStack {
                Spacer()
                Button("取消", action: onDismiss).keyboardShortcut(.cancelAction)
                    .taskTagEditorFrame(.cancel)
                Button(tagID == nil ? "添加" : "确定") {
                    guard workspace.saveTag(tagID, name: name, colorARGB: color, parentID: parentID) != nil else {
                        invalid = true; return
                    }
                    onSaved(parentID); onDismiss()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(TaskTag.normalizedName(name) == nil)
                .taskTagEditorFrame(.save)
            }
        }
        .padding(WFSpace.xxl).frame(width: 420)
        .coordinateSpace(name: TaskTagEditorFrames.coordinateSpace)
        .onAppear { DispatchQueue.main.async { nameFocused = true } }
        .onChange(of: name) { _, _ in invalid = false }
        .onChange(of: parentID) { _, _ in invalid = false }
    }

    private func fieldLabel(_ title: String) -> some View {
        Text(title).font(WFType.body).foregroundStyle(WFColors.secondaryText)
            .frame(width: 64, alignment: .leading)
    }
}

struct TaskTagColorGrid: View {
    @Binding var color: UInt32?

    var body: some View {
        VStack(alignment: .leading, spacing: WFSpace.sm) {
            LazyVGrid(columns: Array(repeating: GridItem(.fixed(22), spacing: 10), count: 7), spacing: 10) {
                ForEach(WFListPalette.argb.indices, id: \.self) { index in
                    let value = WFListPalette.argb[index]
                    Button { color = value } label: {
                        Circle().fill(WFListPalette.swatch(value)).frame(width: 22, height: 22)
                            .overlay {
                                if color == value {
                                    Image(systemName: "checkmark").font(.system(size: 10, weight: .bold))
                                        .foregroundStyle(WFListPalette.checkmarkOn(value))
                                }
                            }
                    }
                    .buttonStyle(.plain).accessibilityLabel("标签颜色 \(index + 1)")
                    .taskTagEditorFrame(.color(value))
                }
            }
            Button("默认颜色") { color = nil }
                .buttonStyle(.plain).font(WFType.supporting).foregroundStyle(WFColors.secondaryText)
        }
        .fixedSize(horizontal: true, vertical: false)
    }
}

enum TaskTagEditorAnchor: Hashable { case cancel, save, color(UInt32) }

struct TaskTagEditorFrames: PreferenceKey {
    static let coordinateSpace = "tag-editor"
    static var defaultValue: [TaskTagEditorAnchor: CGRect] { [:] }
    static func reduce(value: inout [TaskTagEditorAnchor: CGRect],
                       nextValue: () -> [TaskTagEditorAnchor: CGRect]) {
        value.merge(nextValue(), uniquingKeysWith: { _, new in new })
    }
}

private extension View {
    func taskTagEditorFrame(_ anchor: TaskTagEditorAnchor) -> some View {
        background(GeometryReader { geometry in
            Color.clear.preference(key: TaskTagEditorFrames.self,
                value: [anchor: geometry.frame(in: .named(TaskTagEditorFrames.coordinateSpace))])
                .allowsHitTesting(false)
        })
    }
}
