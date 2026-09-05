import * as XLSX from 'xlsx'

import { TABLE_IMPORT_MAX_COLS, TABLE_IMPORT_MAX_ROWS } from './tablePaste'

/**
 * xlsx / xls / csv → { sheet 元信息, 截断后的网格 }。
 * 只在 Worker 与测试里使用：xlsx 体积较大，主线程 bundle 不应引入；
 * 编辑器通过 excelImport.ts 的 Worker 封装拿到同样的数据结构。
 */
export interface SpreadsheetSheetMeta {
  name: string
  rows: number
  cols: number
}

export interface SpreadsheetData {
  sheets: SpreadsheetSheetMeta[]
  grids: Record<string, string[][]>
}

function sheetRange(sheet: XLSX.WorkSheet): XLSX.Range | null {
  const ref = sheet['!ref']
  return ref ? XLSX.utils.decode_range(ref) : null
}

function cellText(sheet: XLSX.WorkSheet, row: number, col: number): string {
  const cell = sheet[XLSX.utils.encode_cell({ r: row, c: col })] as XLSX.CellObject | undefined
  if (!cell) return ''
  // 优先取显示值（w）：数字与日期按文件里的格式呈现，而不是原始序列值。
  if (cell.w != null) return String(cell.w)
  if (cell.v != null) return String(cell.v)
  return ''
}

function cappedGrid(sheet: XLSX.WorkSheet): string[][] {
  const range = sheetRange(sheet)
  if (!range) return []
  const maxRow = Math.min(range.e.r, range.s.r + TABLE_IMPORT_MAX_ROWS - 1)
  const maxCol = Math.min(range.e.c, range.s.c + TABLE_IMPORT_MAX_COLS - 1)
  const grid: string[][] = []
  for (let row = range.s.r; row <= maxRow; row += 1) {
    const cells: string[] = []
    for (let col = range.s.c; col <= maxCol; col += 1) cells.push(cellText(sheet, row, col))
    grid.push(cells)
  }
  return grid
}

export function extractWorkbookData(buffer: ArrayBuffer): SpreadsheetData {
  const workbook = XLSX.read(buffer, { type: 'array' })
  const sheets: SpreadsheetSheetMeta[] = []
  const grids: Record<string, string[][]> = {}
  for (const name of workbook.SheetNames) {
    const sheet = workbook.Sheets[name]
    if (!sheet) continue
    const range = sheetRange(sheet)
    sheets.push({
      name,
      rows: range ? range.e.r - range.s.r + 1 : 0,
      cols: range ? range.e.c - range.s.c + 1 : 0,
    })
    grids[name] = cappedGrid(sheet)
  }
  return { sheets, grids }
}
