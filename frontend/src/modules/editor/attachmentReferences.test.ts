import { describe, expect, it } from 'vitest'

import { collectEmbeddedImageAttachmentIds, filterStandaloneAttachments } from '@/modules/editor/attachmentReferences'

const attachments = [
  { id: 'image-1', originalName: '截图.png', mimeType: 'image/png' },
  { id: 'document-1', originalName: '说明.txt', mimeType: 'text/plain' },
] as never[]

describe('note attachment presentation', () => {
  it('recognizes new image attachment ids', () => {
    const document = {
      type: 'doc',
      content: [{ type: 'image', attrs: { attachmentId: 'image-1', src: '/api/attachments/image-1' } }],
    }

    expect([...collectEmbeddedImageAttachmentIds(document)]).toEqual(['image-1'])
    expect(filterStandaloneAttachments(attachments, document).map((item) => item.id)).toEqual(['document-1'])
  })

  it('keeps legacy src-only images out of the file list', () => {
    const document = {
      type: 'doc',
      content: [{ type: 'image', attrs: { src: '/api/attachments/image-1?download=1' } }],
    }

    expect(filterStandaloneAttachments(attachments, document).map((item) => item.id)).toEqual(['document-1'])
  })

  it('keeps a non-image file reference in the file list', () => {
    const document = {
      type: 'doc',
      content: [{ type: 'file', attrs: { attachmentId: 'document-1' } }],
    }

    expect(filterStandaloneAttachments(attachments, document).map((item) => item.id)).toEqual(['document-1'])
  })
})
