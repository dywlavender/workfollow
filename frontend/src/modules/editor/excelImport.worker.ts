import { extractWorkbookData, type SpreadsheetData } from './excelWorkbook'

/**
 * 表格解析 Worker：主线程 postMessage(ArrayBuffer)，回一个 SpreadsheetData。
 * 大工作簿的解析放在这里，避免卡住编辑器主线程。
 */
type WorkerResponse = { ok: true; data: SpreadsheetData } | { ok: false; message: string }

const scope = self as unknown as {
  addEventListener: (type: 'message', listener: (event: MessageEvent<ArrayBuffer>) => void) => void
  postMessage: (message: WorkerResponse) => void
}

scope.addEventListener('message', (event) => {
  try {
    scope.postMessage({ ok: true, data: extractWorkbookData(event.data) })
  } catch {
    scope.postMessage({ ok: false, message: '无法读取该表格文件，请确认文件未损坏、未加密' })
  }
})
