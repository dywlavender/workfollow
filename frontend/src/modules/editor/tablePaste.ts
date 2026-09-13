import type { JSONContent } from '@tiptap/core'

/**
 * 把外部表格数据（Excel 粘贴的 TSV/HTML、xlsx 导入的二维数组）转换成
 * Tiptap 表格 JSON 的纯函数集合。第一行一律提升为 tableHeader，与
 * Markdown 导出（markdownExport.renderTable 把首行当表头）的语义对齐。
 * 行列上限保护协同文档与 SQL 投影：大表会显著拖慢投影屏障的全量 JSON 比较。
 */
export const TABLE_IMPORT_MAX_ROWS = 200
export const TABLE_IMPORT_MAX_COLS = 20
const MAX_CELL_TEXT_LENGTH = 1000
const MAX_CELL_LINES = 20
const MAX_MERGE_SPAN = 50

export interface ImportedTableMeta {
  rows: number
  cols: number
  originalRows: number
  originalCols: number
}

export interface ImportedTable {
  json: JSONContent
  meta: ImportedTableMeta
}

/** HTML 路径里的单元格：合并信息单独携带，展开时再铺开。 */
export interface SpanCell {
  text: string
  colspan: number
  rowspan: number
}

/**
 * Excel / WPS 复制到剪贴板的纯文本是 TSV。只有真正带 Tab 的文本才值得
 * 转表，否则普通多行文本仍走默认粘贴。
 */
export function parseTsvGrid(text: string): string[][] | null {
  if (!text || !text.includes('\t')) return null
  return text.replace(/(?:\r?\n)+$/, '').split(/\r?\n/).map((line) => line.split('\t'))
}

/**
 * 带 colspan/rowspan 的行矩阵 → 补全占位的规则网格。被合并覆盖的位置补空
 * 串并记录占用，保证每行名义列数一致，是 ProseMirror 表格合法的前提。
 */
export function expandCellMatrix(rows: SpanCell[][]): string[][] {
  const grid: string[][] = []
  const occupied: boolean[][] = []
  const ensureRow = (rowIndex: number) => {
    while (grid.length <= rowIndex) {
      grid.push([])
      occupied.push([])
    }
  }
  rows.forEach((cells, rowIndex) => {
    ensureRow(rowIndex)
    let col = 0
    for (const cell of cells) {
      while (occupied[rowIndex][col]) col += 1
      const colspan = clampSpan(cell.colspan)
      const rowspan = clampSpan(cell.rowspan)
      for (let dr = 0; dr < rowspan; dr += 1) {
        ensureRow(rowIndex + dr)
        for (let dc = 0; dc < colspan; dc += 1) {
          occupied[rowIndex + dr][col + dc] = true
          grid[rowIndex + dr][col + dc] = dr === 0 && dc === 0 ? cell.text : ''
        }
      }
      col += colspan
    }
  })
  return grid
}

function clampSpan(value: number): number {
  const span = Math.floor(Number(value) || 1)
  return Math.max(1, Math.min(MAX_MERGE_SPAN, span))
}

/** 去掉尾部空行空列，补齐参差行的列数。 */
function normalizeGrid(grid: string[][]): { rows: string[][]; originalRows: number; originalCols: number } {
  let rowCount = grid.length
  while (rowCount > 0 && grid[rowCount - 1].every((cell) => !cell.trim())) rowCount -= 1
  const trimmed = grid.slice(0, rowCount)
  const colCount = trimmed.reduce((max, row) => Math.max(max, row.length), 0)
  let colEnd = colCount
  while (colEnd > 0) {
    let anyFilled = false
    for (const row of trimmed) {
      if ((row[colEnd - 1] ?? '').trim()) { anyFilled = true; break }
    }
    if (anyFilled) break
    colEnd -= 1
  }
  return {
    rows: trimmed.map((row) => Array.from({ length: colEnd }, (_, index) => row[index] ?? '')),
    originalRows: rowCount,
    originalCols: colEnd,
  }
}

function cellInlineNodes(text: string): JSONContent[] {
  const segments = text.split('\n').slice(0, MAX_CELL_LINES)
  const inline: JSONContent[] = []
  segments.forEach((segment, index) => {
    if (index > 0) inline.push({ type: 'hardBreak' })
    if (segment) inline.push({ type: 'text', text: segment })
  })
  return inline
}

function makeCell(type: 'tableCell' | 'tableHeader', text: string): JSONContent {
  const capped = text.length > MAX_CELL_TEXT_LENGTH ? text.slice(0, MAX_CELL_TEXT_LENGTH) : text
  return { type, content: [{ type: 'paragraph', content: cellInlineNodes(capped) }] }
}

/**
 * 规则网格 → 表格 JSON。首行提升为表头；超过上限时截断并在 meta 里带上
 * 原始尺寸，调用方负责提示。全空的网格返回 null，调用方不应插入空表。
 */
export function buildImportedTable(rawGrid: string[][]): ImportedTable | null {
  const { rows, originalRows, originalCols } = normalizeGrid(rawGrid)
  if (!rows.length || !originalCols) return null
  const truncatedRows = rows.slice(0, TABLE_IMPORT_MAX_ROWS).map((row) => row.slice(0, TABLE_IMPORT_MAX_COLS))
  const content = truncatedRows.map((row, rowIndex) => ({
    type: 'tableRow',
    content: row.map((text) => makeCell(rowIndex === 0 ? 'tableHeader' : 'tableCell', text)),
  }))
  return {
    json: { type: 'table', content },
    meta: {
      rows: truncatedRows.length,
      cols: truncatedRows[0].length,
      originalRows,
      originalCols,
    },
  }
}

export function tableFromTsv(text: string): ImportedTable | null {
  const grid = parseTsvGrid(text)
  return grid ? buildImportedTable(grid) : null
}

/** 调用方据此提示"超出上限已截断"。 */
export function importedTableTruncated(meta: ImportedTableMeta): boolean {
  return meta.originalRows > meta.rows || meta.originalCols > meta.cols
}

export function tableFromCellMatrix(rows: SpanCell[][]): ImportedTable | null {
  if (!rows.length) return null
  return buildImportedTable(expandCellMatrix(rows))
}

/**
 * 剪贴板 HTML 只在"表格主导"时接管（Excel / Numbers / WPS 的复制结果正文
 * 几乎只有表格）；混排的网页片段仍交给 Tiptap 默认解析，避免丢上下文。
 * 返回的是 DOM 表格元素，测试环境（无 DOMParser）返回 null。
 */
export function dominantTableElement(html: string): HTMLElement | null {
  if (typeof DOMParser === 'undefined') return null
  const doc = new DOMParser().parseFromString(html, 'text/html')
  const table = doc.body.querySelector('table')
  if (!table) return null
  const tableText = (table.textContent ?? '').trim()
  if (!tableText) return null
  const bodyText = (doc.body.textContent ?? '').trim()
  if (tableText.length < bodyText.length * 0.6) return null
  return table as HTMLElement
}

export function cellMatrixFromTableElement(table: HTMLElement): SpanCell[][] {
  const rows = Array.from(table.querySelectorAll<HTMLTableRowElement>('tr'))
    .filter((row) => row.closest('table') === table)
  return rows.map((row) => Array.from(row.cells).map((cell) => ({
    text: (cell.textContent ?? '').replace(/\s+/g, ' ').trim(),
    colspan: Number(cell.getAttribute('colspan') ?? 1) || 1,
    rowspan: Number(cell.getAttribute('rowspan') ?? 1) || 1,
  })))
}

export function tableFromHtml(html: string): ImportedTable | null {
  const table = dominantTableElement(html)
  if (!table) return null
  return tableFromCellMatrix(cellMatrixFromTableElement(table))
}
