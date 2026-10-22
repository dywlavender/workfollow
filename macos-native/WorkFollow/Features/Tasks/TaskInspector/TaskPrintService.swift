import AppKit

/// 任务打印（TI2-11）：滴答「更多」菜单第 14 项 `bottomActionViewDidClickPrint:`。
///
/// 排版与打印动作分开：`document(...)` 是纯函数（可测），`printTask(...)` 才起
/// `NSPrintOperation`。打印内容 = 标题 / 属性行 / 正文（按块给字号与标记）/ 子任务清单。
enum TaskPrintService {

    /// 摘要等通用文档的打印：标题 + 纯文本正文（同一套页边距与分页）。
    @MainActor
    static func printDocument(title: String, body: String) {
        let text = NSMutableAttributedString()
        text.append(NSAttributedString(string: title + "\n\n", attributes: [
            .font: NSFont.systemFont(ofSize: 18, weight: .semibold),
            .foregroundColor: NSColor.labelColor,
        ]))
        text.append(NSAttributedString(string: body, attributes: [
            .font: NSFont.systemFont(ofSize: 13),
            .foregroundColor: NSColor.labelColor,
        ]))
        let view = NSTextView(frame: NSRect(x: 0, y: 0, width: 468, height: 648))
        view.isRichText = true
        view.textStorage?.setAttributedString(text)
        view.textContainer?.widthTracksTextView = true
        view.sizeToFit()
        let info = (NSPrintInfo.shared.copy() as? NSPrintInfo) ?? NSPrintInfo.shared
        info.topMargin = 48
        info.bottomMargin = 48
        info.leftMargin = 48
        info.rightMargin = 48
        info.horizontalPagination = .fit
        info.verticalPagination = .automatic
        NSPrintOperation(view: view, printInfo: info).run()
    }

    @MainActor
    static func printTask(_ task: Task, subtasks: [Task], calendar: Calendar, now: Date = Date()) {
        let text = document(for: task, subtasks: subtasks, calendar: calendar, now: now)
        let view = NSTextView(frame: NSRect(x: 0, y: 0, width: 468, height: 648))
        view.isRichText = true
        view.textStorage?.setAttributedString(text)
        view.textContainer?.widthTracksTextView = true
        view.sizeToFit()
        let info = (NSPrintInfo.shared.copy() as? NSPrintInfo) ?? NSPrintInfo.shared
        info.topMargin = 48
        info.bottomMargin = 48
        info.leftMargin = 48
        info.rightMargin = 48
        info.horizontalPagination = .fit
        info.verticalPagination = .automatic
        NSPrintOperation(view: view, printInfo: info).run()
    }

    /// 打印稿：标题 18 半粗、属性 11 次级、正文 13；子任务用 ☐/☑ 列表。
    static func document(for task: Task, subtasks: [Task],
                         calendar: Calendar, now: Date = Date()) -> NSAttributedString {
        let result = NSMutableAttributedString()

        func append(_ string: String, font: NSFont, color: NSColor = .labelColor,
                    spacingAfter: CGFloat = 0) {
            let paragraph = NSMutableParagraphStyle()
            paragraph.paragraphSpacing = spacingAfter
            paragraph.lineHeightMultiple = 1.15
            result.append(NSAttributedString(string: string, attributes: [
                .font: font,
                .foregroundColor: color,
                .paragraphStyle: paragraph
            ]))
        }

        append(task.title.isEmpty ? "未命名任务" : task.title,
               font: .systemFont(ofSize: 18, weight: .semibold), spacingAfter: 6)

        var meta: [String] = [task.list.name]
        if let due = task.schedule.dueAt {
            meta.append(TaskInspectorSchedulePresentation.label(
                date: due, hasTime: task.schedule.hasTime, now: now, calendar: calendar))
        }
        if let deadline = task.schedule.deadlineAt {
            meta.append("截止 " + TaskDateLabel.text(deadline, hasTime: false, now: now, calendar: calendar))
        }
        if task.priority != .none { meta.append(task.priority.title) }
        if !task.tags.isEmpty { meta.append(task.tags.map { "#\($0)" }.joined(separator: " ")) }
        append(meta.joined(separator: "　·　"),
               font: .systemFont(ofSize: 11), color: .secondaryLabelColor, spacingAfter: 12)

        for block in task.document.blocks {
            let text = block.runs.map(\.text).joined()
            guard !text.isEmpty || block.kind == .divider else { continue }
            switch block.kind {
            case .heading(let level):
                let size: CGFloat = level == 1 ? 16 : level == 2 ? 15 : 13
                append(text, font: .systemFont(ofSize: size, weight: .semibold), spacingAfter: 4)
            case .bullet:
                append("•  " + text, font: .systemFont(ofSize: 13), spacingAfter: 2)
            case .ordered:
                append("◦  " + text, font: .systemFont(ofSize: 13), spacingAfter: 2)
            case .checklist(let checked):
                append((checked ? "☑  " : "☐  ") + text, font: .systemFont(ofSize: 13), spacingAfter: 2)
            case .quote:
                append("│  " + text, font: .systemFont(ofSize: 13), color: .secondaryLabelColor, spacingAfter: 4)
            case .code:
                append(text, font: .monospacedSystemFont(ofSize: 12, weight: .regular), spacingAfter: 4)
            case .divider:
                append("──────────", font: .systemFont(ofSize: 12), color: .tertiaryLabelColor, spacingAfter: 6)
            case .paragraph:
                append(text, font: .systemFont(ofSize: 13), spacingAfter: 4)
            }
        }

        if !subtasks.isEmpty {
            append("\n子任务", font: .systemFont(ofSize: 13, weight: .semibold), spacingAfter: 4)
            for child in subtasks {
                append((child.isClosed ? "☑  " : "☐  ") + (child.title.isEmpty ? "未命名子任务" : child.title),
                       font: .systemFont(ofSize: 13),
                       color: child.isClosed ? .secondaryLabelColor : .labelColor,
                       spacingAfter: 2)
            }
        }
        return result
    }
}
