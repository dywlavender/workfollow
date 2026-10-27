import Foundation

/// 「保存为 → 发送邮件」的草稿。
///
/// `mailto:` 链接会同时带上主题和正文；正文过长时只带主题，正文由
/// `copiesBodyToPasteboard` 标记，调用方负责复制到剪贴板后提示用户粘贴。
struct SummaryMailDraft: Equatable {
    let subject: String
    let body: String
    let url: URL?
    let copiesBodyToPasteboard: Bool

    static let maximumURLBytes = 4_000

    static func make(subject: String, body: String) -> SummaryMailDraft? {
        guard !body.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
        let cleanedSubject = subject.trimmingCharacters(in: .whitespacesAndNewlines)
        let subject = cleanedSubject.isEmpty ? "摘要" : cleanedSubject
        if let url = address(subject: subject, body: body),
           url.absoluteString.utf8.count <= maximumURLBytes {
            return SummaryMailDraft(subject: subject, body: body, url: url,
                                    copiesBodyToPasteboard: false)
        }
        return SummaryMailDraft(subject: subject, body: body,
                                url: address(subject: subject, body: nil),
                                copiesBodyToPasteboard: true)
    }

    private static func address(subject: String, body: String?) -> URL? {
        var components = URLComponents()
        components.scheme = "mailto"
        var items = [URLQueryItem(name: "subject", value: subject)]
        if let body, !body.isEmpty {
            items.append(URLQueryItem(name: "body", value: body))
        }
        components.queryItems = items
        return components.url
    }
}
