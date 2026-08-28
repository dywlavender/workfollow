import { describe, expect, it } from 'vitest'

import { contentJsonSemanticallyEqual } from './contentProjection'

describe('content projection comparison', () => {
  it('ignores editor block ids and default null attributes', () => {
    expect(contentJsonSemanticallyEqual(
      {
        type: 'doc',
        content: [{ type: 'paragraph', attrs: { blockId: 'local-id', textAlign: null }, content: [{ type: 'text', text: '正文' }] }],
      },
      {
        type: 'doc',
        content: [{ type: 'paragraph', content: [{ type: 'text', text: '正文' }] }],
      },
    )).toBe(true)
  })

  it('keeps resource identities and visible edits significant', () => {
    expect(contentJsonSemanticallyEqual(
      { type: 'taskReference', attrs: { taskId: 'task-a', blockId: 'a' } },
      { type: 'taskReference', attrs: { taskId: 'task-b', blockId: 'b' } },
    )).toBe(false)
    expect(contentJsonSemanticallyEqual(
      { type: 'doc', content: [{ type: 'paragraph', content: [{ type: 'text', text: 'A' }] }] },
      { type: 'doc', content: [{ type: 'paragraph', content: [{ type: 'text', text: 'B' }] }] },
    )).toBe(false)
  })
})
