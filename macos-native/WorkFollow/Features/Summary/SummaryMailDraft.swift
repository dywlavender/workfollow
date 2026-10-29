import AppKit
import Foundation

/// 「保存为 → 发送邮件」的草稿：富文本正文交给系统邮件服务，
/// 主题与导出文件名共用「摘要 (10月19日-10月25日)」口径。
struct SummaryMailDraft {
    let subject: String
    let body: NSAttributedString
    let plainText: String

    @MainActor
    static func make(subject: String, document: NativeDocument) -> SummaryMailDraft? {
        let plainText = SummaryExportService.plainText(document)
        guard !plainText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
        let cleaned = subject.trimmingCharacters(in: .whitespacesAndNewlines)
        return SummaryMailDraft(subject: cleaned.isEmpty ? "摘要" : cleaned,
                                body: SummaryExportService.attributedText(document),
                                plainText: plainText)
    }
}
