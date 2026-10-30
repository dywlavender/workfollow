import SwiftUI

struct AIMessageContent: View {
    let text: String
    private enum Block {
        case paragraph(String), heading(String, Int), code(String), table([[String]])
    }
    private func inline(_ text: String) -> AttributedString {
        (try? AttributedString(markdown: text, options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace))) ?? AttributedString(text)
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            ForEach(Array(blocks.enumerated()), id: \.offset) { _, block in
                switch block {
                case let .paragraph(value): Text(inline(value)).font(WFType.body).lineSpacing(4).textSelection(.enabled)
                case let .heading(value, level):
                    Text(inline(value)).font(.system(size: level == 1 ? 20 : level == 2 ? 17 : 14, weight: .semibold)).textSelection(.enabled)
                case let .code(value):
                    ScrollView(.horizontal) {
                        Text(value).font(.system(size: 12, design: .monospaced)).textSelection(.enabled).padding(12)
                    }.background(WFColors.secondarySurface, in: RoundedRectangle(cornerRadius: 8))
                    .compactScrollbars()
                case let .table(rows):
                    ScrollView(.horizontal) {
                        Grid(alignment: .leading, horizontalSpacing: 18, verticalSpacing: 8) {
                            ForEach(rows.indices, id: \.self) { row in
                                GridRow {
                                    ForEach(rows[row].indices, id: \.self) { column in
                                        Text(inline(rows[row][column])).font(WFType.body)
                                            .fontWeight(row == 0 ? .semibold : .regular).textSelection(.enabled)
                                    }
                                }
                                if row == 0 { Divider().gridCellUnsizedAxes(.horizontal) }
                            }
                        }.padding(12)
                    }.background(WFColors.secondarySurface, in: RoundedRectangle(cornerRadius: 8))
                    .compactScrollbars()
                }
            }
        }.frame(maxWidth: .infinity, alignment: .leading)
    }
    private var blocks: [Block] {
        let lines = text.components(separatedBy: "\n")
        var result: [Block] = [], paragraph: [String] = [], index = 0
        func flush() { if !paragraph.isEmpty { result.append(.paragraph(paragraph.joined(separator: "\n"))); paragraph = [] } }
        func cells(_ line: String) -> [String] {
            line.trimmingCharacters(in: .whitespaces).trimmingCharacters(in: CharacterSet(charactersIn: "|"))
                .components(separatedBy: "|").map { $0.trimmingCharacters(in: .whitespaces) }
        }
        while index < lines.count {
            let line = lines[index], trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("```") {
                flush(); index += 1
                var code: [String] = []
                while index < lines.count && !lines[index].trimmingCharacters(in: .whitespaces).hasPrefix("```") {
                    code.append(lines[index]); index += 1
                }
                result.append(.code(code.joined(separator: "\n")))
            } else if trimmed.hasPrefix("#"), let space = trimmed.firstIndex(of: " "),
                      trimmed[..<space].allSatisfy({ $0 == "#" }) {
                flush(); result.append(.heading(String(trimmed[trimmed.index(after: space)...]), trimmed.distance(from: trimmed.startIndex, to: space)))
            } else if line.contains("|"), index + 1 < lines.count,
                      lines[index + 1].contains("-"), lines[index + 1].allSatisfy({ "|:- \t".contains($0) }) {
                flush(); var rows = [cells(line)]; index += 2
                while index < lines.count && lines[index].contains("|") { rows.append(cells(lines[index])); index += 1 }
                result.append(.table(rows)); continue
            } else if trimmed.isEmpty { flush() }
            else {
                if trimmed.hasPrefix("- ") || trimmed.hasPrefix("* ") { paragraph.append("• " + trimmed.dropFirst(2)) }
                else { paragraph.append(line) }
            }
            index += 1
        }
        flush(); return result
    }
}
