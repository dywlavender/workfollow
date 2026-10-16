import Foundation

/// 快速输入的纯组合规则：换行批量添加、`#`/`@` 候选查询与替换。
///
/// 对齐滴答清单的两条录入约定：
/// - 「换行可添加多个任务」——一次提交按行拆成多个任务；
/// - 「在添加任务时输入 # 可快速选择标签」——标记符后实时给出候选。
///
/// 全部是纯函数、不依赖 SwiftUI 与 AppKit，便于在
/// `WorkFollowTests/QuickAddCompositionTests.swift` 里用固定输入覆盖。
enum QuickAddComposition {
    /// 候选列表最多展示多少项。超出部分靠继续输入收敛，避免面板盖住任务列表。
    static let candidateLimit = 6

    // MARK: - 换行批量添加

    /// 按换行拆行、去掉空白行、保留原始顺序。
    ///
    /// 返回单元素数组表示「普通单条创建」，多元素表示「批量创建」；空输入返回空数组。
    /// 先归一化 CRLF/CR，粘贴自其它应用的多行文本才不会把 `\r` 当成普通字符。
    static func batchLines(in input: String) -> [String] {
        input
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
            .components(separatedBy: "\n")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
    }

    // MARK: - `#` / `@` 候选

    /// 输入末尾那个 `#`/`@` 片段。
    struct MarkerQuery: Equatable {
        enum Kind: Equatable { case tag, list }

        let kind: Kind
        /// 标记符之后的部分；只输入了 `#` 时为空串。
        let query: String
        /// 片段（含标记符）在原文中的 UTF-16 区间，用于替换。
        let range: NSRange
        /// 片段原文，例如 `#工作`。用于「已被 Esc 忽略」的比对。
        let raw: String

        /// 只在片段恰好等于某个候选名时成立：此时没有可收敛的空间，候选列表
        /// 应当自行收起，把 Tab（进描述）和回车（建任务）还给用户。
        func isResolved(by names: [String]) -> Bool {
            guard !query.isEmpty else { return false }
            return names.contains { $0.compare(query, options: .caseInsensitive) == .orderedSame }
        }
    }

    /// Reads the marker at the actual UTF-16 caret, including a marker in the
    /// middle of a title. The full token range is replaced without touching its suffix.
    static func markerQuery(in input: String, selection: NSRange? = nil) -> MarkerQuery? {
        let source = input as NSString
        let caret = min(source.length, max(0, selection?.location ?? source.length))
        guard selection?.length ?? 0 == 0, caret > 0 else { return nil }
        var start = caret
        while start > 0, source.substring(with: NSRange(location: start - 1, length: 1)).rangeOfCharacter(from: .whitespacesAndNewlines) == nil {
            start -= 1
        }
        var end = caret
        while end < source.length, source.substring(with: NSRange(location: end, length: 1)).rangeOfCharacter(from: .whitespacesAndNewlines) == nil {
            end += 1
        }
        guard start < caret else { return nil }
        let raw = source.substring(with: NSRange(location: start, length: end - start))
        guard let symbol = raw.first, symbol == "#" || symbol == "@" else { return nil }
        let prefix = source.substring(with: NSRange(location: start + 1, length: caret - start - 1))
        guard !prefix.contains("#"), !prefix.contains("@") else { return nil }
        return MarkerQuery(kind: symbol == "#" ? .tag : .list, query: prefix,
            range: NSRange(location: start, length: end - start), raw: raw)
    }

    /// 候选过滤：空查询返回全部（刚敲下 `#` 时先列出已有名字）；否则不区分大小写包含匹配。
    static func candidates(_ names: [String], matching query: String,
                           limit: Int = candidateLimit) -> [String] {
        let trimmed = query.trimmingCharacters(in: .whitespaces)
        let matched = trimmed.isEmpty
            ? names
            : names.filter { $0.localizedCaseInsensitiveContains(trimmed) }
        return Array(matched.prefix(max(0, limit)))
    }

    /// 把末尾标记片段换成完整名字，并在其后补一个空格。
    ///
    /// 补空格是必要的：候选名一旦落进正文，末尾就不再是标记片段，候选列表自动收起，
    /// 用户可以直接接着输入下一个字段（`@清单`、`!!!` 等）。
    static func replacingTrailingMarker(in input: String, with name: String) -> String {
        replacingMarker(in: input, selection: nil, with: name).text
    }

    static func replacingMarker(in input: String, selection: NSRange?, with name: String) -> (text: String, selection: NSRange) {
        guard let marker = markerQuery(in: input, selection: selection) else {
            return (input, selection ?? NSRange(location: (input as NSString).length, length: 0))
        }
        let text = NSMutableString(string: input)
        let symbol = marker.kind == .tag ? "#" : "@"
        let suffixSpace = NSMaxRange(marker.range) == text.length ? " " : ""
        let replacement = "\(symbol)\(name)" + suffixSpace
        text.replaceCharacters(in: marker.range, with: replacement)
        return (text as String, NSRange(location: marker.range.location + (replacement as NSString).length, length: 0))
    }
}

/// `#`/`@` 候选与描述行的界面状态机。
///
/// 列表快速添加条（`TaskListView`）与全局快速添加面板（`GlobalQuickAddPanelView`）
/// 共用它，免得两处各写一套键盘分层——两边一旦分叉，同一串按键在两个入口会有
/// 不同结果，这是最难查也最容易被用户投诉的一类不一致。
///
/// 纯值类型：`marker` / `isListVisible` 都是无副作用的查询，可直接单测。
struct QuickAddCandidateState: Equatable {
    /// 候选列表里高亮的下标。
    var selection = 0
    /// 被 Esc 忽略掉的片段原文。只在文本变化前有效——继续打字就该重新给候选。
    var suppressedMarker = ""
    /// Tab 是否已经把描述行拉出来。
    var descriptionVisible = false

    /// 文本一变，忽略状态与高亮都作废。
    mutating func textDidChange() {
        suppressedMarker = ""
        selection = 0
    }

    /// 当前应当被候选列表服务的标记片段；输入框没聚焦时一律返回 nil。
    func marker(in draft: String, isFocused: Bool, selection: NSRange? = nil) -> QuickAddComposition.MarkerQuery? {
        guard isFocused, let marker = QuickAddComposition.markerQuery(in: draft, selection: selection) else { return nil }
        guard marker.raw != suppressedMarker else { return nil }
        return marker
    }

    /// 候选列表该不该出现。除了「没有标记片段」和「已被 Esc 忽略」，还有两种收起：
    /// 片段已经精确等于某个候选名（没有可收敛的空间，这时要把 Tab 与回车还给用户），
    /// 以及只敲了 `#`/`@` 但一个候选都没有（不必弹一块空面板）。
    func isListVisible(marker: QuickAddComposition.MarkerQuery?, names: [String]) -> Bool {
        guard let marker else { return false }
        if marker.isResolved(by: names) { return false }
        if marker.query.isEmpty, names.isEmpty { return false }
        return true
    }

    /// 上下键移动高亮并循环；返回 false 表示这次按键没被候选列表消费。
    mutating func move(by delta: Int, count: Int) -> Bool {
        guard count > 0 else { return false }
        selection = ((selection + delta) % count + count) % count
        return true
    }

    /// 一次 Esc 只收掉候选列表这一层，不清空草稿。
    mutating func dismiss(draft: String, selection: NSRange? = nil) {
        guard let marker = QuickAddComposition.markerQuery(in: draft, selection: selection) else { return }
        suppressedMarker = marker.raw
    }

    mutating func reset() {
        selection = 0
        suppressedMarker = ""
        descriptionVisible = false
    }
}

