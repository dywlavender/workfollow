<script setup lang="ts">
import dayjs from 'dayjs'
import {
  IconArrowLeft, IconBell, IconCalendar, IconCheck, IconChevronDown, IconChevronLeft, IconChevronRight, IconClock, IconFlag,
  IconInbox, IconRepeat, IconTag,
} from '@tabler/icons-vue'
import { computed, nextTick, onBeforeUnmount, onMounted, ref, watch } from 'vue'

import ActionFeedback from '@/components/ActionFeedback.vue'
import { parseTaskText } from '@/modules/todo/parser/taskTextParser'
import { getScheduleMarkers } from '@/modules/todo/scheduleMarkers'
import { useTodoStore } from '@/stores/todos'
import AssigneePopover from '@/components/task/AssigneePopover.vue'
import type { TeamMember, Todo, TodoPayload, TodoPriority, TodoRecurrenceType } from '@/services/api'

type ComposerPanel = 'schedule' | 'more' | 'list' | 'tags' | null
type ReminderPreset = 'NONE' | 'AT_DUE' | 'MINUS_10' | 'MINUS_60' | 'MINUS_1440'

const props = withDefaults(defineProps<{
  alwaysOpen?: boolean
  members?: TeamMember[]
  currentUserId?: string
  canAssign?: boolean
  defaultListName?: string
  defaultDueAt?: string
  availableLists?: string[]
  availableTags?: string[]
  calendarTodos?: Todo[]
}>(), {
  alwaysOpen: false, members: () => [], currentUserId: '', canAssign: false,
  defaultListName: '收集箱', defaultDueAt: '', availableLists: () => [], availableTags: () => [], calendarTodos: () => [],
})
const emit = defineEmits<{ created: [] }>()
const todoStore = useTodoStore()
const composerElement = ref<HTMLElement | null>(null)
const input = ref('')
const inputElement = ref<HTMLInputElement | null>(null)
// The reference interaction is a persistent command field, not a collapsed
// “add” button. Keep it mounted so creating a task is always one click away.
const editing = ref(true)
const disabledTokens = ref<Set<string>>(new Set())
const submitting = ref(false)
const error = ref<string | null>(null)
const assigneeIds = ref<string[]>(props.currentUserId ? [props.currentUserId] : [])
const activePanel = ref<ComposerPanel>(null)
const manualSchedule = ref(false)
const scheduleValue = ref(props.defaultDueAt ? dayjs(props.defaultDueAt).format('YYYY-MM-DDTHH:mm') : '')
const calendarMonth = ref((props.defaultDueAt ? dayjs(props.defaultDueAt) : dayjs()).startOf('month'))
const reminderPreset = ref<ReminderPreset>('NONE')
const recurrenceType = ref<TodoRecurrenceType>('NONE')
const explicitTime = ref(Boolean(props.defaultDueAt && (dayjs(props.defaultDueAt).hour() || dayjs(props.defaultDueAt).minute())))
const priority = ref<TodoPriority>('NONE')
const listName = ref(props.defaultListName)
const tags = ref<string[]>([])
const tagQuery = ref('')

const parsed = computed(() => parseTaskText(input.value, undefined, { disabledTokens: disabledTokens.value }))
const visibleTokens = computed(() => parsed.value.tokens)
const effectiveDueAt = computed(() => manualSchedule.value
  ? (scheduleValue.value ? dayjs(scheduleValue.value).format('YYYY-MM-DDTHH:mm:ss') : null)
  : (parsed.value.dueAt ?? (props.defaultDueAt || null)))
const effectiveRecurrence = computed<TodoRecurrenceType>(() => manualSchedule.value
  ? recurrenceType.value
  : (parsed.value.recurrence?.type ?? recurrenceType.value))
const scheduleLabel = computed(() => {
  if (!effectiveDueAt.value) return '无日期'
  const value = dayjs(effectiveDueAt.value)
  const hasTime = explicitTime.value || Boolean(value.hour() || value.minute())
  return value.isSame(dayjs(), 'day') ? (hasTime ? `今天 ${value.format('HH:mm')}` : '今天')
    : value.isSame(dayjs().add(1, 'day'), 'day') ? `明天${hasTime ? ` ${value.format('HH:mm')}` : ''}`
      : value.format(hasTime ? 'M月D日 HH:mm' : 'M月D日')
})
const normalizedLists = computed(() => Array.from(new Set([props.defaultListName, ...props.availableLists].filter(Boolean))))
const normalizedTags = computed(() => Array.from(new Set([...props.availableTags, ...tags.value])).filter((tag) => !tagQuery.value || tag.toLowerCase().includes(tagQuery.value.toLowerCase())))
const weekNames = ['一', '二', '三', '四', '五', '六', '日']
const calendarDays = computed(() => {
  const monthStart = calendarMonth.value.startOf('month')
  const gridStart = monthStart.subtract((monthStart.day() + 6) % 7, 'day')
  return Array.from({ length: 42 }, (_, index) => gridStart.add(index, 'day'))
})
const selectedScheduleDate = computed(() => scheduleValue.value ? dayjs(scheduleValue.value).format('YYYY-MM-DD') : '')
const timeOptions = Array.from({ length: 48 }, (_, index) => dayjs().startOf('day').add(index * 30, 'minute').format('HH:mm'))
const scheduleTime = computed({
  get: () => scheduleValue.value && explicitTime.value ? dayjs(scheduleValue.value).format('HH:mm') : '',
  set: (value: string) => {
    const date = selectedScheduleDate.value || dayjs().format('YYYY-MM-DD')
    manualSchedule.value = true
    explicitTime.value = Boolean(value)
    scheduleValue.value = `${date}T${value || '00:00'}`
  },
})
const existingTodoDates = computed(() => new Set(props.calendarTodos
  .filter((todo) => todo.dueAt && todo.status === 'TODO')
  .map((todo) => dayjs(todo.dueAt).format('YYYY-MM-DD'))))
const previewMarkers = computed(() => getScheduleMarkers({
  startDate: selectedScheduleDate.value,
  recurrenceType: effectiveRecurrence.value,
  recurrenceConfig: effectiveDueAt.value ? recurrenceConfig(effectiveDueAt.value) : null,
  visibleDays: calendarDays.value,
}))
function dayMarkerClass(day: dayjs.Dayjs) {
  const key = day.format('YYYY-MM-DD')
  return { 'has-todo': existingTodoDates.value.has(key), preview: previewMarkers.value.scheduled.has(key) }
}

watch(() => props.defaultListName, (value) => { if (!editing.value || !input.value) listName.value = value })
watch(() => props.defaultDueAt, (value) => {
  if (input.value) return
  manualSchedule.value = false
  scheduleValue.value = value ? dayjs(value).format('YYYY-MM-DDTHH:mm') : ''
  explicitTime.value = Boolean(value && (dayjs(value).hour() || dayjs(value).minute()))
})

async function begin() {
  editing.value = true
  await nextTick()
  inputElement.value?.focus()
}
function resetDraft(_close = false) {
  input.value = ''
  disabledTokens.value = new Set()
  error.value = null
  activePanel.value = null
  manualSchedule.value = false
  scheduleValue.value = props.defaultDueAt ? dayjs(props.defaultDueAt).format('YYYY-MM-DDTHH:mm') : ''
  explicitTime.value = Boolean(props.defaultDueAt && (dayjs(props.defaultDueAt).hour() || dayjs(props.defaultDueAt).minute()))
  reminderPreset.value = 'NONE'
  recurrenceType.value = 'NONE'
  priority.value = 'NONE'
  listName.value = props.defaultListName
  tags.value = []
  tagQuery.value = ''
  assigneeIds.value = props.currentUserId ? [props.currentUserId] : []
  editing.value = true
}
function closeOrGoBack() {
  if (activePanel.value === 'list' || activePanel.value === 'tags') { activePanel.value = 'more'; return }
  if (activePanel.value) { activePanel.value = null; return }
  inputElement.value?.blur()
}
function onDocumentPointerDown(event: PointerEvent) {
  if (!composerElement.value?.contains(event.target as Node)) activePanel.value = null
}
function onInput() { disabledTokens.value = new Set(); error.value = null }
function cancelRecognition(token: { kind: string; text: string }) {
  const next = new Set(disabledTokens.value)
  next.add(`${token.kind}:${token.text}`)
  disabledTokens.value = next
}
function togglePanel(panel: Exclude<ComposerPanel, null>) {
  if (panel === 'schedule' && activePanel.value !== 'schedule') {
    calendarMonth.value = (scheduleValue.value ? dayjs(scheduleValue.value) : dayjs()).startOf('month')
  }
  activePanel.value = activePanel.value === panel ? null : panel
}
function focusInput(event: MouseEvent) {
  if ((event.target as HTMLElement).closest('button')) return
  inputElement.value?.focus()
}
function chooseScheduleDay(day: dayjs.Dayjs) {
  const time = scheduleTime.value || '00:00'
  manualSchedule.value = true
  scheduleValue.value = `${day.format('YYYY-MM-DD')}T${time}`
  if (!day.isSame(calendarMonth.value, 'month')) calendarMonth.value = day.startOf('month')
}
function useScheduleShortcut(days: number, hour?: number) {
  const value = dayjs().add(days, 'day').hour(hour ?? 0).minute(0).second(0)
  manualSchedule.value = true
  explicitTime.value = hour !== undefined
  scheduleValue.value = value.format('YYYY-MM-DDTHH:mm')
}
function clearSchedule() {
  manualSchedule.value = true
  scheduleValue.value = ''
  explicitTime.value = false
  reminderPreset.value = 'NONE'
  recurrenceType.value = 'NONE'
}
function selectList(value: string) { listName.value = value; activePanel.value = 'more' }
function selectPriority(value: TodoPriority) { priority.value = value }
function toggleTag(value: string) { tags.value = tags.value.includes(value) ? tags.value.filter((tag) => tag !== value) : [...tags.value, value] }
function addTag() {
  const value = tagQuery.value.trim().replace(/^#/, '')
  if (value && !tags.value.includes(value)) tags.value = [...tags.value, value]
  tagQuery.value = ''
}
function reminderAt(dueAt: string | null): string | null {
  if (!dueAt || reminderPreset.value === 'NONE') return null
  const minutes = { AT_DUE: 0, MINUS_10: 10, MINUS_60: 60, MINUS_1440: 1440 }[reminderPreset.value]
  return dayjs(dueAt).subtract(minutes, 'minute').format('YYYY-MM-DDTHH:mm:ss')
}
function recurrenceConfig(dueAt: string | null): Record<string, number | string> | null {
  if (!dueAt || effectiveRecurrence.value === 'NONE') return null
  if (!manualSchedule.value && parsed.value.recurrence) return parsed.value.recurrence.config
  if (effectiveRecurrence.value === 'WEEKLY') return { weekday: (dayjs(dueAt).day() + 6) % 7 }
  if (effectiveRecurrence.value === 'MONTHLY') return { day: dayjs(dueAt).date() }
  return {}
}
function buildPayload(): TodoPayload {
  const dueAt = effectiveDueAt.value
  return {
    title: parsed.value.title,
    dueAt,
    reminderAt: reminderAt(dueAt),
    recurrenceType: dueAt ? effectiveRecurrence.value : 'NONE',
    recurrenceConfig: recurrenceConfig(dueAt),
    priority: priority.value,
    listName: listName.value,
    tags: [...tags.value],
    assigneeIds: props.canAssign && assigneeIds.value.length ? assigneeIds.value : undefined,
  }
}
async function submit() {
  if (!input.value.trim() || submitting.value) return
  submitting.value = true
  error.value = null
  try {
    await todoStore.create(buildPayload())
    resetDraft(false)
    emit('created')
    await nextTick()
    inputElement.value?.focus()
  } catch {
    error.value = '创建失败，任务草稿已保留，请重试。'
  } finally { submitting.value = false }
}
defineExpose({ begin, buildPayload })
onMounted(() => document.addEventListener('pointerdown', onDocumentPointerDown))
onBeforeUnmount(() => document.removeEventListener('pointerdown', onDocumentPointerDown))
</script>

<template>
  <div ref="composerElement" class="task-composer" @keydown.esc.stop.prevent="closeOrGoBack">
    <form class="quick-add reference-quick-add" @click="focusInput" @submit.prevent="submit">
      <label class="sr-only" for="quick-todo">快速添加待办</label>
      <input ref="inputElement" id="quick-todo" v-model="input" autocomplete="off" placeholder="添加任务" aria-describedby="quick-todo-hint" @input="onInput" @keydown.enter.exact.prevent="submit" />
      <span id="quick-todo-hint" class="sr-only">输入任务后按回车创建</span>
      <button class="composer-inline-date" type="button" :class="{ active: Boolean(effectiveDueAt) }" :aria-expanded="activePanel === 'schedule'" @click="togglePanel('schedule')"><IconCalendar :size="18" />{{ scheduleLabel }}</button>
      <button class="composer-more-trigger" type="button" aria-label="更多任务设置" :aria-expanded="activePanel === 'more'" @click="togglePanel('more')"><IconChevronDown :size="20" /></button>
    </form>

    <div class="composer-layer-host" aria-label="任务属性">
        <section v-if="activePanel === 'schedule'" class="composer-popover composer-schedule composer-popover-right" role="dialog" aria-label="设置日期和提醒">
          <div class="composer-shortcuts"><button type="button" @click="useScheduleShortcut(0)">今天</button><button type="button" @click="useScheduleShortcut(1)">明天</button><button type="button" @click="useScheduleShortcut(7)">下周</button><button type="button" @click="useScheduleShortcut(0, 20)">今晚</button></div>
          <div class="composer-calendar-head"><button type="button" aria-label="上个月" @click="calendarMonth = calendarMonth.subtract(1, 'month')"><IconChevronLeft :size="16" /></button><strong>{{ calendarMonth.format('YYYY年M月') }}</strong><button type="button" aria-label="下个月" @click="calendarMonth = calendarMonth.add(1, 'month')"><IconChevronRight :size="16" /></button></div>
          <div class="composer-calendar-grid weekdays"><span v-for="name in weekNames" :key="name">{{ name }}</span></div>
          <div class="composer-calendar-grid" role="grid">
            <button v-for="day in calendarDays" :key="day.format('YYYY-MM-DD')" type="button" :class="[{ muted: !day.isSame(calendarMonth, 'month'), today: day.isSame(dayjs(), 'day'), selected: day.format('YYYY-MM-DD') === selectedScheduleDate }, dayMarkerClass(day)]" :aria-label="day.format('YYYY年M月D日')" @click="chooseScheduleDay(day)">{{ day.date() }}</button>
          </div>
          <label><span><IconClock :size="15" />时间</span><select v-model="scheduleTime" :disabled="!selectedScheduleDate"><option value="">不设置时间</option><option v-for="value in timeOptions" :key="value" :value="value">{{ value }}</option></select></label>
          <label><span><IconBell :size="15" />提醒</span><select v-model="reminderPreset" :disabled="!effectiveDueAt"><option value="NONE">不提醒</option><option value="AT_DUE">准时</option><option value="MINUS_10">提前 10 分钟</option><option value="MINUS_60">提前 1 小时</option><option value="MINUS_1440">提前 1 天</option></select></label>
          <label><span><IconRepeat :size="15" />重复</span><select v-model="recurrenceType" :disabled="!effectiveDueAt" @change="manualSchedule = true"><option value="NONE">不重复</option><option value="DAILY">每天</option><option value="WEEKLY">每周</option><option value="MONTHLY">每月</option></select></label>
          <footer><button type="button" @click="clearSchedule">清除</button><button class="primary-button" type="button" @click="activePanel = null">完成</button></footer>
        </section>
        <section v-if="activePanel === 'more'" class="composer-popover composer-reference-menu composer-popover-right" aria-label="更多任务设置">
          <header>优先级</header>
          <div class="composer-priority-flags">
            <button v-for="value in (['HIGH', 'MEDIUM', 'LOW', 'NONE'] as TodoPriority[])" :key="value" type="button" :class="[value.toLowerCase(), { selected: priority === value }]" :aria-label="({ HIGH: '高优先级', MEDIUM: '中优先级', LOW: '低优先级', NONE: '无优先级' })[value]" @click="selectPriority(value)"><IconFlag :size="27" :fill="value === 'NONE' ? 'none' : 'currentColor'" /></button>
          </div>
          <div class="composer-menu-divider" />
          <button type="button" @click="activePanel = 'list'"><IconInbox :size="22" /><span><strong>{{ listName }}</strong><small>清单</small></span><IconChevronRight :size="18" /></button>
          <button type="button" @click="activePanel = 'tags'"><IconTag :size="22" /><span><strong>{{ tags.length ? `${tags.length} 个标签` : '标签' }}</strong><small v-if="tags.length">{{ tags.join('、') }}</small></span><IconChevronRight :size="18" /></button>
          <div v-if="canAssign && currentUserId" class="composer-assignee-row"><AssigneePopover :members="members" :model-value="assigneeIds" :current-user-id="currentUserId" compact @change="assigneeIds = $event" /></div>
        </section>
        <section v-if="activePanel === 'list'" class="composer-popover composer-submenu composer-menu composer-popover-right" aria-label="选择清单">
          <header><button type="button" aria-label="返回更多设置" @click="activePanel = 'more'"><IconArrowLeft :size="18" /></button><strong>选择清单</strong></header>
          <button v-for="value in normalizedLists" :key="value" type="button" @click="selectList(value)"><IconInbox :size="18" /><span>{{ value }}</span><IconCheck v-if="listName === value" :size="15" /></button>
        </section>
        <section v-if="activePanel === 'tags'" class="composer-popover composer-submenu composer-tags composer-popover-right" aria-label="选择标签">
          <header><button type="button" aria-label="返回更多设置" @click="activePanel = 'more'"><IconArrowLeft :size="18" /></button><strong>选择标签</strong></header>
          <form @submit.prevent="addTag"><input v-model="tagQuery" placeholder="搜索或创建标签" autofocus /><button type="submit">添加</button></form>
          <div><button v-for="value in normalizedTags" :key="value" type="button" :class="{ selected: tags.includes(value) }" @click="toggleTag(value)"><IconCheck v-if="tags.includes(value)" :size="13" />#{{ value }}</button></div>
        </section>
    </div>
    <div v-if="visibleTokens.length && editing" class="recognition-row" aria-label="已识别内容"><span>已识别</span><button v-for="token in visibleTokens" :key="`${token.kind}-${token.text}`" class="recognition-chip" type="button" @click="cancelRecognition(token)">{{ token.label }} <span aria-hidden="true">×</span></button><span class="recognized-title">标题“{{ parsed.title }}”</span></div>
    <ActionFeedback :message="error" @dismiss="error = null" />
  </div>
</template>
