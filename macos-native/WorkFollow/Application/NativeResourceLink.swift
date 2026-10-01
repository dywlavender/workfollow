import AppKit

enum NativeResourceLink: Equatable {
    case task(UUID), note(UUID)

    init?(url: URL) {
        guard url.scheme?.lowercased() == "workfollow",
              url.pathComponents.count == 2,
              let id = UUID(uuidString: url.lastPathComponent) else { return nil }
        switch url.host?.lowercased() {
        case "task": self = .task(id)
        case "note": self = .note(id)
        default: return nil
        }
    }

    var url: URL {
        switch self {
        case let .task(id): return URL(string: "workfollow://task/\(id.uuidString)")!
        case let .note(id): return URL(string: "workfollow://note/\(id.uuidString)")!
        }
    }
}

@MainActor
enum NativeResourceLinkRouter {
    @discardableResult
    static func open(_ link: NativeResourceLink, tasks: TaskWorkspaceModel,
                     notes: NotesWorkspaceModel, navigation: AppNavigation) -> Bool {
        switch link {
        case let .task(id):
            guard let task = tasks.task(for: id), task.deletedAt == nil,
                  task.skippedAt == nil, !task.isConverted else { return false }
            if let parentID = task.parentID {
                guard let parent = tasks.task(for: parentID), parent.deletedAt == nil,
                      !parent.isConverted, parent.skippedAt == nil else { return false }
                if tasks.collapsedTaskIDs.contains(parentID) { tasks.toggleExpanded(parentID) }
            }
            tasks.activeList = nil
            tasks.activeTag = nil
            tasks.openFilter(nil)
            tasks.clearBulkSelection()
            let destination: NativeDestination = task.isClosed ? .completed : .allTasks
            navigation.taskSelectionToPreserveOnNextNavigation = navigation.destination == destination ? nil : id
            navigation.destination = destination
            tasks.select(id)
            notes.selectedID = nil
        case let .note(id):
            guard notes.notes.contains(where: { $0.id == id && $0.deletedAt == nil }) else { return false }
            navigation.taskSelectionToPreserveOnNextNavigation = nil
            navigation.destination = .notes
            tasks.select(nil)
            notes.selectedID = id
        }
        return true
    }
}

@MainActor
enum TaskLinkClipboard {
    static func copy(_ task: Task, to pasteboard: NSPasteboard = .general) -> Bool {
        guard task.deletedAt == nil, task.skippedAt == nil, !task.isConverted else { return false }
        let url = NativeResourceLink.task(task.id).url
        let item = NSPasteboardItem()
        item.setString(url.absoluteString, forType: .string)
        item.setString(url.absoluteString, forType: .URL)
        pasteboard.clearContents()
        return pasteboard.writeObjects([item])
    }
}

/// URL delivery can precede the first scene's environment wiring on cold launch.
@MainActor
final class NativeResourceLinkReceiver {
    private var pending: [URL] = []
    private var route: ((URL) -> Bool)?
    private var activate: (() -> Void)?

    func configure(route: @escaping (URL) -> Bool, activate: @escaping () -> Void) {
        self.route = route
        self.activate = activate
        let urls = pending
        pending.removeAll()
        receive(urls)
    }

    func receive(_ urls: [URL]) {
        guard let route else { pending += urls; return }
        for url in urls where route(url) { activate?() }
    }
}
