import Foundation

/// Stable folder identity and migration ordering, retained independently from
/// the flat folder-name presentation used by the current Native notes UI.
struct NoteFolderMeta: Identifiable, Equatable, Codable {
    var id: String
    var parentID: String?
    var name: String
    var sortOrder: Int
    var createdAt: String?
    var updatedAt: String?
}

struct Note: Identifiable, Equatable, Codable {
    let id: UUID
    var title: String
    var document: NativeDocument
    var folder: String
    var folderID: String? = nil
    var favorite = false
    var linkedTaskIDs: [UUID] = []
    var attachments: [NativeAttachment] = []
    var updatedAt: Date
    var deletedAt: Date?
    /// 导入富文本笔记时保留的原始文档 JSON（对齐 Flutter originalContentJson）。
    /// additive Codable：旧快照没有该键时解码为 nil；写入后原文受保护，
    /// 只有显式“创建纯文本副本”才产生可自由编辑的新笔记。
    var originalContentJson: String? = nil

    /// Flutter hasPreservedRichContent 语义：存在保留的原始内容即视为受保护。
    var hasPreservedRichContent: Bool { originalContentJson != nil }
}
