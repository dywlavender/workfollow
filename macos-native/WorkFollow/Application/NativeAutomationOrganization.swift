import Foundation

extension NativeAutomationService {
    static let organizationWrites: Set<String> = [
        "list.create", "list.rename", "list.move", "list.archive", "list.unarchive", "list.delete",
        "group.create", "group.rename", "group.dissolve",
        "section.create", "section.rename", "section.move", "section.delete"
    ]

    func executeOrganization(_ request: AutomationRequest) throws -> AutomationValue? {
        let args = request.arguments
        switch request.operation {
        case "list.list":
            let archived = try boolean(args["archived"])
            let names = tasks.allListNames.filter {
                (archived == nil || tasks.isListArchived($0) == archived) &&
                (args["group"] == nil || tasks.folderName(forList: $0) == args["group"]) &&
                (args["query"] == nil || $0.localizedStandardContains(args["query"]!))
            }
            return try page(names, args: args, encode: listValue)
        case "list.get":
            return listValue(try existingList(args["name"]))
        case "list.create":
            let name = try newListName(args["name"])
            let group = try args["group"].map { try existingGroup($0) }
            try changed(tasks.createAutomationList(name, group: group))
            return listValue(name)
        case "list.rename":
            let name = try managedList(args["name"])
            let target = try nonempty(args["to"], name: "to")
            if target != name {
                _ = try newListName(target)
                try changed(tasks.saveList(target, replacing: name))
            }
            return listValue(target)
        case "list.move":
            let name = try managedList(args["name"])
            guard (args["group"] != nil) != (args["clear-group"] == "true") else {
                throw AutomationFailure.argument("请提供 group 或 clear-group，两者不能同时使用。")
            }
            let group = try args["group"].map { try existingGroup($0) }
            try changed(tasks.setListFolder(name, group))
            return listValue(name)
        case "list.archive", "list.unarchive":
            let name = try managedList(args["name"])
            let archived = request.operation == "list.archive"
            if tasks.isListArchived(name) != archived { try changed(tasks.setListArchived(name, archived)) }
            return listValue(name)
        case "list.delete":
            let name = try managedList(args["name"])
            let count = taskCount(list: name)
            tasks.removeList(name)
            return .object(["name": .string(name), "deleted": .bool(true),
                            "tasksMovedTo": .string(TaskList.inbox.name), "taskCount": .number(Double(count))])
        case "group.list":
            return .array(groupNames.map(groupValue))
        case "group.get":
            return groupValue(try existingGroup(args["name"]))
        case "group.create":
            let name = try nonempty(args["name"], name: "name")
            guard !groupNames.contains(name) else { throw duplicate("清单分组") }
            try changed(tasks.saveListFolder(name))
            return groupValue(name)
        case "group.rename":
            let name = try existingGroup(args["name"])
            let target = try nonempty(args["to"], name: "to")
            if target != name {
                guard !groupNames.contains(target) else { throw duplicate("清单分组") }
                try changed(tasks.renameListFolder(from: name, to: target))
            }
            return groupValue(target)
        case "group.dissolve":
            let name = try existingGroup(args["name"])
            let members = groupMembers(name)
            try changed(tasks.dissolveListFolder(name))
            return .object(["name": .string(name), "dissolved": .bool(true),
                            "listsMovedToTopLevel": .array(members.map { .string($0) })])
        case "section.list":
            let list = try existingList(args["list"])
            return .array(tasks.listSections(forList: list).map(sectionValue))
        case "section.get":
            return sectionValue(try automationSection(nonempty(args["id"], name: "id")))
        case "section.create":
            let list = try managedList(args["list"], requiresActive: true)
            let title = try nonempty(args["title"], name: "title")
            try availableSectionTitle(title, list: list)
            try changed(tasks.addListSection(list, title: title))
            guard let section = tasks.listSections(forList: list).first(where: { $0.title == title }) else {
                throw AutomationFailure(code: "operation_failed", message: "分组创建未完成。")
            }
            return sectionValue(section)
        case "section.rename":
            let section = try automationSection(nonempty(args["id"], name: "id"), requiresActiveList: true)
            let title = try nonempty(args["title"], name: "title")
            if title != section.title {
                try availableSectionTitle(title, list: section.listName, excluding: section.id)
                try changed(tasks.renameListSection(section.id, title: title))
            }
            return sectionValue(try automationSection(section.id))
        case "section.move":
            let section = try automationSection(nonempty(args["id"], name: "id"), requiresActiveList: true)
            let list = try managedList(args["list"], requiresActive: true)
            if list != section.listName {
                try availableSectionTitle(section.title, list: list)
                try changed(tasks.moveListSection(section.id, to: list))
            }
            return sectionValue(try automationSection(section.id))
        case "section.delete":
            let section = try automationSection(nonempty(args["id"], name: "id"), requiresActiveList: true)
            let count = taskCount(section: section.id)
            try changed(tasks.removeListSection(section.id))
            return .object(["id": .string(section.id), "title": .string(section.title), "list": .string(section.listName),
                            "deleted": .bool(true), "tasksUngrouped": .number(Double(count))])
        default: return nil
        }
    }

    func automationSection(_ id: String, inList list: String? = nil, requiresActiveList: Bool = false) throws -> TaskListSection {
        guard let section = tasks.listSections.first(where: { $0.id == id }) else {
            throw AutomationFailure(code: "not_found", message: "任务分组不存在；请先运行 section list。")
        }
        guard list == nil || list == section.listName else {
            throw AutomationFailure.argument("任务分组不属于目标清单，请同时指定该分组所属的 list。")
        }
        _ = try managedList(section.listName, requiresActive: requiresActiveList)
        return section
    }

    private func existingList(_ raw: String?) throws -> String {
        let name = try nonempty(raw, name: "name/list")
        guard tasks.allListNames.contains(name) else {
            throw AutomationFailure(code: "not_found", message: "清单不存在；请先运行 list list。")
        }
        return name
    }
    private func managedList(_ raw: String?, requiresActive: Bool = false) throws -> String {
        let name = try existingList(raw)
        guard name != TaskList.inbox.name else { throw AutomationFailure.argument("收集箱不支持清单管理或自定义分组。") }
        if requiresActive { _ = try taskList(name) }
        return name
    }
    private func newListName(_ raw: String?) throws -> String {
        let name = try nonempty(raw, name: "name/to")
        guard name != TaskList.inbox.name, name != TaskList.notes.name else {
            throw AutomationFailure.argument("该名称由系统使用，请换一个清单名称。")
        }
        guard !tasks.allListNames.contains(name) else { throw duplicate("清单") }
        return name
    }
    private var groupNames: [String] {
        let explicit = tasks.listFolders.sorted { ($0.sortOrder, $0.name) < ($1.sortOrder, $1.name) }.map(\.name)
        let implicit = Set(tasks.listMetas.compactMap(\.folderName)).subtracting(explicit).sorted()
        return explicit + implicit
    }
    private func existingGroup(_ raw: String?) throws -> String {
        let name = try nonempty(raw, name: "group/name")
        guard groupNames.contains(name) else { throw AutomationFailure(code: "not_found", message: "清单分组不存在；请先运行 group list。") }
        return name
    }
    private func groupMembers(_ name: String) -> [String] { tasks.allListNames.filter { tasks.folderName(forList: $0) == name } }
    private func taskCount(list: String? = nil, section: String? = nil) -> Int {
        tasks.allTasks.filter { !$0.isNoteTask && $0.deletedAt == nil && $0.skippedAt == nil && !$0.isConverted
            && (list == nil || $0.list.name == list) && (section == nil || $0.sectionID == section) }.count
    }
    private func listValue(_ name: String) -> AutomationValue {
        .object(["name": .string(name), "group": tasks.folderName(forList: name).map { .string($0) } ?? .null,
                 "archived": .bool(tasks.isListArchived(name)), "taskCount": .number(Double(taskCount(list: name))),
                 "sectionCount": .number(Double(tasks.listSections(forList: name).count))])
    }
    private func groupValue(_ name: String) -> AutomationValue {
        .object(["name": .string(name), "lists": .array(groupMembers(name).map(listValue))])
    }
    private func sectionValue(_ section: TaskListSection) -> AutomationValue {
        .object(["id": .string(section.id), "title": .string(section.title), "list": .string(section.listName),
                 "sortOrder": .number(Double(section.sortOrder)), "taskCount": .number(Double(taskCount(section: section.id)))])
    }
    private func availableSectionTitle(_ title: String, list: String, excluding id: String? = nil) throws {
        guard !tasks.listSections(forList: list).contains(where: { $0.title == title && $0.id != id }) else { throw duplicate("任务分组") }
    }
    private func duplicate(_ object: String) -> AutomationFailure { AutomationFailure(code: "already_exists", message: "同名\(object)已存在。") }
    private func changed(_ result: Bool) throws {
        guard result else { throw AutomationFailure(code: "operation_failed", message: "清单或分组操作未完成。") }
    }
}
