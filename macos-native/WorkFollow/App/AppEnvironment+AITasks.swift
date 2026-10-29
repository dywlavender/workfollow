import Foundation

extension AppEnvironment {
    func aiTaskRequest(for note: Note) throws -> AITaskRequest {
        AITaskRequest(source: .note(note.id), title: note.title.isEmpty ? "未命名笔记" : note.title,
            content: try note.document.materialized().plainText, referenceDate: note.updatedAt,
            existingTitles: taskWorkspace.allTasks.filter {
                $0.deletedAt == nil && ($0.sourceNoteID == note.id || note.linkedTaskIDs.contains($0.id))
            }.map(\.title))
    }

    func aiTaskRequest(for meeting: MeetingRecord) -> AITaskRequest {
        // A generated summary is not a replacement for the original evidence.
        let transcript = meeting.transcript.map { $0.speaker + "：" + $0.text }.joined(separator: "\n")
        let content = transcript.isEmpty ? meeting.minutes.trimmingCharacters(in: .whitespacesAndNewlines) : transcript
        return AITaskRequest(source: .meeting(meeting.id), title: meeting.title,
            content: content,
            referenceDate: meeting.createdAt, existingTitles: taskWorkspace.allTasks.filter {
                $0.deletedAt == nil && $0.sourceMeetingID == meeting.id
            }.map(\.title))
    }

    func aiTaskRequest(for task: Task) throws -> AITaskRequest {
        AITaskRequest(source: .task(task.id), title: task.title,
            content: try task.document.materialized().plainText, referenceDate: Date(),
            existingTitles: taskWorkspace.allTasks.filter { $0.deletedAt == nil && $0.parentID == task.id }.map(\.title))
    }

    func applyAITasks(_ drafts: [AITaskDraft], request: AITaskRequest, list: String, sectionID: String?) throws {
        switch request.source {
        case let .note(id):
            guard notesWorkspace.notes.contains(where: { $0.id == id && $0.deletedAt == nil }) else { throw AITaskError.sourceMissing }
        case let .meeting(id):
            guard meetingStore.meetings.contains(where: { $0.id == id }) else { throw AITaskError.sourceMissing }
        case .task: break
        }
        let ids = try taskWorkspace.createAITasks(drafts, request: request, list: list, sectionID: sectionID)
        if ids.isEmpty { feedback.show(FeedbackEvent(kind: .info, message: "这些任务已存在，无需重复添加")) }
    }
}
