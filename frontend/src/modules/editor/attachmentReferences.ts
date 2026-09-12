import type { Attachment } from '@/services/api'

const ATTACHMENT_URL_PREFIX = '/api/attachments/'

function isRecord(value: unknown): value is Record<string, unknown> {
  return typeof value === 'object' && value !== null && !Array.isArray(value)
}

function attachmentIdFromUrl(value: unknown): string | null {
  if (typeof value !== 'string' || !value.trim()) return null
  const markerIndex = value.indexOf(ATTACHMENT_URL_PREFIX)
  if (markerIndex < 0) return null
  return value.slice(markerIndex + ATTACHMENT_URL_PREFIX.length).split(/[/?#]/, 1)[0] || null
}

function attachmentIdFromImage(node: Record<string, unknown>): string | null {
  const attrs = isRecord(node.attrs) ? node.attrs : {}
  for (const key of ['attachmentId', 'fileId', 'attachment_id', 'file_id']) {
    const id = typeof attrs[key] === 'string' && attrs[key].trim() ? attrs[key].trim() : null
    if (id) return id
  }
  return attachmentIdFromUrl(attrs.src)
}

function attachmentIdsFromDiagram(node: Record<string, unknown>): string[] {
  const attrs = isRecord(node.attrs) ? node.attrs : {}
  const ids: string[] = []
  for (const key of ['sourceAttachmentId', 'previewAttachmentId']) {
    const id = typeof attrs[key] === 'string' && attrs[key].trim() ? attrs[key].trim() : null
    if (id) ids.push(id)
  }
  return ids
}

/** Collect attachment ids used by embedded content: images and diagram blocks. */
export function collectEmbeddedImageAttachmentIds(document: unknown): Set<string> {
  const ids = new Set<string>()

  function visit(node: unknown) {
    if (!isRecord(node)) return
    if (node.type === 'image') {
      const id = attachmentIdFromImage(node)
      if (id) ids.add(id)
    }
    if (node.type === 'diagramBlock') {
      attachmentIdsFromDiagram(node).forEach((id) => ids.add(id))
    }
    if (Array.isArray(node.content)) {
      node.content.forEach(visit)
    }
  }

  visit(document)
  return ids
}

/** Keep only files that are not already rendered as images in the document. */
export function filterStandaloneAttachments(attachments: Attachment[], document: unknown): Attachment[] {
  const embeddedIds = collectEmbeddedImageAttachmentIds(document)
  return attachments.filter((attachment) => (
    !attachment.mimeType.toLowerCase().startsWith('image/')
    && !embeddedIds.has(attachment.id)
  ))
}
