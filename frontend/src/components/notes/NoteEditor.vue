<script setup lang="ts">
import { BubbleMenu, EditorContent, useEditor } from '@tiptap/vue-3'
import {
  IconBook,
  IconCopy,
  IconBookmark,
  IconDownload,
  IconFile,
  IconMaximize,
  IconMinimize,
  IconNotebook,
  IconPlus,
  IconShare,
  IconDots,
  IconStar,
  IconTrash,
} from '@tabler/icons-vue'
import type { Editor as TiptapEditor, JSONContent } from '@tiptap/core'
import { computed, nextTick, onBeforeUnmount, onMounted, ref, watch } from 'vue'

import {
  fetchTaskBriefs, postResourceRelation, postTodo,
  type Attachment, type Folder, type Note, type TaskBrief, type TeamMember, type Todo, type TodoPayload,
} from '@/services/api'
import InputDialog from '@/components/InputDialog.vue'
import RichTextToolbar from '@/components/RichTextToolbar.vue'
import TaskSearchDialog from '@/components/notes/TaskSearchDialog.vue'
import TodoDialog from '@/components/todo/TodoDialog.vue'
import { filterStandaloneAttachments } from '@/modules/editor/attachmentReferences'
import { createWorkFollowEditorExtensions } from '@/modules/editor/tiptap'
import { workFollowSlashCommands, type WorkFollowSlashCommand } from '@/modules/editor/slashCommands'
import { useClickOutside } from '@/composables/useClickOutside'
import { useRealtimeStore } from '@/stores/realtime'


const props = defineProps<{
  note: Note | null
  folders: Folder[]
  attachments: Attachment[]
  uploadFile: (file: File) => Promise<Attachment>
  collaboration?: boolean
  knowledgeState?: 'none' | 'published' | 'update-draft' | 'update-pending' | 'update-needs-revision'
  knowledgeTargetTitle?: string | null
  taskMembers?: TeamMember[]
  currentUserId?: string
  canAssignTasks?: boolean
  focusBlockId?: string | null
}>()
const realtime = useRealtimeStore()
const emit = defineEmits<{
  save: [payload: { noteId: string; title: string; folderId: string | null; contentJson?: Record<string, unknown>; plainText?: string }]
  deleteAttachment: [attachment: Attachment]
  openTask: [taskId: string]
  share: []
  publish: []
  favorite: [value: boolean]
  duplicate: [note: Note]
  export: [note: Note]
  saveAsTemplate: [payload: { note: Note; title: string; folderId: string | null; contentJson: Record<string, unknown>; plainText: string }]
  remove: []
}>()

const title = ref('')
const folderId = ref<string | null>(null)
const saveState = ref<'idle' | 'saving' | 'saved'>('idle')
const fileInput = ref<HTMLInputElement | null>(null)
const linkDialogOpen = ref(false)
const linkValue = ref('')
const slashMenuOpen = ref(false)
const slashActiveIndex = ref(0)
const slashPosition = ref({ left: 0, top: 0 })
const slashRange = ref<{ from: number; to: number } | null>(null)
const moreOpen = ref(false)
const moreHost = ref<HTMLElement | null>(null)
useClickOutside(moreHost, moreOpen, () => { moreOpen.value = false })
const taskDialogOpen = ref(false)
const taskSearchOpen = ref(false)
const taskInitialTitle = ref('')
const taskActionMode = ref<'selection' | 'insert'>('selection')
const pendingTaskContext = ref<{ from: number; to: number; position: number; blockId: string | null; excerpt: string } | null>(null)
const taskFeedback = ref('')
const immersiveOpen = ref(false)
const immersiveClosing = ref(false)
const immersiveTrigger = ref<HTMLButtonElement | null>(null)
const attachmentPanelOpen = ref(false)
const fileUploadMode = ref<'embedded' | 'standalone'>('embedded')
const embeddedFileAccept = '.png,.jpg,.jpeg,.webp,.pdf,.docx,.xlsx,.md,.txt'
const standaloneFileAccept = '.pdf,.docx,.xlsx,.md,.txt'
const editorContent = ref<Record<string, unknown> | null>(props.note?.contentJson ?? null)
const visibleAttachments = computed(() => filterStandaloneAttachments(
  props.attachments,
  editorContent.value ?? props.note?.contentJson,
))
let saveTimer: number | undefined
let contentSnapshotTimer: number | undefined
let slashDetectTimer: number | undefined
let taskHydrateTimer: number | undefined
let contentDirty = false
let taskHydrateRequest = 0
let taskIdsKey = ''
let taskBriefCache = new Map<string, TaskBrief>()

const bubbleMenuOptions = {
  duration: 120,
  // Keep the interactive menu next to its reference in DOM order. This
  // avoids Tippy's keyboard-accessibility warning and makes Tab traversal
  // predictable for the selection actions.
  appendTo: 'parent' as const,
}

const editor = useEditor({
  extensions: createWorkFollowEditorExtensions('输入内容，或输入 / 插入格式'),
  content: { type: 'doc', content: [{ type: 'paragraph' }] },
  editorProps: {
    attributes: {
      role: 'textbox',
      'aria-label': '笔记正文',
      'aria-multiline': 'true',
    },
    handleKeyDown: (_view, event) => {
      if (!slashMenuOpen.value) return false
      if (event.key === 'ArrowDown') moveSlashSelection(1)
      else if (event.key === 'ArrowUp') moveSlashSelection(-1)
      else if (event.key === 'Enter') insertSlashBlock(workFollowSlashCommands[slashActiveIndex.value].type)
      else if (event.key === 'Escape') closeSlashMenu()
      else return false
      event.preventDefault()
      return true
    },
    handlePaste: (_view, event) => {
      const files = Array.from(event.clipboardData?.files ?? []).filter((file) => file.type.startsWith('image/'))
      if (!files.length) return false
      event.preventDefault()
      for (const file of files) {
        void props.uploadFile(file).then((attachment) => {
          editor.value?.chain().focus().insertContent({
            type: 'image',
            attrs: { src: attachment.url, alt: attachment.originalName, attachmentId: attachment.id },
          }).run()
        })
      }
      return true
    },
    handleClick: (_view, _position, event) => {
      const target = event.target as HTMLElement | null
      const relation = target?.closest<HTMLElement>('[data-task-link], [data-task-reference]')
      const taskId = relation?.dataset.taskId
      if (!taskId) return false
      emit('openTask', taskId)
      return true
    },
  },
  onUpdate: ({ editor: currentEditor }) => {
    contentDirty = true
    scheduleSave()
    scheduleContentSnapshot(currentEditor)
    scheduleTaskHydration()
    window.clearTimeout(slashDetectTimer)
    slashDetectTimer = window.setTimeout(() => detectSlashCommand(currentEditor), 0)
  },
})

function placeSlashMenuAtCaret(currentEditor: TiptapEditor) {
  const rect = currentEditor.view.coordsAtPos(currentEditor.state.selection.from)
  slashPosition.value = {
    left: Math.max(8, Math.min(window.innerWidth - 276, rect.left)),
    top: Math.max(8, Math.min(window.innerHeight - 430, rect.bottom + 8)),
  }
}

function detectSlashCommand(currentEditor: TiptapEditor) {
  const { selection } = currentEditor.state
  if (!selection.empty) return
  const textBeforeCursor = selection.$from.parent.textBetween(0, selection.$from.parentOffset, '\n', '\n')
  if (!textBeforeCursor.endsWith('/')) return
  slashRange.value = { from: Math.max(0, selection.from - 1), to: selection.from }
  placeSlashMenuAtCaret(currentEditor)
  slashActiveIndex.value = 0
  slashMenuOpen.value = true
}

function closeSlashMenu() {
  slashMenuOpen.value = false
  slashRange.value = null
}

function moveSlashSelection(direction: number) {
  slashActiveIndex.value = (slashActiveIndex.value + direction + workFollowSlashCommands.length) % workFollowSlashCommands.length
  void nextTick(() => document.getElementById(`note-slash-command-${workFollowSlashCommands[slashActiveIndex.value].type}`)?.scrollIntoView({ block: 'nearest' }))
}

function insertSlashBlock(type: WorkFollowSlashCommand) {
  const currentEditor = editor.value
  if (!currentEditor) return
  const chain = currentEditor.chain().focus()
  if (slashRange.value) chain.deleteRange({ from: slashRange.value.from, to: currentEditor.state.selection.from })
  if (type === 'link') {
    chain.run(); closeSlashMenu(); setLink(); return
  }
  if (type === 'attachment') {
    chain.run(); closeSlashMenu(); openFilePicker('embedded'); return
  }
  if (type === 'createTask' || type === 'linkTask') {
    chain.run()
    closeSlashMenu()
    if (type === 'createTask') openTaskCreateAtCursor()
    else openTaskSearchAtCursor()
    return
  }
  if (type === 'h1') chain.toggleHeading({ level: 1 })
  else if (type === 'h2') chain.toggleHeading({ level: 2 })
  else if (type === 'h3') chain.toggleHeading({ level: 3 })
  else if (type === 'quote') chain.toggleBlockquote()
  else if (type === 'code') chain.toggleCodeBlock()
  else if (type === 'ul') chain.toggleBulletList()
  else if (type === 'ol') chain.toggleOrderedList()
  else if (type === 'check') chain.toggleTaskList()
  else if (type === 'hr') chain.setHorizontalRule()
  else if (type === 'table') chain.insertTable({ rows: 3, cols: 3, withHeaderRow: true })
  else if (type === 'subtask') chain.toggleTaskList().insertContent('子任务')
  else if (type === 'tag') chain.insertContent('#标签')
  else chain.insertContent('关联任务 / 笔记')
  chain.run()
  closeSlashMenu()
}

watch(
  () => props.note?.id,
  (_newId, oldId) => {
    if (oldId && saveTimer) emitCurrentContent(oldId)
    window.clearTimeout(saveTimer)
    window.clearTimeout(contentSnapshotTimer)
    saveTimer = undefined
    contentSnapshotTimer = undefined
    title.value = props.note?.title ?? ''
    folderId.value = props.note?.folderId ?? null
    saveState.value = 'idle'
    attachmentPanelOpen.value = false
    editorContent.value = props.note?.contentJson ?? null
    taskIdsKey = ''
    taskBriefCache = new Map()
    closeSlashMenu()
    if (props.note && editor.value) editor.value.commands.setContent(props.note.contentJson as JSONContent, false)
    scheduleTaskHydration()
    void focusSourceBlock()
  },
  { immediate: true },
)

watch(
  () => [props.note?.id, props.focusBlockId] as const,
  async ([noteId, blockId]) => {
    if (noteId && blockId) await focusSourceBlock()
  },
  { immediate: true },
)

async function focusSourceBlock(attempt = 0) {
  const requestedBlockId = props.focusBlockId ?? new URLSearchParams(window.location.search).get('block')
  if (!props.note || !requestedBlockId) return
  await nextTick()
  window.setTimeout(() => {
    const currentEditor = editor.value
    const blocks = currentEditor?.view.dom.querySelectorAll<HTMLElement>('[data-block-id]') ?? []
    const block = [...blocks].find((item) => item.dataset.blockId === requestedBlockId)
    if (!block) {
      if (attempt < 8) void focusSourceBlock(attempt + 1)
      return
    }
    let blockPosition: number | null = null
    currentEditor?.state.doc.descendants((node, position) => {
      if (node.attrs.blockId === requestedBlockId && blockPosition === null) blockPosition = position
    })
    if (blockPosition !== null) currentEditor?.chain().setNodeSelection(blockPosition).scrollIntoView().run()
    block.classList.add('note-source-focus')
    window.setTimeout(() => block.classList.remove('note-source-focus'), 1800)
  }, 120)
}

watch(editor, () => { void focusSourceBlock() })

function scheduleSave() {
  if (!props.note) return
  saveState.value = 'saving'
  window.clearTimeout(saveTimer)
  saveTimer = window.setTimeout(() => {
    if (!props.note) return
    emitCurrentContent(props.note.id)
    saveTimer = undefined
    saveState.value = 'saved'
  }, 1200)
}

function scheduleContentSnapshot(currentEditor: TiptapEditor | null = editor.value ?? null) {
  if (!currentEditor) return
  window.clearTimeout(contentSnapshotTimer)
  contentSnapshotTimer = window.setTimeout(() => {
    if (editor.value !== currentEditor) return
    editorContent.value = currentEditor.getJSON() as Record<string, unknown>
    contentSnapshotTimer = undefined
  }, 250)
}

function emitCurrentContent(noteId: string) {
  if (!editor.value) return
  const dirty = contentDirty
  contentDirty = false
  if (dirty && contentSnapshotTimer !== undefined) {
    window.clearTimeout(contentSnapshotTimer)
    contentSnapshotTimer = undefined
    editorContent.value = editor.value.getJSON() as Record<string, unknown>
  }
  // Only send the (potentially large) document JSON when the body actually
  // changed. Title/folder edits then save a tiny payload instead of the full
  // contentJson + plainText every time — less bandwidth and backend work.
  const contentJson = dirty
    ? (editorContent.value ?? editor.value.getJSON() as Record<string, unknown>)
    : undefined
  emit('save', {
    noteId,
    title: title.value.trim() || '未命名笔记',
    folderId: folderId.value || null,
    ...(contentJson ? {
      contentJson,
      plainText: editor.value.getText({ blockSeparator: '\n' }),
    } : {}),
  })
}

function requestSaveAsTemplate() {
  if (!props.note || !editor.value) return
  emit('saveAsTemplate', {
    note: props.note,
    title: title.value.trim() || '未命名笔记',
    folderId: folderId.value || null,
    contentJson: editor.value.getJSON() as Record<string, unknown>,
    plainText: editor.value.getText({ blockSeparator: '\n' }),
  })
}

function toggleImmersive() {
  if (!props.note || immersiveClosing.value) return
  moreOpen.value = false
  immersiveOpen.value = !immersiveOpen.value
}

function finishImmersiveClose() {
  if (!immersiveClosing.value) return
  immersiveOpen.value = false
  immersiveClosing.value = false
  void nextTick(() => immersiveTrigger.value?.focus({ preventScroll: true }))
}

function handleImmersiveAnimationDone(event: AnimationEvent) {
  if (event.target !== event.currentTarget || event.animationName !== 'note-editor-immersive-exit') return
  finishImmersiveClose()
}

function closeImmersive() {
  if (!immersiveOpen.value || immersiveClosing.value) return
  immersiveClosing.value = true
  if (window.matchMedia('(prefers-reduced-motion: reduce)').matches) void nextTick(finishImmersiveClose)
}

function handleImmersiveKeydown(event: KeyboardEvent) {
  if (!immersiveOpen.value || event.key !== 'Escape') return

  // Let the currently open editor popover consume Escape first. A second
  // Escape exits immersive editing, so nested interactions are not dismissed
  // unexpectedly.
  if (linkDialogOpen.value || taskDialogOpen.value || taskSearchOpen.value) return
  if (moreOpen.value) {
    moreOpen.value = false
    return
  }
  if (slashMenuOpen.value) {
    closeSlashMenu()
    return
  }
  closeImmersive()
}

function setLink() {
  const previous = editor.value?.getAttributes('link').href as string | undefined
  linkValue.value = previous ?? 'https://'
  linkDialogOpen.value = true
}

function applyLink(url: string) {
  linkDialogOpen.value = false
  if (!editor.value) return
  if (!url.trim()) editor.value.chain().focus().extendMarkRange('link').unsetLink().run()
  else editor.value.chain().focus().extendMarkRange('link').setLink({ href: url.trim() }).run()
}

function selectedText(): string {
  if (!editor.value) return ''
  const { from, to } = editor.value.state.selection
  return editor.value.state.doc.textBetween(from, to, ' ').trim()
}

function activeBlockId(currentEditor: TiptapEditor): string | null {
  const resolved = currentEditor.state.selection.$from
  for (let depth = resolved.depth; depth > 0; depth -= 1) {
    const blockId = resolved.node(depth).attrs.blockId
    if (typeof blockId !== 'string' || !blockId) continue
    let occurrences = 0
    currentEditor.state.doc.descendants((node) => {
      if (node.attrs.blockId === blockId) occurrences += 1
    })
    if (occurrences === 1) return blockId
    const replacement = globalThis.crypto?.randomUUID?.()
      ?? `block-${Date.now()}-${Math.random().toString(16).slice(2)}`
    currentEditor.view.dispatch(currentEditor.state.tr.setNodeMarkup(
      resolved.before(depth), undefined, { ...resolved.node(depth).attrs, blockId: replacement },
    ))
    return replacement
  }
  for (let depth = resolved.depth; depth > 0; depth -= 1) {
    const node = resolved.node(depth)
    if (!['paragraph', 'heading', 'blockquote', 'listItem', 'taskItem'].includes(node.type.name)) continue
    const blockId = globalThis.crypto?.randomUUID?.()
      ?? `block-${Date.now()}-${Math.random().toString(16).slice(2)}`
    currentEditor.view.dispatch(currentEditor.state.tr.setNodeMarkup(
      resolved.before(depth), undefined, { ...node.attrs, blockId },
    ))
    return blockId
  }
  return null
}

function createTodoFromSelection() {
  const text = selectedText()
  const currentEditor = editor.value
  if (!text || !currentEditor) return
  const { from, to } = currentEditor.state.selection
  pendingTaskContext.value = {
    from, to, position: to, blockId: activeBlockId(currentEditor), excerpt: text,
  }
  taskActionMode.value = 'selection'
  taskInitialTitle.value = text
  taskDialogOpen.value = true
}

function openTaskCreateAtCursor() {
  const currentEditor = editor.value
  if (!currentEditor) return
  const position = currentEditor.state.selection.from
  pendingTaskContext.value = {
    from: position, to: position, position, blockId: activeBlockId(currentEditor), excerpt: '',
  }
  taskActionMode.value = 'insert'
  taskInitialTitle.value = ''
  taskDialogOpen.value = true
}

function openTaskSearchAtCursor() {
  const currentEditor = editor.value
  if (!currentEditor) return
  const position = currentEditor.state.selection.from
  pendingTaskContext.value = {
    from: position, to: position, position, blockId: activeBlockId(currentEditor), excerpt: '',
  }
  taskSearchOpen.value = true
}

async function saveLinkedTask(payload: TodoPayload) {
  if (!props.note || !pendingTaskContext.value || !editor.value) return
  const context = pendingTaskContext.value
  const created = await postTodo({
    ...payload,
    source: {
      resourceType: 'PERSONAL_NOTE',
      resourceId: props.note.id,
      blockId: context.blockId,
      excerpt: context.excerpt || null,
    },
  })
  if (taskActionMode.value === 'selection') {
    editor.value.chain().focus().setTextSelection({ from: context.from, to: context.to })
      .setMark('taskLink', { taskId: created.id }).run()
  } else {
    editor.value.chain().focus().insertContentAt(context.position, {
      type: 'taskReference', attrs: { taskId: created.id },
    }).run()
  }
  taskDialogOpen.value = false
  showTaskFeedback('✓ 已创建待办')
  scheduleTaskHydration()
}

async function linkExistingTask(todo: Todo) {
  if (!props.note || !pendingTaskContext.value || !editor.value) return
  const context = pendingTaskContext.value
  await postResourceRelation({
    sourceType: 'PERSONAL_NOTE',
    sourceId: props.note.id,
    sourceBlockId: context.blockId,
    targetType: 'TASK',
    targetId: todo.id,
    relationType: 'REFERENCES',
  })
  editor.value.chain().focus().insertContentAt(context.position, {
    type: 'taskReference', attrs: { taskId: todo.id },
  }).run()
  taskSearchOpen.value = false
  showTaskFeedback('✓ 已关联待办')
  scheduleTaskHydration()
}

function showTaskFeedback(message: string) {
  taskFeedback.value = message
  window.setTimeout(() => { if (taskFeedback.value === message) taskFeedback.value = '' }, 1400)
}

function scheduleTaskHydration() {
  window.clearTimeout(taskHydrateTimer)
  taskHydrateTimer = window.setTimeout(refreshTaskReferences, 250)
}

function briefMeta(brief: TaskBrief): string {
  const parts: string[] = []
  if (brief.dueAt) parts.push(new Date(brief.dueAt).toLocaleDateString('zh-CN', { month: 'numeric', day: 'numeric' }))
  if (brief.priority && brief.priority !== 'NONE') parts.push({ LOW: '低优先级', MEDIUM: '中优先级', HIGH: '高优先级' }[brief.priority])
  if (brief.assignees.length) parts.push(brief.assignees.map((item) => item.nickname).join('、'))
  return parts.join(' · ')
}

async function refreshTaskReferences() {
  const currentEditor = editor.value
  if (!currentEditor) return
  const ids = [...new Set(
    [...currentEditor.view.dom.querySelectorAll<HTMLElement>('[data-task-link], [data-task-reference]')]
      .map((element) => element.dataset.taskId)
      .filter((id): id is string => Boolean(id)),
  )].sort()
  const nextKey = ids.join('\u0000')
  if (!ids.length) {
    taskIdsKey = ''
    taskBriefCache = new Map()
    return
  }
  if (nextKey === taskIdsKey && taskBriefCache.size === ids.length) {
    await renderTaskBriefs(currentEditor, taskBriefCache)
    return
  }
  taskIdsKey = nextKey
  const requestId = ++taskHydrateRequest
  const briefs = new Map((await fetchTaskBriefs(ids)).map((item) => [item.id, item]))
  if (requestId !== taskHydrateRequest) return
  taskBriefCache = briefs
  await renderTaskBriefs(currentEditor, briefs)
}

async function renderTaskBriefs(currentEditor: TiptapEditor, briefs: Map<string, TaskBrief>) {
  await nextTick()
  for (const element of currentEditor.view.dom.querySelectorAll<HTMLElement>('[data-task-link], [data-task-reference]')) {
    const taskId = element.dataset.taskId
    const brief = taskId ? briefs.get(taskId) : undefined
    if (!brief || !brief.accessible) {
      const label = brief?.deleted ? '该待办已删除' : '该待办不可访问'
      element.dataset.taskState = brief?.deleted ? 'deleted' : 'forbidden'
      element.title = label
      element.querySelector<HTMLElement>('[data-task-reference-title]')?.replaceChildren(label)
      element.querySelector<HTMLElement>('[data-task-reference-status]')?.replaceChildren('—')
      element.querySelector<HTMLElement>('[data-task-reference-meta]')?.replaceChildren('')
      continue
    }
    const done = brief.status === 'DONE'
    element.dataset.taskState = done ? 'done' : 'todo'
    element.title = `${brief.title ?? ''}${briefMeta(brief) ? `\n${briefMeta(brief)}` : ''}`
    element.querySelector<HTMLElement>('[data-task-reference-title]')?.replaceChildren(brief.title ?? '')
    element.querySelector<HTMLElement>('[data-task-reference-status]')?.replaceChildren(done ? '✓' : '○')
    element.querySelector<HTMLElement>('[data-task-reference-meta]')?.replaceChildren(briefMeta(brief))
  }
}

function applyRealtimeTaskChange(change: NonNullable<typeof realtime.lastTaskChange>) {
  const currentEditor = editor.value
  if (!currentEditor) return
  const brief = change.brief
  for (const element of currentEditor.view.dom.querySelectorAll<HTMLElement>('[data-task-link], [data-task-reference]')) {
    if (element.dataset.taskId !== change.taskId) continue
    if (brief.deleted) {
      element.dataset.taskState = 'deleted'
      element.title = '该待办已删除'
      element.querySelector<HTMLElement>('[data-task-reference-title]')?.replaceChildren('该待办已删除')
      element.querySelector<HTMLElement>('[data-task-reference-status]')?.replaceChildren('—')
      element.querySelector<HTMLElement>('[data-task-reference-meta]')?.replaceChildren('')
      continue
    }
    const done = brief.status === 'DONE'
    element.dataset.taskState = done ? 'done' : 'todo'
    element.title = brief.title
    element.querySelector<HTMLElement>('[data-task-reference-title]')?.replaceChildren(brief.title)
    element.querySelector<HTMLElement>('[data-task-reference-status]')?.replaceChildren(done ? '✓' : '○')
  }
}

watch(() => realtime.lastTaskChange, (change) => {
  if (change) applyRealtimeTaskChange(change)
})

watch(() => realtime.reconnectGeneration, () => {
  taskIdsKey = ''
  void refreshTaskReferences()
})

async function copySelection() {
  const text = selectedText()
  if (text) await navigator.clipboard.writeText(text)
}

async function handleFiles(files: FileList | null) {
  if (!files) return
  let uploadedStandaloneFile = false
  const insertImages = fileUploadMode.value === 'embedded'
  for (const file of Array.from(files)) {
    const attachment = await props.uploadFile(file)
    if (file.type.startsWith('image/') && insertImages) {
      editor.value?.chain().focus().insertContent({
        type: 'image',
        attrs: { src: attachment.url, alt: attachment.originalName, attachmentId: attachment.id },
      }).run()
    } else {
      uploadedStandaloneFile = true
    }
  }
  if (uploadedStandaloneFile) attachmentPanelOpen.value = true
  if (fileInput.value) fileInput.value.value = ''
}

function openFilePicker(mode: 'embedded' | 'standalone') {
  fileUploadMode.value = mode
  fileInput.value?.click()
}

function formatSize(size: number): string {
  if (size < 1024) return `${size} B`
  if (size < 1024 * 1024) return `${(size / 1024).toFixed(1)} KB`
  return `${(size / 1024 / 1024).toFixed(1)} MB`
}

onMounted(() => {
  window.addEventListener('keydown', handleImmersiveKeydown)
  window.setTimeout(() => { void focusSourceBlock() }, 900)
})

onBeforeUnmount(() => {
  if (saveTimer && props.note) emitCurrentContent(props.note.id)
  window.clearTimeout(saveTimer)
  window.clearTimeout(contentSnapshotTimer)
  window.clearTimeout(slashDetectTimer)
  window.clearTimeout(taskHydrateTimer)
  window.removeEventListener('keydown', handleImmersiveKeydown)
  document.body.classList.remove('note-editor-immersive-open')
})

watch(immersiveOpen, (open) => {
  document.body.classList.toggle('note-editor-immersive-open', open)
  if (open) void nextTick(() => editor.value?.commands.focus())
})
</script>

<template>
  <section class="notes-column editor-column">
    <div
      class="note-editor-surface"
      :class="{ 'note-editor-immersive': immersiveOpen, 'is-closing': immersiveClosing }"
      :role="immersiveOpen ? 'dialog' : undefined"
      :aria-modal="immersiveOpen ? 'true' : undefined"
      :aria-label="immersiveOpen ? '沉浸式笔记编辑器' : undefined"
      @animationend="handleImmersiveAnimationDone"
      @animationcancel="handleImmersiveAnimationDone"
    >
    <div v-if="!note" class="editor-empty"><span><IconNotebook :size="28" /></span><strong>选择或创建一篇笔记</strong><p>正文、图片和附件会自动保存到本地。</p></div>
    <template v-else>
      <header class="editor-header">
        <div class="note-editor-title-row">
          <input v-model="title" class="note-title-input" aria-label="笔记标题" maxlength="500" @input="scheduleSave" />
          <div class="note-editor-actions">
            <button
              ref="immersiveTrigger"
              type="button"
              class="secondary-button note-immersive-toggle"
              :aria-label="immersiveOpen ? '退出沉浸式编辑' : '进入沉浸式编辑'"
              :aria-pressed="immersiveOpen"
              :title="immersiveOpen ? '退出沉浸式编辑（Esc）' : '进入沉浸式编辑'"
              @click="immersiveOpen ? closeImmersive() : toggleImmersive()"
            >
              <IconMinimize v-if="immersiveOpen" :size="15" />
              <IconMaximize v-else :size="15" />
              <span>{{ immersiveOpen ? '退出沉浸式' : '沉浸式编辑' }}</span>
            </button>
            <div ref="moreHost" class="note-more-host">
              <button type="button" class="mini-action" aria-label="更多笔记操作" @click="moreOpen = !moreOpen"><IconDots :size="18" /></button>
              <section v-if="moreOpen" class="note-more-menu">
                <button v-if="collaboration" type="button" @click="emit('share'); moreOpen = false"><IconShare :size="15" />分享</button>
                <button type="button" @click="emit('favorite', !note?.isFavorite); moreOpen = false"><IconStar :size="15" />{{ note?.isFavorite ? '取消收藏' : '收藏' }}</button>
                <button type="button" @click="emit('duplicate', note); moreOpen = false"><IconCopy :size="15" />复制笔记</button>
                <button type="button" @click="requestSaveAsTemplate(); moreOpen = false"><IconBookmark :size="15" />保存为模板</button>
                <button type="button" @click="emit('export', note); moreOpen = false"><IconDownload :size="15" />导出 Markdown</button>
                <button v-if="collaboration" type="button" :disabled="knowledgeState === 'update-pending'" @click="emit('publish'); moreOpen = false"><IconBook :size="15" />{{ knowledgeState === 'published' ? '申请更新团队版本' : knowledgeState === 'update-draft' ? '提交更新申请' : knowledgeState === 'update-needs-revision' ? '重新提交更新申请' : knowledgeState === 'update-pending' ? '更新审核中' : '发布到团队知识库' }}</button>
                <span />
                <button class="danger-text" type="button" @click="emit('remove'); moreOpen = false">删除</button>
              </section>
            </div>
          </div>
        </div>
        <div class="editor-meta-row">
          <select v-model="folderId" aria-label="移动到文件夹" @change="scheduleSave">
            <option :value="null">未分类</option>
            <option v-for="folder in folders" :key="folder.id" :value="folder.id">{{ folder.name }}</option>
          </select>
          <span class="save-state" :class="saveState">{{ saveState === 'saving' ? '保存中…' : saveState === 'saved' ? '已自动保存' : '本地笔记' }}</span>
          <span v-if="knowledgeState === 'update-draft' || knowledgeState === 'update-pending' || knowledgeState === 'update-needs-revision'" class="knowledge-update-target">更新目标：{{ knowledgeTargetTitle ?? '团队知识' }}</span>
        </div>
      </header>
      <RichTextToolbar v-if="editor" :editor="editor" attachment @link="setLink" @attachment="openFilePicker('embedded')" />
      <input ref="fileInput" class="sr-only" type="file" multiple :accept="fileUploadMode === 'embedded' ? embeddedFileAccept : standaloneFileAccept" @change="handleFiles(($event.target as HTMLInputElement).files)" />
      <div class="selection-menu-host">
        <BubbleMenu v-if="editor" :editor="editor" :tippy-options="bubbleMenuOptions" class="selection-menu">
          <button type="button" @mousedown.prevent @click="createTodoFromSelection">创建待办</button>
          <button type="button" @mousedown.prevent @click="copySelection">复制</button>
        </BubbleMenu>
      </div>
      <EditorContent class="tiptap-editor" :editor="editor" />
      <span v-if="taskFeedback" class="note-task-feedback" role="status">{{ taskFeedback }}</span>
      <Teleport to="body">
        <section v-if="slashMenuOpen" class="task-slash-menu" :style="{ left: `${slashPosition.left}px`, top: `${slashPosition.top}px` }" role="menu" aria-label="插入格式" @mousedown.prevent.stop @click.stop>
          <button
            v-for="(command, index) in workFollowSlashCommands"
            :id="`note-slash-command-${command.type}`"
            :key="command.type"
            type="button"
            role="menuitem"
            :class="{ active: slashActiveIndex === index }"
            :aria-current="slashActiveIndex === index ? 'true' : undefined"
            @mousemove="slashActiveIndex = index"
            @click="insertSlashBlock(command.type)"
          ><span>{{ command.mark }}</span><strong>{{ command.label }}</strong></button>
        </section>
      </Teleport>
      <section class="attachment-panel" :class="{ 'is-expanded': attachmentPanelOpen }">
        <header>
          <button type="button" class="attachment-panel-toggle" :aria-expanded="attachmentPanelOpen" aria-controls="note-file-attachments" @click="attachmentPanelOpen = !attachmentPanelOpen">
            <strong>文件附件</strong><span>{{ visibleAttachments.length }}</span>
          </button>
          <button type="button" @click="openFilePicker('standalone')"><IconPlus :size="15" /> 上传文件</button>
        </header>
        <div v-if="attachmentPanelOpen" id="note-file-attachments" class="attachment-panel-body">
          <div v-if="visibleAttachments.length" class="attachment-list">
            <article v-for="attachment in visibleAttachments" :key="attachment.id">
              <span class="attachment-icon"><IconFile :size="17" /></span>
              <a :href="attachment.url" target="_blank" rel="noopener noreferrer"><strong>{{ attachment.originalName }}</strong><small>{{ formatSize(attachment.size) }}</small></a>
              <button type="button" aria-label="删除附件" @click="emit('deleteAttachment', attachment)"><IconTrash :size="16" /></button>
            </article>
          </div>
          <p v-else>正文图片只在正文中展示；这里用于管理 PDF、DOCX、Markdown 和文本文件。</p>
        </div>
      </section>
      <InputDialog :open="linkDialogOpen" title="设置链接" label="链接地址" :initial-value="linkValue" placeholder="https://（留空可移除链接）" confirm-label="应用" :required="false" @close="linkDialogOpen = false" @submit="applyLink" />
      <TodoDialog
        :open="taskDialogOpen"
        :initial-title="taskInitialTitle"
        :members="taskMembers ?? []"
        :current-user-id="currentUserId"
        :can-assign="canAssignTasks"
        :initial-due-at="null"
        @close="taskDialogOpen = false"
        @save="saveLinkedTask"
        @open-source="() => undefined"
      />
      <TaskSearchDialog :open="taskSearchOpen" @close="taskSearchOpen = false" @select="linkExistingTask" />
    </template>
    </div>
  </section>
</template>
