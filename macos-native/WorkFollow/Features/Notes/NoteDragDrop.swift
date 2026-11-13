import SwiftUI
import UniformTypeIdentifiers

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

extension UTType {
    static let workfollowNoteFolder = UTType(exportedAs: "com.workfollow.native.note-folder", conformingTo: .data)
}

struct NoteFolderDragSource: ViewModifier {
    let id: String
    let name: String
    /// 明确选择的图标枚举；nil 时按 symbol 兜底（真文件夹/未归档托盘也走双色调）。
    var icon: NoteDirectoryIcon? = nil
    let symbol: String

    func body(content: Content) -> some View {
        content.onDrag {
            let provider = NSItemProvider()
            let data = Data(id.utf8)
            provider.registerDataRepresentation(forTypeIdentifier: UTType.workfollowNoteFolder.identifier,
                                                visibility: .ownProcess) { completion in
                completion(data, nil)
                return nil
            }
            return provider
        } preview: {
            HStack(spacing: 5) {
                NoteDirectoryGlyph(icon: icon, symbol: symbol, size: 14)
                    .foregroundStyle(WFColors.secondaryText)
                Text(name).font(WFType.navigation)
            }
            .padding(.horizontal, 8).padding(.vertical, 5)
        }
    }
}

struct NoteDirectoryDropDelegate: DropDelegate {
    let notes: NotesWorkspaceModel
    let rowID: String?
    let folderName: String?
    @Binding var indicator: NoteFolderPlacement?

    static let rowHeight: CGFloat = 30

    var types: [UTType] {
        switch rowID {
        case nil: return [.workfollowNoteFolder]
        case NoteFolderTree.unfiledNodeID: return [.utf8PlainText]
        default: return [.workfollowNoteFolder, .utf8PlainText]
        }
    }

    static func folderPlacement(rowID: String?, y: CGFloat) -> NoteFolderPlacement? {
        guard let rowID else { return .root }
        guard rowID != NoteFolderTree.unfiledNodeID else { return nil }
        if y < rowHeight * 0.27 { return .before(rowID) }
        if y > rowHeight * 0.73 { return .after(rowID) }
        return .inside(rowID)
    }

    private func placement(for info: DropInfo) -> NoteFolderPlacement? {
        if info.hasItemsConforming(to: [.workfollowNoteFolder]) {
            return Self.folderPlacement(rowID: rowID, y: info.location.y)
        }
        guard let rowID, info.hasItemsConforming(to: [.utf8PlainText]) else { return nil }
        return .inside(rowID)
    }

    func validateDrop(info: DropInfo) -> Bool { placement(for: info) != nil }

    func dropEntered(info: DropInfo) { indicator = placement(for: info) }

    func dropUpdated(info: DropInfo) -> DropProposal? {
        let target = placement(for: info)
        indicator = target
        return DropProposal(operation: target == nil ? .cancel : .move)
    }

    func dropExited(info: DropInfo) {
        if let indicator, indicator.anchorID == rowID { self.indicator = nil }
    }

    func performDrop(info: DropInfo) -> Bool {
        indicator = nil
        guard let target = placement(for: info) else { return false }
        if let provider = info.itemProviders(for: [.workfollowNoteFolder]).first {
            provider.loadDataRepresentation(forTypeIdentifier: UTType.workfollowNoteFolder.identifier) { data, _ in
                guard let data, let id = String(data: data, encoding: .utf8) else { return }
                _Concurrency.Task { @MainActor in notes.moveFolder(id: id, to: target) }
            }
            return true
        }
        guard let folderName, let provider = info.itemProviders(for: [.utf8PlainText]).first,
              provider.canLoadObject(ofClass: NSString.self) else { return false }
        provider.loadObject(ofClass: NSString.self) { value, _ in
            _Concurrency.Task { @MainActor in
                NoteFolderDrop.move(payload: value as? String, to: folderName, notes: notes)
            }
        }
        return true
    }
}

private extension NoteFolderPlacement {
    var anchorID: String? {
        switch self {
        case .inside(let id), .before(let id), .after(let id): return id
        case .root: return nil
        }
    }
}
