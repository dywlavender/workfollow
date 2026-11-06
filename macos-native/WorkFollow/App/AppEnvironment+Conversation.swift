import Foundation

extension AppEnvironment {
    func conversationClient() -> AIConversationClient {
        AIConversationClient(executable: meetingStore.configuration.executable,
            model: meetingStore.configuration.resolvedMinutesModel, directory: aiChat.sessionDirectory,
            assistantContext: { [weak self] in
                (self?.assistantMemories.entries ?? [], self?.assistantBriefing.context ?? "")
            })
    }
}
