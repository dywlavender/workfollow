import { reactive } from 'vue'

/**
 * 流程图编辑存在感（第一档协同）：借协同服务的 awareness 广播"谁正在编辑
 * 哪张图"。不产生任何后端改动，也不阻断编辑——只在其他人正文里显示徽标，
 * 打开时给出非阻断提示。bridge 写入宿主提供的 reactive 对象，NodeView 经
 * editor.storage 读取它获得响应性。
 */

export interface DiagramEditingPeer {
  userName: string
}

export interface DiagramPresenceBridge {
  /** sourceId → 正在编辑这张图的人（只含他人）。 */
  editorsBySource: Record<string, DiagramEditingPeer>
  setLocalEditing(sourceId: string | null): void
  destroy(): void
}

interface AwarenessLike {
  clientID: number
  getStates(): Map<number, Record<string, unknown>>
  setLocalStateField(field: string, value: unknown): void
  on(event: string, handler: () => void): void
  off(event: string, handler: () => void): void
}

export type { AwarenessLike }

export function createDiagramPresenceBridge(
  awareness: AwarenessLike | null,
  target: Record<string, DiagramEditingPeer>,
): DiagramPresenceBridge | null {
  if (!awareness) return null

  const rebuild = () => {
    const next: Record<string, DiagramEditingPeer> = {}
    awareness.getStates().forEach((state, clientID) => {
      if (clientID === awareness.clientID) return
      const editing = state.diagramEditing as { sourceId?: unknown } | undefined
      if (!editing || typeof editing.sourceId !== 'string' || !editing.sourceId) return
      const user = state.user as { name?: unknown } | undefined
      next[editing.sourceId] = {
        userName: typeof user?.name === 'string' && user.name ? user.name : '其他人',
      }
    })
    // 原地更新：保持对象引用不变，宿主与 NodeView 持有的都是同一响应式对象。
    for (const key of Object.keys(target)) {
      if (!next[key]) delete target[key]
    }
    for (const [key, value] of Object.entries(next)) {
      target[key] = value
    }
  }

  awareness.on('change', rebuild)
  awareness.on('remove', rebuild)
  rebuild()

  return {
    editorsBySource: target,
    setLocalEditing(sourceId: string | null) {
      awareness.setLocalStateField('diagramEditing', sourceId ? { sourceId } : null)
    },
    destroy() {
      awareness.setLocalStateField('diagramEditing', null)
      awareness.off('change', rebuild)
      awareness.off('remove', rebuild)
    },
  }
}
