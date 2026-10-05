import AppKit

/// 打印文本的**纯函数**（与 AppKit 解耦，可单测）：把一个视图当前的分组结果
/// 变成可打印的纯文本。分组头沿用 `TaskGroupDisplay.title`（与列表/看板同一份文案）。
enum TaskPrintDocument {
    /// 一行一条任务：`• 标题 · 日期 · 优先级 · #标签`；已完成/已放弃用 `✓` 前缀。
    static func text(title: String, groups: [TaskListGroup], now: Date,
                     calendar: Calendar) -> String {
        var lines: [String] = [title, String(repeating: "─", count: max(8, title.count))]
        for group in groups {
            let header = TaskGroupDisplay.title(group, now: now)
            if !header.isEmpty {
                lines.append("")
                lines.append("\(header)（\(group.tasks.count)）")
            }
            for task in group.tasks {
                lines.append(line(for: task, now: now, calendar: calendar))
            }
        }
        return lines.joined(separator: "\n") + "\n"
    }

    static func line(for task: Task, now: Date, calendar: Calendar) -> String {
        var parts: [String] = []
        if let due = task.schedule.dueAt {
            parts.append(TaskDateLabel.text(due, hasTime: task.schedule.hasTime,
                                            now: now, calendar: calendar))
        }
        if task.priority != .none {
            parts.append(task.priority.title)
        }
        for tag in task.tags { parts.append("#" + tag) }
        let prefix = task.isClosed ? "✓ " : "• "
        let body = task.title.isEmpty ? "无标题" : task.title
        return prefix + body + (parts.isEmpty ? "" : "  ·  " + parts.joined(separator: " · "))
    }
}

/// 打印动作（薄层，不做单测）：把文本交给系统的打印面板。
@MainActor
enum TaskPrintService {
    static func printDocument(title: String, text: String) {
        let view = NSTextView(frame: NSRect(x: 0, y: 0, width: 468, height: 648))
        view.isEditable = false
        view.string = text
        view.font = .systemFont(ofSize: 12)
        view.textContainerInset = NSSize(width: 24, height: 24)

        let info = NSPrintInfo.shared
        info.topMargin = 48; info.bottomMargin = 48
        info.leftMargin = 48; info.rightMargin = 48
        let operation = NSPrintOperation(view: view, printInfo: info)
        operation.jobTitle = title
        operation.showsPrintPanel = true
        operation.showsProgressPanel = true
        operation.run()
    }
}
