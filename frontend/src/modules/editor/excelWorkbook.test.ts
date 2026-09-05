import * as XLSX from 'xlsx'
import { describe, expect, it } from 'vitest'

import { extractWorkbookData } from './excelWorkbook'

function workbookBuffer(sheets: Record<string, unknown[][]>): ArrayBuffer {
  const workbook = XLSX.utils.book_new()
  for (const [name, rows] of Object.entries(sheets)) {
    const sheet = XLSX.utils.aoa_to_sheet(rows)
    XLSX.utils.book_append_sheet(workbook, sheet, name)
  }
  const output = XLSX.write(workbook, { type: 'array', bookType: 'xlsx' })
  return output as ArrayBuffer
}

describe('extractWorkbookData', () => {
  it('读取 sheet 名单与网格', () => {
    const data = extractWorkbookData(workbookBuffer({
      表格1: [['名称', '数量'], ['笔', 3]],
      表格2: [['a']],
    }))
    expect(data.sheets.map((sheet) => sheet.name)).toEqual(['表格1', '表格2'])
    expect(data.sheets[0]).toMatchObject({ rows: 2, cols: 2 })
    expect(data.grids['表格1']).toEqual([['名称', '数量'], ['笔', '3']])
  })

  it('空 sheet 产生空网格', () => {
    const data = extractWorkbookData(workbookBuffer({ 表格1: [] }))
    expect(data.grids['表格1']).toEqual([])
  })

  it('纯文本按 CSV 解析', () => {
    const csv = new TextEncoder().encode('a,b\n1,2').buffer as ArrayBuffer
    const data = extractWorkbookData(csv)
    expect(data.sheets).toHaveLength(1)
    expect(data.grids[data.sheets[0].name]).toEqual([['a', 'b'], ['1', '2']])
  })

  it('损坏的 xlsx 抛错', () => {
    const bytes = new Uint8Array([0x50, 0x4b, 0x03, 0x04, 1, 2, 3, 4])
    expect(() => extractWorkbookData(bytes.buffer as ArrayBuffer)).toThrow()
  })
})
