import type { Extensions } from '@tiptap/core'
import type { Editor as CoreEditor } from '@tiptap/core'
import Highlight from '@tiptap/extension-highlight'
import Image from '@tiptap/extension-image'
import Link from '@tiptap/extension-link'
import Placeholder from '@tiptap/extension-placeholder'
import Table from '@tiptap/extension-table'
import TableCell from '@tiptap/extension-table-cell'
import TableHeader from '@tiptap/extension-table-header'
import TableRow from '@tiptap/extension-table-row'
import TaskItem from '@tiptap/extension-task-item'
import TaskList from '@tiptap/extension-task-list'
import TextStyle from '@tiptap/extension-text-style'
import Underline from '@tiptap/extension-underline'
import StarterKit from '@tiptap/starter-kit'
import { VueNodeViewRenderer } from '@tiptap/vue-3'
import ResizableImageNode from '@/components/editor/ResizableImageNode.vue'
import { normalizeFontSize } from '@/modules/editor/fontSizing'
import { NoteLinkMark, TaskLinkMark, TaskReferenceNode, WorkFollowBlockId } from '@/modules/editor/taskRelations'
import { normalizeImageWidth } from '@/modules/editor/imageSizing'
import { TABLE_MIN_COLUMN_WIDTH } from '@/modules/editor/tableSizing'

// Keep the shared color mark compatible with the installed Tiptap 2.27
// package, which exposes TextStyle but not the newer Color helper.
export const WorkFollowTextStyle = TextStyle.extend({
  addAttributes() {
    return {
      ...this.parent?.(),
      color: {
        default: null,
        parseHTML: (element: HTMLElement) => element.style.color || null,
        renderHTML: (attributes: { color?: string | null }) => attributes.color ? { style: `color: ${attributes.color}` } : {},
      },
      fontSize: {
        default: null,
        parseHTML: (element: HTMLElement) => normalizeFontSize(element.style.fontSize),
        renderHTML: (attributes: { fontSize?: string | null }) => {
          const fontSize = normalizeFontSize(attributes.fontSize)
          return fontSize ? { style: `font-size: ${fontSize}` } : {}
        },
      },
    }
  },
})

/** Keep the binary identity beside an image so attachment lifecycle cleanup
 * does not have to infer ownership from a display URL alone. */
export const WorkFollowImage = Image.extend({
  addAttributes() {
    return {
      ...this.parent?.(),
      attachmentId: {
        default: null,
        parseHTML: (element: HTMLElement) => element.getAttribute('data-attachment-id'),
        renderHTML: (attributes: { attachmentId?: string | null }) => attributes.attachmentId
          ? { 'data-attachment-id': attributes.attachmentId }
          : {},
      },
      width: {
        default: null,
        parseHTML: (element: HTMLElement) => normalizeImageWidth(element.getAttribute('data-image-width')),
        renderHTML: (attributes: { width?: number | null }) => {
          const width = normalizeImageWidth(attributes.width)
          return width === null ? {} : { 'data-image-width': String(width), style: `width: ${width}%` }
        },
      },
    }
  },
  addNodeView() {
    return VueNodeViewRenderer(ResizableImageNode)
  },
})

export const workFollowTextColors = [
  { label: '默认文字颜色', value: null, swatch: 'currentColor' },
  { label: '灰色文字', value: '#737780', swatch: '#737780' },
  { label: '红色文字', value: '#c84b55', swatch: '#c84b55' },
  { label: '橙色文字', value: '#c27b23', swatch: '#c27b23' },
  { label: '黄色文字', value: '#a98511', swatch: '#a98511' },
  { label: '绿色文字', value: '#31805d', swatch: '#31805d' },
  { label: '蓝色文字', value: '#3567c8', swatch: '#3567c8' },
  { label: '紫色文字', value: '#7655b8', swatch: '#7655b8' },
] as const

export const workFollowHighlightColors = [
  { label: '无背景色', value: null, swatch: 'transparent' },
  { label: '灰色背景', value: '#eef0f3', swatch: '#eef0f3' },
  { label: '红色背景', value: '#ffe1e3', swatch: '#ffe1e3' },
  { label: '橙色背景', value: '#ffedcf', swatch: '#ffedcf' },
  { label: '黄色背景', value: '#fff5b8', swatch: '#fff5b8' },
  { label: '绿色背景', value: '#dff5e9', swatch: '#dff5e9' },
  { label: '蓝色背景', value: '#e1eaff', swatch: '#e1eaff' },
  { label: '紫色背景', value: '#eee5ff', swatch: '#eee5ff' },
] as const

/**
 * 协同文档刚建立时，编辑器默认空段与同步链路写入的初始段可能各存一份，
 * 合并成多个空段落——首行吞掉占位符、正文顶部多出空行。整篇只由空段落
 * 组成时不含任何用户内容，收敛为一个段落是零损失的自愈。
 */
export function collapseAllEmptyParagraphs(editor: CoreEditor): boolean {
  const doc = editor.state.doc
  if (doc.childCount <= 1) return false
  const allEmpty = Array.from(doc.children).every(
    (node) => node.type.name === 'paragraph' && node.content.size === 0,
  )
  if (!allEmpty) return false
  const tr = editor.state.tr
  tr.delete(doc.firstChild!.nodeSize, doc.content.size)
  editor.view.dispatch(tr)
  return true
}

/**
 * The single document schema used by task and note editors.
 * Domain-specific menus and persistence adapters stay in their own components.
 */
export function createWorkFollowEditorExtensions(
  placeholder: string,
  options: { collaboration?: boolean } = {},
): Extensions {
  const starterKitOptions: Parameters<typeof StarterKit.configure>[0] = {
    heading: { levels: [1, 2, 3, 4, 5, 6] },
  }
  if (options.collaboration) starterKitOptions.history = false

  return [
    StarterKit.configure(starterKitOptions),
    WorkFollowBlockId,
    TaskLinkMark,
    NoteLinkMark,
    TaskReferenceNode,
    Underline,
    WorkFollowTextStyle,
    Highlight.configure({ multicolor: true }),
    Link.configure({ openOnClick: false }),
    WorkFollowImage.configure({ inline: false }),
    Placeholder.configure({ placeholder }),
    TaskList,
    TaskItem.configure({ nested: true }),
    Table.configure({ resizable: true, cellMinWidth: TABLE_MIN_COLUMN_WIDTH }),
    TableRow,
    TableHeader,
    TableCell,
  ]
}
