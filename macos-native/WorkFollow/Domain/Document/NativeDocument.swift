import Foundation

struct NativeDocument: Equatable, Codable {
    var blocks: [DocumentBlock]

    static var empty: NativeDocument { NativeDocument(plainText: "") }

    init(blocks: [DocumentBlock]) {
        self.blocks = blocks.isEmpty ? [DocumentBlock(kind: .paragraph)] : blocks
    }

    init(plainText: String) {
        let normalized = plainText
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
        self.blocks = normalized.components(separatedBy: "\n").map {
            DocumentBlock(kind: .paragraph, runs: [DocumentRun(text: $0)])
        }
    }

    var plainText: String { blocks.map(\.plainText).joined(separator: "\n") }
    var isEmpty: Bool { blocks.count == 1 && blocks[0].plainText.isEmpty }

    /// Rebuilds the first-version paragraph model while retaining IDs for lines
    /// that stayed in place or moved outside the edited span.
    func replacingPlainText(_ text: String) -> NativeDocument {
        let normalized = text
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
        let newLines = normalized.components(separatedBy: "\n")
        let oldLines = blocks.map(\.plainText)
        var ids = Array<UUID?>(repeating: nil, count: newLines.count)

        var prefix = 0
        while prefix < min(oldLines.count, newLines.count),
              oldLines[prefix] == newLines[prefix] {
            ids[prefix] = blocks[prefix].id
            prefix += 1
        }

        var oldSuffix = oldLines.count
        var newSuffix = newLines.count
        while oldSuffix > prefix, newSuffix > prefix,
              oldLines[oldSuffix - 1] == newLines[newSuffix - 1] {
            oldSuffix -= 1
            newSuffix -= 1
            ids[newSuffix] = blocks[oldSuffix].id
        }

        let oldEditedCount = oldSuffix - prefix
        let newEditedCount = newSuffix - prefix
        for offset in 0..<min(oldEditedCount, newEditedCount) {
            ids[prefix + offset] = blocks[prefix + offset].id
        }

        let newBlocks = newLines.enumerated().map { index, line in
            DocumentBlock(id: ids[index] ?? UUID(), kind: .paragraph,
                          runs: [DocumentRun(text: line)])
        }
        return NativeDocument(blocks: newBlocks)
    }
}

struct DocumentBlock: Identifiable, Equatable, Codable {
    let id: UUID
    var kind: DocumentBlockKind
    var runs: [DocumentRun]

    init(id: UUID = UUID(), kind: DocumentBlockKind, runs: [DocumentRun] = []) {
        self.id = id
        self.kind = kind
        self.runs = runs
    }

    var plainText: String { runs.map(\.text).joined() }
}

enum DocumentBlockKind: Equatable, Codable {
    case paragraph
    case heading(Int)
    case bullet
    case ordered
    case checklist(Bool)
    case quote
    case code
}

struct DocumentRun: Equatable, Codable {
    var text: String
    var marks: Set<DocumentMark>

    init(text: String, marks: Set<DocumentMark> = []) {
        self.text = text
        self.marks = marks
    }
}

enum DocumentMark: Hashable, Codable {
    case bold
    case italic
    case underline
    case highlight
    case strikethrough
    case code
    case link(String)
}
