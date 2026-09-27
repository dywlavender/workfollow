import { describe, expect, it } from 'vitest'

import { createDiagramPresenceBridge } from './diagramPresence'

function fakeAwareness() {
  const states = new Map<number, Record<string, unknown>>()
  const handlers: Array<() => void> = []
  return {
    clientID: 1,
    getStates: () => states,
    setLocalStateField: (field: string, value: unknown) => {
      const local = states.get(1) ?? {}
      if (value === null) delete local[field]
      else local[field] = value
      states.set(1, local)
    },
    on: (_event: string, handler: () => void) => { handlers.push(handler) },
    off: (_event: string, handler: () => void) => { const index = handlers.indexOf(handler); if (index >= 0) handlers.splice(index, 1) },
    emitChange: () => { handlers.forEach((handler) => handler()) },
    states,
  }
}

describe('createDiagramPresenceBridge', () => {
  it('收集他人正在编辑的图，忽略自己；无 user 字段时显示“其他人”', () => {
    const awareness = fakeAwareness()
    awareness.states.set(1, { diagramEditing: { sourceId: 'src-self' }, user: { name: '我' } })
    awareness.states.set(2, { diagramEditing: { sourceId: 'src-a' }, user: { name: '张三' } })
    awareness.states.set(3, { diagramEditing: { sourceId: 'src-b' } })
    awareness.states.set(4, { user: { name: '路人' } })

    const target: Record<string, { userName: string }> = {}
    const bridge = createDiagramPresenceBridge(awareness, target)
    expect(bridge).not.toBeNull()
    expect(Object.keys(target).sort()).toEqual(['src-a', 'src-b'])
    expect(target['src-a'].userName).toBe('张三')
    expect(target['src-b'].userName).toBe('其他人')
    bridge?.destroy()
  })

  it('change 事件后重建映射并移除过期项', () => {
    const awareness = fakeAwareness()
    awareness.states.set(2, { diagramEditing: { sourceId: 'src-a' }, user: { name: '张三' } })
    const target: Record<string, { userName: string }> = {}
    const bridge = createDiagramPresenceBridge(awareness, target)
    expect(target['src-a']).toBeDefined()

    awareness.states.delete(2)
    awareness.states.set(2, { diagramEditing: { sourceId: 'src-c' }, user: { name: '李四' } })
    awareness.emitChange()
    expect(target['src-a']).toBeUndefined()
    expect(target['src-c'].userName).toBe('李四')
    bridge?.destroy()
  })

  it('setLocalEditing 写入并清除本端字段', () => {
    const awareness = fakeAwareness()
    const bridge = createDiagramPresenceBridge(awareness, {})
    bridge?.setLocalEditing('src-x')
    expect(awareness.states.get(1)?.diagramEditing).toEqual({ sourceId: 'src-x' })
    bridge?.setLocalEditing(null)
    expect(awareness.states.get(1)?.diagramEditing).toBeUndefined()
    bridge?.destroy()
  })

  it('awareness 为空时返回 null（非协同视图）', () => {
    expect(createDiagramPresenceBridge(null, {})).toBeNull()
  })
})
