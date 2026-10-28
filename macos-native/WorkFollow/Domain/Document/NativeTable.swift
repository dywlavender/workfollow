import Foundation

/// 正文内的表格。行/列都是普通字符串单元格，随 Delta 的 `workfollow-block`
/// embed 往返；渲染与编辑分别由附件单元和表格编辑窗负责。
struct NativeTable: Equatable, Codable, Identifiable {
    var id: UUID
    var rows: [[String]]

    static let defaultRowCount = 3
    static let defaultColumnCount = 3

    init(id: UUID = UUID(), rows: [[String]] = []) {
        self.id = id
        self.rows = Self.normalized(rows)
    }

    static func empty(rows: Int = defaultRowCount, columns: Int = defaultColumnCount) -> NativeTable {
        NativeTable(rows: Array(repeating: Array(repeating: "", count: max(1, columns)),
                                count: max(1, rows)))
    }

    /// 确保至少一行一列，且每行等宽（以最宽的一行为准补空单元格）。
    static func normalized(_ rows: [[String]]) -> [[String]] {
        let columns = max(1, rows.map(\.count).max() ?? defaultColumnCount)
        let source = rows.isEmpty
            ? Array(repeating: Array(repeating: "", count: columns), count: defaultRowCount)
            : rows
        return source.map { row in
            var padded = Array(row.prefix(columns))
            if padded.count < columns {
                padded.append(contentsOf: Array(repeating: "", count: columns - padded.count))
            }
            return padded
        }
    }

    var rowCount: Int { rows.count }
    var columnCount: Int { rows.first?.count ?? 0 }

    func text(row: Int, column: Int) -> String {
        guard rows.indices.contains(row), rows[row].indices.contains(column) else { return "" }
        return rows[row][column]
    }

    mutating func setText(_ text: String, row: Int, column: Int) {
        guard rows.indices.contains(row), rows[row].indices.contains(column) else { return }
        rows[row][column] = text
    }

    mutating func addRow() {
        rows.append(Array(repeating: "", count: max(1, columnCount)))
    }

    mutating func removeLastRow() {
        guard rows.count > 1 else { return }
        rows.removeLast()
    }

    mutating func addColumn() {
        rows = rows.map { $0 + [""] }
    }

    mutating func removeLastColumn() {
        guard columnCount > 1 else { return }
        rows = rows.map { Array($0.dropLast()) }
    }

    private enum CodingKeys: String, CodingKey { case id, rows }

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        id = try values.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        rows = Self.normalized(try values.decodeIfPresent([[String]].self, forKey: .rows) ?? [])
    }
}

/// 正文内的 LaTeX 公式（行内附件）。渲染由 `FormulaTypesetter` 完成，
/// 只覆盖常用排版子集，不做完整 TeX。
struct NativeFormula: Equatable, Codable, Identifiable {
    var id: UUID
    var latex: String

    init(id: UUID = UUID(), latex: String = "E = mc^2") {
        self.id = id
        self.latex = latex
    }

    static let empty = NativeFormula()
}
