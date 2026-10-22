import Foundation

/// One day's summary: the short essay the user writes for a calendar day.
/// The JSON keys (`dayKey`, `content`, `updatedAt`) are part of the on-disk
/// `summary.json` format introduced by the Wave 1 F3 stub and must stay stable.
struct DailySummary: Identifiable, Codable, Equatable {
    var id: String { dayKey }
    let dayKey: String  // yyyy-MM-dd in the user's calendar.
    /// 纯文本正文（F3 起的旧格式）。`document` 存在时以它为准，
    /// 这里保留是为了旧 `summary.json` 能直接解码，不做批量迁移。
    var content: String
    /// 富文本正文（对齐滴答摘要：正文是一篇可编辑文档）。
    /// 缺字段的旧文件解码后为 nil，由 `resolvedDocument` 兜底。
    var document: NativeDocument?
    var updatedAt: Date

    /// 统一读取入口：新数据取 `document`，旧数据把 `content` 转成单段文档。
    var resolvedDocument: NativeDocument {
        document ?? NativeDocument(plainText: content)
    }
}
