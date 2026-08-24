import { describe, expect, it } from 'vitest'
import { Schema } from '@tiptap/pm/model'

import { changedBlockRange, clampDocumentRange, collectTaskIds } from '@/modules/editor/taskRelations'

const schema = new Schema({
  nodes: {
    doc: { content: 'block+' },
    paragraph: { content: 'inline*', group: 'block' },
    text: { group: 'inline' },
  },
})

function createDocument() {
  return schema.node('doc', null, [schema.node('paragraph', null, [schema.text('边界测试')])])
}

describe('Note Task references', () => {
  it('collects task identities without requiring copied Task facts', () => {
    const document = {
      type: 'doc',
      content: [
        {
          type: 'paragraph',
          content: [{
            type: 'text',
            text: '接口联调',
            marks: [{ type: 'taskLink', attrs: { taskId: 'task-inline' } }],
          }],
        },
        { type: 'taskReference', attrs: { taskId: 'task-block' } },
      ],
    }

    expect(collectTaskIds(document)).toEqual(['task-inline', 'task-block'])
    expect(Object.keys(document.content[1].attrs!)).toEqual(['taskId'])
    expect(Object.keys(document.content[0].content![0].marks![0].attrs!)).toEqual(['taskId'])
  })

  it('keeps scan ranges inside the document at replacement boundaries', () => {
    const document = createDocument()
    const range = changedBlockRange(document, 0, document.content.size)

    expect(range).toEqual({ from: 0, to: document.content.size })
    expect(() => document.nodesBetween(range.from, range.to, () => undefined)).not.toThrow()
  })

  it('clamps malformed mapping endpoints before scanning', () => {
    const document = createDocument()

    expect(clampDocumentRange(document, -10, document.content.size + 10)).toEqual({
      from: 0,
      to: document.content.size,
    })
  })
})
