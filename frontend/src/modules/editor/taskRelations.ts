import { Extension, Mark, Node, mergeAttributes, type JSONContent } from '@tiptap/core'
import { Node as ProseMirrorNode } from '@tiptap/pm/model'
import { Plugin, PluginKey } from '@tiptap/pm/state'

const blockTypes = ['paragraph', 'heading', 'blockquote', 'listItem', 'taskItem']

function newBlockId(): string {
  return globalThis.crypto?.randomUUID?.() ?? `block-${Date.now()}-${Math.random().toString(16).slice(2)}`
}

/** Stable IDs let a Task backlink reopen a note at the originating block. */
export const WorkFollowBlockId = Extension.create({
  name: 'workFollowBlockId',
  addGlobalAttributes() {
    return [{
      types: blockTypes,
      attributes: {
        blockId: {
          default: null,
          parseHTML: (element: HTMLElement) => element.getAttribute('data-block-id'),
          renderHTML: (attributes: { blockId?: string | null }) => attributes.blockId
            ? { 'data-block-id': attributes.blockId }
            : {},
        },
      },
    }]
  },
  addProseMirrorPlugins() {
    return [new Plugin({
      key: new PluginKey('workFollowBlockIds'),
      state: {
        init: (_config, state) => {
          const counts = new Map<string, number>()
          state.doc.descendants((node) => {
            if (!blockTypes.includes(node.type.name)) return
            const blockId = typeof node.attrs.blockId === 'string' ? node.attrs.blockId : null
            if (blockId) counts.set(blockId, (counts.get(blockId) ?? 0) + 1)
          })
          return counts
        },
        apply: (transaction, previous, oldState, newState) => {
          if (!transaction.docChanged) return previous
          const next = new Map(previous)
          const positions: Array<{ oldFrom: number; oldTo: number; newFrom: number; newTo: number }> = []
          transaction.mapping.maps.forEach((map) => {
            map.forEach((oldFrom, oldTo, newFrom, newTo) => {
              positions.push({ oldFrom, oldTo, newFrom, newTo })
            })
          })
          const decrement = (id: string) => {
            const count = next.get(id) ?? 0
            if (count <= 1) next.delete(id)
            else next.set(id, count - 1)
          }
          const increment = (id: string) => next.set(id, (next.get(id) ?? 0) + 1)
          for (const range of positions) {
            oldState.doc.nodesBetween(range.oldFrom, range.oldTo, (node) => {
              if (blockTypes.includes(node.type.name) && typeof node.attrs.blockId === 'string') {
                decrement(node.attrs.blockId)
              }
            })
            newState.doc.nodesBetween(range.newFrom, range.newTo, (node) => {
              if (blockTypes.includes(node.type.name) && typeof node.attrs.blockId === 'string') {
                increment(node.attrs.blockId)
              }
            })
          }
          return next
        },
      },
      appendTransaction: (transactions, _oldState, newState) => {
        if (!transactions.some((transaction) => transaction.docChanged)) return null
        const fullScan = transactions.some((transaction) => transaction.getMeta('uiEvent') === 'paste')
        const positions: number[] = []
        for (const transaction of transactions) {
          if (!transaction.docChanged) continue
          transaction.mapping.maps.forEach((map) => {
            map.forEach((_oldFrom, _oldTo, newFrom, newTo) => {
              positions.push(newFrom, newTo)
            })
          })
        }
        if (!positions.length) positions.push(newState.selection.from, newState.selection.to)
        const scanRange = fullScan
          ? { from: 0, to: newState.doc.content.size }
          : changedBlockRange(newState.doc, Math.min(...positions), Math.max(...positions))
        const transaction = newState.tr
        let changed = false
        const seen = new Set<string>()
        newState.doc.nodesBetween(scanRange.from, scanRange.to, (node, position) => {
          if (!blockTypes.includes(node.type.name)) return
          const blockId = typeof node.attrs.blockId === 'string' ? node.attrs.blockId : null
          // Ordinary keystrokes only repair newly inserted blocks. Paste/import
          // runs the bounded global normalization needed to preserve backlinks.
          if (blockId && !seen.has(blockId)) {
            seen.add(blockId)
            return
          }
          const replacement = newBlockId()
          seen.add(replacement)
          transaction.setNodeMarkup(position, undefined, { ...node.attrs, blockId: replacement })
          changed = true
        })
        return changed ? transaction : null
      },
    })]
  },
})

function changedBlockRange(doc: ProseMirrorNode, from: number, to: number): { from: number; to: number } {
  const ranges: Array<{ from: number; to: number }> = []
  for (const position of [from, to]) {
    const resolved = doc.resolve(Math.max(0, Math.min(position, doc.content.size)))
    for (let depth = resolved.depth; depth > 0; depth -= 1) {
      if (!blockTypes.includes(resolved.node(depth).type.name)) continue
      const start = resolved.start(depth)
      ranges.push({ from: start, to: start + resolved.node(depth).nodeSize })
      break
    }
  }
  if (!ranges.length) return { from: Math.max(0, from - 1), to: Math.max(from, to + 1) }
  return {
    from: Math.min(...ranges.map((range) => range.from)),
    to: Math.max(...ranges.map((range) => range.to)),
  }
}

/** Inline source text keeps its text; this mark adds only the Task identity. */
export const TaskLinkMark = Mark.create({
  name: 'taskLink',
  inclusive: false,
  addAttributes() {
    return {
      taskId: {
        default: null,
        parseHTML: (element: HTMLElement) => element.getAttribute('data-task-id'),
        renderHTML: (attributes: { taskId?: string | null }) => attributes.taskId
          ? { 'data-task-id': attributes.taskId }
          : {},
      },
    }
  },
  parseHTML() { return [{ tag: 'span[data-task-link]' }] },
  renderHTML({ HTMLAttributes }) {
    return ['span', mergeAttributes(HTMLAttributes, { 'data-task-link': '', class: 'task-link-mark' }), 0]
  },
})

/** Block references are intentionally atom nodes with taskId as their only fact. */
export const TaskReferenceNode = Node.create({
  name: 'taskReference',
  group: 'block',
  atom: true,
  selectable: true,
  addAttributes() {
    return {
      taskId: {
        default: null,
        parseHTML: (element: HTMLElement) => element.getAttribute('data-task-id'),
        renderHTML: (attributes: { taskId?: string | null }) => attributes.taskId
          ? { 'data-task-id': attributes.taskId }
          : {},
      },
    }
  },
  parseHTML() { return [{ tag: 'div[data-task-reference]' }] },
  renderHTML({ HTMLAttributes }) {
    return ['div', mergeAttributes(HTMLAttributes, {
      'data-task-reference': '',
      class: 'task-reference',
      contenteditable: 'false',
    }),
    ['span', { 'data-task-reference-status': '' }, '○'],
    ['span', { 'data-task-reference-title': '' }, '正在读取待办…'],
    ['span', { 'data-task-reference-meta': '' }, '']]
  },
})

export function collectTaskIds(content: JSONContent | Record<string, unknown>): string[] {
  const ids = new Set<string>()
  const visit = (value: unknown) => {
    if (Array.isArray(value)) { value.forEach(visit); return }
    if (!value || typeof value !== 'object') return
    const node = value as Record<string, unknown>
    const attrs = node.attrs as Record<string, unknown> | undefined
    if (node.type === 'taskReference' && typeof attrs?.taskId === 'string') ids.add(attrs.taskId)
    if (Array.isArray(node.marks)) {
      for (const mark of node.marks as Array<Record<string, unknown>>) {
        const markAttrs = mark.attrs as Record<string, unknown> | undefined
        if (mark.type === 'taskLink' && typeof markAttrs?.taskId === 'string') ids.add(markAttrs.taskId)
      }
    }
    Object.values(node).forEach(visit)
  }
  visit(content)
  return [...ids]
}
