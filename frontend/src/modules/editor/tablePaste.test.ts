import { describe, expect, it } from 'vitest'

import {
  buildImportedTable,
  expandCellMatrix,
  parseTsvGrid,
  tableFromCellMatrix,
  tableFromTsv,
  TABLE_IMPORT_MAX_COLS,
  TABLE_IMPORT_MAX_ROWS,
  type SpanCell,
} from './tablePaste'

type AnyNode = { type?: string; text?: string; content?: AnyNode[] }

function rowsOf(json: { content?: AnyNode[] }): AnyNode[][] {
  return (json.content ?? []).map((row) => row.content ?? [])
}

describe('parseTsvGrid', () => {
  it('按 Tab 和换行拆分', () => {
    expect(parseTsvGrid('a\tb\nc\td')).toEqual([['a', 'b'], ['c', 'd']])
  })

  it('容忍 CRLF 与结尾换行', () => {
    expect(parseTsvGrid('a\tb\r\nc\td\r\n')).toEqual([['a', 'b'], ['c', 'd']])
  })

  it('没有 Tab 的文本不转表', () => {
    expect(parseTsvGrid('普通的一段文字')).toBeNull()
    expect(parseTsvGrid('')).toBeNull()
  })

  it('单行多列也能转表', () => {
    expect(parseTsvGrid('a\tb\tc')).toEqual([['a', 'b', 'c']])
  })
})

describe('expandCellMatrix', () => {
  it('铺开 colspan/rowspan 并占位空串', () => {
    const rows: SpanCell[][] = [
      [{ text: '合并', colspan: 2, rowspan: 1 }],
      [{ text: 'c', colspan: 1, rowspan: 1 }, { text: 'd', colspan: 1, rowspan: 1 }],
    ]
    expect(expandCellMatrix(rows)).toEqual([
      ['合并', ''],
      ['c', 'd'],
    ])
  })

  it('rowspan 跨行时后续行从占用位置之后排布', () => {
    const rows: SpanCell[][] = [
      [{ text: '纵', colspan: 1, rowspan: 2 }, { text: 'b', colspan: 1, rowspan: 1 }],
      [{ text: 'c', colspan: 1, rowspan: 1 }],
    ]
    expect(expandCellMatrix(rows)).toEqual([
      ['纵', 'b'],
      ['', 'c'],
    ])
  })

  it('非法跨度按 1 处理', () => {
    const rows: SpanCell[][] = [[{ text: 'a', colspan: Number.NaN, rowspan: 0 }]]
    expect(expandCellMatrix(rows)).toEqual([['a']])
  })
})

describe('buildImportedTable', () => {
  it('生成 table/tableRow/tableHeader 结构', () => {
    const table = buildImportedTable([['名称', '数量'], ['笔', '3']])
    expect(table).not.toBeNull()
    expect(table!.json.type).toBe('table')
    const rows = table!.json.content as Array<{ type: string; content: Array<{ type: string }> }>
    expect(rows).toHaveLength(2)
    expect(rows[0].content.every((cell) => cell.type === 'tableHeader')).toBe(true)
    expect(rows[1].content.every((cell) => cell.type === 'tableCell')).toBe(true)
    expect(table!.meta).toEqual({ rows: 2, cols: 2, originalRows: 2, originalCols: 2 })
  })

  it('单元格文本进入 paragraph，换行转 hardBreak', () => {
    const table = buildImportedTable([['第一行\n第二行']])
    const header = rowsOf(table!.json)[0][0].content![0]
    expect(header.type).toBe('paragraph')
    expect(header.content?.map((node) => node.type)).toEqual(['text', 'hardBreak', 'text'])
  })

  it('去掉尾部空行空列并补齐参差行', () => {
    const table = buildImportedTable([
      ['a', 'b', ''],
      ['c', 'd', ''],
      ['', '', ''],
    ])
    expect(table!.meta).toEqual({ rows: 2, cols: 2, originalRows: 2, originalCols: 2 })
  })

  it('超过上限时截断并保留原始尺寸', () => {
    const grid = Array.from({ length: TABLE_IMPORT_MAX_ROWS + 5 }, (_, row) =>
      Array.from({ length: TABLE_IMPORT_MAX_COLS + 3 }, (_, col) => `r${row}c${col}`))
    const table = buildImportedTable(grid)
    expect(table!.meta.rows).toBe(TABLE_IMPORT_MAX_ROWS)
    expect(table!.meta.cols).toBe(TABLE_IMPORT_MAX_COLS)
    expect(table!.meta.originalRows).toBe(TABLE_IMPORT_MAX_ROWS + 5)
    expect(table!.meta.originalCols).toBe(TABLE_IMPORT_MAX_COLS + 3)
  })

  it('全空网格返回 null', () => {
    expect(buildImportedTable([[''], ['', '']])).toBeNull()
    expect(buildImportedTable([])).toBeNull()
  })

  it('参差行缺失的格子补空串', () => {
    const table = buildImportedTable([['a', 'b'], ['c']])
    const secondRow = rowsOf(table!.json)[1]
    expect(secondRow.map((cell) => (cell.content?.[0]?.content ?? []).map((node) => node.text ?? ''))).toEqual([['c'], []])
  })
})

describe('tableFromTsv', () => {
  it('TSV 直接转成带表头的表格', () => {
    const table = tableFromTsv('名称\t数量\n笔\t3')
    expect(table!.meta.cols).toBe(2)
    const headerRow = (table!.json.content as Array<{ content: Array<{ type: string }> }>)[0]
    expect(headerRow.content[0].type).toBe('tableHeader')
  })

  it('无 Tab 文本返回 null', () => {
    expect(tableFromTsv('just text')).toBeNull()
  })
})

describe('tableFromCellMatrix', () => {
  it('合并单元格展开后仍是规则网格', () => {
    const table = tableFromCellMatrix([
      [{ text: '合计', colspan: 2, rowspan: 1 }],
      [{ text: 'a', colspan: 1, rowspan: 1 }, { text: 'b', colspan: 1, rowspan: 1 }],
    ])
    expect(table!.meta).toEqual({ rows: 2, cols: 2, originalRows: 2, originalCols: 2 })
    const rows = table!.json.content as Array<{ content: Array<{ type: string }> }>
    expect(rows[1].content).toHaveLength(2)
  })
})
