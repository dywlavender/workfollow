import Foundation

struct SummaryDraftReview {
    struct Section: Identifiable {
        let id: Int
        let title: String
        let before: [DocumentBlock]
        let after: [DocumentBlock]
        var changed: Bool {
            before.map { $0.runs } != after.map { $0.runs }
                || before.map { $0.kind } != after.map { $0.kind }
        }
    }
    let sections: [Section]
    var changedIDs: Set<Int> { Set(sections.filter(\.changed).map(\.id)) }

    init(original: NativeDocument, candidate: NativeDocument) {
        func split(_ document: NativeDocument) -> [(String, [DocumentBlock])] {
            var result: [(String, [DocumentBlock])] = []
            for block in document.blocks {
                if case .heading(let level) = block.kind, level <= 2 { result.append((block.plainText, [block])) }
                else if result.isEmpty { result.append(("正文", [block])) }
                else { result[result.count - 1].1.append(block) }
            }
            return result
        }
        let before = split(original), after = split(Self.restoringLinks(in: candidate, from: original))
        var used: Set<Int> = []
        var values: [Section] = []
        for (title, blocks) in before {
            let match = after.indices.first { !used.contains($0) && after[$0].0 == title }
            if let match { used.insert(match) }
            values.append(.init(id: values.count, title: title, before: blocks, after: match.map { after[$0].1 } ?? []))
        }
        for index in after.indices where !used.contains(index) {
            values.append(.init(id: values.count, title: after[index].0, before: [], after: after[index].1))
        }
        sections = values
    }
    /// Exact task titles retain their existing resource links in rewritten text.
    /// Existing links in the candidate remain authoritative.
    private static func restoringLinks(in candidate: NativeDocument, from original: NativeDocument) -> NativeDocument {
        let linked = original.blocks.flatMap(\.runs).filter { run in
            !run.text.isEmpty && run.marks.contains { if case .link = $0 { return true }; return false }
        }
        let known = Dictionary(grouping: linked, by: \.text).compactMap { title, runs -> DocumentRun? in
            let links = Set(runs.flatMap(\.marks).filter { if case .link = $0 { return true }; return false })
            guard links.count == 1 else { return nil }
            return DocumentRun(text: title, marks: links)
        }
        return NativeDocument(blocks: candidate.blocks.map { block in
            var value = block
            value.runs = block.runs.flatMap { run -> [DocumentRun] in
                guard run.attachment == nil, run.diagram == nil,
                      run.table == nil, run.formula == nil,
                      !run.marks.contains(where: { if case .link = $0 { return true }; return false }) else { return [run] }
                var remainder = run.text[...]
                var parts: [DocumentRun] = []
                while !remainder.isEmpty {
                    let match = known.compactMap { link -> (DocumentRun, Range<String.Index>)? in
                        remainder.range(of: link.text).map { (link, $0) }
                    }.min {
                        $0.1.lowerBound == $1.1.lowerBound ? $0.0.text.count > $1.0.text.count : $0.1.lowerBound < $1.1.lowerBound
                    }
                    guard let (link, range) = match else {
                        parts.append(.init(text: String(remainder), marks: run.marks)); break
                    }
                    if remainder.startIndex < range.lowerBound {
                        parts.append(.init(text: String(remainder[..<range.lowerBound]), marks: run.marks))
                    }
                    parts.append(.init(text: link.text, marks: run.marks.union(link.marks)))
                    remainder = remainder[range.upperBound...]
                }
                return parts.isEmpty ? [run] : parts
            }
            return value
        })
    }

    func applying(_ selected: Set<Int>) -> NativeDocument {
        NativeDocument(blocks: sections.flatMap {
            $0.changed && selected.contains($0.id) ? $0.after : $0.before
        })
    }
}
