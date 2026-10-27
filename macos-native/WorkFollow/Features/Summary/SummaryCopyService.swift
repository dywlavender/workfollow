import AppKit
import Foundation

enum SummaryCopyFormat: String, CaseIterable, Hashable {
    case plainText, richText, markdown

    var menuTitle: String {
        switch self {
        case .plainText: "纯文本"
        case .richText: "富文本"
        case .markdown: "Markdown"
        }
    }

    var anchor: String {
        switch self {
        case .plainText: "plainText"
        case .richText: "richText"
        case .markdown: "markdown"
        }
    }
}

struct SummaryClipboardPayload: Equatable {
    var string: String?
    var rtf: Data?
    var html: Data?
}

/// 摘要「复制」：纯文本、富文本与 Markdown 共用导出服务的渲染结果。
///
/// 富文本同时写入 RTF 与 HTML，粘贴到邮件、备忘录等应用时保留层级、
/// 加粗与高亮；任务标题保持导出图片里的蓝色，但不带下划线。
@MainActor
enum SummaryCopyService {
    static func payload(for format: SummaryCopyFormat,
                        document: NativeDocument) throws -> SummaryClipboardPayload {
        switch format {
        case .plainText:
            let text = SummaryExportService.plainText(document)
            guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                throw SummaryExportError.emptyDocument
            }
            return SummaryClipboardPayload(string: text)
        case .markdown:
            let text = SummaryExportService.markdown(document)
            guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                throw SummaryExportError.emptyDocument
            }
            return SummaryClipboardPayload(string: text)
        case .richText:
            let attributed = SummaryExportService.attributedText(document)
            guard !attributed.string.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                throw SummaryExportError.emptyDocument
            }
            let range = NSRange(location: 0, length: attributed.length)
            do {
                let rtf = try attributed.data(from: range, documentAttributes: [
                    .documentType: NSAttributedString.DocumentType.rtf,
                ])
                let html = try attributed.data(from: range, documentAttributes: [
                    .documentType: NSAttributedString.DocumentType.html,
                    .characterEncoding: String.Encoding.utf8.rawValue,
                ])
                guard !rtf.isEmpty, !html.isEmpty else {
                    throw SummaryExportError.renderFailed
                }
                return SummaryClipboardPayload(string: attributed.string, rtf: rtf, html: html)
            } catch let error as SummaryExportError {
                throw error
            } catch {
                throw SummaryExportError.renderFailed
            }
        }
    }

    static func copy(_ document: NativeDocument, format: SummaryCopyFormat,
                     to pasteboard: NSPasteboard = .general) throws {
        let payload = try payload(for: format, document: document)
        pasteboard.clearContents()
        if let string = payload.string {
            pasteboard.setString(string, forType: .string)
        }
        if let rtf = payload.rtf {
            pasteboard.setData(rtf, forType: .rtf)
        }
        if let html = payload.html {
            pasteboard.setData(html, forType: .html)
        }
    }
}
