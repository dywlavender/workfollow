import { describe, expect, it, vi } from 'vitest'

import { TaskSaveQueue, type TaskSaveData } from '@/modules/todo/taskSaveQueue'

type SavePayload = { title: string; description: string; contentJson: { type: string; content: Array<{ type: string; text: string }> } }
type Deferred = { request: TaskSaveData<SavePayload>; settle: (ok: boolean) => void }

function deferredDispatch() {
  const calls: Deferred[] = []
  const dispatch = vi.fn((request: TaskSaveData<SavePayload>) => new Promise<boolean>((resolve) => calls.push({ request, settle: resolve })))
  return { calls, dispatch }
}

async function tick() { await Promise.resolve(); await Promise.resolve() }

describe('TaskSaveQueue', () => {
  it('keeps the latest edits for A and B when switching tasks under slow requests', async () => {
    const { calls, dispatch } = deferredDispatch()
    const queue = new TaskSaveQueue<SavePayload>(dispatch)

    queue.enqueue('A', { title: 'A1' })
    queue.enqueue('A', { title: 'A2', description: 'A正文最终版' })
    queue.enqueue('B', { title: 'B1' })
    queue.enqueue('B', { title: 'B2', description: 'B正文最终版' })

    expect(calls.map(({ request }) => request.todoId)).toEqual(['A', 'B'])
    calls[0].settle(true)
    calls[1].settle(true)
    await tick()
    expect(calls).toHaveLength(4)
    expect(calls[2].request).toMatchObject({ todoId: 'A', data: { title: 'A2', description: 'A正文最终版' } })
    expect(calls[3].request).toMatchObject({ todoId: 'B', data: { title: 'B2', description: 'B正文最终版' } })
    calls[2].settle(true)
    calls[3].settle(true)
    await tick()
    expect(queue.status('A')).toBe('saved')
    expect(queue.status('B')).toBe('saved')
  })

  it('binds failure to its task, lets the other task finish, and retries retained data', async () => {
    const { calls, dispatch } = deferredDispatch()
    const statuses: Array<[string, string]> = []
    const queue = new TaskSaveQueue<SavePayload>(dispatch, (id, status) => statuses.push([id, status]))

    queue.enqueue('A', { title: 'A最终版', description: '不可丢失' })
    queue.enqueue('B', { title: 'B最终版' })
    calls[0].settle(false)
    calls[1].settle(true)
    await tick()

    expect(queue.status('A')).toBe('error')
    expect(queue.status('B')).toBe('saved')
    expect(statuses).toContainEqual(['A', 'error'])
    expect(statuses).toContainEqual(['B', 'saved'])

    queue.retry('A')
    expect(calls[2].request).toMatchObject({ todoId: 'A', data: { title: 'A最终版', description: '不可丢失' } })
    calls[2].settle(true)
    await tick()
    expect(queue.status('A')).toBe('saved')
  })

  it('waits for an unmount flush and snapshots the complete payload at enqueue time', async () => {
    const { calls, dispatch } = deferredDispatch()
    const queue = new TaskSaveQueue<SavePayload>(dispatch)
    const payload = {
      title: '关闭前标题',
      description: '关闭前正文',
      contentJson: { type: 'doc', content: [{ type: 'text', text: '关闭前正文' }] },
    }

    queue.enqueue('A', payload)
    payload.title = '入队后被修改'
    payload.contentJson.content[0].text = '入队后被修改'
    const flushed = queue.waitFor('A')

    expect(queue.hasUnsaved('A')).toBe(true)
    expect(calls[0].request.data).toEqual({
      title: '关闭前标题',
      description: '关闭前正文',
      contentJson: { type: 'doc', content: [{ type: 'text', text: '关闭前正文' }] },
    })
    calls[0].settle(true)
    await expect(flushed).resolves.toBe(true)
    expect(queue.hasUnsaved('A')).toBe(false)
  })

  it('reports a failed unmount flush so closing can be cancelled', async () => {
    const { calls, dispatch } = deferredDispatch()
    const queue = new TaskSaveQueue<SavePayload>(dispatch)
    queue.enqueue('A', { title: '未保存标题' })

    const flushed = queue.waitFor('A')
    calls[0].settle(false)

    await expect(flushed).resolves.toBe(false)
    expect(queue.hasUnsaved('A')).toBe(true)
    expect(queue.status('A')).toBe('error')
  })
})
