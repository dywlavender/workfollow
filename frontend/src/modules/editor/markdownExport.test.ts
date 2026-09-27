import { describe, expect, it } from 'vitest'

import { noteToMarkdown } from './markdownExport'

describe('noteToMarkdown diagramBlock', () => {
  it('导出预览图链接（带 revision 缓存参数）', () => {
    const markdown = noteToMarkdown({
      title: '部署说明',
      contentJson: {
        type: 'doc',
        content: [
          {
            type: 'diagramBlock',
            attrs: { sourceAttachmentId: 'src-1', previewAttachmentId: 'pv-1', revision: 3, title: '部署流程' },
          },
        ],
      },
    })
    expect(markdown).toContain('![部署流程](/api/attachments/pv-1?v=3)')
  })

  it('缺少预览附件时跳过该块', () => {
    const markdown = noteToMarkdown({
      title: '部署说明',
      contentJson: {
        type: 'doc',
        content: [{ type: 'diagramBlock', attrs: { sourceAttachmentId: 'src-1', revision: 1 } }],
      },
    })
    expect(markdown).not.toContain('/api/attachments/')
  })
})
