import Foundation

struct AutomationInvocation {
    var request: AutomationRequest?
    var appPath: String?
    var timeout: TimeInterval = 20
    var json = false

    static let options: [String: Set<String>] = [
        "status": [],
        "task.add": ["title", "list", "section", "priority", "date", "due", "content"],
        "task.list": ["query", "list", "section", "completed", "limit", "offset"],
        "task.lists": [], "task.get": ["id"],
        "task.update": ["id", "version", "title", "list", "section", "clear-section", "priority", "date", "due", "clear-date", "clear-due", "content"],
        "task.complete": ["id", "version"], "task.reopen": ["id", "version"],
        "note.create": ["title", "folder", "content"],
        "note.list": ["query", "folder", "limit", "offset"], "note.folders": [], "note.get": ["id"],
        "note.update": ["id", "version", "title", "folder", "content"],
        "note.append": ["id", "version", "content"],
        "list.list": ["query", "group", "archived", "limit", "offset"],
        "list.get": ["name"], "list.create": ["name", "group"],
        "list.rename": ["name", "to"], "list.move": ["name", "group", "clear-group"],
        "list.archive": ["name"], "list.unarchive": ["name"], "list.delete": ["name"],
        "group.list": [], "group.get": ["name"], "group.create": ["name"],
        "group.rename": ["name", "to"], "group.dissolve": ["name"],
        "section.list": ["list"], "section.get": ["id"],
        "section.create": ["list", "title"], "section.rename": ["id", "title"],
        "section.move": ["id", "list"], "section.delete": ["id"]
    ]
    static let help = """
    workfollowctl — 操作本机 WorkFollow 原生 App

      status
      task add --title TEXT [--list NAME] [--section ID] [--priority none|low|medium|high]
               [--date YYYY-MM-DD|ISO8601] [--due YYYY-MM-DD|ISO8601] [--content TEXT]
      task list [--query TEXT] [--list NAME] [--section ID] [--completed true|false] [--limit N] [--offset N]
      task lists
      task get --id UUID
      task update --id UUID --version VERSION [--title TEXT] [--list NAME] [--priority VALUE]
                  [--section ID|--clear-section] [--date DATE|--clear-date] [--due DATE|--clear-due] [--content TEXT]
      task complete|reopen --id UUID --version VERSION
      note create [--title TEXT] [--folder NAME] [--content TEXT]
      note list [--query TEXT] [--folder NAME] [--limit N] [--offset N]
      note folders
      note get --id UUID
      note update --id UUID --version VERSION [--title TEXT] [--folder NAME] [--content TEXT]
      note append --id UUID --version VERSION --content TEXT

      list list [--query TEXT] [--group NAME] [--archived true|false] [--limit N] [--offset N]
      list get --name NAME
      list create --name NAME [--group NAME]
      list rename --name NAME --to NAME
      list move --name NAME (--group NAME|--clear-group)
      list archive|unarchive|delete --name NAME
      group list
      group get --name NAME
      group create --name NAME
      group rename --name NAME --to NAME
      group dissolve --name NAME
      section list --list NAME
      section get --id ID
      section create --list NAME --title TEXT
      section rename --id ID --title TEXT
      section move --id ID --list NAME
      section delete --id ID

    --content-file PATH 可替代 --content，UTF-8 纯文本；PATH 为 - 时读取标准输入。
    --date 是安排日期，--due 是截止日期。待办和笔记的版本从各自 get 返回值取得。
    group 是侧边栏清单分组；section 是清单内任务分组，--section 使用 section list 返回的 ID。
    删除清单把任务移回收集箱；解散 group 或删除 section 保留内容并移出该分组。
    通用选项：--json（单行 JSON）、--app PATH（指定 App）、--timeout SECONDS（默认 20）。
    App 未运行时会在后台启动。待办/笔记写入返回 ID、版本及打开链接；分类命令返回对应元数据或移除结果。
    """

    static func parse(_ tokens: [String], readContent: (String) throws -> String) throws -> Self {
        var invocation = Self(), words: [String] = [], values: [String: String] = [:]
        var index = 0
        while index < tokens.count {
            let token = tokens[index]
            if token == "--help" || token == "-h" { return invocation }
            if !token.hasPrefix("--") { words.append(token); index += 1; continue }
            let key = String(token.dropFirst(2))
            guard values[key] == nil else { throw AutomationFailure.argument("选项重复：\(token)") }
            if ["json", "clear-date", "clear-due", "clear-section", "clear-group"].contains(key) { values[key] = "true"; index += 1; continue }
            guard index + 1 < tokens.count, !tokens[index + 1].hasPrefix("--") else {
                throw AutomationFailure.argument("\(token) 缺少值。")
            }
            values[key] = tokens[index + 1]; index += 2
        }
        if words.isEmpty { return invocation }
        let operation = words.joined(separator: ".")
        guard let allowed = options[operation] else { throw AutomationFailure.argument("未知命令：\(words.joined(separator: " "))。请运行 --help。") }
        let global: Set<String> = ["json", "app", "timeout", "content-file"]
        for key in values.keys where !allowed.contains(key) && !global.contains(key) {
            throw AutomationFailure.argument("\(operation) 不支持 --\(key)。")
        }
        invocation.json = values.removeValue(forKey: "json") != nil
        invocation.appPath = values.removeValue(forKey: "app")
        if let raw = values.removeValue(forKey: "timeout") {
            guard let seconds = Double(raw), seconds.isFinite, seconds > 0, seconds <= 120 else {
                throw AutomationFailure.argument("--timeout 须在 0 到 120 秒之间。")
            }
            invocation.timeout = seconds
        }
        if let file = values.removeValue(forKey: "content-file") {
            guard allowed.contains("content"), values["content"] == nil else {
                throw AutomationFailure.argument("--content-file 只用于正文写入，且不能与 --content 同时使用。")
            }
            values["content"] = try readContent(file)
        }
        var required: [String] = []
        if ["task.add", "section.create", "section.rename"].contains(operation) { required.append("title") }
        if operation.hasPrefix("list.") && operation != "list.list"
            || operation.hasPrefix("group.") && operation != "group.list" { required.append("name") }
        if operation == "list.rename" || operation == "group.rename" { required.append("to") }
        if ["section.list", "section.create", "section.move"].contains(operation) { required.append("list") }
        if ["section.get", "section.rename", "section.move", "section.delete"].contains(operation) { required.append("id") }
        for key in required where values[key]?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty != false {
            throw AutomationFailure.argument("请提供非空 --\(key)。")
        }
        if ["task.get", "task.update", "task.complete", "task.reopen", "note.get", "note.update", "note.append"].contains(operation) {
            guard let id = values["id"], UUID(uuidString: id) != nil else { throw AutomationFailure.argument("请提供有效的 --id UUID。") }
        }
        if ["task.update", "task.complete", "task.reopen", "note.update", "note.append"].contains(operation), values["version"] == nil {
            throw AutomationFailure.argument("请先 get 读取记录，再传入其 --version。")
        }
        if operation.hasSuffix(".update"), Set(values.keys).subtracting(["id", "version"]).isEmpty {
            throw AutomationFailure.argument("请至少提供一个要修改的字段。")
        }
        if operation == "note.append", values["content"]?.isEmpty != false { throw AutomationFailure.argument("追加内容不能为空。") }
        for (field, clear) in [("date", "clear-date"), ("due", "clear-due"), ("section", "clear-section"), ("group", "clear-group")] where values[field] != nil && values[clear] != nil {
            throw AutomationFailure.argument("--\(field) 与 --\(clear) 不能同时使用。")
        }
        if operation == "list.move", values["group"] == nil && values["clear-group"] == nil {
            throw AutomationFailure.argument("请提供 --group 或 --clear-group。")
        }
        invocation.request = AutomationRequest(operation: operation, arguments: values,
            expiresAt: Date().addingTimeInterval(invocation.timeout))
        return invocation
    }
}
