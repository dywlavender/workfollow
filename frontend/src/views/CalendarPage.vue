<script setup lang="ts">
import type { CalendarOptions, DatesSetArg, EventClickArg, EventContentArg, EventDropArg } from '@fullcalendar/core'
import zhCnLocale from '@fullcalendar/core/locales/zh-cn'
import dayGridPlugin from '@fullcalendar/daygrid'
import interactionPlugin, { type DateClickArg } from '@fullcalendar/interaction'
import FullCalendar from '@fullcalendar/vue3'
import {
  IconCalendarMonth, IconChevronDown, IconChevronLeft, IconChevronRight,
  IconDots, IconEye, IconEyeOff, IconListCheck, IconPlus,
} from '@tabler/icons-vue'
import dayjs from 'dayjs'
import { computed, onBeforeUnmount, onMounted, ref, watch } from 'vue'
import { useRoute, useRouter } from 'vue-router'

import TodoDialog from '@/components/todo/TodoDialog.vue'
import { isDateOnlyDue } from '@/modules/todo/dueDate'
import { fetchTodos, putTodo, type Todo, type TodoPayload } from '@/services/api'
import { consumePrefetchedCalendarTodos } from '@/services/prefetch'
import { useFeedbackStore } from '@/stores/feedback'
import { cloneTodo, optimisticCompletedTodo, optimisticRestoredTodo, useTodoStore } from '@/stores/todos'

const router = useRouter()
const route = useRoute()
const todoStore = useTodoStore()
const feedback = useFeedbackStore()
const root = ref<HTMLElement | null>(null)
const calendarRef = ref<InstanceType<typeof FullCalendar> | null>(null)
const allTodos = ref<Todo[]>([])
const requestedDate = typeof route.query.date === 'string' && /^\d{4}-\d{2}-\d{2}$/.test(route.query.date)
  ? route.query.date
  : dayjs().format('YYYY-MM-DD')
const selectedDate = ref(requestedDate)
const currentView = ref('dayGridMonth')
const currentTitle = ref(dayjs(requestedDate).format('YYYY年M月'))
const initialLoading = ref(true)
const refreshing = ref(false)
const loadError = ref<string | null>(null)
const createOpen = ref(false)
const selectedTodo = ref<Todo | null>(null)
const moreOpen = ref(false)
const showCompleted = ref(true)

const dialogOpen = computed(() => createOpen.value || selectedTodo.value !== null)
const isExecutionDone = (todo: Todo) => todo.myAssignment?.status === 'DONE' || (!todo.myAssignment && todo.status === 'DONE')

function eventClass(todo: Todo) {
  const listClasses: Record<string, string> = {
    收集箱: 'calendar-list-inbox',
    工作: 'calendar-list-work',
    个人: 'calendar-list-personal',
    学习: 'calendar-list-study',
  }
  const listClass = listClasses[todo.listName] ?? 'calendar-list-neutral'
  return [listClass, isExecutionDone(todo) ? 'calendar-event-done' : todo.status === 'ABANDONED' ? 'calendar-event-abandoned' : '']
}

const calendarEvents = computed(() => allTodos.value
  .filter((todo) => todo.dueAt && (showCompleted.value || !isExecutionDone(todo)))
  .map((todo) => ({
    id: todo.id,
    title: todo.title,
    start: todo.dueAt!,
    end: todo.dueEndAt || undefined,
    editable: todo.status === 'TODO' && todo.permissions.completable && !isExecutionDone(todo),
    classNames: eventClass(todo),
    extendedProps: { todo },
  })))

function renderEvent(arg: EventContentArg) {
  const todo = arg.event.extendedProps.todo as Todo
  const row = document.createElement('div')
  row.className = 'calendar-event-content'

  const check = document.createElement('button')
  check.type = 'button'
  check.className = `calendar-event-check${isExecutionDone(todo) ? ' done' : todo.status === 'ABANDONED' ? ' abandoned' : ''}`
  check.setAttribute('aria-label', isExecutionDone(todo) ? `恢复 ${todo.title}` : `完成 ${todo.title}`)
  check.textContent = isExecutionDone(todo) ? '✓' : todo.status === 'ABANDONED' ? '×' : ''
  check.addEventListener('click', (event) => {
    event.preventDefault()
    event.stopPropagation()
    void toggle(todo)
  })

  const title = document.createElement('span')
  title.className = 'calendar-event-title'
  title.textContent = todo.title
  row.append(check, title)

  if (arg.isStart && todo.dueAt && !isDateOnlyDue(todo.dueAt)) {
    const time = document.createElement('time')
    time.className = 'calendar-event-time'
    time.dateTime = todo.dueAt
    time.textContent = dayjs(todo.dueAt).format('HH:mm')
    row.append(time)
  }
  return { domNodes: [row] }
}

const calendarOptions: CalendarOptions = {
  plugins: [dayGridPlugin, interactionPlugin],
  initialView: currentView.value,
  initialDate: requestedDate,
  locale: zhCnLocale,
  firstDay: 0,
  height: '100%',
  expandRows: true,
  fixedWeekCount: true,
  dayMaxEvents: 4,
  moreLinkContent: (arg) => `+${arg.num}`,
  editable: true,
  eventStartEditable: true,
  headerToolbar: false,
  displayEventTime: false,
  // Keep the FullCalendar instance mounted. Events are synchronized through
  // the calendar API so loading never replaces the whole calendar surface.
  events: [],
  dateClick: onDateClick,
  eventClick: onEventClick,
  eventDrop: onEventDrop,
  eventContent: renderEvent,
  datesSet: onDatesSet,
  dayHeaderContent: (arg) => `周${['日', '一', '二', '三', '四', '五', '六'][arg.date.getDay()]}`,
  dayCellContent: (arg) => {
    const date = dayjs(arg.date)
    return date.date() === 1 ? `${date.month() + 1}月1日` : String(date.date())
  },
}

function syncCalendarEvents() {
  const api = calendarRef.value?.getApi()
  if (!api) return

  api.removeAllEvents()
  for (const event of calendarEvents.value) api.addEvent(event)
}

watch(calendarEvents, syncCalendarEvents, { deep: true })

async function loadCalendar() {
  const isInitialLoad = initialLoading.value
  if (isInitialLoad) initialLoading.value = true
  else refreshing.value = true
  loadError.value = null
  try {
    allTodos.value = isInitialLoad
      ? await consumePrefetchedCalendarTodos()
      : await fetchTodos()
  } catch {
    loadError.value = '无法读取日历，请确认本地服务已启动。'
  } finally {
    if (isInitialLoad) initialLoading.value = false
    else refreshing.value = false
  }
}

function onDatesSet(arg: DatesSetArg) {
  currentView.value = arg.view.type
  currentTitle.value = arg.view.type === 'dayGridMonth'
    ? dayjs(arg.view.currentStart).format('YYYY年M月')
    : arg.view.title.replace(/[–—]/g, '-')
}

function calendarAction(action: 'prev' | 'next' | 'today') {
  calendarRef.value?.getApi()[action]()
}

function changeView(event: Event) {
  const view = (event.target as HTMLSelectElement).value
  currentView.value = view
  calendarRef.value?.getApi().changeView(view)
}

function beginCreate(date = selectedDate.value) {
  selectedDate.value = date
  selectedTodo.value = null
  createOpen.value = true
  moreOpen.value = false
}

function onDateClick(arg: DateClickArg) {
  beginCreate(arg.dateStr)
}

function onEventClick(arg: EventClickArg) {
  const todo = arg.event.extendedProps.todo as Todo | undefined
  selectedTodo.value = todo ?? allTodos.value.find((item) => item.id === arg.event.id) ?? null
  createOpen.value = false
  moreOpen.value = false
}

async function onEventDrop(arg: EventDropArg) {
  const todo = allTodos.value.find((item) => item.id === arg.event.id)
  if (!todo?.dueAt || todo.status !== 'TODO' || !arg.event.start) { arg.revert(); return }

  const originalDueAt = dayjs(todo.dueAt)
  const droppedDate = dayjs(arg.event.start)
  const dayShift = droppedDate.startOf('day').diff(originalDueAt.startOf('day'), 'day')
  const dueAt = droppedDate.hour(originalDueAt.hour()).minute(originalDueAt.minute()).second(originalDueAt.second()).millisecond(0).format('YYYY-MM-DDTHH:mm:ss')
  const dueEndAt = todo.dueEndAt ? dayjs(todo.dueEndAt).add(dayShift, 'day').format('YYYY-MM-DDTHH:mm:ss') : null

  try {
    const updated = await putTodo(todo.id, { dueAt, dueEndAt })
    const merged = { ...updated, sources: updated.sources.length ? updated.sources : todo.sources }
    allTodos.value = allTodos.value.map((item) => item.id === merged.id ? merged : item)
    if (selectedTodo.value?.id === merged.id) selectedTodo.value = merged
    selectedDate.value = droppedDate.format('YYYY-MM-DD')
  } catch {
    arg.revert()
    feedback.error('改期失败，任务已恢复到原日期。')
  }
}

async function toggle(todo: Todo) {
  if (!todo.permissions.completable) return
  const snapshot = allTodos.value.map(cloneTodo)
  const replace = (updated: Todo) => {
    const current = allTodos.value.find((item) => item.id === updated.id)
    allTodos.value = allTodos.value.map((item) => item.id === updated.id
      ? { ...updated, sources: updated.sources.length ? updated.sources : current?.sources ?? [] }
      : item)
    if (selectedTodo.value?.id === updated.id) {
      selectedTodo.value = { ...updated, sources: updated.sources.length ? updated.sources : selectedTodo.value.sources }
    }
  }
  const upsert = (updated: Todo) => {
    if (allTodos.value.some((item) => item.id === updated.id)) replace(updated)
    else allTodos.value = [...allTodos.value, updated]
  }
  try {
    if (isExecutionDone(todo)) {
      replace(optimisticRestoredTodo(todo))
      replace(await todoStore.restore(todo.id))
    } else {
      replace(optimisticCompletedTodo(todo))
      const result = await todoStore.complete(todo.id)
      replace(result.todo)
      if (result.nextTodo) upsert(result.nextTodo)
      feedback.completed()
    }
  } catch {
    allTodos.value = snapshot
    if (selectedTodo.value?.id === todo.id) selectedTodo.value = snapshot.find((item) => item.id === todo.id) ?? null
    feedback.error('任务状态更新失败，请稍后重试。')
  }
}

function closeDialog() {
  createOpen.value = false
  selectedTodo.value = null
}

async function saveTodo(payload: TodoPayload) {
  try {
    if (selectedTodo.value) await todoStore.update(selectedTodo.value.id, payload)
    else await todoStore.create(payload)
    closeDialog()
    await loadCalendar()
  } catch {
    feedback.error(selectedTodo.value ? '更新任务失败，请稍后重试。' : '创建任务失败，请检查任务设置。')
  }
}

function openSource(noteId: string) {
  closeDialog()
  void router.push({ path: '/notes', query: { note: noteId } })
}

function toggleCompleted() {
  showCompleted.value = !showCompleted.value
  moreOpen.value = false
}

function closeFloating(event: MouseEvent) {
  if (!root.value?.contains(event.target as Node)) moreOpen.value = false
}

onMounted(() => {
  document.addEventListener('click', closeFloating)
  syncCalendarEvents()
  void loadCalendar()
})
onBeforeUnmount(() => document.removeEventListener('click', closeFloating))
</script>

<template>
  <div class="calendar-page-shell">
  <section ref="root" class="page-content calendar-page calendar-month-page">
    <header class="calendar-topbar">
      <div class="calendar-title"><IconCalendarMonth :size="25" :stroke-width="1.8" aria-hidden="true" /><h1>{{ currentTitle }}</h1></div>
      <div class="calendar-toolbar" aria-label="日历工具栏">
        <button class="calendar-tool-button calendar-add-button" type="button" aria-label="新建任务" title="新建任务" @click="beginCreate()"><IconPlus :size="20" /></button>
        <label class="calendar-view-select"><span class="sr-only">日历视图</span><select :value="currentView" @change="changeView"><option value="dayGridMonth">月</option><option value="dayGridWeek">周</option><option value="dayGridDay">日</option></select><IconChevronDown :size="15" aria-hidden="true" /></label>
        <div class="calendar-period-nav">
          <button type="button" aria-label="上一周期" title="上一周期" @click="calendarAction('prev')"><IconChevronLeft :size="19" /></button>
          <button type="button" @click="calendarAction('today')">今天</button>
          <button type="button" aria-label="下一周期" title="下一周期" @click="calendarAction('next')"><IconChevronRight :size="19" /></button>
        </div>
        <div class="calendar-more-host">
          <button class="calendar-tool-button" type="button" aria-label="更多日历操作" title="更多" @click.stop="moreOpen = !moreOpen"><IconDots :size="21" /></button>
          <section v-if="moreOpen" class="calendar-more-menu" role="menu" aria-label="更多日历操作" @click.stop>
            <button type="button" role="menuitem" @click="toggleCompleted"><component :is="showCompleted ? IconEyeOff : IconEye" :size="16" />{{ showCompleted ? '隐藏已完成' : '显示已完成' }}</button>
            <RouterLink role="menuitem" to="/todos"><IconListCheck :size="16" />打开任务列表</RouterLink>
          </section>
        </div>
      </div>
    </header>

    <p v-if="loadError" class="calendar-error calendar-floating-error" role="alert">{{ loadError }}<button type="button" aria-label="关闭错误" @click="loadError = null">×</button></p>
    <main class="calendar-canvas" :aria-busy="initialLoading || refreshing" aria-label="任务日历">
      <FullCalendar ref="calendarRef" :options="calendarOptions" />
      <div
        v-if="initialLoading || refreshing"
        class="calendar-loading-indicator"
        role="status"
        aria-live="polite"
      >
        <span class="calendar-loading-spinner" aria-hidden="true" />
        <span>{{ initialLoading ? '正在读取日历' : '正在更新' }}</span>
      </div>
    </main>

    <TodoDialog
      :open="dialogOpen"
      :todo="selectedTodo"
      :initial-due-at="selectedTodo ? null : `${selectedDate}T00:00:00`"
      @close="closeDialog"
      @save="saveTodo"
      @open-source="openSource"
    />
  </section>
  </div>
</template>
