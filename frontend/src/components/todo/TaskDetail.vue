<script setup lang="ts">
import { Editor as TiptapEditor } from '@tiptap/vue-3'
import type { Editor as CoreEditor } from '@tiptap/core'
import Collaboration from '@tiptap/extension-collaboration'
import { EditorContent } from '@tiptap/vue-3'
import dayjs, { type Dayjs } from 'dayjs'
import {
  IconBell, IconCalendar, IconCalendarOff, IconCheck, IconChevronLeft, IconChevronRight, IconClock,
  IconDots, IconFile, IconFlag, IconLink, IconRepeat, IconTag, IconTrash, IconX,
} from '@tabler/icons-vue'
import { computed, nextTick, onBeforeUnmount, onMounted, ref, shallowRef, watch } from 'vue'
import * as Y from 'yjs'

import ConfirmDialog from '@/components/ConfirmDialog.vue'
import EditorBubbleMenu from '@/components/EditorBubbleMenu.vue'
import EditorLinkDialog from '@/components/editor/EditorLinkDialog.vue'
import EditorSlashMenu from '@/components/editor/EditorSlashMenu.vue'
import AssigneePopover from '@/components/task/AssigneePopover.vue'
import TaskRelationDialog from '@/components/task/TaskRelationDialog.vue'
import { createWorkFollowEditorExtensions, collapseAllEmptyParagraphs } from '@/modules/editor/tiptap'
import { workFollowSlashCommands, type WorkFollowSlashCommand } from '@/modules/editor/slashCommands'
import { useSlashMenu } from '@/modules/editor/slashMenu'
import { isDateOnlyDue } from '@/modules/todo/dueDate'
import { formatLastSavedAt } from '@/modules/editor/saveStatus'
import { getScheduleMarkers } from '@/modules/todo/scheduleMarkers'
import { createTaskCollaboration, type TaskCollaborationSession, type TaskCollaborationStatus } from '@/modules/editor/taskCollaboration'
import { fetchTodo, uploadTaskAttachment, type Attachment, type NoteListItem, type TeamMember, type Todo, type TodoAssignmentStatus, type TodoPayload, type TodoPriority, type TodoRecurrenceType } from '@/services/api'
import { initializeCollaborativeField, CollaborationInitializationError } from '@/modules/editor/collaborationInitialization'
import { contentJsonSemanticallyEqual } from '@/modules/editor/contentProjection'

const props = withDefaults(defineProps<{
  todo: Todo | null
  updating?: boolean
  members?: TeamMember[]
  currentUserId?: string
}>(), { members: () => [], currentUserId: '' })
const emit = defineEmits<{
  close: []
  toggle: [todo: Todo]
  remove: [todo: Todo]
  assign: [todo: Todo, userIds: string[]]
  openSource: [noteId: string, blockId?: string | null]
  openTask: [taskId: string]
}>()

type ReminderPreset = 'NONE' | 'AT_DUE' | 'MINUS_10' | 'MINUS_60' | 'MINUS_1440'
type DateMode = 'date' | 'range'
type EditorSelection = { from: number; to: number }

const root = ref<HTMLElement | null>(null)
const dateTrigger = ref<HTMLButtonElement | null>(null)
const priorityTrigger = ref<HTMLButtonElement | null>(null)
const currentTaskId = ref<string | null>(null)
const taskTitle = ref('')
const titleInput = ref<HTMLTextAreaElement | null>(null)
const dueAt = ref('')
const dueEndAt = ref('')
const priority = ref<TodoPriority>('NONE')
const recurrenceType = ref<TodoRecurrenceType>('NONE')
const reminderPreset = ref<ReminderPreset>('NONE')
const currentTaskContentEditable = ref(false)
const collaborationSession = shallowRef<TaskCollaborationSession | null>(null)
const collaborationStatus = ref<TaskCollaborationStatus>('connecting')
const collaborationPendingChanges = ref(0)
const metadataCollaborationSession = shallowRef<TaskCollaborationSession | null>(null)
const metadataCollaborationStatus = ref<TaskCollaborationStatus>('connecting')
const metadataCollaborationPendingChanges = ref(0)
const lastSavedAt = ref<string | null>(props.todo?.updatedAt ?? props.todo?.createdAt ?? null)
const datePanelOpen = ref(false)
const datePanelAnchorStyle = ref<Record<string, string> | null>(null)
const priorityPanelOpen = ref(false)
const priorityPanelStyle = ref<Record<string, string> | null>(null)
const moreMenuOpen = ref(false)
const removeDialogOpen = ref(false)
const inlineNotice = ref('')
const dateMode = ref<DateMode>('date')
const selectedDate = ref('')
const selectedEndDate = ref('')
const choosingRangeEnd = ref(false)
const timeValue = ref('')
const calendarMonth = ref(dayjs().startOf('month'))
const savedSelection = ref<EditorSelection | null>(null)
const linkDialog = ref<InstanceType<typeof EditorLinkDialog> | null>(null)
const slash = useSlashMenu({
  commands: () => availableCommands.value,
  idPrefix: 'task-slash-command',
})
const fileInput = ref<HTMLInputElement | null>(null)
const attachmentItems = ref<Attachment[]>([])
const attachmentUploading = ref(false)
const tagPanelOpen = ref(false)
const tagValue = ref('')
const relationDialogOpen = ref(false)
let slashDetectTimer: number | undefined
let collaborationSeedTimer: number | undefined
let metadataSeedTimer: number | undefined
const OFFLINE_SEED_DELAY_MS = 10000
let hydratingEditor = false
let hydratingMetadata = false
let editorReady = false
let collaborationContentReady = false
const metadataCollaborationReady = ref(false)
let metadataObserverCleanup: (() => void) | undefined
let syncRequest = 0
let activeTaskSnapshot: Todo | null = null
let bodyInitializationAuthFailed = false
let metadataInitializationAuthFailed = false
let projectionConfirmTimer: number | undefined

function assignmentStatusLabel(status: TodoAssignmentStatus): string {
  if (status === 'DONE') return '已完成'
  if (status === 'IN_PROGRESS') return '进行中'
  return '待处理'
}

const priorityLabels: Record<TodoPriority, string> = { NONE: '无优先级', LOW: '低优先级', MEDIUM: '中优先级', HIGH: '高优先级' }
const recurrenceLabels: Record<TodoRecurrenceType, string> = { NONE: '不重复', DAILY: '每天', WEEKLY: '每周', MONTHLY: '每月', CUSTOM: '自定义' }
const weekNames = ['一', '二', '三', '四', '五', '六', '日']
const commands = workFollowSlashCommands.filter((command) => !command.noteOnly)

function sourceHref(source: Todo['sources'][number]): string {
  const params = new URLSearchParams({ note: source.resourceId ?? '' })
  if (source.blockId) params.set('block', source.blockId)
  return `/notes?${params.toString()}`
}

const editor = shallowRef<TiptapEditor | null>(null)

const collaborationStatusLabel = computed(() => {
  if (!collaborationSession.value) return ''
  const statuses = [collaborationStatus.value]
  if (metadataCollaborationSession.value) statuses.push(metadataCollaborationStatus.value)
  if (statuses.includes('error')) return '协同认证失败'
  if (statuses.includes('disconnected')) return '协同离线，正在重连…'
  if (statuses.includes('connecting')) return '连接协同…'
  if (collaborationPendingChanges.value || metadataCollaborationPendingChanges.value) return '协同保存中…'
  return '协同已连接'
})

function createTaskEditor(document: TaskCollaborationSession['document']) {
  const instance = new TiptapEditor({
    extensions: [
      ...createWorkFollowEditorExtensions('输入内容，或输入 / 插入格式', { collaboration: true }),
      Collaboration.configure({ document, field: 'default' }),
    ],
    editorProps: {
      attributes: {
        class: 'task-body-editor-content',
        role: 'textbox',
        'aria-label': '任务正文',
        'aria-multiline': 'true',
      },
      handleKeyDown: (_view, event) => {
        if (!slash.open.value) return false
        if (event.key === 'ArrowDown') slash.moveSelection(1)
        else if (event.key === 'ArrowUp') slash.moveSelection(-1)
        else if (event.key === 'Enter') {
          const command = availableCommands.value[slash.activeIndex.value]
          if (command) insertBlock(command.type)
        }
        else if (event.key === 'Escape') slash.close()
        else return false
        event.preventDefault()
        return true
      },
      handleClick: (_view, _position, event) => {
        const target = event.target as HTMLElement | null
        const noteLink = target?.closest<HTMLElement>('[data-note-link]')
        const noteId = noteLink?.dataset.noteId
        if (noteId) {
          emit('openSource', noteId)
          return true
        }
        const taskLink = target?.closest<HTMLElement>('[data-task-link], [data-task-reference]')
        const taskId = taskLink?.dataset.taskId
        if (taskId && taskId !== props.todo?.id) {
          emit('openTask', taskId)
          return true
        }
        return false
      },
    },
    onUpdate: ({ editor: currentEditor }) => {
      if (hydratingEditor || !editorReady) return
      window.clearTimeout(slashDetectTimer)
      slashDetectTimer = window.setTimeout(() => slash.detect(currentEditor), 0)
    },
    onSelectionUpdate: ({ editor: currentEditor }) => rememberSelection(currentEditor),
  })
  instance.setEditable(currentTaskContentEditable.value && collaborationContentReady)
  editor.value = instance
}

function escapeHtml(value: string) {
  return value.replaceAll('&', '&amp;').replaceAll('<', '&lt;').replaceAll('>', '&gt;')
}

function sanitizeEditorHtml(value: string) {
  if (!value.trim()) return '<p></p>'
  if (!/<\/?[a-z][\s\S]*>/i.test(value)) return value.split(/\r?\n/).map((line) => `<p>${line ? escapeHtml(line) : '<br>'}</p>`).join('')
  const documentValue = new DOMParser().parseFromString(value, 'text/html')
  const allowed = new Set([
    'P', 'DIV', 'SPAN', 'BR', 'H1', 'H2', 'H3', 'UL', 'OL', 'LI', 'BLOCKQUOTE', 'HR', 'STRONG', 'B', 'EM', 'I', 'U',
    'A', 'IMG', 'INPUT', 'PRE', 'CODE', 'MARK', 'TABLE', 'THEAD', 'TBODY', 'TR', 'TH', 'TD',
  ])
  const safeStyle = (valueToCheck: string | null) => valueToCheck?.split(';').map((part) => part.trim()).filter((part) => {
    const color = part.match(/^(color|background-color)\s*:\s*(#[\da-f]{3,8}|rgba?\([^)]*\)|hsla?\([^)]*\)|[a-z]+)$/i)
    const fontSize = part.match(/^font-size\s*:\s*(12|14|16|18|20|24)px$/i)
    return Boolean(color || fontSize)
  }).join('; ') ?? ''
  for (const element of [...documentValue.body.querySelectorAll('*')]) {
    if (!allowed.has(element.tagName)) { element.replaceWith(...element.childNodes); continue }
    const href = element.tagName === 'A' ? element.getAttribute('href') : null
    const src = element.tagName === 'IMG' ? element.getAttribute('src') : null
    const alt = element.tagName === 'IMG' ? element.getAttribute('alt') : null
    const blockType = element.getAttribute('data-task-block')
    const dataType = element.getAttribute('data-type')
    const dataChecked = element.getAttribute('data-checked')
    const dataColor = element.getAttribute('data-color')
    const isCheckbox = element.tagName === 'INPUT' && element.getAttribute('type') === 'checkbox'
    const checked = isCheckbox && (element as HTMLInputElement).checked
    const style = safeStyle(element.getAttribute('style'))
    const colspan = element.getAttribute('colspan')
    const rowspan = element.getAttribute('rowspan')
    const colwidth = element.getAttribute('data-colwidth')
    if (element.tagName === 'IMG' && (!src || !/^(https?:|\/)/i.test(src))) { element.remove(); continue }
    for (const attribute of [...element.attributes]) element.removeAttribute(attribute.name)
    if (href && /^(https?:|mailto:|#)/i.test(href)) element.setAttribute('href', href)
    if (element.tagName === 'IMG' && src) {
      element.setAttribute('src', src)
      if (alt) element.setAttribute('alt', alt)
    }
    if (blockType) element.setAttribute('data-task-block', blockType)
    if (element.tagName === 'UL' && dataType === 'taskList') element.setAttribute('data-type', 'taskList')
    if (element.tagName === 'LI' && dataType === 'taskItem') {
      element.setAttribute('data-type', 'taskItem')
      if (dataChecked === 'true' || dataChecked === 'false') element.setAttribute('data-checked', dataChecked)
    }
    if (style && (element.tagName === 'SPAN' || element.tagName === 'MARK')) element.setAttribute('style', style)
    if (element.tagName === 'MARK' && dataColor && /^(#[\da-f]{3,8}|rgba?\([^)]*\)|hsla?\([^)]*\)|[a-z]+)$/i.test(dataColor)) element.setAttribute('data-color', dataColor)
    if ((element.tagName === 'TH' || element.tagName === 'TD') && colspan && /^\d+$/.test(colspan)) element.setAttribute('colspan', colspan)
    if ((element.tagName === 'TH' || element.tagName === 'TD') && rowspan && /^\d+$/.test(rowspan)) element.setAttribute('rowspan', rowspan)
    if ((element.tagName === 'TH' || element.tagName === 'TD') && colwidth && /^[\d,]+$/.test(colwidth)) element.setAttribute('data-colwidth', colwidth)
    if (isCheckbox) {
      element.setAttribute('type', 'checkbox')
      element.setAttribute('contenteditable', 'false')
      if (checked) element.setAttribute('checked', '')
    }
  }
  return documentValue.body.innerHTML || '<p></p>'
}

function asInput(value: string | null) { return value ? dayjs(value).format('YYYY-MM-DDTHH:mm') : '' }
function detectReminder(todo: Todo): ReminderPreset {
  if (!todo.reminderAt || !todo.dueAt) return 'NONE'
  const minutes = dayjs(todo.dueAt).diff(dayjs(todo.reminderAt), 'minute')
  if (minutes === 10) return 'MINUS_10'
  if (minutes === 60) return 'MINUS_60'
  if (minutes === 1440) return 'MINUS_1440'
  return 'AT_DUE'
}

function buildReminderAt() {
  if (!dueAt.value || reminderPreset.value === 'NONE') return null
  const minutes = { AT_DUE: 0, MINUS_10: 10, MINUS_60: 60, MINUS_1440: 1440 }[reminderPreset.value]
  return dayjs(dueAt.value).subtract(minutes, 'minute').format('YYYY-MM-DDTHH:mm:ss')
}
function buildRecurrenceConfig(): Record<string, number | string> | null {
  if (!dueAt.value || recurrenceType.value === 'NONE') return null
  if (recurrenceType.value === 'WEEKLY') return { weekday: (dayjs(dueAt.value).day() + 6) % 7 }
  if (recurrenceType.value === 'MONTHLY') return { day: dayjs(dueAt.value).date() }
  if (recurrenceType.value === 'CUSTOM') {
    const shared = metadataCollaborationSession.value?.document.getMap<unknown>('metadata').get('recurrenceConfig')
    return (shared as Record<string, number | string> | null | undefined)
      ?? props.todo?.recurrenceConfig
      ?? { frequency: 'WEEKLY', interval: 1 }
  }
  return {}
}
const canEdit = computed(() => Boolean(props.todo?.permissions.editable))
const canEditContent = computed(() => Boolean(props.todo?.permissions.contentEditable ?? props.todo?.permissions.editable))
const canEditMetadata = computed(() => canEdit.value && metadataCollaborationReady.value)
const contentOnlyCommandTypes = new Set<WorkFollowSlashCommand>(['attachment', 'relation'])
const metadataOnlyCommandTypes = new Set<WorkFollowSlashCommand>(['tag'])
const availableCommands = computed(() => commands.filter((command) => {
  if (metadataOnlyCommandTypes.has(command.type)) return canEditMetadata.value
  if (contentOnlyCommandTypes.has(command.type)) return canEditContent.value
  return true
}))
const executionDone = computed(() => props.todo?.myAssignment?.status === 'DONE' || (!props.todo?.myAssignment && props.todo?.status === 'DONE'))

function metadataPayload(): Pick<TodoPayload, 'dueAt' | 'dueEndAt' | 'reminderAt' | 'recurrenceType' | 'recurrenceConfig'> {
  return {
    dueAt: dueAt.value ? dayjs(dueAt.value).format('YYYY-MM-DDTHH:mm:ss') : null,
    dueEndAt: dueEndAt.value ? dayjs(dueEndAt.value).format('YYYY-MM-DDTHH:mm:ss') : null,
    reminderAt: buildReminderAt(),
    recurrenceType: recurrenceType.value,
    recurrenceConfig: buildRecurrenceConfig(),
  }
}

type SharedTaskMetadata = {
  title: string
  dueAt: string | null
  dueEndAt: string | null
  priority: TodoPriority
  reminderAt: string | null
  recurrenceType: TodoRecurrenceType
  recurrenceConfig: Record<string, number | string> | null
  tags: string[]
}

function metadataValuesFromTodo(todo: Todo): SharedTaskMetadata {
  return {
    title: todo.title,
    dueAt: todo.dueAt,
    dueEndAt: todo.dueEndAt,
    priority: todo.priority,
    reminderAt: todo.reminderAt,
    recurrenceType: todo.recurrenceType,
    recurrenceConfig: todo.recurrenceConfig,
    tags: normalizeCollaborativeTags(todo.tags),
  }
}

function normalizeCollaborativeTags(values: unknown[]): string[] {
  return [...new Set(values
    .map((tag) => String(tag).trim().replace(/^#/, ''))
    .filter(Boolean))]
}

function metadataMap(session = metadataCollaborationSession.value) {
  return session?.document.getMap<unknown>('metadata')
}

function metadataValuesFromDocument(document: Y.Doc, initialTask: Todo): SharedTaskMetadata {
  const map = document.getMap<unknown>('metadata')
  const initialized = map.get('initialized') === true || document.getMap('config').get('metadataInitialized') === true
  const tags = normalizeCollaborativeTags(document.getArray<unknown>('tags').toArray())
  const initialValues = metadataValuesFromTodo(initialTask)
  const priorityValue = map.get('priority')
  const recurrenceValue = map.get('recurrenceType')
  return {
    title: initialized ? document.getText('title').toString() : initialValues.title,
    dueAt: initialized && map.has('dueAt') ? map.get('dueAt') as string | null : initialValues.dueAt,
    dueEndAt: initialized && map.has('dueEndAt') ? map.get('dueEndAt') as string | null : initialValues.dueEndAt,
    priority: initialized && typeof priorityValue === 'string' ? priorityValue as TodoPriority : initialValues.priority,
    reminderAt: initialized && map.has('reminderAt') ? map.get('reminderAt') as string | null : initialValues.reminderAt,
    recurrenceType: initialized && typeof recurrenceValue === 'string' ? recurrenceValue as TodoRecurrenceType : initialValues.recurrenceType,
    recurrenceConfig: initialized && map.has('recurrenceConfig')
      ? map.get('recurrenceConfig') as SharedTaskMetadata['recurrenceConfig'] | null
      : initialValues.recurrenceConfig,
    tags: initialized ? tags : initialValues.tags,
  }
}

function applyMetadataValues(values: SharedTaskMetadata) {
  hydratingMetadata = true
  try {
    taskTitle.value = values.title
    dueAt.value = asInput(values.dueAt)
    dueEndAt.value = asInput(values.dueEndAt)
    priority.value = values.priority
    recurrenceType.value = values.recurrenceType
    reminderPreset.value = props.todo ? detectReminder({ ...props.todo, dueAt: values.dueAt, reminderAt: values.reminderAt }) : 'NONE'
  } finally {
    hydratingMetadata = false
  }
}

function bindMetadataDocument(task: Todo, document: Y.Doc) {
  metadataObserverCleanup?.()
  const metadata = document.getMap<unknown>('metadata')
  const title = document.getText('title')
  const tags = document.getArray<unknown>('tags')
  const apply = () => {
    if (currentTaskId.value !== task.id) return
    applyMetadataValues(metadataValuesFromDocument(document, task))
  }
  metadata.observe(apply)
  title.observe(apply)
  tags.observe(apply)
  metadataObserverCleanup = () => {
    metadata.unobserve(apply)
    title.unobserve(apply)
    tags.unobserve(apply)
    metadataObserverCleanup = undefined
  }
  apply()
}

function seedMetadataDocument(task: Todo, document: Y.Doc, initial?: Partial<Todo>) {
  const values = metadataValuesFromTodo({ ...task, ...initial, tags: Array.isArray(initial?.tags) ? initial.tags : task.tags } as Todo)
  const title = document.getText('title')
  const metadata = document.getMap<unknown>('metadata')
  const tags = document.getArray<string>('tags')
  document.transact(() => {
    metadata.set('initialized', true)
    if (title.length === 0 && values.title) title.insert(0, values.title)
    Object.entries(values).forEach(([key, value]) => {
      if (key !== 'title' && key !== 'tags' && !metadata.has(key)) metadata.set(key, value)
    })
    if (tags.length === 0 && values.tags.length > 0) tags.push(values.tags)
  }, 'workfollow-metadata-seed')
}

function replaceCollaborativeTitle(value: string) {
  const session = metadataCollaborationSession.value
  if (!session || !metadataCollaborationReady.value || hydratingMetadata) return
  const title = session.document.getText('title')
  const current = title.toString()
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
    if (currentEnd > start) title.delete(start, currentEnd - start)
    if (nextEnd > start) title.insert(start, value.slice(start, nextEnd))
  }, 'workfollow-metadata-input')
}

function updateCollaborativeMetadata(patch: Partial<SharedTaskMetadata>): boolean {
  const session = metadataCollaborationSession.value
  const metadata = metadataMap(session)
  if (!session || !metadataCollaborationReady.value || !metadata) return false
  session.document.transact(() => {
    Object.entries(patch).forEach(([key, value]) => {
      if (key !== 'title' && key !== 'tags') metadata.set(key, value ?? null)
    })
  }, 'workfollow-metadata-input')
  return true
}

function updateCollaborativeTags(nextTags: string[]): boolean {
  const session = metadataCollaborationSession.value
  if (!session || !metadataCollaborationReady.value) return false
  const tags = session.document.getArray<string>('tags')
  const normalized = [...new Set(nextTags.map((tag) => tag.trim().replace(/^#/, '')).filter(Boolean))]
  session.document.transact(() => {
    if (tags.length > 0) tags.delete(0, tags.length)
    if (normalized.length > 0) tags.push(normalized)
  }, 'workfollow-metadata-input')
  return true
}

function seedTaskBodyDocument(
  task: Todo,
  document: Y.Doc,
  initial?: Partial<Todo>,
) {
  const session = collaborationSession.value
  const currentEditor = editor.value
  if (!currentEditor || currentTaskId.value !== task.id || document !== session?.document) return

  const config = document.getMap('config')
  if (config.get('bodyInitialized') === true || config.get('initialContentLoaded') === true) return
  // 与 NoteEditor 同因：编辑器挂载写入的默认空段落要先清掉再写种子，
  // 否则合并出两个空段落，占位符漂到第二行且永远渲染不出来。
  const fragment = document.getXmlFragment('default')
  const doc = currentEditor.state.doc
  const onlyEmptyParagraphs = doc.childCount > 0
    && Array.from(doc.children).every((node) => node.type.name === 'paragraph' && node.content.size === 0)
  if (fragment.length > 0 && !onlyEmptyParagraphs) return
  const source = initial && typeof initial === 'object' ? initial : task
  hydratingEditor = true
  try {
    if (fragment.length > 0) fragment.delete(0, fragment.length)
    currentEditor.commands.setContent(
      source.contentJson ?? task.contentJson ?? sanitizeEditorHtml(source.description ?? task.description ?? ''),
      false,
    )
    // Do not make a failed setContent call look initialized. A retry must be
    // able to seed the authoritative SQL snapshot instead of leaving a blank
    // collaborative document marked as ready.
    config.set('initialContentLoaded', true)
    config.set('bodyInitialized', true)
  } finally {
    hydratingEditor = false
  }
}

async function initializeTaskBody(task: Todo): Promise<boolean> {
  const session = collaborationSession.value
  const currentEditor = editor.value
  if (!session || !currentEditor || currentTaskId.value !== task.id) return false
  const config = session.document.getMap('config')
  if (config.get('bodyInitialized') === true || config.get('initialContentLoaded') === true || session.document.getXmlFragment('default').length > 0) {
    return true
  }
  if (!currentTaskContentEditable.value || bodyInitializationAuthFailed) return true
  try {
    await initializeCollaborativeField(
      `task:${task.id}`,
      'body',
      (initial) => seedTaskBodyDocument(task, session.document, initial as Partial<Todo> | undefined),
    )
    return true
  } catch (error) {
    if (error instanceof CollaborationInitializationError && error.kind === 'auth') bodyInitializationAuthFailed = true
    if (currentTaskId.value === task.id) {
      editor.value?.setEditable(false)
      showNotice(`正文初始化失败：${error instanceof Error ? error.message : '请稍后重试'}`)
    }
    return false
  }
}

async function initializeTaskMetadata(
  task: Todo,
  session: TaskCollaborationSession = metadataCollaborationSession.value as TaskCollaborationSession,
): Promise<boolean> {
  if (!session || currentTaskId.value !== task.id) return false
  const metadata = session.document.getMap<unknown>('metadata')
  const config = session.document.getMap('config')
  if (metadata.get('initialized') === true || config.get('metadataInitialized') === true) return true
  if (!canEdit.value || metadataInitializationAuthFailed) return true
  try {
    await initializeCollaborativeField(
      `task-meta:${task.id}`,
      'metadata',
      (initial) => seedMetadataDocument(task, session.document, initial as Partial<Todo> | undefined),
    )
    return true
  } catch (error) {
    if (error instanceof CollaborationInitializationError && error.kind === 'auth') metadataInitializationAuthFailed = true
    if (currentTaskId.value === task.id) showNotice(`任务属性初始化失败：${error instanceof Error ? error.message : '请稍后重试'}`)
    return false
  }
}

function scheduleOfflineCollaborationSeed(task: Todo) {
  window.clearTimeout(collaborationSeedTimer)
  collaborationSeedTimer = window.setTimeout(() => {
    const session = collaborationSession.value
    if (
      currentTaskId.value === task.id
      && session
      && !session.provider.isSynced
      && (collaborationStatus.value === 'disconnected' || collaborationStatus.value === 'error')
    ) {
      void initializeTaskBody(task).then((ready) => {
        if (ready && currentTaskId.value === task.id) {
          collaborationContentReady = true
          editor.value?.setEditable(currentTaskContentEditable.value)
        }
      })
    }
  }, OFFLINE_SEED_DELAY_MS)
}

function scheduleOfflineMetadataSeed(task: Todo) {
  window.clearTimeout(metadataSeedTimer)
  metadataSeedTimer = window.setTimeout(() => {
    const session = metadataCollaborationSession.value
    if (
      currentTaskId.value === task.id
      && session
      && !session.provider.isSynced
      && (metadataCollaborationStatus.value === 'disconnected' || metadataCollaborationStatus.value === 'error')
    ) {
      void initializeTaskMetadata(task, session).then((ready) => {
        if (ready && currentTaskId.value === task.id) {
          applyMetadataValues(metadataValuesFromDocument(session.document, task))
          metadataCollaborationReady.value = true
        }
      })
    }
  }, OFFLINE_SEED_DELAY_MS)
}

function startTaskCollaboration(task: Todo) {
  collaborationContentReady = false
  bodyInitializationAuthFailed = false
  collaborationStatus.value = 'connecting'
  collaborationPendingChanges.value = 0
  metadataCollaborationReady.value = false
  metadataInitializationAuthFailed = false
  metadataCollaborationStatus.value = 'connecting'
  metadataCollaborationPendingChanges.value = 0
  let metadataSession: TaskCollaborationSession
  const bodySession = createTaskCollaboration(task.id, null, {
    onStatus: (status) => {
      if (currentTaskId.value !== task.id) return
      collaborationStatus.value = status
      if (status === 'connected') {
        window.clearTimeout(collaborationSeedTimer)
      } else if (status === 'disconnected' || (status === 'error' && !bodyInitializationAuthFailed)) {
        if (!collaborationContentReady) editor.value?.setEditable(false)
        scheduleOfflineCollaborationSeed(task)
      }
    },
    onSynced: () => {
      if (currentTaskId.value !== task.id) return
      collaborationStatus.value = 'connected'
      window.clearTimeout(collaborationSeedTimer)
      void nextTick(async () => {
        if (currentTaskId.value !== task.id) return
        const ready = await initializeTaskBody(task)
        if (currentTaskId.value !== task.id) return
        if (ready && editor.value) collapseAllEmptyParagraphs(editor.value)
        collaborationContentReady = ready
        editor.value?.setEditable(currentTaskContentEditable.value && ready)
      })
    },
    onError: (message) => {
      bodyInitializationAuthFailed = /认证|权限|登录|unauthor/i.test(message)
      if (currentTaskId.value === task.id) showNotice(`协同连接失败：${message}`)
    },
    onUnsyncedChanges: (count) => {
      if (currentTaskId.value === task.id) {
        collaborationPendingChanges.value = count
        if (count === 0) scheduleProjectionConfirmation()
      }
    },
  }, 'body')
  metadataSession = createTaskCollaboration(task.id, null, {
    onStatus: (status) => {
      if (currentTaskId.value !== task.id) return
      metadataCollaborationStatus.value = status
      if (status === 'connected') {
        window.clearTimeout(metadataSeedTimer)
      } else if (status === 'disconnected' || (status === 'error' && !metadataInitializationAuthFailed)) {
        scheduleOfflineMetadataSeed(task)
      }
    },
    onSynced: () => {
      if (currentTaskId.value !== task.id) return
      metadataCollaborationStatus.value = 'connected'
      window.clearTimeout(metadataSeedTimer)
      void initializeTaskMetadata(task, metadataSession).then((ready) => {
        if (currentTaskId.value !== task.id) return
        if (ready) bindMetadataDocument(task, metadataSession.document)
        metadataCollaborationReady.value = ready
      })
    },
    onError: (message) => {
      metadataInitializationAuthFailed = /认证|权限|登录|unauthor/i.test(message)
      if (currentTaskId.value === task.id) showNotice(`元数据协同连接失败：${message}`)
    },
    onUnsyncedChanges: (count) => {
      if (currentTaskId.value === task.id) {
        metadataCollaborationPendingChanges.value = count
        if (count === 0) scheduleProjectionConfirmation()
      }
    },
  }, 'metadata')
  collaborationSession.value = bodySession
  metadataCollaborationSession.value = metadataSession
  createTaskEditor(bodySession.document)
}

function disposeTaskEditor() {
  window.clearTimeout(collaborationSeedTimer)
  collaborationSeedTimer = undefined
  window.clearTimeout(metadataSeedTimer)
  metadataSeedTimer = undefined
  window.clearTimeout(projectionConfirmTimer)
  projectionConfirmTimer = undefined
  // Tear down the ProseMirror binding before destroying its Y.Doc.  The
  // collaboration plugin unregisters observers from that document while the
  // editor is destroyed.
  const currentEditor = editor.value
  const currentSession = collaborationSession.value
  const currentMetadataSession = metadataCollaborationSession.value
  currentEditor?.destroy()
  currentSession?.destroy()
  metadataObserverCleanup?.()
  currentMetadataSession?.destroy()
  editor.value = null
  collaborationSession.value = null
  metadataCollaborationSession.value = null
  collaborationStatus.value = 'connecting'
  metadataCollaborationStatus.value = 'connecting'
  collaborationPendingChanges.value = 0
  metadataCollaborationPendingChanges.value = 0
  collaborationContentReady = false
  metadataCollaborationReady.value = false
  activeTaskSnapshot = null
}

function flushCollaboration() {
  collaborationSession.value?.provider.flushPendingUpdates()
  metadataCollaborationSession.value?.provider.flushPendingUpdates()
}

function sameTaskDate(actual: string | null, expected: string | null) {
  if (actual === expected) return true
  if (!actual || !expected) return false
  const actualTime = Date.parse(actual)
  const expectedTime = Date.parse(expected)
  return Number.isFinite(actualTime) && Number.isFinite(expectedTime) && actualTime === expectedTime
}

function taskProjectionMatches(
  latest: Todo,
  expected: { contentJson?: Record<string, unknown> | null; metadata?: SharedTaskMetadata },
) {
  if (expected.contentJson !== undefined && !contentJsonSemanticallyEqual(latest.contentJson, expected.contentJson)) return false
  if (!expected.metadata) return true
  const values = expected.metadata
  return latest.title === values.title.trim()
    && sameTaskDate(latest.dueAt, values.dueAt)
    && sameTaskDate(latest.dueEndAt, values.dueEndAt)
    && latest.priority === values.priority
    && sameTaskDate(latest.reminderAt, values.reminderAt)
    && latest.recurrenceType === values.recurrenceType
    && JSON.stringify(latest.recurrenceConfig ?? null) === JSON.stringify(values.recurrenceConfig ?? null)
    && JSON.stringify(normalizeCollaborativeTags(latest.tags).sort()) === JSON.stringify(normalizeCollaborativeTags(values.tags).sort())
}

function hasPendingCollaborativeChanges() {
  return collaborationPendingChanges.value > 0 || metadataCollaborationPendingChanges.value > 0
}

async function flushAndWaitForProjection(timeoutMs = 6000, task = activeTaskSnapshot): Promise<Todo> {
  if (!task) throw new Error('任务协同尚未就绪，无法读取最新内容。')
  flushCollaboration()
  // Opening a task can establish a clean Y.Doc whose SQL projection is already
  // current. Do not make ordinary selection/navigation wait for the server's
  // debounce window or another HTTP round-trip in that no-edit case. A real
  // local edit increments one of the pending counters above and still takes
  // the full projection barrier.
  if (!hasPendingCollaborativeChanges()) {
    return task
  }
  let latest = await fetchTodo(task.id)
  const deadline = Date.now() + timeoutMs
  // The Yjs document can receive another user's edit while this barrier is
  // polling. Recompute the expected state instead of waiting for a stale
  // point-in-time snapshot; the collaboration service projects the merged
  // document, so the final read should match the current Yjs state.
  const currentExpected = () => {
    const bodyEditor = editor.value
    const bodyReady = collaborationContentReady && bodyEditor && currentTaskId.value === task.id
    const metadataReady = metadataCollaborationReady.value
      && metadataCollaborationSession.value
      && currentTaskId.value === task.id
    return {
      contentJson: bodyReady ? bodyEditor.getJSON() as Record<string, unknown> : undefined,
      metadata: metadataReady
        ? metadataValuesFromDocument(metadataCollaborationSession.value!.document, task)
        : undefined,
    }
  }
  let expected = currentExpected()
  while (!taskProjectionMatches(latest, expected)) {
    if (Date.now() >= deadline) throw new Error('任务内容尚未同步完成，请稍后重试。')
    await new Promise((resolve) => window.setTimeout(resolve, 180))
    expected = currentExpected()
    latest = await fetchTodo(task.id)
  }
  lastSavedAt.value = latest.updatedAt ?? lastSavedAt.value
  return latest
}

function scheduleProjectionConfirmation() {
  window.clearTimeout(projectionConfirmTimer)
  projectionConfirmTimer = window.setTimeout(() => {
    projectionConfirmTimer = undefined
    if (!activeTaskSnapshot || collaborationPendingChanges.value || metadataCollaborationPendingChanges.value) return
    void flushAndWaitForProjection().catch(() => undefined)
  }, 260)
}
function resizeTitleInput() {
  if (!titleInput.value) return
  titleInput.value.style.height = 'auto'
  titleInput.value.style.height = `${titleInput.value.scrollHeight}px`
}
function onTitleInput() {
  const normalized = taskTitle.value.replace(/[\r\n]+/g, ' ')
  if (normalized !== taskTitle.value) taskTitle.value = normalized
  resizeTitleInput()
  if (!editorReady || hydratingEditor || hydratingMetadata || !canEditMetadata.value || !props.todo || !currentTaskId.value) return
  // Keep the shared title valid while still allowing the user to replace it
  // naturally: an empty intermediate input stays local until blur/Enter.
  if (!taskTitle.value.trim()) return
  replaceCollaborativeTitle(taskTitle.value)
}
function commitCollaborativeTitle() {
  if (!canEditMetadata.value || !metadataCollaborationSession.value) return
  if (!taskTitle.value.trim()) {
    taskTitle.value = metadataCollaborationSession.value.document.getText('title').toString() || props.todo?.title || ''
    resizeTitleInput()
    showNotice('标题不能为空，已保留原值')
  } else {
    replaceCollaborativeTitle(taskTitle.value)
  }
  flushCollaboration()
}

async function sync(todo: Todo | null) {
  const request = ++syncRequest
  editorReady = false
  const previousTaskId = currentTaskId.value
  const previousTask = activeTaskSnapshot
  if (previousTaskId && previousTaskId !== todo?.id) {
    // Selection changes must wait for the last Yjs projection. A provider
    // flush only hands bytes to WebSocket; polling the SQL projection closes
    // the race with completion/duplicate/list refresh actions.
    if (previousTask) {
      try { await flushAndWaitForProjection(6000, previousTask) }
      catch (error) {
        showNotice(error instanceof Error ? error.message : '任务内容尚未同步完成，请稍后重试')
        // Keep the old Y.Doc alive when the SQL projection has not confirmed
        // it. Disposing here would make the unsaved in-memory document
        // unreachable while the parent has already moved to another row.
        return
      }
    } else flushCollaboration()
    lastSavedAt.value = todo?.updatedAt ?? todo?.createdAt ?? null
    if (props.todo?.id !== todo?.id) return
  }
  disposeTaskEditor()
  currentTaskId.value = todo?.id ?? null
  activeTaskSnapshot = todo
  datePanelOpen.value = false
  datePanelAnchorStyle.value = null
  priorityPanelOpen.value = false
  priorityPanelStyle.value = null
  moreMenuOpen.value = false
  currentTaskContentEditable.value = Boolean(todo?.permissions.contentEditable ?? todo?.permissions.editable)
  taskTitle.value = todo?.title ?? ''
  dueAt.value = asInput(todo?.dueAt ?? null)
  dueEndAt.value = asInput(todo?.dueEndAt ?? null)
  priority.value = todo?.priority ?? 'NONE'
  recurrenceType.value = todo?.recurrenceType ?? 'NONE'
  reminderPreset.value = todo ? detectReminder(todo) : 'NONE'
  lastSavedAt.value = todo?.updatedAt ?? todo?.createdAt ?? null
  slash.close()
  savedSelection.value = null
  await nextTick()
  // A task can be selected again before this async turn resumes. Never start
  // a collaboration session for a stale selection; it would continue sending
  // updates after the detail panel has already moved to another task.
  if (request !== syncRequest || props.todo?.id !== todo?.id) return
  if (todo) {
    editorReady = true
    startTaskCollaboration(todo)
  } else {
    editorReady = false
  }
  attachmentItems.value = []
  resizeTitleInput()
}

watch(() => props.todo?.id, () => { void sync(props.todo) }, { immediate: true })
watch(() => props.todo?.updatedAt, (updatedAt) => {
  if (updatedAt && props.todo?.id === currentTaskId.value) lastSavedAt.value = updatedAt
})
watch(() => props.todo?.title, (title) => {
  if (!metadataCollaborationSession.value && title !== undefined && title !== taskTitle.value) {
    taskTitle.value = title
    void nextTick(resizeTitleInput)
  }
})
watch(() => props.todo?.permissions.contentEditable ?? props.todo?.permissions.editable, (editable) => {
  currentTaskContentEditable.value = Boolean(editable)
  editor.value?.setEditable(Boolean(editable) && collaborationContentReady)
})
const dateLabel = computed(() => {
  if (!dueAt.value) return '设置日期'
  const due = dayjs(dueAt.value)
  const prefix = due.isSame(dayjs(), 'day') ? '今天' : due.isSame(dayjs().add(1, 'day'), 'day') ? '明天' : due.format('M月D日')
  if (dueEndAt.value && !dayjs(dueEndAt.value).isSame(due, 'day')) return `${prefix} – ${dayjs(dueEndAt.value).format('M月D日')}`
  return isDateOnlyDue(dueAt.value) ? prefix : `${prefix}，${due.format('HH:mm')}`
})

const calendarDays = computed(() => {
  const monthStart = calendarMonth.value.startOf('month')
  const offset = (monthStart.day() + 6) % 7
  const first = monthStart.subtract(offset, 'day')
  return Array.from({ length: 42 }, (_, index) => first.add(index, 'day'))
})
function hydrateDatePanel() {
  selectedDate.value = dueAt.value ? dayjs(dueAt.value).format('YYYY-MM-DD') : ''
  selectedEndDate.value = dueEndAt.value ? dayjs(dueEndAt.value).format('YYYY-MM-DD') : ''
  timeValue.value = dueAt.value && !isDateOnlyDue(dueAt.value) ? dayjs(dueAt.value).format('HH:mm') : ''
  dateMode.value = dueEndAt.value ? 'range' : 'date'
  choosingRangeEnd.value = false
  calendarMonth.value = (dueAt.value ? dayjs(dueAt.value) : dayjs()).startOf('month')
}
function datePanelStyle(anchor?: Pick<DOMRect, 'left' | 'bottom'>) {
  const triggerRect = dateTrigger.value?.getBoundingClientRect()
  const leftAnchor = anchor?.left ?? triggerRect?.left ?? 8
  const bottomAnchor = anchor?.bottom ?? triggerRect?.bottom ?? 8
  const width = 340
  const edge = 8
  const top = Math.max(edge, Math.min(Math.round(bottomAnchor + 6), window.innerHeight - 240 - edge))
  const left = Math.round(Math.max(edge, Math.min(leftAnchor, window.innerWidth - width - edge)))
  return {
    position: 'fixed',
    top: `${top}px`,
    right: 'auto',
    left: `${left}px`,
    width: `${width}px`,
    maxHeight: `calc(100dvh - ${top + edge}px)`,
  }
}
function priorityPanelPosition() {
  const rect = priorityTrigger.value?.getBoundingClientRect()
  const edge = 8
  const width = 175
  const top = Math.max(edge, Math.min(Math.round((rect?.bottom ?? 8) + 6), window.innerHeight - 190 - edge))
  const right = Math.max(edge, window.innerWidth - (rect?.right ?? window.innerWidth - edge))
  return {
    position: 'fixed',
    top: `${top}px`,
    right: `${right}px`,
    left: 'auto',
    width: `${width}px`,
  }
}
function openDatePanel(anchor?: Pick<DOMRect, 'left' | 'bottom'>) {
  if (!canEditMetadata.value) return
  hydrateDatePanel()
  datePanelAnchorStyle.value = datePanelStyle(anchor)
  datePanelOpen.value = true
  priorityPanelOpen.value = false
  priorityPanelStyle.value = null
}
function openPriorityPanel() {
  if (!canEditMetadata.value) return
  priorityPanelStyle.value = priorityPanelPosition()
  priorityPanelOpen.value = true
  datePanelOpen.value = false
  datePanelAnchorStyle.value = null
}
function setShortcut(offset: number, hour?: number) {
  if (!canEditMetadata.value) return
  const date = dayjs().add(offset, 'day')
  selectedDate.value = date.format('YYYY-MM-DD')
  selectedEndDate.value = ''
  choosingRangeEnd.value = dateMode.value === 'range'
  calendarMonth.value = date.startOf('month')
  if (hour !== undefined) timeValue.value = `${String(hour).padStart(2, '0')}:00`
}
function chooseDay(day: Dayjs) {
  if (!canEditMetadata.value) return
  const value = day.format('YYYY-MM-DD')
  if (dateMode.value === 'date') { selectedDate.value = value; selectedEndDate.value = ''; return }
  if (!selectedDate.value || !choosingRangeEnd.value) {
    selectedDate.value = value; selectedEndDate.value = ''; choosingRangeEnd.value = true
  } else {
    selectedEndDate.value = dayjs(value).isBefore(dayjs(selectedDate.value), 'day') ? selectedDate.value : value
    if (dayjs(value).isBefore(dayjs(selectedDate.value), 'day')) selectedDate.value = value
    choosingRangeEnd.value = false
  }
}
const scheduleMarkers = computed(() => getScheduleMarkers({
  startDate: selectedDate.value,
  endDate: selectedEndDate.value || null,
  recurrenceType: recurrenceType.value,
  // Only CUSTOM carries an interval/frequency in the persisted config. Do
  // not reuse an old custom interval after the user switches to DAILY/WEEKLY.
  recurrenceConfig: recurrenceType.value === 'CUSTOM'
    ? metadataCollaborationSession.value?.document.getMap<unknown>('metadata').get('recurrenceConfig') as SharedTaskMetadata['recurrenceConfig'] | null
      ?? props.todo?.recurrenceConfig
      ?? null
    : null,
  visibleDays: calendarDays.value,
}))
function calendarDayClasses(day: Dayjs) {
  const key = day.format('YYYY-MM-DD')
  return {
    'task-schedule-marked': scheduleMarkers.value.scheduled.has(key),
    'task-schedule-range': scheduleMarkers.value.range.has(key),
    'task-schedule-recurring': scheduleMarkers.value.recurring.has(key),
  }
}
function applySchedule() {
  if (!canEditMetadata.value || !selectedDate.value) return
  const selectedTime = timeValue.value || '00:00'
  dueAt.value = `${selectedDate.value}T${selectedTime}`
  dueEndAt.value = dateMode.value === 'range' && selectedEndDate.value ? `${selectedEndDate.value}T${selectedTime}` : ''
  datePanelOpen.value = false
  if (!updateCollaborativeMetadata(metadataPayload())) showNotice('协同尚未就绪，请稍候再试')
}
function clearSchedule() {
  if (!canEditMetadata.value) return
  dueAt.value = ''; dueEndAt.value = ''; selectedDate.value = ''; selectedEndDate.value = ''
  reminderPreset.value = 'NONE'; recurrenceType.value = 'NONE'
  datePanelOpen.value = false
  const patch = { dueAt: null, dueEndAt: null, reminderAt: null, recurrenceType: 'NONE' as TodoRecurrenceType, recurrenceConfig: null }
  if (!updateCollaborativeMetadata(patch)) showNotice('协同尚未就绪，请稍候再试')
}
function selectPriority(value: TodoPriority) {
  if (!canEditMetadata.value) return
  priority.value = value
  priorityPanelOpen.value = false
  if (!updateCollaborativeMetadata({ priority: value })) showNotice('协同尚未就绪，请稍候再试')
}

function rememberSelection(currentEditor: CoreEditor | undefined = editor.value ?? undefined) {
  if (!currentEditor) return
  const { from, to } = currentEditor.state.selection
  savedSelection.value = { from, to }
}
function beginCommand(currentEditor: CoreEditor, withSlash: boolean) {
  const chain = currentEditor.chain().focus()
  if (withSlash && slash.range.value) {
    chain.deleteRange({ from: slash.range.value.from, to: currentEditor.state.selection.from })
  } else if (savedSelection.value) {
    chain.setTextSelection(savedSelection.value)
  }
  return chain
}
function insertBlock(type: WorkFollowSlashCommand) {
  const currentEditor = editor.value
  if (!currentEditor || !collaborationContentReady) return
  const withSlash = Boolean(slash.range.value)
  const chain = beginCommand(currentEditor, withSlash)
  if (type === 'link') {
    chain.run()
    slash.close()
    openLinkDialog()
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
  else if (type === 'attachment') {
    if (!canEditContent.value) return
    chain.run(); slash.close(); fileInput.value?.click(); return
  }
  else if (type === 'tag') {
    if (!canEditMetadata.value) return
    chain.run(); slash.close(); tagPanelOpen.value = true; return
  }
  else if (type === 'relation') {
    if (!canEditContent.value) return
    chain.run(); slash.close(); relationDialogOpen.value = true; return
  }
  chain.run()
  slash.close()
  savedSelection.value = null
}
async function uploadAttachmentFile(event: Event) {
  const file = (event.target as HTMLInputElement).files?.[0]
  if (!file || !props.todo || !canEditContent.value || !collaborationContentReady) return
  attachmentUploading.value = true
  try {
    const attachment = await uploadTaskAttachment(props.todo.id, file)
    attachmentItems.value = [...attachmentItems.value, attachment]
    const chain = editor.value?.chain().focus()
    if (file.type.startsWith('image/')) {
      // The installed Tiptap command typings do not know about our extended
      // attachmentId attribute, but the runtime node schema does.
      chain?.setImage({ src: attachment.url, alt: attachment.originalName, attachmentId: attachment.id } as { src: string; alt?: string; title?: string }).run()
    }
    else chain?.setLink({ href: attachment.url }).insertContent(attachment.originalName).unsetLink().run()
    flushCollaboration()
    showNotice('附件已上传')
  } catch { showNotice('附件上传失败，请重试') }
  finally { attachmentUploading.value = false; (event.target as HTMLInputElement).value = '' }
}
function addTaskTag() {
  if (!canEditMetadata.value) {
    showNotice('你没有修改任务标签的权限')
    return
  }
  const value = tagValue.value.trim().replace(/^#/, '')
  if (!value || !props.todo) return
  const currentTags = metadataValuesFromDocument(metadataCollaborationSession.value!.document, props.todo).tags
  if (currentTags.includes(value)) return
  if (!updateCollaborativeTags([...currentTags, value])) {
    showNotice('协同尚未就绪，请稍候再试')
    return
  }
  tagValue.value = ''
  tagPanelOpen.value = false
}
async function relateTask(todo: Todo) {
  if (!props.todo || !canEditContent.value || !collaborationContentReady || !editor.value) return
  try {
    // The identity belongs to the collaborative body. The server reconciles
    // the backlink row from this mark when the Yjs snapshot is projected; a
    // separate HTTP relation first would race the body update and survive
    // after the user removes the link.
    editor.value.chain().focus().insertContent({
      type: 'text',
      text: todo.title || '无标题任务',
      marks: [{ type: 'taskLink', attrs: { taskId: todo.id } }],
    }).run()
    relationDialogOpen.value = false
    showNotice('已关联任务')
  } catch { showNotice('关联失败，请确认访问权限') }
}
async function relateNote(note: NoteListItem) {
  if (!props.todo || !canEditContent.value || !collaborationContentReady || !editor.value) return
  try {
    editor.value.chain().focus().insertContent({
      type: 'text',
      text: note.title || '无标题笔记',
      marks: [{ type: 'noteLink', attrs: { noteId: note.id } }],
    }).run()
    relationDialogOpen.value = false
    showNotice('已关联笔记')
  } catch { showNotice('关联失败，请确认访问权限') }
}
function openLinkDialog() {
  linkDialog.value?.open()
}

async function requestClose() {
  if (activeTaskSnapshot) {
    try {
      await flushAndWaitForProjection()
    } catch (error) {
      showNotice(error instanceof Error ? error.message : '任务内容尚未同步完成，请稍后重试')
      return
    }
  } else flushCollaboration()
  emit('close')
}
function confirmRemove() { if (props.todo) { removeDialogOpen.value = false; emit('remove', props.todo) } }
function showNotice(message: string) { inlineNotice.value = message; window.setTimeout(() => { if (inlineNotice.value === message) inlineNotice.value = '' }, 1800) }
function closeFloatingPanels(event: MouseEvent) {
  const target = event.target as Element | null
  if (target?.closest('.task-schedule-popover, .task-priority-popover, .task-slash-menu, .task-editor-more-menu')) return
  datePanelOpen.value = false; datePanelAnchorStyle.value = null
  priorityPanelOpen.value = false; priorityPanelStyle.value = null
  slash.close(); moreMenuOpen.value = false
}
function closeEditorPanels() {
  datePanelOpen.value = false
  datePanelAnchorStyle.value = null
  priorityPanelOpen.value = false
  priorityPanelStyle.value = null
  moreMenuOpen.value = false
}

defineExpose({ openDatePanel, openPriorityPanel, flushAndWaitForProjection })
onMounted(() => {
  document.addEventListener('click', closeFloatingPanels)
})
onBeforeUnmount(() => {
  syncRequest += 1
  editorReady = false
  window.clearTimeout(projectionConfirmTimer)
  projectionConfirmTimer = undefined
  flushCollaboration()
  window.clearTimeout(slashDetectTimer)
  document.removeEventListener('click', closeFloatingPanels)
  disposeTaskEditor()
})
</script>

<template>
  <aside v-if="todo" ref="root" class="task-detail task-editor-detail" :class="{ terminal: executionDone || todo.status === 'ABANDONED', abandoned: todo.status === 'ABANDONED', readonly: !canEditContent }" aria-label="任务正文">
    <header class="task-editor-top">
      <div class="task-editor-meta-row">
        <button class="task-editor-check" :class="{ done: executionDone, abandoned: todo.status === 'ABANDONED' }" type="button" :disabled="!todo.permissions.completable" :aria-label="executionDone ? '恢复任务' : '完成任务'" @click="emit('toggle', todo)">
          <IconCheck v-if="todo.status !== 'ABANDONED'" :size="14" :stroke-width="2.3" />
          <IconX v-else :size="14" :stroke-width="2.3" />
        </button>
        <span class="task-editor-divider" aria-hidden="true" />
        <div class="task-editor-popover-host task-editor-date-host">
          <button ref="dateTrigger" class="task-editor-date" type="button" :disabled="!canEditMetadata" @click.stop="openDatePanel()"><IconCalendar :size="18" /><span>{{ dateLabel }}</span></button>
          <Teleport to="body">
          <section
            v-if="datePanelOpen"
            class="task-schedule-popover task-schedule-popover-external"
            :style="datePanelAnchorStyle ?? undefined"
            role="dialog"
            aria-label="设置任务日期"
            @click.stop
          >
            <div class="task-date-tabs" role="tablist">
              <button :class="{ active: dateMode === 'date' }" type="button" role="tab" :disabled="!canEditMetadata" @click="dateMode = 'date'; selectedEndDate = ''">日期</button>
              <button :class="{ active: dateMode === 'range' }" type="button" role="tab" :disabled="!canEditMetadata" @click="dateMode = 'range'">时间段</button>
            </div>
            <div class="task-schedule-shortcuts"><button type="button" :disabled="!canEditMetadata" @click="setShortcut(0)">今天</button><button type="button" :disabled="!canEditMetadata" @click="setShortcut(1)">明天</button><button type="button" :disabled="!canEditMetadata" @click="setShortcut(7)">下周</button><button type="button" :disabled="!canEditMetadata" @click="setShortcut(0, 20)">今晚</button></div>
            <div class="task-calendar-head"><button type="button" aria-label="上个月" :disabled="!canEditMetadata" @click="calendarMonth = calendarMonth.subtract(1, 'month')"><IconChevronLeft :size="16" /></button><strong>{{ calendarMonth.format('YYYY年M月') }}</strong><button type="button" aria-label="下个月" :disabled="!canEditMetadata" @click="calendarMonth = calendarMonth.add(1, 'month')"><IconChevronRight :size="16" /></button></div>
            <div class="task-calendar-grid weekdays"><span v-for="name in weekNames" :key="name">{{ name }}</span></div>
            <div class="task-calendar-grid" role="grid">
              <button v-for="day in calendarDays" :key="day.format('YYYY-MM-DD')" type="button" :disabled="!canEditMetadata" :class="[calendarDayClasses(day), { muted: !day.isSame(calendarMonth, 'month'), today: day.isSame(dayjs(), 'day'), selected: day.format('YYYY-MM-DD') === selectedDate || day.format('YYYY-MM-DD') === selectedEndDate }]" :aria-label="day.format('YYYY年M月D日')" @click="chooseDay(day)">{{ day.date() }}</button>
            </div>
            <div class="task-schedule-fields">
              <label><span><IconClock :size="15" />时间</span><input v-model="timeValue" type="time" :disabled="!canEditMetadata" /></label>
              <label><span><IconBell :size="15" />提醒</span><select v-model="reminderPreset" :disabled="!canEditMetadata || !selectedDate"><option value="NONE">不提醒</option><option value="AT_DUE">准时</option><option value="MINUS_10">提前 10 分钟</option><option value="MINUS_60">提前 1 小时</option><option value="MINUS_1440">提前 1 天</option></select></label>
              <label><span><IconRepeat :size="15" />重复</span><select v-model="recurrenceType" :disabled="!canEditMetadata || !selectedDate"><option v-for="(label, value) in recurrenceLabels" :key="value" :value="value">{{ label }}</option></select></label>
            </div>
            <p v-if="dateMode === 'range' && selectedDate && !selectedEndDate" class="task-popover-hint">请选择结束日期</p>
            <footer><button class="secondary-button" type="button" :disabled="!canEditMetadata" @click="clearSchedule"><IconCalendarOff :size="14" />清除</button><button class="primary-button" type="button" :disabled="!canEditMetadata || !selectedDate || (dateMode === 'range' && !selectedEndDate)" @click="applySchedule">确定</button></footer>
          </section>
          </Teleport>
        </div>
        <span v-if="todo.teamId && todo.creatorId !== currentUserId" class="task-assigned-source">{{ todo.creator.nickname }}分配</span>
        <span class="task-editor-meta-spacer" />
        <span v-if="collaborationSession" class="task-collaboration-state" :class="collaborationStatus" role="status" :title="collaborationStatusLabel">{{ collaborationStatusLabel }}</span>
        <span class="task-editor-save-state" aria-live="polite">{{ formatLastSavedAt(lastSavedAt) }}</span>
        <AssigneePopover
          v-if="todo.permissions.assignable && currentUserId"
          :members="members"
          :model-value="todo.assignments.map((item) => item.userId)"
          :current-user-id="currentUserId"
          compact
          @change="emit('assign', todo, $event)"
        />
        <div class="task-editor-popover-host">
          <button ref="priorityTrigger" class="task-editor-flag" :class="priority.toLowerCase()" type="button" :disabled="!canEditMetadata" :title="priorityLabels[priority]" @click.stop="openPriorityPanel"><IconFlag :size="18" /></button>
          <Teleport to="body">
            <section v-if="priorityPanelOpen" class="task-priority-popover task-priority-popover-fixed" :style="priorityPanelStyle ?? undefined" aria-label="设置优先级" @click.stop><button v-for="value in (['HIGH', 'MEDIUM', 'LOW', 'NONE'] as TodoPriority[])" :key="value" type="button" :disabled="!canEditMetadata" :class="value.toLowerCase()" @click="selectPriority(value)"><IconFlag :size="16" /><span>{{ priorityLabels[value] }}</span><IconCheck v-if="priority === value" :size="14" /></button></section>
          </Teleport>
        </div>
        <div v-if="todo.permissions.deletable || todo.sourceNoteId" class="task-editor-popover-host">
          <button class="task-editor-more-button" type="button" title="更多" aria-label="更多正文操作" @click.stop="moreMenuOpen = !moreMenuOpen"><IconDots :size="18" /></button>
          <section v-if="moreMenuOpen" class="task-editor-more-menu" @click.stop>
            <button v-if="todo.sourceNoteId" type="button" @click="emit('openSource', todo.sourceNoteId); moreMenuOpen = false"><IconLink :size="16" />打开来源笔记</button>
            <button v-if="todo.permissions.deletable" class="danger" type="button" @click="removeDialogOpen = true; moreMenuOpen = false"><IconTrash :size="16" />删除任务</button>
          </section>
        </div>
        <button class="task-editor-close" type="button" aria-label="关闭详情" @click="requestClose"><IconX :size="17" /></button>
      </div>
      <label class="sr-only" for="task-editor-title">任务标题</label>
      <textarea
        id="task-editor-title"
        ref="titleInput"
        v-model="taskTitle"
        class="task-editor-title task-editor-spacer"
        rows="1"
        maxlength="200"
        :readonly="!canEditMetadata"
        aria-label="任务标题"
        @input="onTitleInput"
        @blur="commitCollaborativeTitle"
        @keydown.enter.prevent="commitCollaborativeTitle"
      />
    </header>

    <div class="task-editor-area" @click="closeEditorPanels">
      <EditorBubbleMenu v-if="editor && canEditContent" :editor="editor || undefined" :attachment="canEditContent" @link="openLinkDialog" @attachment="fileInput?.click()" />
      <EditorContent class="task-body-editor" :editor="editor || undefined" @click="closeEditorPanels" />
      <span v-if="inlineNotice" class="task-editor-inline-notice" role="status">{{ inlineNotice }}</span>
      <input ref="fileInput" class="sr-only" type="file" accept=".png,.jpg,.jpeg,.webp,.pdf,.doc,.docx,.xls,.xlsx,.ppt,.pptx,.md,.txt,.mp4,.mov,.m4v,.webm" @change="uploadAttachmentFile" />
      <section v-if="tagPanelOpen && canEditMetadata" class="task-inline-property-panel" role="dialog" aria-label="添加任务标签" @click.stop><form @submit.prevent="addTaskTag"><IconTag :size="16" /><input v-model="tagValue" autofocus placeholder="输入标签" maxlength="24" /><button class="primary-button" type="submit">添加</button><button type="button" aria-label="关闭" @click="tagPanelOpen = false"><IconX :size="15" /></button></form></section>
      <section v-if="attachmentUploading || attachmentItems.length" class="task-attachment-summary" aria-label="本次上传的附件"><span v-if="attachmentUploading">正在上传附件…</span><a v-for="attachment in attachmentItems" :key="attachment.id" :href="attachment.url" target="_blank" rel="noopener noreferrer"><IconFile :size="15" />{{ attachment.originalName }}</a></section>
    </div>

    <section v-if="todo.sources.length" class="task-source-section" aria-label="任务来源">
      <strong>来源</strong>
      <article v-for="source in todo.sources" :key="source.relationId" :class="{ inaccessible: !source.accessible }">
        <template v-if="source.accessible && source.resourceId">
          <a :href="sourceHref(source)">
            <IconLink :size="15" /><span>{{ source.title }}</span><IconChevronRight :size="15" />
          </a>
          <p v-if="source.excerpt">“{{ source.excerpt }}”</p>
        </template>
        <span v-else><IconLink :size="15" />来源笔记不可访问</span>
      </article>
    </section>

    <section v-if="todo.teamId" class="task-assignment-summary" aria-label="任务指派进度">
      <span class="task-assignment-avatars" aria-label="任务成员"><span v-for="assignment in todo.assignments" :key="assignment.id" :class="{ done: assignment.status === 'DONE' }" :title="`${assignment.user.nickname || assignment.user.username} · ${assignmentStatusLabel(assignment.status)}`"><strong>{{ assignment.user.nickname || assignment.user.username }}</strong><small>{{ assignmentStatusLabel(assignment.status) }}</small></span></span>
      <strong>{{ todo.completedAssignments }} / {{ todo.totalAssignments }}</strong>
      <small v-if="!canEditContent">公共正文只读，你只能更新自己的完成状态</small>
      <small v-else-if="!canEdit">你可以编辑任务正文，但不能修改任务属性</small>
      <small v-else-if="!canEditMetadata">任务属性协同尚未就绪，暂时不能修改标题、日期和标签</small>
    </section>

    <EditorSlashMenu :commands="availableCommands" :active-index="slash.activeIndex.value" :position="slash.position.value" :open="slash.open.value" id-prefix="task-slash-command" @select="insertBlock" @hover="slash.activeIndex.value = $event" />
    <ConfirmDialog :open="removeDialogOpen" title="删除任务" :message="`确定删除“${todo.title}”吗？删除后无法恢复。`" confirm-label="删除" :danger="true" @close="removeDialogOpen = false" @confirm="confirmRemove" />
    <EditorLinkDialog ref="linkDialog" :editor="() => editor" />
    <TaskRelationDialog :open="relationDialogOpen" :current-task-id="todo.id" @close="relationDialogOpen = false" @select-task="relateTask" @select-note="relateNote" />
  </aside>
  <aside v-else class="task-detail task-detail-empty" aria-label="任务正文">
    <div><IconChevronRight :size="24" :stroke-width="1.5" /><strong>选择一个任务</strong><p>任务正文会显示在这里。</p></div>
  </aside>
</template>
