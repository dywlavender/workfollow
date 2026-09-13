<script setup lang="ts">
import { BubbleMenu, Editor as TiptapEditor, EditorContent } from '@tiptap/vue-3'
import Collaboration, { isChangeOrigin } from '@tiptap/extension-collaboration'
import type { Editor as CoreEditor } from '@tiptap/core'
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
import * as Y from 'yjs'
import { computed, nextTick, onBeforeUnmount, onMounted, reactive, ref, shallowRef, watch } from 'vue'

import {
  fetchNote, fetchTaskBriefs, postTodo,
  type Attachment, type Folder, type Note, type TaskBrief, type TeamMember, type Todo, type TodoPayload,
} from '@/services/api'
import EditorLinkDialog from '@/components/editor/EditorLinkDialog.vue'
import EditorSheetPickerDialog from '@/components/editor/EditorSheetPickerDialog.vue'
import DiagramConflictConfirm from '@/components/editor/DiagramConflictConfirm.vue'
import DrawioEditorModal from '@/components/editor/DrawioEditorModal.vue'
import EditorSlashMenu from '@/components/editor/EditorSlashMenu.vue'
import RichTextDocument from '@/components/RichTextDocument.vue'
import RichTextToolbar from '@/components/RichTextToolbar.vue'
import TaskSearchDialog from '@/components/notes/TaskSearchDialog.vue'
import TodoDialog from '@/components/todo/TodoDialog.vue'
import { createDiagramEditorHandler } from '@/modules/editor/diagramEditor'
import { createDiagramPresenceBridge, type DiagramPresenceBridge } from '@/modules/editor/diagramPresence'
import {
  isSpreadsheetFile,
  isSpreadsheetName,
  readSpreadsheet,
  readSpreadsheetBuffer,
  spreadsheetTable,
  type SpreadsheetData,
  type SpreadsheetSheetMeta,
} from '@/modules/editor/excelImport'
import { filterStandaloneAttachments } from '@/modules/editor/attachmentReferences'
import { formatLastSavedAt } from '@/modules/editor/saveStatus'
import { createNoteCollaboration, type DocumentCollaborationSession, type DocumentCollaborationStatus } from '@/modules/editor/documentCollaboration'
import { CollaborationInitializationError, initializeCollaborativeField } from '@/modules/editor/collaborationInitialization'
import { createWorkFollowEditorExtensions, collapseAllEmptyParagraphs } from '@/modules/editor/tiptap'
import { contentJsonSemanticallyEqual } from '@/modules/editor/contentProjection'
import { importedTableTruncated, tableFromHtml, tableFromTsv, type ImportedTable } from '@/modules/editor/tablePaste'
import { workFollowSlashCommands, type WorkFollowSlashCommand } from '@/modules/editor/slashCommands'
import { useSlashMenu } from '@/modules/editor/slashMenu'
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
  taskTeamId?: string | null
  currentUserId?: string
  canAssignTasks?: boolean
  focusBlockId?: string | null
}>()
const realtime = useRealtimeStore()
const emit = defineEmits<{
  moveFolder: [folderId: string | null]
  deleteAttachment: [attachment: Attachment]
  openTask: [taskId: string]
  share: []
  publish: []
  favorite: [value: boolean]
  duplicate: [note: Note]
  export: [note: Note]
  change: [payload: { title: string; contentJson: Record<string, unknown>; plainText: string }]
  saveAsTemplate: [payload: { note: Note; title: string; folderId: string | null; contentJson: Record<string, unknown>; plainText: string }]
  remove: []
}>()

const title = ref('')
const folderId = ref<string | null>(null)
const lastSavedAt = ref<string | null>(props.note?.updatedAt ?? props.note?.createdAt ?? null)
const fileInput = ref<HTMLInputElement | null>(null)
const linkDialog = ref<InstanceType<typeof EditorLinkDialog> | null>(null)
const drawioModal = ref<InstanceType<typeof DrawioEditorModal> | null>(null)
const diagramConflict = ref<InstanceType<typeof DiagramConflictConfirm> | null>(null)
// 流程图编辑存在感：bridge 写入这个响应式对象，NodeView 经 storage 读取。
const diagramEditingPresence = reactive<Record<string, { userName: string }>>({})
const diagramPresenceBridge = shallowRef<DiagramPresenceBridge | null>(null)
const slash = useSlashMenu({
  commands: () => workFollowSlashCommands,
  idPrefix: 'note-slash-command',
})
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
const fileUploadMode = ref<'embedded' | 'standalone' | 'excel'>('embedded')
const embeddedFileAccept = '.png,.jpg,.jpeg,.webp,.pdf,.docx,.xlsx,.md,.txt'
const standaloneFileAccept = '.pdf,.docx,.xlsx,.md,.txt'
const excelFileAccept = '.xlsx,.xls,.csv'
const fileAccept = computed(() => {
  if (fileUploadMode.value === 'excel') return excelFileAccept
  return fileUploadMode.value === 'standalone' ? standaloneFileAccept : embeddedFileAccept
})
const sheetPickerOpen = ref(false)
const sheetPickerSheets = ref<SpreadsheetSheetMeta[]>([])
let sheetPickerResolve: ((sheetName: string | null) => void) | null = null
const editorContent = ref<Record<string, unknown> | null>(props.note?.contentJson ?? null)
const collaborationSession = shallowRef<DocumentCollaborationSession | null>(null)
const collaborationStatus = ref<DocumentCollaborationStatus>('connecting')
const collaborationPendingChanges = ref(0)
type NoteEditorActionSnapshot = {
  note: Note
  title: string
  contentJson: Record<string, unknown>
  plainText: string
}
let collaborationSeedTimer: number | undefined
let collaborationConnectTimer: number | undefined
let hydratingEditor = false
let collaborationInitializationAuthFailed = false
let projectionConfirmTimer: number | undefined
let titleHydrationComplete = false
const collaborationContentReady = ref(false)
// A provider having no queued WebSocket updates is not the same thing as the
// SQL projection having caught up. Track edits made by this editor so opening
// an untouched note can stay responsive while a real local edit still gets a
// projection barrier before navigation/actions.
let localEditGeneration = 0
let projectedEditGeneration = 0
let projectionLifecycle = 0
let projectionFlushPromise: Promise<NoteEditorActionSnapshot> | null = null
const visibleAttachments = computed(() => filterStandaloneAttachments(
  props.attachments,
  editorContent.value ?? props.note?.contentJson,
))
const collaborationStatusLabel = computed(() => {
  if (!collaborationSession.value) return ''
  if (collaborationStatus.value === 'error') return '协同认证失败'
  if (collaborationStatus.value === 'disconnected') return '协同离线，正在重连…'
  if (collaborationStatus.value === 'connecting') return '连接协同…'
  if (!collaborationContentReady.value) return '正文同步中…'
  if (collaborationPendingChanges.value > 0) return '协同保存中…'
  return '协同已连接'
})
let contentSnapshotTimer: number | undefined
let slashDetectTimer: number | undefined
let taskHydrateTimer: number | undefined
let taskHydrateRequest = 0
const OFFLINE_SEED_DELAY_MS = 10000
let taskIdsKey = ''
let taskBriefCache = new Map<string, TaskBrief>()
let titleObserverCleanup: (() => void) | undefined

const bubbleMenuOptions = {
  duration: 120,
  // Keep the interactive menu next to its reference in DOM order. This
  // avoids Tippy's keyboard-accessibility warning and makes Tab traversal
  // predictable for the selection actions.
  appendTo: 'parent' as const,
}

const editor = shallowRef<TiptapEditor | null>(null)

function createNoteEditor(document: Y.Doc) {
  if (editor.value || document !== collaborationSession.value?.document) return
  const instance = new TiptapEditor({
    extensions: [
      ...createWorkFollowEditorExtensions('输入内容，或输入 / 插入格式', { collaboration: true }),
      Collaboration.configure({ document, field: 'default' }),
    ],
    editorProps: {
      attributes: { role: 'textbox', 'aria-label': '笔记正文', 'aria-multiline': 'true' },
      handleKeyDown: (_view, event) => {
        if (!slash.open.value) return false
        if (event.key === 'ArrowDown') slash.moveSelection(1)
        else if (event.key === 'ArrowUp') slash.moveSelection(-1)
        else if (event.key === 'Enter') insertSlashBlock(workFollowSlashCommands[slash.activeIndex.value].type)
        else if (event.key === 'Escape') slash.close()
        else return false
        event.preventDefault()
        return true
      },
      handlePaste: (_view, event) => {
        if (!collaborationContentReady.value) return false
        const clipboard = event.clipboardData
        if (!clipboard) return false
        const files = Array.from(clipboard.files ?? [])
        const images = files.filter((file) => file.type.startsWith('image/'))
        const spreadsheets = files.filter((file) => isSpreadsheetFile(file))
        if (images.length || spreadsheets.length) {
          event.preventDefault()
          for (const file of images) uploadAndInsertImage(file)
          for (const file of spreadsheets) importSpreadsheetFile(file)
          return true
        }
        // Excel / Numbers / WPS 复制的表格：首行提升为表头；混排网页片段
        // 仍走 Tiptap 默认解析。纯文本 TSV（复制区域为文本）同样转表。
        const html = clipboard.getData('text/html')
        if (html) {
          const table = tableFromHtml(html)
          if (!table) return false
          event.preventDefault()
          insertPastedTable(table)
          return true
        }
        const textTable = tableFromTsv(clipboard.getData('text/plain'))
        if (!textTable) return false
        event.preventDefault()
        insertPastedTable(textTable)
        return true
      },
      handleDrop: (_view, event, _slice, moved) => {
        if (moved || !collaborationContentReady.value) return false
        const files = Array.from(event.dataTransfer?.files ?? [])
        const images = files.filter((file) => file.type.startsWith('image/'))
        const spreadsheets = files.filter((file) => isSpreadsheetFile(file))
        if (!images.length && !spreadsheets.length) return false
        event.preventDefault()
        for (const file of images) uploadAndInsertImage(file)
        for (const file of spreadsheets) importSpreadsheetFile(file)
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
    onUpdate: ({ editor: currentEditor, transaction }) => {
      if (hydratingEditor) return
      // Collaboration-originated transactions are remote/Yjs render updates.
      // Only a transaction initiated by this editor should make navigation
      // wait for the SQL projection.
      const userEdit = transaction.docChanged && (currentEditor.isFocused || transaction.getMeta('uiEvent') != null)
      if (collaborationContentReady.value && userEdit && !isChangeOrigin(transaction)) markLocalEdit()
      scheduleContentSnapshot(currentEditor)
      scheduleTaskHydration()
      window.clearTimeout(slashDetectTimer)
      slashDetectTimer = window.setTimeout(() => slash.detect(currentEditor), 0)
    },
  })
  instance.setEditable(collaborationContentReady.value)
  instance.storage.diagramBlock.openEditor = openDiagramEditor
  instance.storage.diagramBlock.editingPresence = diagramEditingPresence
  editor.value = instance
}

function hasReliableLocalBody(document: Y.Doc): boolean {
  const config = document.getMap('config')
  const initialized = config.get('bodyInitialized') === true
    || config.get('initialContentLoaded') === true
  // An initialized empty body is valid, but it must still wait for the server
  // snapshot before mounting. A non-empty, marked document is safe to render
  // from IndexedDB while the provider reconnects because mounting it cannot
  // create the first default paragraph.
  return initialized && document.getXmlFragment('default').length > 0
}

function mountNoteEditor(document: Y.Doc): boolean {
  if (document !== collaborationSession.value?.document) return false
  if (!editor.value) createNoteEditor(document)
  return editor.value != null
}

function replaceCollaborativeTitle(value: string) {
  const session = collaborationSession.value
  if (!session) return
  const target = session.document.getText('title')
  const current = target.toString()
  if (current === value) return
  let start = 0
  while (start < current.length && start < value.length && current[start] === value[start]) start += 1
  let currentEnd = current.length
  let nextEnd = value.length
  while (currentEnd > start && nextEnd > start && current[currentEnd - 1] === value[nextEnd - 1]) {
    currentEnd -= 1
    nextEnd -= 1
  }
  session.document.transact(() => {
    if (currentEnd > start) target.delete(start, currentEnd - start)
    if (nextEnd > start) target.insert(start, value.slice(start, nextEnd))
  }, 'workfollow-note-title')
  markLocalEdit()
}

function bindNoteTitle(document: Y.Doc) {
  titleObserverCleanup?.()
  const target = document.getText('title')
  const apply = () => {
    if (document !== collaborationSession.value?.document) return
    const nextTitle = target.toString()
    if (nextTitle || collaborationContentReady.value) {
      title.value = nextTitle
      if (titleHydrationComplete) emitCurrentNoteChange()
    }
  }
  target.observe(apply)
  titleObserverCleanup = () => {
    target.unobserve(apply)
    titleObserverCleanup = undefined
  }
  apply()
}

function seedNoteDocument(note: Note, document: Y.Doc, initial?: Partial<Note>) {
  const config = document.getMap('config')
  const titleText = document.getText('title')
  const fragment = document.getXmlFragment('default')
  const currentEditor = editor.value
  if (!currentEditor) return
  if (config.get('bodyInitialized') === true || config.get('initialContentLoaded') === true) return
  // 编辑器挂载即向空协同文档写入一个默认空段落；若不清理，它会与种子内容
  // 合并成两个空段落——首行吞掉占位符、投影出多余空行。种子必须以 SQL 快照
  // 为准：只含空段落时整段清掉再写；已有真实内容则仍然短路。
  const doc = currentEditor.state.doc
  const onlyEmptyParagraphs = doc.childCount > 0
    && Array.from(doc.children).every((node) => node.type.name === 'paragraph' && node.content.size === 0)
  if (fragment.length > 0 && !onlyEmptyParagraphs) return
  const source = initial && typeof initial === 'object' ? { ...note, ...initial } : note
  if (!titleText.length && source.title) titleText.insert(0, source.title)
  hydratingEditor = true
  try {
    if (fragment.length > 0) fragment.delete(0, fragment.length)
    currentEditor.commands.setContent(source.contentJson ?? note.contentJson, false)
    // Set the markers only after the editor accepted the SQL snapshot. If a
    // malformed legacy document is rejected, a later initialization attempt
    // must still be allowed to retry instead of treating an empty fragment as
    // successfully seeded.
    config.set('initialContentLoaded', true)
    config.set('bodyInitialized', true)
  }
  finally { hydratingEditor = false }
}

async function initializeNoteBody(note: Note, session: DocumentCollaborationSession): Promise<boolean> {
  const config = session.document.getMap('config')
  const fragment = session.document.getXmlFragment('default')
  if (config.get('bodyInitialized') === true || config.get('initialContentLoaded') === true || fragment.length > 0) return true
  if (collaborationInitializationAuthFailed) return false
  let claimedInitialization = false
  let claimedInitial: Record<string, unknown> | undefined
  try {
    await initializeCollaborativeField(
      `note:${note.id}`,
      'body',
      (initial) => {
        // Do not seed from the initialization callback until the Y.Doc has a
        // Tiptap editor. The callback can run before the editor is mounted;
        // queue the authoritative SQL snapshot and mount only after the
        // provider has finished its initial sync.
        claimedInitialization = true
        claimedInitial = initial
      },
    )
    if (claimedInitialization) {
      if (props.note?.id !== note.id || collaborationSession.value !== session) return false
      if (!mountNoteEditor(session.document)) return false
      seedNoteDocument(note, session.document, claimedInitial as Partial<Note> | undefined)
    }
    return true
  } catch (error) {
    if (error instanceof CollaborationInitializationError && error.kind === 'auth') collaborationInitializationAuthFailed = true
    if (props.note?.id === note.id) {
      collaborationStatus.value = 'error'
      taskFeedback.value = error instanceof Error ? error.message : '协同初始化失败'
    }
    return false
  }
}

function scheduleOfflineNoteSeed(note: Note) {
  window.clearTimeout(collaborationSeedTimer)
  collaborationSeedTimer = window.setTimeout(() => {
    const session = collaborationSession.value
    if (
      props.note?.id === note.id
      && session
      && !session.provider.isSynced
      && (collaborationStatus.value === 'disconnected' || collaborationStatus.value === 'error')
    ) {
      void initializeNoteBody(note, session).then((ready) => {
        if (ready && props.note?.id === note.id) {
          mountNoteEditor(session.document)
          if (editor.value) collapseAllEmptyParagraphs(editor.value)
          titleHydrationComplete = true
          collaborationContentReady.value = true
          editor.value?.setEditable(true)
        }
      })
    }
  }, OFFLINE_SEED_DELAY_MS)
}

function scheduleCollaborationConnectWatchdog(note: Note) {
  window.clearTimeout(collaborationConnectTimer)
  collaborationConnectTimer = window.setTimeout(() => {
    if (props.note?.id !== note.id || collaborationStatus.value !== 'connecting') return
    const session = collaborationSession.value
    if (session?.provider.isSynced) {
      collaborationStatus.value = 'connected'
      void initializeNoteBody(note, session).then((ready) => {
        if (ready && props.note?.id === note.id) {
          mountNoteEditor(session.document)
          if (editor.value) collapseAllEmptyParagraphs(editor.value)
          titleHydrationComplete = true
          collaborationContentReady.value = true
          editor.value?.setEditable(true)
        }
      })
      return
    }
    collaborationStatus.value = 'error'
    scheduleOfflineNoteSeed(note)
  // createNoteCollaboration deliberately waits for IndexedDB hydration (up
  // to 15s) before attaching the websocket. Do not report a connection error
  // before that barrier can finish on a cold browser profile.
  }, 18000)
}

function startNoteCollaboration(note: Note) {
  collaborationStatus.value = 'connecting'
  collaborationPendingChanges.value = 0
  localEditGeneration = 0
  projectedEditGeneration = 0
  projectionFlushPromise = null
  collaborationInitializationAuthFailed = false
  titleHydrationComplete = false
  collaborationContentReady.value = false
  let session: DocumentCollaborationSession | null = null
  session = createNoteCollaboration(note.id, null, {
    onStatus: (status) => {
      if (props.note?.id !== note.id) return
      collaborationStatus.value = status
      if (status === 'connected') {
        window.clearTimeout(collaborationConnectTimer)
        window.clearTimeout(collaborationSeedTimer)
      }
      else if (status === 'disconnected' || (status === 'error' && !collaborationInitializationAuthFailed)) {
        window.clearTimeout(collaborationConnectTimer)
        scheduleOfflineNoteSeed(note)
      }
    },
    onSynced: () => {
      if (props.note?.id !== note.id || !session) return
      window.clearTimeout(collaborationConnectTimer)
      collaborationStatus.value = 'connected'
      window.clearTimeout(collaborationSeedTimer)
      const currentSession = session
      void initializeNoteBody(note, currentSession).then((ready) => {
        if (props.note?.id !== note.id || !ready) return
        mountNoteEditor(currentSession.document)
        if (editor.value) collapseAllEmptyParagraphs(editor.value)
        titleHydrationComplete = true
        collaborationContentReady.value = true
        editor.value?.setEditable(true)
      })
    },
    onError: (message) => {
      collaborationInitializationAuthFailed = /认证|权限|登录|unauthor/i.test(message)
      if (collaborationInitializationAuthFailed) collaborationStatus.value = 'error'
    },
    onUnsyncedChanges: (count) => {
      if (props.note?.id !== note.id) return
      collaborationPendingChanges.value = count
      if (count === 0) scheduleProjectionConfirmation()
    },
  })
  collaborationSession.value = session
  bindNoteTitle(session.document)
  diagramPresenceBridge.value?.destroy()
  diagramPresenceBridge.value = createDiagramPresenceBridge(session.provider.awareness, diagramEditingPresence)
  // A cold Y.Doc has no content yet. Keep the SQL projection visible while
  // IndexedDB and the provider hydrate it; only a marked local document may
  // mount early, because it already contains a complete collaborative body.
  void session.localReady.then(() => {
    if (props.note?.id !== note.id || collaborationSession.value !== session) return
    if (hasReliableLocalBody(session.document)) mountNoteEditor(session.document)
  })
  scheduleCollaborationConnectWatchdog(note)
}

function disposeNoteCollaboration() {
  // Invalidate any projection poll that was started by the previous note.
  // Its already-running HTTP request may still settle, but it must not keep
  // polling or update state after this editor is torn down.
  projectionLifecycle += 1
  projectionFlushPromise = null
  window.clearTimeout(collaborationConnectTimer)
  collaborationConnectTimer = undefined
  window.clearTimeout(collaborationSeedTimer)
  collaborationSeedTimer = undefined
  window.clearTimeout(projectionConfirmTimer)
  projectionConfirmTimer = undefined
  titleObserverCleanup?.()
  editor.value?.destroy()
  collaborationSession.value?.destroy()
  diagramPresenceBridge.value?.destroy()
  diagramPresenceBridge.value = null
  editor.value = null
  collaborationSession.value = null
  collaborationContentReady.value = false
  titleHydrationComplete = false
  collaborationPendingChanges.value = 0
  localEditGeneration = 0
  projectedEditGeneration = 0
  collaborationStatus.value = 'connecting'
}

async function syncNoteCollaboration(note: Note | null) {
  disposeNoteCollaboration()
  if (!note) return
  await nextTick()
  if (props.note?.id === note.id) startNoteCollaboration(note)
}

function onTitleInput() {
  title.value = title.value.replace(/[\r\n]+/g, ' ')
  if (collaborationContentReady.value && title.value.trim()) replaceCollaborativeTitle(title.value)
}

function commitCollaborativeTitle() {
  if (!collaborationContentReady.value) return
  if (!title.value.trim()) {
    title.value = collaborationSession.value?.document.getText('title').toString() || props.note?.title || '未命名笔记'
  }
  replaceCollaborativeTitle(title.value.trim() || '未命名笔记')
}

function moveFolder() {
  emit('moveFolder', folderId.value || null)
}

function flushCollaboration() {
  collaborationSession.value?.provider.flushPendingUpdates()
}

function markLocalEdit() {
  if (!props.note || !collaborationContentReady.value) return
  localEditGeneration += 1
  scheduleProjectionConfirmation()
}

function scheduleProjectionConfirmation() {
  window.clearTimeout(projectionConfirmTimer)
  projectionConfirmTimer = window.setTimeout(() => {
    projectionConfirmTimer = undefined
    if (
      !props.note
      || collaborationPendingChanges.value > 0
      || !collaborationContentReady.value
      || localEditGeneration <= projectedEditGeneration
    ) return
    void flushAndWaitForProjection().catch(() => undefined)
  }, 260)
}

function insertSlashBlock(type: WorkFollowSlashCommand) {
  const currentEditor = editor.value
  if (!currentEditor || !collaborationContentReady.value) return
  const chain = currentEditor.chain().focus()
  slash.deleteRange(chain, currentEditor.state.selection.from)
  if (type === 'link') {
    chain.run(); slash.close(); setLink(); return
  }
  if (type === 'attachment') {
    chain.run(); slash.close(); openFilePicker('embedded'); return
  }
  if (type === 'importExcel') {
    chain.run(); slash.close(); openFilePicker('excel'); return
  }
  if (type === 'createTask' || type === 'linkTask') {
    chain.run()
    slash.close()
    if (type === 'createTask') openTaskCreateAtCursor()
    else openTaskSearchAtCursor()
    return
  }
  if (type === 'diagram') {
    chain.run()
    slash.close()
    void openDiagramEditor(null, (payload) => {
      currentEditor.chain().focus().insertContent(payload).run()
    })
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
  else if (type === 'subtask') chain.toggleTaskList().insertContent('子代办')
  else if (type === 'tag') chain.insertContent('#标签')
  else chain.insertContent('关联代办 / 笔记')
  chain.run()
  slash.close()
}

watch(
  () => props.note?.id,
  (_newId, oldId) => {
    window.clearTimeout(contentSnapshotTimer)
    contentSnapshotTimer = undefined
    title.value = props.note?.title ?? ''
    folderId.value = props.note?.folderId ?? null
    lastSavedAt.value = props.note?.updatedAt ?? props.note?.createdAt ?? null
    attachmentPanelOpen.value = false
    editorContent.value = props.note?.contentJson ?? null
    taskIdsKey = ''
    taskBriefCache = new Map()
    slash.close()
    if (oldId !== props.note?.id) void syncNoteCollaboration(props.note)
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

watch(() => props.note?.updatedAt, (updatedAt) => {
  if (updatedAt && props.note?.id) lastSavedAt.value = updatedAt
})

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

function scheduleContentSnapshot(currentEditor: CoreEditor | null = editor.value ?? null) {
  if (!currentEditor) return
  window.clearTimeout(contentSnapshotTimer)
  contentSnapshotTimer = window.setTimeout(() => {
    if (editor.value !== currentEditor) return
    editorContent.value = currentEditor.getJSON() as Record<string, unknown>
    emitCurrentNoteChange(currentEditor)
    contentSnapshotTimer = undefined
  }, 250)
}

function currentNoteSnapshot(currentEditor: CoreEditor | null = editor.value ?? null) {
  return {
    title: title.value.trim() || '未命名笔记',
    contentJson: (currentEditor?.getJSON() ?? editorContent.value ?? props.note?.contentJson ?? {
      type: 'doc',
      content: [{ type: 'paragraph' }],
    }) as Record<string, unknown>,
    plainText: currentEditor?.getText({ blockSeparator: '\n' }) ?? props.note?.plainText ?? '',
  }
}

function emitCurrentNoteChange(currentEditor: CoreEditor | null = editor.value ?? null) {
  if (!props.note || !collaborationContentReady.value) return
  emit('change', currentNoteSnapshot(currentEditor))
}

async function runProjectionBarrier(timeoutMs: number, lifecycle: number): Promise<NoteEditorActionSnapshot> {
  const note = props.note
  const currentEditor = editor.value
  if (!note || !currentEditor || !collaborationContentReady.value || collaborationStatus.value === 'error') {
    throw new Error('笔记协同尚未就绪，无法读取最新内容。')
  }

  const noteId = note.id
  flushCollaboration()
  const deadline = Date.now() + timeoutMs
  let latest = await fetchNote(noteId)
  // Re-read the current Yjs document on every poll. A remote edit may arrive
  // after the first snapshot was captured; waiting for that obsolete snapshot
  // would report a false timeout even though the merged document is being
  // projected correctly. The returned snapshot is the same latest state that
  // the caller is about to navigate/copy/export.
  let snapshot = currentNoteSnapshot(currentEditor)
  let snapshotGeneration = localEditGeneration
  while (true) {
    if (
      lifecycle !== projectionLifecycle
      || props.note?.id !== noteId
      || editor.value !== currentEditor
    ) {
      throw new Error('笔记已切换，取消旧内容同步确认。')
    }
    // A keystroke can arrive while the GET is in flight. Do not acknowledge
    // the older generation just because the SQL response happened to match
    // the snapshot captured before that keystroke.
    if (
      localEditGeneration === snapshotGeneration
      && latest.title === snapshot.title
      && contentJsonSemanticallyEqual(latest.contentJson, snapshot.contentJson)
    ) break
    if (Date.now() >= deadline) throw new Error('笔记内容尚未同步完成，请稍后重试。')
    await new Promise((resolve) => window.setTimeout(resolve, 180))
    snapshot = currentNoteSnapshot(currentEditor)
    snapshotGeneration = localEditGeneration
    latest = await fetchNote(noteId)
  }
  if (
    lifecycle !== projectionLifecycle
    || props.note?.id !== noteId
    || editor.value !== currentEditor
  ) {
    throw new Error('笔记已切换，取消旧内容同步确认。')
  }
  projectedEditGeneration = Math.max(projectedEditGeneration, snapshotGeneration)
  // The projection response is the authoritative save acknowledgement. Do
  // not wait for the optional SSE event before updating the local indicator;
  // otherwise a healthy save can keep showing the previous timestamp when
  // the event stream is reconnecting.
  lastSavedAt.value = latest.updatedAt ?? lastSavedAt.value
  return { note: latest, ...snapshot }
}

async function flushAndWaitForProjection(timeoutMs = 6000): Promise<NoteEditorActionSnapshot> {
  // No local edit has happened since the last projection barrier. Returning
  // the current Yjs snapshot avoids a GET + polling round trip on every
  // action and still gives actions (copy/export/publish) the current content.
  if (localEditGeneration <= projectedEditGeneration) {
    if (!props.note) throw new Error('没有可用的笔记。')
    // While the collaboration document is still connecting, the editor is
    // disabled and cannot contain a user edit. Use the SQL detail directly so
    // switching away is not blocked by a cold WebSocket/IndexedDB startup.
    if (!editor.value || !collaborationContentReady.value) {
      return {
        note: props.note,
        title: props.note.title,
        contentJson: props.note.contentJson,
        plainText: props.note.plainText,
      }
    }
    const snapshot = currentNoteSnapshot()
    return {
      note: {
        ...props.note,
        title: snapshot.title,
        contentJson: snapshot.contentJson,
        plainText: snapshot.plainText,
      },
      ...snapshot,
    }
  }

  if (!props.note || !editor.value || !collaborationContentReady.value || collaborationStatus.value === 'error') {
    throw new Error('笔记协同尚未就绪，无法读取最新内容。')
  }

  if (projectionFlushPromise) return projectionFlushPromise
  const lifecycle = projectionLifecycle
  const request = runProjectionBarrier(timeoutMs, lifecycle)
  projectionFlushPromise = request
  void request.finally(() => {
    if (projectionFlushPromise === request) projectionFlushPromise = null
  }).catch(() => undefined)
  return request
}

defineExpose({ flushCollaboration, flushAndWaitForProjection })

function requestSaveAsTemplate() {
  if (!props.note) return
  const snapshot = currentNoteSnapshot()
  emit('saveAsTemplate', {
    note: props.note,
    title: snapshot.title,
    folderId: folderId.value || null,
    contentJson: snapshot.contentJson,
    plainText: snapshot.plainText,
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
  if (linkDialog.value || taskDialogOpen.value || taskSearchOpen.value) return
  if (moreOpen.value) {
    moreOpen.value = false
    return
  }
  if (slash.open.value) {
    slash.close()
    return
  }
  closeImmersive()
}

function setLink() {
  if (!collaborationContentReady.value) return
  linkDialog.value?.open()
}

function selectedText(): string {
  if (!editor.value) return ''
  const { from, to } = editor.value.state.selection
  return editor.value.state.doc.textBetween(from, to, ' ').trim()
}

function activeBlockId(currentEditor: CoreEditor): string | null {
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
  if (!text || !currentEditor || !collaborationContentReady.value) return
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
  if (!currentEditor || !collaborationContentReady.value) return
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
  if (!currentEditor || !collaborationContentReady.value) return
  const position = currentEditor.state.selection.from
  pendingTaskContext.value = {
    from: position, to: position, position, blockId: activeBlockId(currentEditor), excerpt: '',
  }
  taskSearchOpen.value = true
}

async function saveLinkedTask(payload: TodoPayload) {
  if (!props.note || !pendingTaskContext.value || !editor.value || !collaborationContentReady.value) return
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
  showTaskFeedback('✓ 已创建代办')
  scheduleTaskHydration()
}

async function linkExistingTask(todo: Todo) {
  if (!props.note || !pendingTaskContext.value || !editor.value || !collaborationContentReady.value) return
  const context = pendingTaskContext.value
  // The taskReference node is the source of truth. The collaboration
  // snapshot reconciles its REFERENCES backlink in the same transaction as
  // the note body, so removing the node cannot leave a stale relation behind.
  editor.value.chain().focus().insertContentAt(context.position, {
    type: 'taskReference', attrs: { taskId: todo.id },
  }).run()
  taskSearchOpen.value = false
  showTaskFeedback('✓ 已关联代办')
  scheduleTaskHydration()
}

function showTaskFeedback(message: string) {
  taskFeedback.value = message
  window.setTimeout(() => { if (taskFeedback.value === message) taskFeedback.value = '' }, 1400)
}

// 流程图（drawio）：编辑宿主逻辑在 modules/editor/diagramEditor.ts，这里只接通道。
function openDiagramEditor(
  attrs: Record<string, unknown> | null,
  applyUpdate: (payload: Record<string, unknown>) => void,
) {
  if (!collaborationContentReady.value) return
  void createDiagramEditorHandler({
    uploadFile: async (file) => {
      const attachment = await props.uploadFile(file)
      return { id: attachment.id, name: attachment.originalName }
    },
    openModal: (options) => drawioModal.value?.open(options, { onSave: options.onSave }) ?? Promise.resolve(null),
    feedback: showTaskFeedback,
    confirm: (message, options) => diagramConflict.value?.ask(message, options) ?? Promise.resolve(false),
    onEditingChange: (sourceId) => diagramPresenceBridge.value?.setLocalEditing(sourceId),
    editingPeer: (sourceId) => diagramEditingPresence[sourceId] ?? null,
  })(attrs, applyUpdate)
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

async function renderTaskBriefs(currentEditor: CoreEditor, briefs: Map<string, TaskBrief>) {
  await nextTick()
  for (const element of currentEditor.view.dom.querySelectorAll<HTMLElement>('[data-task-link], [data-task-reference]')) {
    const taskId = element.dataset.taskId
    const brief = taskId ? briefs.get(taskId) : undefined
    if (!brief || !brief.accessible) {
      const label = brief?.deleted ? '该代办已删除' : '该代办不可访问'
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
      element.title = '该代办已删除'
      element.querySelector<HTMLElement>('[data-task-reference-title]')?.replaceChildren('该代办已删除')
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

function uploadAndInsertImage(file: File) {
  void props.uploadFile(file).then((attachment) => {
    editor.value?.chain().focus().insertContent({
      type: 'image',
      attrs: { src: attachment.url, alt: attachment.originalName, attachmentId: attachment.id },
    }).run()
  })
}

/** 表格落点在文档末尾时补一个空段落，否则光标没有逃出表格的落点。 */
/** 表格落点在文档末尾时补一个空段落，否则光标没有逃出表格的落点。
 * 光标已经在表格内时，新表格插到当前表格之后（表格不能嵌套）。 */
function insertImportedTable(table: ImportedTable): boolean {
  const currentEditor = editor.value
  if (!currentEditor) return false
  const { selection } = currentEditor.state
  const $from = selection.$from
  let tableDepth = -1
  for (let depth = $from.depth; depth > 0; depth -= 1) {
    if ($from.node(depth).type.name === 'table') { tableDepth = depth; break }
  }
  const chain = currentEditor.chain().focus()
  let insertEnd = selection.to
  if (tableDepth > 0) {
    insertEnd = $from.after(tableDepth)
    chain.insertContentAt(insertEnd, table.json)
  } else {
    chain.insertContent(table.json)
  }
  if (insertEnd >= currentEditor.state.doc.content.size - 1) chain.insertContent({ type: 'paragraph' })
  chain.run()
  return true
}

function insertPastedTable(table: ImportedTable) {
  if (!insertImportedTable(table)) return
  if (importedTableTruncated(table.meta)) {
    showTaskFeedback(`表格较大，已截断为 ${table.meta.rows} 行 × ${table.meta.cols} 列`)
  }
}

function chooseSheet(data: SpreadsheetData): Promise<string | null> {
  if (data.sheets.length === 1) return Promise.resolve(data.sheets[0]?.name ?? null)
  if (!data.sheets.length) return Promise.resolve(null)
  sheetPickerSheets.value = data.sheets
  sheetPickerOpen.value = true
  return new Promise((resolve) => { sheetPickerResolve = resolve })
}

function resolveSheetPicker(sheetName: string | null) {
  sheetPickerOpen.value = false
  sheetPickerResolve?.(sheetName)
  sheetPickerResolve = null
}

async function importSpreadsheetIntoBody(load: () => Promise<SpreadsheetData>) {
  const currentEditor = editor.value
  if (!currentEditor || !collaborationContentReady.value) return
  showTaskFeedback('正在读取表格…')
  try {
    const data = await load()
    const sheetName = await chooseSheet(data)
    if (!sheetName) return
    const table = spreadsheetTable(data, sheetName)
    if (!table) {
      showTaskFeedback('表格内容为空，未插入')
      return
    }
    insertImportedTable(table)
    const size = `${table.meta.rows} 行 × ${table.meta.cols} 列`
    showTaskFeedback(importedTableTruncated(table.meta)
      ? `已导入「${sheetName}」：${size}（超出上限已截断，原表 ${table.meta.originalRows} 行 × ${table.meta.originalCols} 列）`
      : `已导入「${sheetName}」：${size}`)
  } catch (error) {
    showTaskFeedback(error instanceof Error ? error.message : '读取表格失败，请重试')
  }
}

/** 二进制原件照常上传为附件（原文以附件为准），表格内容只是快照；上传失败不阻塞插入。 */
function importSpreadsheetFile(file: File) {
  void props.uploadFile(file).catch(() => undefined)
  void importSpreadsheetIntoBody(() => readSpreadsheet(file))
}

async function importAttachmentAsTable(attachment: { url: string }) {
  await importSpreadsheetIntoBody(async () => {
    const response = await fetch(attachment.url)
    if (!response.ok) throw new Error('附件读取失败，请重试')
    return readSpreadsheetBuffer(await response.arrayBuffer())
  })
}

async function handleFiles(files: FileList | null) {
  if (!files || !collaborationContentReady.value) return
  let uploadedStandaloneFile = false
  const insertImages = fileUploadMode.value === 'embedded'
  for (const file of Array.from(files)) {
    if ((insertImages || fileUploadMode.value === 'excel') && isSpreadsheetFile(file)) {
      importSpreadsheetFile(file)
      continue
    }
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

function openFilePicker(mode: 'embedded' | 'standalone' | 'excel') {
  if (!collaborationContentReady.value) return
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
  window.clearTimeout(collaborationConnectTimer)
  window.clearTimeout(contentSnapshotTimer)
  window.clearTimeout(slashDetectTimer)
  window.clearTimeout(taskHydrateTimer)
  window.removeEventListener('keydown', handleImmersiveKeydown)
  document.body.classList.remove('note-editor-immersive-open')
  flushCollaboration()
  disposeNoteCollaboration()
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
          <input v-model="title" class="note-title-input" aria-label="笔记标题" maxlength="500" :disabled="!collaborationContentReady" @input="onTitleInput" @blur="commitCollaborativeTitle" />
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
          <select v-model="folderId" aria-label="移动到文件夹" @change="moveFolder">
            <option :value="null">未分类</option>
            <option v-for="folder in folders" :key="folder.id" :value="folder.id">{{ folder.name }}</option>
          </select>
          <span v-if="knowledgeState === 'update-draft' || knowledgeState === 'update-pending' || knowledgeState === 'update-needs-revision'" class="knowledge-update-target">更新目标：{{ knowledgeTargetTitle ?? '团队知识' }}</span>
          <span class="task-editor-meta-spacer" aria-hidden="true" />
          <span v-if="collaborationSession" class="task-collaboration-state" :class="collaborationStatus" role="status" :title="collaborationStatusLabel">{{ collaborationStatusLabel }}</span>
          <span class="task-editor-save-state" aria-live="polite">{{ formatLastSavedAt(lastSavedAt) }}</span>
        </div>
      </header>
      <RichTextToolbar v-if="editor && collaborationContentReady" :editor="editor" attachment diagram @link="setLink" @attachment="openFilePicker('embedded')" @diagram="openDiagramEditor(null, (payload) => { editor?.chain().focus().insertContent(payload).run() })" />
      <input ref="fileInput" class="sr-only" type="file" multiple :accept="fileAccept" @change="handleFiles(($event.target as HTMLInputElement).files)" />
      <div class="selection-menu-host">
        <BubbleMenu v-if="editor" :editor="editor" :tippy-options="bubbleMenuOptions" class="selection-menu">
          <button type="button" @mousedown.prevent @click="createTodoFromSelection">创建代办</button>
          <button type="button" @mousedown.prevent @click="copySelection">复制</button>
        </BubbleMenu>
      </div>
      <RichTextDocument
        v-if="!editor"
        class="note-editor-collaboration-fallback"
        :model-value="editorContent ?? note.contentJson"
        :editable="false"
      />
      <EditorContent v-else class="tiptap-editor" :editor="editor" />
      <span v-if="taskFeedback" class="note-task-feedback" role="status">{{ taskFeedback }}</span>
      <EditorSlashMenu :commands="workFollowSlashCommands" :active-index="slash.activeIndex.value" :position="slash.position.value" :open="slash.open.value" id-prefix="note-slash-command" @select="insertSlashBlock" @hover="slash.activeIndex.value = $event" />
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
              <button v-if="isSpreadsheetName(attachment.originalName)" type="button" class="attachment-import-button" @click="importAttachmentAsTable(attachment)">插入为表格</button>
              <button type="button" aria-label="删除附件" @click="emit('deleteAttachment', attachment)"><IconTrash :size="16" /></button>
            </article>
          </div>
          <p v-else>正文图片只在正文中展示；这里用于管理 PDF、DOCX、Markdown 和文本文件。</p>
        </div>
      </section>
      <EditorLinkDialog ref="linkDialog" :editor="() => editor" />
      <EditorSheetPickerDialog :open="sheetPickerOpen" :sheets="sheetPickerSheets" @select="resolveSheetPicker($event)" @close="resolveSheetPicker(null)" />
      <DrawioEditorModal ref="drawioModal" />
      <DiagramConflictConfirm ref="diagramConflict" />
      <TodoDialog
        :open="taskDialogOpen"
        :initial-title="taskInitialTitle"
        :members="taskMembers ?? []"
        :team-id="taskTeamId"
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
