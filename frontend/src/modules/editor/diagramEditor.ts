import { dataUrlToBlob, type DiagramEditorResult } from './drawioEmbed'
import { DiagramSaveConflictError, saveDiagramContent } from '@/services/api'

/**
 * diagramBlock 的编辑宿主逻辑（NoteEditor / RichTextDocument / TaskDetail 共用）：
 * 打开 drawio 弹窗后，弹窗头部每次"保存/保存并退出"都会回调一次持久化——
 * 新图首次保存成对创建附件并插入节点，已有图走成对保存端点（revision 乐观锁，
 * 冲突时备份对方版本再覆盖）。编辑存在感经 awareness 广播给其他协作者。
 */

const BLANK_PNG_DATA_URL = 'data:image/png;base64,iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQDwAEhQGAhKmMIQAAAABJRU5ErkJggg=='

export interface DiagramEditorHost {
  /** 新建流程图时的文件上传通道（笔记/代办各有端点）。 */
  uploadFile: (file: File) => Promise<{ id: string; name?: string }>
  /**
   * 打开 drawio 弹窗。弹窗内每次保存都会回调 options.onSave（宿主持久化并
   * 返回反馈文案）；弹窗关闭时 Promise 以 null 结束（内容已随存随报）。
   */
  openModal: (options: {
    xml: string | null
    sourceId: string | null
    onSave: (result: DiagramEditorResult) => Promise<string | null>
  }) => Promise<null>
  /** 轻量结果反馈（弹窗外的场景，如读取失败）。 */
  feedback: (message: string) => void
  /** 确认对话框：覆盖冲突、他人编辑中的非阻断提示。 */
  confirm: (message: string, options?: { title?: string; confirmLabel?: string; danger?: boolean }) => Promise<boolean>
  /** 本端开始/结束编辑某张图（写 awareness 存在感）。 */
  onEditingChange?: (sourceId: string | null) => void
  /** 其他人是否正在编辑这张图。 */
  editingPeer?: (sourceId: string) => { userName: string } | null
}

function diagramFile(name: string, content: string | Blob, type: string): File {
  const part = typeof content === 'string' ? new Blob([content], { type }) : content
  return new File([part], name, { type })
}

async function fetchText(attachmentId: string, failureMessage: string): Promise<string> {
  const response = await fetch(`/api/attachments/${attachmentId}`)
  if (!response.ok) throw new Error(failureMessage)
  return response.text()
}

async function fetchBlob(attachmentId: string, failureMessage: string): Promise<Blob> {
  const response = await fetch(`/api/attachments/${attachmentId}`)
  if (!response.ok) throw new Error(failureMessage)
  return response.blob()
}

export function createDiagramEditorHandler(host: DiagramEditorHost) {
  return async function openDiagramEditor(
    attrs: Record<string, unknown> | null,
    applyUpdate: (payload: Record<string, unknown>) => void,
  ): Promise<void> {
    const title = (attrs?.title as string | undefined)?.trim() || '流程图'
    const sourceId = attrs?.sourceAttachmentId as string | undefined
    const previewId = attrs?.previewAttachmentId as string | undefined
    if (sourceId && !previewId) {
      host.feedback('流程图数据异常，请删除后重新插入')
      return
    }

    // 编辑存在感：他人正在编辑时给出非阻断提示，仍可选择打开。
    if (sourceId) {
      const peer = host.editingPeer?.(sourceId) ?? null
      if (peer) {
        const proceed = await host.confirm(
          `${peer.userName} 正在编辑这张流程图，同时保存会相互覆盖。仍要打开吗？`,
          { title: '流程图正在被编辑', confirmLabel: '仍要打开', danger: false },
        )
        if (!proceed) return
      }
      host.onEditingChange?.(sourceId)
    }

    let xml: string | null = null
    if (sourceId) {
      try {
        xml = await fetchText(sourceId, '流程图源读取失败，请重试')
      } catch (error) {
        host.feedback(error instanceof Error ? error.message : '流程图源读取失败')
        return
      }
    }

    // 弹窗生命周期内的当前附件引用：新图首次保存后建立，之后每次保存原地推进。
    let currentSourceId = sourceId ?? null
    let currentPreviewId = previewId ?? null
    let currentRevision = Number(attrs?.revision ?? 1)

    const persist = async (result: DiagramEditorResult): Promise<string | null> => {
      const previewBlob = result.pngDataUrl
        ? dataUrlToBlob(result.pngDataUrl)
        : currentPreviewId
          ? await fetchBlob(currentPreviewId, '流程图预览读取失败，请重试')
          : dataUrlToBlob(BLANK_PNG_DATA_URL)
      const previewFile = new File(
        [previewBlob ?? (dataUrlToBlob(BLANK_PNG_DATA_URL) as Blob)],
        `${title}-预览.png`,
        { type: 'image/png' },
      )

      if (!currentSourceId) {
        const sourceAttachment = await host.uploadFile(diagramFile(`${title}.drawio`, result.xml, 'application/xml'))
        const previewAttachment = previewBlob
          ? await host.uploadFile(new File([previewBlob], `${title}-预览.png`, { type: 'image/png' }))
          : null
        currentSourceId = sourceAttachment.id
        currentPreviewId = previewAttachment?.id ?? null
        currentRevision = 1
        applyUpdate({
          type: 'diagramBlock',
          attrs: {
            sourceAttachmentId: currentSourceId,
            previewAttachmentId: currentPreviewId,
            revision: 1,
            title,
          },
        })
        // 新图落进正文后其他协作者才能感知，这里补上编辑存在感。
        host.onEditingChange?.(currentSourceId)
        return '已插入流程图'
      }

      const xmlFile = diagramFile(`${title}.drawio`, result.xml, 'application/xml')
      let saved
      let backupName: string | null = null
      try {
        saved = await saveDiagramContent({
          sourceAttachmentId: currentSourceId,
          previewAttachmentId: currentPreviewId as string,
          expectedRevision: currentRevision,
          xmlFile,
          previewFile,
        })
      } catch (error) {
        if (!(error instanceof DiagramSaveConflictError)) throw error
        const overwrite = await host.confirm('流程图已被他人更新。确定要用你的版本覆盖吗？', {
          title: '流程图保存冲突',
          confirmLabel: '覆盖并备份对方版本',
          danger: true,
        })
        if (!overwrite) {
          return '已取消保存，保留对方的最新版本'
        }
        // 覆盖前保全对方版本：把对方的图源另存为附件，任何一方的修改都可找回。
        try {
          const theirsXml = await fetchText(currentSourceId, '读取对方版本失败')
          const stamp = new Date().toISOString().slice(0, 19).replace(/[:T]/g, '-')
          const backup = await host.uploadFile(
            diagramFile(`${title}-冲突备份-${stamp}.drawio`, theirsXml, 'application/xml'),
          )
          backupName = backup.name ?? `${title}-冲突备份-${stamp}.drawio`
        } catch {
          backupName = null
        }
        saved = await saveDiagramContent({
          sourceAttachmentId: currentSourceId,
          previewAttachmentId: currentPreviewId as string,
          expectedRevision: error.currentRevision,
          xmlFile,
          previewFile,
        })
      }
      currentSourceId = saved.sourceAttachmentId
      currentPreviewId = saved.previewAttachmentId
      currentRevision = saved.revision
      applyUpdate({
        sourceAttachmentId: saved.sourceAttachmentId,
        previewAttachmentId: saved.previewAttachmentId,
        revision: saved.revision,
      })
      const backupSuffix = backupName ? `；对方版本已备份为「${backupName}」` : ''
      return saved.copied
        ? `已保存为新版本（原投稿/发布版本不受影响）${backupSuffix}`
        : `流程图已保存${backupSuffix}`
    }

    try {
      await host.openModal({ xml, sourceId: currentSourceId, onSave: persist })
    } catch (error) {
      host.feedback(error instanceof Error ? error.message : '流程图编辑器加载失败')
    } finally {
      if (currentSourceId) host.onEditingChange?.(null)
    }
  }
}
