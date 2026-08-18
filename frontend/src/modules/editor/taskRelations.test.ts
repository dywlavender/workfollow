import { describe, expect, it } from 'vitest'

import { collectTaskIds } from '@/modules/editor/taskRelations'

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
})
