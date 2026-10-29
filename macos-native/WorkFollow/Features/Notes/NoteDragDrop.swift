import SwiftUI

/// 笔记行拖拽负载。用独立前缀而不是裸 UUID：任务侧只认 UUID / `wf-list:`，
/// 笔记掉进任务清单会被忽略；反过来任务也进不了笔记文件夹，两个域不会互相误收。
enum NoteDragPayload {
    static let prefix = "wf-note:"

    static func encode(_ id: UUID) -> String { prefix + id.uuidString }

    static func decode(_ raw: String?) -> UUID? {
        guard let raw, raw.hasPrefix(prefix) else { return nil }
        return UUID(uuidString: String(raw.dropFirst(prefix.count)))
    }
}

/// 拖放意图（纯函数，可单测）：只有真实的文件夹行接收笔记。
enum NoteFolderDrop {
    /// 「全部笔记」「收藏」「垃圾桶」不是归属，只有文件夹（含未归档）能接。
    static func target(folder: String?, trash: Bool) -> String? {
        trash ? nil : folder
    }

    @MainActor
    @discardableResult
    static func move(payload: String?, to folder: String, notes: NotesWorkspaceModel) -> Bool {
        guard let folder = target(folder: folder, trash: false),
              let id = NoteDragPayload.decode(payload),
              notes.notes.contains(where: { $0.id == id && $0.deletedAt == nil }) else { return false }
        notes.moveNoteToFolder(id, named: folder)
        return true
    }
}

/// 笔记行作为拖动源；垃圾桶里的笔记不可拖。
struct NoteDragSource: ViewModifier {
    let note: Note
    var enabled: Bool

    func body(content: Content) -> some View {
        if enabled {
            content.draggable(NoteDragPayload.encode(note.id)) {
                TaskDragPreview(title: note.title.isEmpty ? "未命名笔记" : note.title)
            }
        } else {
            content
        }
    }
}

/// 侧栏文件夹行作为落点；悬停时描边提示。
struct NoteFolderDropTarget: ViewModifier {
    let folder: String
    @ObservedObject var notes: NotesWorkspaceModel
    @Binding var targeted: String?

    func body(content: Content) -> some View {
        content
            .overlay {
                if targeted == folder {
                    RoundedRectangle(cornerRadius: 6).stroke(WFColors.accent, lineWidth: 1.5)
                }
            }
            .dropDestination(for: String.self) { values, _ in
                NoteFolderDrop.move(payload: values.first, to: folder, notes: notes)
            } isTargeted: { inside in
                if inside { targeted = folder }
                else if targeted == folder { targeted = nil }
            }
    }
}
