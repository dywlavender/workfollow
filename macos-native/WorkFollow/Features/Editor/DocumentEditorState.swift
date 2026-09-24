import Foundation

struct DocumentEditorState: Equatable {
    private(set) var taskID: UUID
    private(set) var selectedRange = NSRange(location: 0, length: 0)

    init(taskID: UUID) {
        self.taskID = taskID
    }

    mutating func bind(to taskID: UUID) {
        guard self.taskID != taskID else { return }
        self.taskID = taskID
        selectedRange = NSRange(location: 0, length: 0)
    }

    mutating func updateSelection(_ range: NSRange) {
        selectedRange = range
    }
}
