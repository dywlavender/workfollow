/**
 * drawio embed 模式的 postMessage 协议封装（proto=json：消息是序列化的 JSON 字符串）。
 *
 * 会话模型：
 * - {event:'init'} → 宿主发 {action:'load', xml}；
 * - capture()：宿主随时用 {action:'export'} 拉取当前图源（xml）与预览（png），
 *   用于"保存但不退出"的频繁保存；
 * - drawio 自己的保存/保存并退出/退出按钮产生的 {event:'save'}/{event:'exit'}
 *   也会更新/结束会话：exit 时 resolve 最后已知结果（未保存过则 null）。
 */

export interface DiagramEditorResult {
  xml: string
  pngDataUrl: string | null
}

export interface DrawioSession {
  /** 用户退出（未保存）时 resolve null；保存并退出/内部保存退出时 resolve 最后已知结果。 */
  whenFinished: Promise<DiagramEditorResult | null>
  /** 从编辑器导出当前图源与预览；导出失败返回 null。 */
  capture(): Promise<DiagramEditorResult | null>
  /** 请求编辑器退出，不触发保存。 */
  exit(): void
}

const INIT_TIMEOUT_MS = 20000
const EXPORT_TIMEOUT_MS = 20000

export const EMPTY_DIAGRAM_XML = [
  '<mxfile host="WorkFollow">',
  '<diagram name="Page-1">',
  '<mxGraphModel dx="900" dy="640" grid="1" gridSize="10" guides="1" tooltips="1" connect="1" arrows="1" fold="1" page="1" pageScale="1" pageWidth="850" pageHeight="1100">',
  '<root>',
  '<mxCell id="0" />',
  '<mxCell id="1" parent="0" />',
  '</root>',
  '</mxGraphModel>',
  '</diagram>',
  '</mxfile>',
].join('')

export function dataUrlToBlob(dataUrl: string): Blob | null {
  const match = /^data:([^;,]+)?(;base64)?,(.*)$/.exec(dataUrl)
  if (!match) return null
  const mime = match[1] || 'application/octet-stream'
  const isBase64 = Boolean(match[2])
  const payload = match[3]
  try {
    if (isBase64) {
      const bytes = Uint8Array.from(atob(payload), (character) => character.charCodeAt(0))
      return new Blob([bytes], { type: mime })
    }
    return new Blob([decodeURIComponent(payload)], { type: mime })
  } catch {
    return null
  }
}

export function startDrawioSession(
  iframe: HTMLIFrameElement,
  options: {
    xml: string | null
    onPhase?: (phase: 'editing' | 'exporting') => void
    onError?: (message: string) => void
  },
): DrawioSession {
  const { xml, onPhase } = options
  let latest: DiagramEditorResult | null = null
  let finished = false
  let initTimer: number | undefined
  let exportTimer: number | undefined
  let finishResolve: ((result: DiagramEditorResult | null) => void) | null = null
  let exportWaiter: { format: string; resolve: (data: string | null) => void } | null = null
  /** capture() 等待内部"保存"按钮触发的 save 事件时挂起的回调。 */
  let pendingXmlResolve: ((xml: string | null) => void) | null = null

  const whenFinished = new Promise<DiagramEditorResult | null>((resolve) => { finishResolve = resolve })

  const post = (message: Record<string, unknown>) => {
    iframe.contentWindow?.postMessage(JSON.stringify(message), '*')
  }

  const finish = (result: DiagramEditorResult | null) => {
    if (finished) return
    finished = true
    window.clearTimeout(initTimer)
    window.clearTimeout(exportTimer)
    window.removeEventListener('message', onMessage)
    finishResolve?.(result)
    finishResolve = null
  }

  const requestExport = (format: 'xml' | 'png'): Promise<string | null> =>
    new Promise((resolve) => {
      if (finished) { resolve(null); return }
      if (exportWaiter) { resolve(null); return }
      exportWaiter = { format, resolve }
      post({
        action: 'export',
        format,
        ...(format === 'png' ? { fill: '#ffffff', scale: '2' } : {}),
      })
      window.setTimeout(() => {
        if (exportWaiter?.format === format) {
          exportWaiter = null
          resolve(null)
        }
      }, EXPORT_TIMEOUT_MS)
    })

  const onMessage = (event: MessageEvent) => {
    if (event.source !== iframe.contentWindow) return
    let data: Record<string, unknown>
    try {
      data = (typeof event.data === 'string' ? JSON.parse(event.data) : event.data) as Record<string, unknown>
    } catch {
      return
    }
    if (!data || typeof data !== 'object') return

    if (data.event === 'export' && exportWaiter && data.format === exportWaiter.format) {
      const waiter = exportWaiter
      exportWaiter = null
      waiter.resolve(typeof data.data === 'string' ? data.data : null)
      return
    }

    switch (data.event) {
      case 'init':
        window.clearTimeout(initTimer)
        post({ action: 'load', xml: xml ?? EMPTY_DIAGRAM_XML })
        break
      case 'save':
        if (typeof data.xml === 'string' && data.xml) {
          latest = { xml: data.xml, pngDataUrl: latest?.pngDataUrl ?? null }
          if (pendingXmlResolve) {
            // capture() 在等图源：交给它，PNG 由它自己请求。
            const resolveXml = pendingXmlResolve
            pendingXmlResolve = null
            resolveXml(data.xml)
          } else {
            onPhase?.('exporting')
            void requestExport('png').then((png) => {
              if (latest && png !== null) latest.pngDataUrl = png
            })
          }
        }
        break
      case 'exit':
        finish(latest)
        break
    }
  }

  const session: DrawioSession = {
    whenFinished,
    async capture() {
      if (finished) return null
      onPhase?.('exporting')
      try {
        // embed 协议没有"导出 xml"动作：点击 drawio 内部的"保存"按钮触发
        // {event:'save'} 拿图源（同源 DOM 可达），PNG 仍走 export 动作。
        const doc = iframe.contentDocument
        const saveButton = [...(doc?.querySelectorAll<HTMLButtonElement | HTMLAnchorElement>('button, .geBtn, a.geBtn') ?? [])]
          .find((button) => button.textContent?.trim() === '保存')
        if (!saveButton) return null
        const xmlPromise = new Promise<string | null>((resolve) => { pendingXmlResolve = resolve })
        saveButton.click()
        const xml = await Promise.race([
          xmlPromise,
          new Promise<string | null>((resolve) => window.setTimeout(() => resolve(null), EXPORT_TIMEOUT_MS)),
        ])
        pendingXmlResolve = null
        if (xml === null) return null
        latest = { xml, pngDataUrl: latest?.pngDataUrl ?? null }
        const png = await requestExport('png')
        if (png !== null) latest.pngDataUrl = png
        return { xml, pngDataUrl: latest.pngDataUrl }
      } finally {
        onPhase?.('editing')
      }
    },
    exit() {
      post({ action: 'exit' })
    },
  }

  initTimer = window.setTimeout(() => {
    if (finished) return
    const message = '流程图编辑器加载超时，请检查 drawio 资源部署'
    options.onError?.(message)
    finish(null)
  }, INIT_TIMEOUT_MS)

  window.addEventListener('message', onMessage)
  return session
}
