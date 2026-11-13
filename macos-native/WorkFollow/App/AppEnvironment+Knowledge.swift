import Foundation

extension AppEnvironment {
    func textAIClient() throws -> SummaryPiOptimizer {
        var client = SummaryPiOptimizer()
        client.executable = meetingStore.configuration.executable
        client.model = meetingStore.configuration.resolvedMinutesModel
        client.textModel = try aiModels.request()
        client.conversationDirectory = aiChat.sessionDirectory
        return client
    }

    func knowledgeCorpus() -> KnowledgeCorpus {
        KnowledgeCorpus(tasks: taskWorkspace.allTasks, notes: notesWorkspace.notes,
            meetings: meetingStore.meetings, currentList: taskWorkspace.activeList,
            now: taskWorkspace.clock(), calendar: taskWorkspace.calendar, index: knowledgeIndex)
    }

    @discardableResult
    func openKnowledgeSource(_ source: KnowledgePassage) -> Bool {
        let link: NativeResourceLink
        switch source.kind {
        case .task: link = .task(source.resourceID)
        case .note: link = .note(source.resourceID)
        case .meeting: link = .meeting(source.resourceID)
        }
        guard NativeResourceLinkRouter.open(link, tasks: taskWorkspace, notes: notesWorkspace,
            navigation: navigation, meetings: meetingStore) else {
            feedback.show(FeedbackEvent(kind: .error, message: "这份来源已不可用，请重新提问。")); return false
        }
        switch source.kind {
        case .meeting: meetingStore.revealTranscript(meetingID: source.resourceID, lineID: source.lineID)
        case .task: taskWorkspace.requestSearchReveal(taskID: source.resourceID, query: source.revealQuery ?? "", blockID: source.blockID)
        case .note: notesWorkspace.requestSearchReveal(noteID: source.resourceID, query: source.revealQuery ?? "", blockID: source.blockID)
        }
        commandPalettePresented = false
        feedback.show(FeedbackEvent(kind: .navigation, message: "已打开「\(source.title)」",
            destinationTitle: "返回问答", destinationAction: { [weak self] in self?.commandPalettePresented = true }))
        return true
    }
}
