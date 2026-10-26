import Foundation

enum DocumentListStructure {
    static func ordinal(at index: Int, in blocks: [DocumentBlock]) -> Int {
        guard blocks.indices.contains(index), blocks[index].kind == .ordered else { return 1 }
        let current = blocks[index]
        if let start = current.listStart { return start }
        var ordinal = 1
        for previous in blocks[..<index].reversed() {
            guard previous.kind.isList, previous.indentLevel >= current.indentLevel else { break }
            if previous.indentLevel > current.indentLevel { continue }
            guard previous.kind == .ordered else { break }
            if let start = previous.listStart { return start + ordinal }
            ordinal += 1
        }
        return ordinal
    }

    /// Moving an item also moves its descendants, retaining relative depth.
    static func shifted(_ blocks: [DocumentBlock], selected: Set<Int>, by delta: Int) -> [DocumentBlock] {
        var affected = selected.filter { blocks.indices.contains($0) && blocks[$0].kind.isList }
        for index in Array(affected) {
            var child = index + 1
            while child < blocks.count, blocks[child].kind.isList,
                  blocks[child].indentLevel > blocks[index].indentLevel {
                affected.insert(child)
                child += 1
            }
        }
        guard !affected.isEmpty else { return blocks }
        let minimum = affected.map { blocks[$0].indentLevel }.min() ?? 0
        let maximum = affected.map { blocks[$0].indentLevel }.max() ?? 0
        let change = delta > 0 ? min(delta, 8 - maximum) : max(delta, -minimum)
        guard change != 0 else { return blocks }
        var result = blocks
        for index in affected { result[index].indentLevel += change }
        return result
    }
}
