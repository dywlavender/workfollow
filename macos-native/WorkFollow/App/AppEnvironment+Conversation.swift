import Foundation

extension AppEnvironment {
    func conversationClient() -> AIConversationClient {
        AIConversationClient(executable: meetingStore.configuration.executable,
            model: meetingStore.configuration.resolvedMinutesModel, directory: aiChat.sessionDirectory)
    }
}
