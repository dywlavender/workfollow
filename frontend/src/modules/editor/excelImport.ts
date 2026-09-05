import { buildImportedTable, type ImportedTable } from './tablePaste'
import type { SpreadsheetData } from './excelWorkbook'

/**
 * 表格导入的主线程入口：把 xlsx/xls/csv 文件交给 Worker 解析，再转成
 * Tiptap 表格 JSON。xlsx 依赖只出现在 Worker chunk 里，主线程不引入。
 */
export type { SpreadsheetData, SpreadsheetSheetMeta } from './excelWorkbook'

const WORKER_TIMEOUT_MS = 30000
const SPREADSHEET_SUFFIXES = ['xlsx', 'xls', 'csv']

export function isSpreadsheetName(name: string): boolean {
  const suffix = name.split('.').pop()?.toLowerCase() ?? ''
  return SPREADSHEET_SUFFIXES.includes(suffix)
}

export function isSpreadsheetFile(file: { name: string }): boolean {
  return isSpreadsheetName(file.name)
}

function runWorker(buffer: ArrayBuffer): Promise<SpreadsheetData> {
  return new Promise((resolve, reject) => {
    let worker: Worker
    try {
      worker = new Worker(new URL('./excelImport.worker.ts', import.meta.url), { type: 'module' })
    } catch {
      reject(new Error('无法启动表格解析线程，请重试'))
      return
    }
    const cleanup = () => {
      window.clearTimeout(timer)
      worker.terminate()
    }
    const timer = window.setTimeout(() => {
      cleanup()
      reject(new Error('表格解析超时，请拆分文件后重试'))
    }, WORKER_TIMEOUT_MS)
    worker.addEventListener('message', (event: MessageEvent<{ ok: true; data: SpreadsheetData } | { ok: false; message: string }>) => {
      cleanup()
      const response = event.data
      if (response.ok) resolve(response.data)
      else reject(new Error(response.message))
    })
    worker.addEventListener('error', () => {
      cleanup()
      reject(new Error('表格解析失败，请重试'))
    })
    worker.postMessage(buffer, [buffer])
  })
}

export async function readSpreadsheet(source: File | Blob): Promise<SpreadsheetData> {
  const buffer = await source.arrayBuffer()
  return runWorker(buffer)
}

export async function readSpreadsheetBuffer(buffer: ArrayBuffer): Promise<SpreadsheetData> {
  return runWorker(buffer)
}

export function spreadsheetTable(data: SpreadsheetData, sheetName: string): ImportedTable | null {
  const grid = data.grids[sheetName]
  return grid ? buildImportedTable(grid) : null
}
