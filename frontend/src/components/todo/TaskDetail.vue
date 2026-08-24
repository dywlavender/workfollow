<script setup lang="ts">
import { EditorContent, useEditor } from '@tiptap/vue-3'
import type { Editor as TiptapEditor } from '@tiptap/core'
import dayjs, { type Dayjs } from 'dayjs'
import {
  IconBell, IconCalendar, IconCalendarOff, IconCheck, IconChevronLeft, IconChevronRight, IconClock,
  IconDots, IconFile, IconFlag, IconInbox, IconLink, IconRepeat, IconTag, IconTrash, IconX,
} from '@tabler/icons-vue'
import { computed, nextTick, onBeforeUnmount, onMounted, ref, watch } from 'vue'

import ConfirmDialog from '@/components/ConfirmDialog.vue'
import EditorBubbleMenu from '@/components/EditorBubbleMenu.vue'
import InputDialog from '@/components/InputDialog.vue'
import AssigneePopover from '@/components/task/AssigneePopover.vue'
import TaskRelationDialog from '@/components/task/TaskRelationDialog.vue'
import { createWorkFollowEditorExtensions } from '@/modules/editor/tiptap'
import { workFollowSlashCommands, type WorkFollowSlashCommand } from '@/modules/editor/slashCommands'
import { isDateOnlyDue } from '@/modules/todo/dueDate'
import { getScheduleMarkers } from '@/modules/todo/scheduleMarkers'
import { TaskSaveQueue, type TaskSaveStatus } from '@/modules/todo/taskSaveQueue'
import { postResourceRelation, uploadTaskAttachment, type Attachment, type NoteListItem, type TeamMember, type Todo, type TodoPayload, type TodoPriority, type TodoRecurrenceType } from '@/services/api'

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
  update: [todoId: string, payload: Partial<TodoPayload>, quiet?: boolean, settled?: (ok: boolean) => void]
  assign: [todo: Todo, userIds: string[]]
  openSource: [noteId: string, blockId?: string | null]
}>()

type ReminderPreset = 'NONE' | 'AT_DUE' | 'MINUS_10' | 'MINUS_60' | 'MINUS_1440'
type SaveState = 'idle' | 'dirty' | 'saving' | 'saved' | 'error'
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
const currentTaskEditable = ref(false)
const dirty = ref(false)
const titleDirty = ref(false)
const saveState = ref<SaveState>('idle')
const datePanelOpen = ref(false)
const datePanelAnchorStyle = ref<Record<string, string> | null>(null)
const priorityPanelOpen = ref(false)
const priorityPanelStyle = ref<Record<string, string> | null>(null)
const slashMenuOpen = ref(false)
const slashActiveIndex = ref(0)
const moreMenuOpen = ref(false)
const removeDialogOpen = ref(false)
const inlineNotice = ref('')
const dateMode = ref<DateMode>('date')
const selectedDate = ref('')
const selectedEndDate = ref('')
const choosingRangeEnd = ref(false)
const timeValue = ref('')
const calendarMonth = ref(dayjs().startOf('month'))
const slashPosition = ref({ left: 0, top: 0 })
const savedSelection = ref<EditorSelection | null>(null)
const slashRange = ref<EditorSelection | null>(null)
const linkDialogOpen = ref(false)
const linkValue = ref('')
const fileInput = ref<HTMLInputElement | null>(null)
const attachmentItems = ref<Attachment[]>([])
const attachmentUploading = ref(false)
const tagPanelOpen = ref(false)
const tagValue = ref('')
const relationDialogOpen = ref(false)
let saveTimer: number | undefined
let titleSaveTimer: number | undefined
let slashDetectTimer: number | undefined
let savedStateTimer: number | undefined
let hydratingEditor = false

const saveQueue = new TaskSaveQueue<TodoPayload>(
  (request) => new Promise<boolean>((resolve) => emit('update', request.todoId, request.data, request.quiet, resolve)),
  (todoId, status) => reflectSaveStatus(todoId, status),
)

const priorityLabels: Record<TodoPriority, string> = { NONE: '无优先级', LOW: '低优先级', MEDIUM: '中优先级', HIGH: '高优先级' }
const recurrenceLabels: Record<TodoRecurrenceType, string> = { NONE: '不重复', DAILY: '每天', WEEKLY: '每周', MONTHLY: '每月', CUSTOM: '自定义' }
const weekNames = ['一', '二', '三', '四', '五', '六', '日']
const commands = workFollowSlashCommands.filter((command) => !command.noteOnly)

function sourceHref(source: Todo['sources'][number]): string {
  const params = new URLSearchParams({ note: source.resourceId ?? '' })
  if (source.blockId) params.set('block', source.blockId)
  return `/notes?${params.toString()}`
}

const editor = useEditor({
  extensions: createWorkFollowEditorExtensions('输入内容，或输入 / 插入格式'),
  content: { type: 'doc', content: [{ type: 'paragraph' }] },
  editorProps: {
    attributes: {
      class: 'task-body-editor-content',
      role: 'textbox',
      'aria-label': '任务正文',
      'aria-multiline': 'true',
    },
    handleKeyDown: (_view, event) => {
      if (!slashMenuOpen.value) return false
      if (event.key === 'ArrowDown') moveSlashSelection(1)
      else if (event.key === 'ArrowUp') moveSlashSelection(-1)
      else if (event.key === 'Enter') insertBlock(commands[slashActiveIndex.value].type)
      else if (event.key === 'Escape') closeSlashMenu()
      else return false
      event.preventDefault()
      return true
    },
  },
  onUpdate: ({ editor: currentEditor }) => {
    if (hydratingEditor) return
    scheduleSave()
    window.clearTimeout(slashDetectTimer)
    slashDetectTimer = window.setTimeout(() => detectSlashCommand(currentEditor), 0)
  },
  onSelectionUpdate: ({ editor: currentEditor }) => rememberSelection(currentEditor),
})

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
  if (recurrenceType.value === 'CUSTOM') return props.todo?.recurrenceConfig ?? { frequency: 'WEEKLY', interval: 1 }
  return {}
}
const formInvalid = computed(() => (recurrenceType.value !== 'NONE' || reminderPreset.value !== 'NONE') && !dueAt.value)
const canEdit = computed(() => Boolean(props.todo?.permissions.editable))
const executionDone = computed(() => props.todo?.myAssignment?.status === 'DONE' || (!props.todo?.myAssignment && props.todo?.status === 'DONE'))

function payload(): TodoPayload {
  return {
    title: taskTitle.value.trim(),
    contentJson: (editor.value?.getJSON() ?? props.todo?.contentJson ?? { type: 'doc', content: [{ type: 'paragraph' }] }) as Record<string, unknown>,
    description: editor.value?.getText({ blockSeparator: '\n' }).trim() || null,
    priority: priority.value,
    dueAt: dueAt.value ? dayjs(dueAt.value).format('YYYY-MM-DDTHH:mm:ss') : null,
    dueEndAt: dueEndAt.value ? dayjs(dueEndAt.value).format('YYYY-MM-DDTHH:mm:ss') : null,
    reminderAt: buildReminderAt(), recurrenceType: recurrenceType.value, recurrenceConfig: buildRecurrenceConfig(),
  }
}
function save(quiet = true) {
  window.clearTimeout(saveTimer)
  window.clearTimeout(titleSaveTimer)
  if (!currentTaskEditable.value || !currentTaskId.value || (!dirty.value && !titleDirty.value) || formInvalid.value) return
  if (titleDirty.value && !taskTitle.value.trim()) {
    taskTitle.value = props.todo?.title ?? ''
    titleDirty.value = false
    resizeTitleInput()
    if (!dirty.value) saveState.value = 'idle'
    showNotice('标题不能为空，已保留原值')
    return
  }
  const todoId = currentTaskId.value
  const data: Partial<TodoPayload> = dirty.value ? payload() : { title: taskTitle.value.trim() }
  dirty.value = false
  titleDirty.value = false
  saveQueue.enqueue(todoId, data, quiet)
}
function reflectSaveStatus(todoId: string, status: TaskSaveStatus) {
  if (currentTaskId.value !== todoId) return
  window.clearTimeout(savedStateTimer)
  saveState.value = status
  if (status === 'error') showNotice('保存失败，内容仍保留，可点击重试')
  if (status === 'saved') savedStateTimer = window.setTimeout(() => {
    if (currentTaskId.value === todoId && saveState.value === 'saved') saveState.value = 'idle'
  }, 1000)
}
function retrySave() {
  if (!currentTaskId.value) return
  saveQueue.retry(currentTaskId.value)
}
function scheduleSave() {
  if (!canEdit.value || !props.todo || !editor.value) return
  dirty.value = true
  saveState.value = 'dirty'
  window.clearTimeout(saveTimer)
  saveTimer = window.setTimeout(() => save(true), 750)
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
  if (!canEdit.value || !props.todo || !currentTaskId.value) return
  titleDirty.value = true
  saveState.value = 'dirty'
  window.clearTimeout(titleSaveTimer)
  titleSaveTimer = window.setTimeout(() => save(true), 500)
}

async function sync(todo: Todo | null) {
  const previousTaskId = currentTaskId.value
  if (previousTaskId && previousTaskId !== todo?.id) {
    if (dirty.value || titleDirty.value) save(true)
    await saveQueue.waitFor(previousTaskId)
    if (props.todo?.id !== todo?.id) return
  }
  window.clearTimeout(saveTimer)
  window.clearTimeout(titleSaveTimer)
  currentTaskId.value = todo?.id ?? null
  datePanelOpen.value = false
  datePanelAnchorStyle.value = null
  priorityPanelOpen.value = false
  priorityPanelStyle.value = null
  moreMenuOpen.value = false
  currentTaskEditable.value = Boolean(todo?.permissions.editable)
  taskTitle.value = todo?.title ?? ''
  dueAt.value = asInput(todo?.dueAt ?? null)
  dueEndAt.value = asInput(todo?.dueEndAt ?? null)
  priority.value = todo?.priority ?? 'NONE'
  recurrenceType.value = todo?.recurrenceType ?? 'NONE'
  reminderPreset.value = todo ? detectReminder(todo) : 'NONE'
  dirty.value = false
  titleDirty.value = false
  saveState.value = todo ? saveQueue.status(todo.id) : 'idle'
  slashMenuOpen.value = false
  slashRange.value = null
  savedSelection.value = null
  await nextTick()
  if (editor.value) {
    editor.value.setEditable(Boolean(todo?.permissions.editable))
    hydratingEditor = true
    editor.value.commands.setContent(todo?.contentJson ?? sanitizeEditorHtml(todo?.description ?? ''), false)
    hydratingEditor = false
    dirty.value = false
  }
  attachmentItems.value = []
  resizeTitleInput()
}

watch(() => props.todo?.id, () => { void sync(props.todo) }, { immediate: true })
watch(() => props.todo?.title, (title) => {
  if (!titleDirty.value && title !== undefined && title !== taskTitle.value) {
    taskTitle.value = title
    void nextTick(resizeTitleInput)
  }
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
  if (!canEdit.value) return
  hydrateDatePanel()
  datePanelAnchorStyle.value = datePanelStyle(anchor)
  datePanelOpen.value = true
  priorityPanelOpen.value = false
  priorityPanelStyle.value = null
}
function openPriorityPanel() {
  if (!canEdit.value) return
  priorityPanelStyle.value = priorityPanelPosition()
  priorityPanelOpen.value = true
  datePanelOpen.value = false
  datePanelAnchorStyle.value = null
}
function setShortcut(offset: number, hour?: number) {
  const date = dayjs().add(offset, 'day')
  selectedDate.value = date.format('YYYY-MM-DD')
  selectedEndDate.value = ''
  choosingRangeEnd.value = dateMode.value === 'range'
  calendarMonth.value = date.startOf('month')
  if (hour !== undefined) timeValue.value = `${String(hour).padStart(2, '0')}:00`
}
function chooseDay(day: Dayjs) {
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
  recurrenceConfig: recurrenceType.value === 'CUSTOM' ? props.todo?.recurrenceConfig ?? null : null,
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
  if (!selectedDate.value) return
  const selectedTime = timeValue.value || '00:00'
  dueAt.value = `${selectedDate.value}T${selectedTime}`
  dueEndAt.value = dateMode.value === 'range' && selectedEndDate.value ? `${selectedEndDate.value}T${selectedTime}` : ''
  dirty.value = true
  datePanelOpen.value = false
  save(true)
}
function clearSchedule() {
  dueAt.value = ''; dueEndAt.value = ''; selectedDate.value = ''; selectedEndDate.value = ''
  reminderPreset.value = 'NONE'; recurrenceType.value = 'NONE'; dirty.value = true
  datePanelOpen.value = false
  save(true)
}
function selectPriority(value: TodoPriority) { priority.value = value; dirty.value = true; priorityPanelOpen.value = false; save(true) }

function rememberSelection(currentEditor: TiptapEditor | undefined = editor.value) {
  if (!currentEditor) return
  const { from, to } = currentEditor.state.selection
  savedSelection.value = { from, to }
}
function placeMenuAtCaret(currentEditor: TiptapEditor | undefined = editor.value) {
  if (!currentEditor) return
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
  const from = Math.max(0, selection.from - 1)
  slashRange.value = { from, to: selection.from }
  placeMenuAtCaret(currentEditor)
  slashActiveIndex.value = 0
  slashMenuOpen.value = true
}
function closeSlashMenu() {
  slashMenuOpen.value = false
  slashRange.value = null
}
function scrollActiveSlashCommand() {
  void nextTick(() => document.getElementById(`task-slash-command-${commands[slashActiveIndex.value].type}`)?.scrollIntoView({ block: 'nearest' }))
}
function moveSlashSelection(direction: number) {
  slashActiveIndex.value = (slashActiveIndex.value + direction + commands.length) % commands.length
  scrollActiveSlashCommand()
}
function beginCommand(currentEditor: TiptapEditor, withSlash: boolean) {
  const chain = currentEditor.chain().focus()
  if (withSlash && slashRange.value) {
    chain.deleteRange({ from: slashRange.value.from, to: currentEditor.state.selection.from })
  } else if (savedSelection.value) {
    chain.setTextSelection(savedSelection.value)
  }
  return chain
}
function insertBlock(type: WorkFollowSlashCommand) {
  const currentEditor = editor.value
  if (!currentEditor) return
  const withSlash = Boolean(slashRange.value)
  const chain = beginCommand(currentEditor, withSlash)
  if (type === 'link') {
    chain.run()
    slashMenuOpen.value = false
    slashRange.value = null
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
  else if (type === 'attachment') { chain.run(); closeSlashMenu(); fileInput.value?.click(); return }
  else if (type === 'tag') { chain.run(); closeSlashMenu(); tagPanelOpen.value = true; return }
  else if (type === 'relation') { chain.run(); closeSlashMenu(); relationDialogOpen.value = true; return }
  chain.run()
  slashMenuOpen.value = false
  slashRange.value = null
  savedSelection.value = null
}
async function uploadAttachmentFile(event: Event) {
  const file = (event.target as HTMLInputElement).files?.[0]
  if (!file || !props.todo) return
  attachmentUploading.value = true
  try {
    const attachment = await uploadTaskAttachment(props.todo.id, file)
    attachmentItems.value = [...attachmentItems.value, attachment]
    const chain = editor.value?.chain().focus()
    if (file.type.startsWith('image/')) chain?.setImage({ src: attachment.url, alt: attachment.originalName }).run()
    else chain?.setLink({ href: attachment.url }).insertContent(attachment.originalName).unsetLink().run()
    dirty.value = true
    save(true)
    showNotice('附件已上传')
  } catch { showNotice('附件上传失败，请重试') }
  finally { attachmentUploading.value = false; (event.target as HTMLInputElement).value = '' }
}
function addTaskTag() {
  const value = tagValue.value.trim().replace(/^#/, '')
  if (!value || !props.todo || props.todo.tags.includes(value)) return
  emit('update', props.todo.id, { tags: [...props.todo.tags, value] }, false)
  tagValue.value = ''
  tagPanelOpen.value = false
}
async function relateTask(todo: Todo) {
  if (!props.todo) return
  try {
    await postResourceRelation({ sourceType: 'TASK', sourceId: props.todo.id, targetType: 'TASK', targetId: todo.id })
    editor.value?.chain().focus().insertContent(`[[${todo.title}]]`).run()
    relationDialogOpen.value = false
    showNotice('已关联任务')
  } catch { showNotice('关联失败，请确认访问权限') }
}
async function relateNote(note: NoteListItem) {
  if (!props.todo) return
  try {
    await postResourceRelation({ sourceType: 'TASK', sourceId: props.todo.id, targetType: 'PERSONAL_NOTE', targetId: note.id })
    editor.value?.chain().focus().insertContent(`[[${note.title || '无标题笔记'}]]`).run()
    relationDialogOpen.value = false
    showNotice('已关联笔记')
  } catch { showNotice('关联失败，请确认访问权限') }
}
function openLinkDialog() {
  if (!editor.value) return
  linkValue.value = (editor.value.getAttributes('link').href as string | undefined) ?? 'https://'
  linkDialogOpen.value = true
}
function applyLink(value: string) {
  linkDialogOpen.value = false
  if (!editor.value) return
  const url = value.trim()
  if (!url) editor.value.chain().focus().extendMarkRange('link').unsetLink().run()
  else editor.value.chain().focus().extendMarkRange('link').setLink({ href: url }).run()
}

async function requestClose() {
  const todoId = currentTaskId.value
  save(true)
  if (!todoId || await saveQueue.waitFor(todoId)) emit('close')
  else showNotice('保存失败，请重试后再关闭')
}
function protectUnsavedBeforeUnload(event: BeforeUnloadEvent) {
  save(true)
  if (!dirty.value && !titleDirty.value && !saveQueue.hasUnsaved()) return
  event.preventDefault()
  event.returnValue = ''
}
function confirmRemove() { if (props.todo) { removeDialogOpen.value = false; emit('remove', props.todo) } }
function showNotice(message: string) { inlineNotice.value = message; window.setTimeout(() => { if (inlineNotice.value === message) inlineNotice.value = '' }, 1800) }
function closeFloatingPanels(event: MouseEvent) {
  const target = event.target as Element | null
  if (target?.closest('.task-schedule-popover, .task-priority-popover, .task-slash-menu, .task-editor-more-menu')) return
  datePanelOpen.value = false; datePanelAnchorStyle.value = null
  priorityPanelOpen.value = false; priorityPanelStyle.value = null
  slashMenuOpen.value = false; moreMenuOpen.value = false
}
function closeEditorPanels() {
  datePanelOpen.value = false
  datePanelAnchorStyle.value = null
  priorityPanelOpen.value = false
  priorityPanelStyle.value = null
  moreMenuOpen.value = false
}

defineExpose({ openDatePanel, openPriorityPanel })
onMounted(() => {
  document.addEventListener('click', closeFloatingPanels)
  window.addEventListener('beforeunload', protectUnsavedBeforeUnload)
  void sync(props.todo)
})
onBeforeUnmount(() => {
  save(true)
  window.clearTimeout(saveTimer)
  window.clearTimeout(titleSaveTimer)
  window.clearTimeout(slashDetectTimer)
  window.clearTimeout(savedStateTimer)
  document.removeEventListener('click', closeFloatingPanels)
  window.removeEventListener('beforeunload', protectUnsavedBeforeUnload)
})
</script>

<template>
  <aside v-if="todo" ref="root" class="task-detail task-editor-detail" :class="{ terminal: executionDone || todo.status === 'ABANDONED', abandoned: todo.status === 'ABANDONED', readonly: !canEdit }" aria-label="任务正文">
    <header class="task-editor-top">
      <div class="task-editor-meta-row">
        <button class="task-editor-check" :class="{ done: executionDone, abandoned: todo.status === 'ABANDONED' }" type="button" :disabled="!todo.permissions.completable" :aria-label="executionDone ? '恢复任务' : '完成任务'" @click="emit('toggle', todo)">
          <IconCheck v-if="todo.status !== 'ABANDONED'" :size="14" :stroke-width="2.3" />
          <IconX v-else :size="14" :stroke-width="2.3" />
        </button>
        <span class="task-editor-divider" aria-hidden="true" />
        <div class="task-editor-popover-host task-editor-date-host">
          <button ref="dateTrigger" class="task-editor-date" type="button" :disabled="!canEdit" @click.stop="openDatePanel()"><IconCalendar :size="18" /><span>{{ dateLabel }}</span></button>
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
              <button :class="{ active: dateMode === 'date' }" type="button" role="tab" @click="dateMode = 'date'; selectedEndDate = ''">日期</button>
              <button :class="{ active: dateMode === 'range' }" type="button" role="tab" @click="dateMode = 'range'">时间段</button>
            </div>
            <div class="task-schedule-shortcuts"><button type="button" @click="setShortcut(0)">今天</button><button type="button" @click="setShortcut(1)">明天</button><button type="button" @click="setShortcut(7)">下周</button><button type="button" @click="setShortcut(0, 20)">今晚</button></div>
            <div class="task-calendar-head"><button type="button" aria-label="上个月" @click="calendarMonth = calendarMonth.subtract(1, 'month')"><IconChevronLeft :size="16" /></button><strong>{{ calendarMonth.format('YYYY年M月') }}</strong><button type="button" aria-label="下个月" @click="calendarMonth = calendarMonth.add(1, 'month')"><IconChevronRight :size="16" /></button></div>
            <div class="task-calendar-grid weekdays"><span v-for="name in weekNames" :key="name">{{ name }}</span></div>
            <div class="task-calendar-grid" role="grid">
              <button v-for="day in calendarDays" :key="day.format('YYYY-MM-DD')" type="button" :class="[calendarDayClasses(day), { muted: !day.isSame(calendarMonth, 'month'), today: day.isSame(dayjs(), 'day'), selected: day.format('YYYY-MM-DD') === selectedDate || day.format('YYYY-MM-DD') === selectedEndDate }]" :aria-label="day.format('YYYY年M月D日')" @click="chooseDay(day)">{{ day.date() }}</button>
            </div>
            <div class="task-schedule-fields">
              <label><span><IconClock :size="15" />时间</span><input v-model="timeValue" type="time" /></label>
              <label><span><IconBell :size="15" />提醒</span><select v-model="reminderPreset" :disabled="!selectedDate"><option value="NONE">不提醒</option><option value="AT_DUE">准时</option><option value="MINUS_10">提前 10 分钟</option><option value="MINUS_60">提前 1 小时</option><option value="MINUS_1440">提前 1 天</option></select></label>
              <label><span><IconRepeat :size="15" />重复</span><select v-model="recurrenceType" :disabled="!selectedDate"><option v-for="(label, value) in recurrenceLabels" :key="value" :value="value">{{ label }}</option></select></label>
            </div>
            <p v-if="dateMode === 'range' && selectedDate && !selectedEndDate" class="task-popover-hint">请选择结束日期</p>
            <footer><button class="secondary-button" type="button" @click="clearSchedule"><IconCalendarOff :size="14" />清除</button><button class="primary-button" type="button" :disabled="!selectedDate || (dateMode === 'range' && !selectedEndDate)" @click="applySchedule">确定</button></footer>
          </section>
          </Teleport>
        </div>
        <span v-if="todo.teamId && todo.creatorId !== currentUserId" class="task-assigned-source">{{ todo.creator.nickname }}分配</span>
        <span class="task-editor-meta-spacer" />
        <AssigneePopover
          v-if="todo.permissions.assignable && currentUserId"
          :members="members"
          :model-value="todo.assignments.map((item) => item.userId)"
          :current-user-id="currentUserId"
          compact
          @change="emit('assign', todo, $event)"
        />
        <div class="task-editor-popover-host">
          <button ref="priorityTrigger" class="task-editor-flag" :class="priority.toLowerCase()" type="button" :disabled="!canEdit" :title="priorityLabels[priority]" @click.stop="openPriorityPanel"><IconFlag :size="18" /></button>
          <Teleport to="body">
            <section v-if="priorityPanelOpen" class="task-priority-popover task-priority-popover-fixed" :style="priorityPanelStyle ?? undefined" aria-label="设置优先级" @click.stop><button v-for="value in (['HIGH', 'MEDIUM', 'LOW', 'NONE'] as TodoPriority[])" :key="value" type="button" :class="value.toLowerCase()" @click="selectPriority(value)"><IconFlag :size="16" /><span>{{ priorityLabels[value] }}</span><IconCheck v-if="priority === value" :size="14" /></button></section>
          </Teleport>
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
        :readonly="!canEdit"
        aria-label="任务标题"
        @input="onTitleInput"
        @blur="save(true)"
        @keydown.enter.prevent="save(true)"
      />
    </header>

    <div class="task-editor-area" @click="closeEditorPanels">
      <EditorBubbleMenu v-if="editor && canEdit" :editor="editor" attachment @link="openLinkDialog" @attachment="fileInput?.click()" />
      <EditorContent class="task-body-editor" :editor="editor" @click="closeEditorPanels" />
      <button v-if="saveState === 'error'" class="task-editor-save-state error" type="button" aria-live="polite" @click="retrySave">保存失败，点击重试</button>
      <span v-else-if="saveState !== 'idle'" class="task-editor-save-state" :class="saveState" aria-live="polite">{{ saveState === 'saving' ? '保存中…' : saveState === 'saved' ? '已保存' : '等待保存' }}</span>
      <span v-if="inlineNotice" class="task-editor-inline-notice" role="status">{{ inlineNotice }}</span>
      <input ref="fileInput" class="sr-only" type="file" accept=".png,.jpg,.jpeg,.webp,.pdf,.doc,.docx,.xls,.xlsx,.ppt,.pptx,.md,.txt,.mp4,.mov,.m4v,.webm" @change="uploadAttachmentFile" />
      <section v-if="tagPanelOpen" class="task-inline-property-panel" role="dialog" aria-label="添加任务标签" @click.stop><form @submit.prevent="addTaskTag"><IconTag :size="16" /><input v-model="tagValue" autofocus placeholder="输入标签" maxlength="24" /><button class="primary-button" type="submit">添加</button><button type="button" aria-label="关闭" @click="tagPanelOpen = false"><IconX :size="15" /></button></form></section>
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
      <span class="task-assignment-avatars"><span v-for="assignment in todo.assignments" :key="assignment.id" :class="{ done: assignment.status === 'DONE' }" :title="`${assignment.user.nickname} · ${assignment.status === 'DONE' ? '已完成' : assignment.status === 'IN_PROGRESS' ? '进行中' : '待处理'}`">{{ assignment.user.nickname.slice(0, 1).toUpperCase() }}</span></span>
      <strong>{{ todo.completedAssignments }} / {{ todo.totalAssignments }}</strong>
      <small v-if="!canEdit">公共正文只读，你只能更新自己的完成状态</small>
    </section>

    <footer class="task-editor-footer">
      <span class="task-editor-list"><IconInbox :size="16" /><span>{{ todo.listName }}</span></span>
      <div class="task-editor-footer-actions">
        <div v-if="canEdit" class="task-editor-popover-host">
          <button class="task-editor-footer-button" type="button" title="更多" aria-label="更多正文操作" @click.stop="moreMenuOpen = !moreMenuOpen"><IconDots :size="18" /></button>
          <section v-if="moreMenuOpen" class="task-editor-more-menu" @click.stop>
            <button v-if="todo.sourceNoteId && !todo.sources.length" type="button" @click="emit('openSource', todo.sourceNoteId); moreMenuOpen = false"><IconLink :size="16" />打开来源笔记</button>
            <button v-if="todo.permissions.deletable" class="danger" type="button" @click="removeDialogOpen = true; moreMenuOpen = false"><IconTrash :size="16" />删除任务</button>
          </section>
        </div>
      </div>
    </footer>

    <Teleport to="body">
      <section v-if="slashMenuOpen" class="task-slash-menu" :style="{ left: `${slashPosition.left}px`, top: `${slashPosition.top}px` }" role="menu" aria-label="插入格式" @mousedown.prevent.stop @click.stop>
        <button
          v-for="(command, index) in commands"
          :id="`task-slash-command-${command.type}`"
          :key="command.type"
          type="button"
          role="menuitem"
          :class="{ active: slashActiveIndex === index }"
          :aria-current="slashActiveIndex === index ? 'true' : undefined"
          @mousemove="slashActiveIndex = index"
          @click="insertBlock(command.type)"
        ><span>{{ command.mark }}</span><strong>{{ command.label }}</strong></button>
      </section>
    </Teleport>
    <ConfirmDialog :open="removeDialogOpen" title="删除任务" :message="`确定删除“${todo.title}”吗？删除后无法恢复。`" confirm-label="删除" :danger="true" @close="removeDialogOpen = false" @confirm="confirmRemove" />
    <InputDialog :open="linkDialogOpen" title="设置链接" label="链接地址" :initial-value="linkValue" placeholder="https://（留空可移除链接）" confirm-label="应用" :required="false" @close="linkDialogOpen = false" @submit="applyLink" />
    <TaskRelationDialog :open="relationDialogOpen" :current-task-id="todo.id" @close="relationDialogOpen = false" @select-task="relateTask" @select-note="relateNote" />
  </aside>
  <aside v-else class="task-detail task-detail-empty" aria-label="任务正文">
    <div><IconChevronRight :size="24" :stroke-width="1.5" /><strong>选择一个任务</strong><p>任务正文会显示在这里。</p></div>
  </aside>
</template>
