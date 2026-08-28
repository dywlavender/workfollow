<script setup lang="ts">
import {
  IconArrowRight,
  IconBook2,
  IconCheck,
  IconChecklist,
  IconChevronLeft,
  IconChevronRight,
  IconClock,
  IconFileText,
  IconPencil,
  IconPlus,
  IconShare,
} from '@tabler/icons-vue'
import dayjs from 'dayjs'
import { computed, onMounted, ref } from 'vue'
import { useRouter } from 'vue-router'

import {
  fetchMySubmissions,
  fetchNotes,
  fetchNotifications,
  fetchReviewSubmissions,
  fetchTodos,
  type NoteListItem,
  type Todo,
  type TodoView,
} from '@/services/api'
import { cloneTodo, optimisticCompletedTodo, optimisticRestoredTodo, useTodoStore } from '@/stores/todos'
import { useFeedbackStore } from '@/stores/feedback'
import { useWorkspaceStore } from '@/stores/workspace'

const todoStore = useTodoStore()
const feedback = useFeedbackStore()
const workspace = useWorkspaceStore()
const router = useRouter()
const allTodayTodos = ref<Todo[]>([])
const calendarTodos = ref<Todo[]>([])
const assignedTodos = ref<Todo[]>([])
const recentNotes = ref<NoteListItem[]>([])
const pendingCounts = ref({ assigned: 0, shared: 0, revision: 0, review: 0 })
const pendingCountsReady = ref(false)
const loading = ref(true)
const error = ref<string | null>(null)
const calendarMonth = ref(dayjs().startOf('month'))

const weekdayLabels = ['周日', '周一', '周二', '周三', '周四', '周五', '周六']
const calendarWeekdays = ['日', '一', '二', '三', '四', '五', '六']
const todayStart = () => dayjs().startOf('day')
const isExecutionDone = (todo: Todo) => todo.myAssignment?.status === 'DONE' || (!todo.myAssignment && todo.status === 'DONE')

const dateLabel = computed(() => `${dayjs().format('M月D日')} ${weekdayLabels[dayjs().day()]}`)
const todayItems = computed(() => allTodayTodos.value.filter((todo) => todo.dueAt && dayjs(todo.dueAt).isSame(dayjs(), 'day')))
const todayPending = computed(() => todayItems.value.filter((todo) => todo.status === 'TODO' && !isExecutionDone(todo)))
const todayDone = computed(() => todayItems.value.filter(isExecutionDone).length)
const overdueTodos = computed(() => allTodayTodos.value.filter((todo) => (
  todo.status === 'TODO' && !isExecutionDone(todo) && todo.dueAt && dayjs(todo.dueAt).isBefore(todayStart())
)))
const assignedOpen = computed(() => assignedTodos.value.filter((todo) => todo.status === 'TODO'))

interface UpcomingGroup { key: string; label: string; items: Todo[] }
const upcomingGroups = computed<UpcomingGroup[]>(() => {
  const tomorrow = dayjs().add(1, 'day').startOf('day')
  const groups = new Map<string, Todo[]>()
  calendarTodos.value
    .filter((todo) => todo.status === 'TODO' && !isExecutionDone(todo) && todo.dueAt && dayjs(todo.dueAt).isAfter(todayStart(), 'day'))
    .sort((left, right) => dayjs(left.dueAt).valueOf() - dayjs(right.dueAt).valueOf())
    .slice(0, 8)
    .forEach((todo) => {
      const key = dayjs(todo.dueAt).format('YYYY-MM-DD')
      groups.set(key, [...(groups.get(key) ?? []), todo])
    })
  return [...groups.entries()].slice(0, 3).map(([key, items]) => {
    const date = dayjs(key)
    const label = date.isSame(tomorrow, 'day') ? '明天' : date.diff(dayjs(), 'day') < 7 ? weekdayLabels[date.day()] : date.format('M月D日')
    return { key, label, items }
  })
})

const calendarDays = computed(() => {
  const monthStart = calendarMonth.value.startOf('month')
  const gridStart = monthStart.subtract(monthStart.day(), 'day')
  return Array.from({ length: 42 }, (_, index) => gridStart.add(index, 'day'))
})

const calendarTaskStates = computed(() => {
  const states = new Map<string, { pending: number; completed: number }>()
  for (const todo of calendarTodos.value) {
    if (!todo.dueAt || todo.status === 'ABANDONED') continue
    const key = dayjs(todo.dueAt).format('YYYY-MM-DD')
    const current = states.get(key) ?? { pending: 0, completed: 0 }
    if (todo.status === 'TODO' && !isExecutionDone(todo)) current.pending += 1
    else current.completed += 1
    states.set(key, current)
  }
  return states
})

const pendingItems = computed(() => [
  { label: '新分配任务', count: pendingCounts.value.assigned, icon: IconChecklist, to: { path: '/todos', query: { view: 'assigned-to-me' } } },
  { label: '分享给我的笔记', count: pendingCounts.value.shared, icon: IconShare, to: { path: '/notes', query: { view: 'shared' } } },
  { label: '投稿需要修改', count: pendingCounts.value.revision, icon: IconPencil, to: { path: '/notes', query: { view: 'submissions' } } },
  { label: '知识待审核', count: pendingCounts.value.review, icon: IconBook2, to: { path: '/notes', query: { view: 'review' } } },
])

async function loadOptionalHomeData() {
  pendingCountsReady.value = false
  const teamId = workspace.currentTeam?.id ?? workspace.teams[0]?.id
  let notificationsResult: PromiseSettledResult<Awaited<ReturnType<typeof fetchNotifications>>>
  let mineResult: PromiseSettledResult<Awaited<ReturnType<typeof fetchMySubmissions>>> | null = null
  let reviewResult: PromiseSettledResult<Awaited<ReturnType<typeof fetchReviewSubmissions>>> | null = null
  try {
    if (teamId) {
      [notificationsResult, mineResult, reviewResult] = await Promise.allSettled([
        fetchNotifications(true),
        fetchMySubmissions(teamId),
        fetchReviewSubmissions(teamId),
      ])
    } else {
      [notificationsResult] = await Promise.allSettled([fetchNotifications(true)])
    }
    const notifications = notificationsResult.status === 'fulfilled' ? notificationsResult.value : []
    const mine = mineResult?.status === 'fulfilled' ? mineResult.value : []
    const review = reviewResult?.status === 'fulfilled' ? reviewResult.value : []
    pendingCounts.value = {
      assigned: notifications.filter((item) => item.type === 'TEAM_TASK_ASSIGNED').length,
      shared: notifications.filter((item) => item.type === 'NOTE_SHARED').length,
      revision: mine.filter((item) => item.status === 'NEEDS_REVISION').length,
      review: review.filter((item) => item.status === 'PENDING').length,
    }
  } finally {
    pendingCountsReady.value = true
  }
}

async function loadHome() {
  loading.value = true
  error.value = null
  try {
    const [today, all, assigned, notes] = await Promise.all([
      fetchTodos('today'),
      fetchTodos('all'),
      fetchTodos('assigned-by-me'),
      fetchNotes({ limit: 5 }),
    ])
    allTodayTodos.value = today
    calendarTodos.value = all
    assignedTodos.value = assigned
    recentNotes.value = notes.slice(0, 5)
  } catch {
    error.value = '工作台读取失败，请确认本地服务已启动。'
  } finally {
    loading.value = false
  }
  // These badges are useful, but they are not part of the dashboard's
  // critical path. Let the primary cards paint first and fill the badges in
  // the background.
  void loadOptionalHomeData()
}

onMounted(() => void loadHome())

function openTodo(todo: Todo, view: TodoView) {
  void router.push({ path: '/todos', query: { view, todo: todo.id } })
}

function changeCalendarMonth(offset: number) {
  calendarMonth.value = calendarMonth.value.add(offset, 'month').startOf('month')
}

function openCalendarDate(date: dayjs.Dayjs) {
  void router.push({ path: '/calendar', query: { date: date.format('YYYY-MM-DD') } })
}

async function toggle(todo: Todo) {
  if (!todo.permissions.completable) return
  const snapshot = {
    today: allTodayTodos.value.map(cloneTodo),
    calendar: calendarTodos.value.map(cloneTodo),
    assigned: assignedTodos.value.map(cloneTodo),
  }
  const wasAssignedByMe = assignedTodos.value.some((item) => item.id === todo.id)
  const updateList = (list: Todo[], updated: Todo, includeIfMissing = false) => {
    const index = list.findIndex((item) => item.id === updated.id)
    if (index >= 0) {
      const next = [...list]
      next[index] = { ...updated, sources: updated.sources.length ? updated.sources : list[index].sources }
      return next
    }
    return includeIfMissing ? [...list, updated] : list
  }
  const replace = (updated: Todo) => {
    allTodayTodos.value = updateList(allTodayTodos.value, updated)
    calendarTodos.value = updateList(calendarTodos.value, updated)
    assignedTodos.value = updateList(assignedTodos.value, updated)
  }
  try {
    if (isExecutionDone(todo)) {
      replace(optimisticRestoredTodo(todo))
      replace(await todoStore.restore(todo.id))
    } else {
      replace(optimisticCompletedTodo(todo))
      const result = await todoStore.complete(todo.id)
      replace(result.todo)
      if (result.nextTodo) {
        allTodayTodos.value = updateList(
          allTodayTodos.value,
          result.nextTodo,
          Boolean(result.nextTodo.dueAt && dayjs(result.nextTodo.dueAt).isSame(dayjs(), 'day')),
        )
        calendarTodos.value = updateList(calendarTodos.value, result.nextTodo, true)
        assignedTodos.value = updateList(assignedTodos.value, result.nextTodo, wasAssignedByMe)
      }
      feedback.completed()
    }
  } catch {
    allTodayTodos.value = snapshot.today
    calendarTodos.value = snapshot.calendar
    assignedTodos.value = snapshot.assigned
    feedback.error('任务状态更新失败，已恢复原状态。')
  }
}

function dueTime(todo: Todo) {
  return todo.dueAt ? dayjs(todo.dueAt).format('HH:mm') : ''
}

function overdueLabel(todo: Todo) {
  if (!todo.dueAt) return ''
  const due = dayjs(todo.dueAt)
  if (due.isSame(dayjs().subtract(1, 'day'), 'day')) return '昨天'
  return due.format('M月D日')
}

function noteTime(note: NoteListItem) {
  const updated = dayjs(note.updatedAt)
  if (updated.isSame(dayjs(), 'minute')) return '刚刚'
  if (updated.isSame(dayjs(), 'day')) return updated.format('HH:mm')
  if (updated.isSame(dayjs().subtract(1, 'day'), 'day')) return '昨天'
  return updated.format('M月D日')
}

</script>

<template>
  <div class="home-dashboard">
    <header class="home-dashboard-header">
      <h1>{{ dateLabel }}</h1>
      <RouterLink class="home-quick-add" :to="{ path: '/todos', query: { view: 'today', add: '1' } }">
        <IconPlus :size="16" :stroke-width="1.9" aria-hidden="true" />快速添加
      </RouterLink>
    </header>

    <p v-if="error" class="state-message error home-dashboard-state" role="alert">{{ error }}</p>
    <div v-else-if="loading" class="home-dashboard-loading" aria-label="正在读取工作台">
      <span class="sk-panel sk-7 sk-h336" />
      <span class="sk-panel sk-5 sk-h336" />
      <span class="sk-panel sk-4 sk-h224" />
      <span class="sk-panel sk-4 sk-h224" />
      <span class="sk-panel sk-4 sk-h224" />
      <span class="sk-panel sk-8 sk-h214" />
      <span class="sk-panel sk-4 sk-h214" />
    </div>

    <main v-else class="home-dashboard-grid">
      <section class="home-dashboard-panel home-today-panel">
        <header class="home-panel-header">
          <RouterLink :to="{ path: '/todos', query: { view: 'today' } }"><h2>今天</h2></RouterLink>
          <span class="home-panel-count">{{ todayDone }}/{{ todayItems.length }}</span>
        </header>
        <div v-if="todayPending.length" class="home-compact-list">
          <div v-for="todo in todayPending.slice(0, 5)" :key="todo.id" class="home-task-row">
            <button class="home-task-check" type="button" :disabled="!todo.permissions.completable" :aria-label="`完成${todo.title}`" @click="toggle(todo)"><IconCheck :size="13" /></button>
            <button class="home-task-main" type="button" @click="openTodo(todo, 'today')">
              <span class="home-task-copy"><strong>{{ todo.title }}</strong><small v-if="todo.sourceType === 'TEAM'">{{ todo.creator.nickname }}分配</small></span>
              <time v-if="dueTime(todo)">{{ dueTime(todo) }}</time>
            </button>
          </div>
        </div>
        <div v-else class="home-panel-empty"><IconCheck :size="17" /><span>今天的任务已处理完</span></div>
        <RouterLink class="home-inline-add" :to="{ path: '/todos', query: { view: 'today', add: '1' } }"><IconPlus :size="14" />添加任务</RouterLink>
      </section>

      <section class="home-dashboard-panel home-calendar-panel" aria-labelledby="home-calendar-title">
        <header class="home-calendar-header">
          <button type="button" aria-label="上个月" title="上个月" @click="changeCalendarMonth(-1)"><IconChevronLeft :size="18" /></button>
          <RouterLink id="home-calendar-title" :to="{ path: '/calendar', query: { date: calendarMonth.format('YYYY-MM-DD') } }">{{ calendarMonth.format('YYYY年M月') }}</RouterLink>
          <button type="button" aria-label="下个月" title="下个月" @click="changeCalendarMonth(1)"><IconChevronRight :size="18" /></button>
        </header>
        <div class="home-calendar-weekdays" aria-hidden="true"><span v-for="label in calendarWeekdays" :key="label">{{ label }}</span></div>
        <div class="home-calendar-grid">
          <button
            v-for="date in calendarDays"
            :key="date.format('YYYY-MM-DD')"
            type="button"
            :class="{
              muted: !date.isSame(calendarMonth, 'month'),
              today: date.isSame(dayjs(), 'day'),
              'has-pending': calendarTaskStates.get(date.format('YYYY-MM-DD'))?.pending,
              'has-completed': !calendarTaskStates.get(date.format('YYYY-MM-DD'))?.pending && calendarTaskStates.get(date.format('YYYY-MM-DD'))?.completed,
            }"
            :aria-label="`${date.format('YYYY年M月D日')}，${calendarTaskStates.get(date.format('YYYY-MM-DD'))?.pending ?? 0}项待办`"
            @click="openCalendarDate(date)"
          >{{ date.date() }}</button>
        </div>
      </section>

      <section class="home-dashboard-panel home-upcoming-panel">
        <header class="home-panel-header"><RouterLink :to="{ path: '/todos', query: { view: 'week' } }"><h2>接下来</h2></RouterLink></header>
        <div v-if="upcomingGroups.length" class="home-upcoming-groups">
          <div v-for="group in upcomingGroups" :key="group.key" class="home-upcoming-group">
            <h3>{{ group.label }}</h3>
            <div v-for="todo in group.items" :key="todo.id" class="home-mini-task">
              <button class="home-mini-check" type="button" :disabled="!todo.permissions.completable" :aria-label="`完成${todo.title}`" @click.stop="toggle(todo)"><IconCheck :size="12" /></button>
              <button class="home-mini-task-main" type="button" @click="openTodo(todo, 'month')"><strong>{{ todo.title }}</strong><time>{{ dueTime(todo) }}</time></button>
            </div>
          </div>
        </div>
        <div v-else class="home-panel-empty"><IconClock :size="17" /><span>近期没有任务</span></div>
      </section>

      <section class="home-dashboard-panel home-overdue-panel">
        <header class="home-panel-header"><RouterLink :to="{ path: '/todos', query: { view: 'today' } }"><h2>逾期</h2></RouterLink><span class="home-panel-count danger">{{ overdueTodos.length }}</span></header>
        <div v-if="overdueTodos.length" class="home-compact-list">
          <div v-for="todo in overdueTodos.slice(0, 4)" :key="todo.id" class="home-task-row">
            <button class="home-task-check overdue" type="button" :disabled="!todo.permissions.completable" :aria-label="`完成${todo.title}`" @click="toggle(todo)"><IconCheck :size="13" /></button>
            <button class="home-task-main" type="button" @click="openTodo(todo, 'today')">
              <span class="home-task-copy"><strong>{{ todo.title }}</strong></span>
              <time class="overdue-time">{{ overdueLabel(todo) }}</time>
            </button>
          </div>
        </div>
        <div v-else class="home-panel-empty compact"><IconCheck :size="17" /><span>没有逾期任务</span></div>
      </section>

      <section class="home-dashboard-panel home-assigned-panel">
        <header class="home-panel-header"><RouterLink :to="{ path: '/todos', query: { view: 'assigned-by-me' } }"><h2>我分配的</h2></RouterLink><span class="home-panel-count">{{ assignedOpen.length }}</span></header>
        <div v-if="assignedOpen.length" class="home-assigned-list">
          <button v-for="todo in assignedOpen.slice(0, 4)" :key="todo.id" class="home-assigned-row" type="button" @click="openTodo(todo, 'assigned-by-me')">
            <strong>{{ todo.title }}</strong>
            <span class="home-assignees" aria-label="任务成员"><span v-for="assignment in todo.assignments.slice(0, 3)" :key="assignment.id" :title="assignment.user.nickname">{{ assignment.user.nickname.slice(0, 1) }}</span></span>
            <span class="home-assignment-progress">{{ todo.completedAssignments }}/{{ todo.totalAssignments }}</span>
          </button>
        </div>
        <div v-else class="home-panel-empty compact"><IconChecklist :size="17" /><span>没有进行中的分配</span></div>
      </section>

      <section class="home-dashboard-panel home-notes-panel">
        <header class="home-panel-header"><RouterLink to="/notes"><h2>最近笔记</h2></RouterLink><RouterLink class="home-panel-more" to="/notes" aria-label="查看全部笔记"><IconArrowRight :size="15" /></RouterLink></header>
        <div v-if="recentNotes.length" class="home-note-list">
          <RouterLink v-for="note in recentNotes.slice(0, 4)" :key="note.id" class="home-note-row" :to="{ path: '/notes', query: { note: note.id } }">
            <IconFileText :size="15" aria-hidden="true" /><strong>{{ note.title }}</strong><time>{{ noteTime(note) }}</time>
          </RouterLink>
        </div>
        <div v-else class="home-panel-empty compact"><IconFileText :size="17" /><span>还没有笔记</span></div>
      </section>

      <section class="home-dashboard-panel home-pending-panel">
        <header class="home-panel-header"><RouterLink to="/notifications"><h2>待处理</h2></RouterLink></header>
        <nav class="home-pending-list" aria-label="待处理事项" :aria-busy="!pendingCountsReady">
          <RouterLink v-for="item in pendingItems" :key="item.label" :to="item.to" :class="{ empty: pendingCountsReady && item.count === 0 }">
            <component :is="item.icon" :size="15" aria-hidden="true" /><span>{{ item.label }}</span><strong>{{ pendingCountsReady ? item.count : '—' }}</strong>
          </RouterLink>
        </nav>
      </section>
    </main>
  </div>
</template>
