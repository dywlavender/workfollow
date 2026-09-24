import Foundation

struct DocumentEditorState: Equatable {
    private(set) var documentID: UUID
    private(set) var selectedRange = NSRange(location: 0, length: 0)

    init(documentID: UUID) {
        self.documentID = documentID
    }

    mutating func bind(to documentID: UUID) {
        guard self.documentID != documentID else { return }
        self.documentID = documentID
        selectedRange = NSRange(location: 0, length: 0)
    }

    mutating func updateSelection(_ range: NSRange) {
        selectedRange = range
    }
}
