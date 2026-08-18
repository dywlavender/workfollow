import { Extension, Mark, Node, mergeAttributes, type JSONContent } from '@tiptap/core'
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
      appendTransaction: (transactions, _oldState, newState) => {
        if (!transactions.some((transaction) => transaction.docChanged)) return null
        const transaction = newState.tr
        let changed = false
        const seen = new Set<string>()
        newState.doc.descendants((node, position) => {
          if (!blockTypes.includes(node.type.name)) return
          const blockId = typeof node.attrs.blockId === 'string' ? node.attrs.blockId : null
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
