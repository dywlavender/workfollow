import Foundation

extension AppEnvironment {
    /// Returns true for recognized local links, including unavailable targets,
    /// so an internal link never falls back to opening an unrelated URL handler.
    @discardableResult
    func openResourceLink(_ url: URL) -> Bool {
        guard let link = NativeResourceLink(url: url) else { return false }
        if !NativeResourceLinkRouter.open(link, tasks: taskWorkspace, notes: notesWorkspace, navigation: navigation) {
            feedback.show(FeedbackEvent(kind: .error, message: "链接目标不存在或已不可用"))
        }
        return true
    }
}
