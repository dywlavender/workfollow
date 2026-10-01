import Foundation

/// The existing responder order, shared as an explicit interaction contract.
enum DocumentEditorEscapeRoute: Equatable {
    case inputMethod, slash, selectionToolbar, findBar, host

    static func resolve(composing: Bool, slash: Bool, selectionToolbar: Bool,
                        findBar: Bool) -> Self {
        if composing { return .inputMethod }
        if slash { return .slash }
        if selectionToolbar { return .selectionToolbar }
        if findBar { return .findBar }
        return .host
    }
}

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
