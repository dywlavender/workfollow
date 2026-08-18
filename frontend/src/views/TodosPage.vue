<script setup lang="ts">
import dayjs from 'dayjs'
import {
  IconBell,
  IconArrowsSort,
  IconCalendar,
  IconCalendarMonth,
  IconCalendarWeek,
  IconCircleCheck,
  IconInbox,
  IconList,
  IconDots,
  IconLayoutSidebarLeftCollapse,
  IconLayoutSidebarLeftExpand,
  IconPlus,
  IconSearch,
  IconSend,
  IconUsers,
  IconX,
} from '@tabler/icons-vue'
import { computed, nextTick, onBeforeUnmount, onMounted, ref, watch } from 'vue'
import { useRoute, useRouter } from 'vue-router'

import ActionFeedback from '@/components/ActionFeedback.vue'
import QuickTodoInput from '@/components/todo/QuickTodoInput.vue'
import TaskDetailPanel from '@/components/task/TaskDetailPanel.vue'
import TaskListGrouped from '@/components/task/TaskListGrouped.vue'
import TodoDialog from '@/components/todo/TodoDialog.vue'
import TodoItem from '@/components/todo/TodoItem.vue'
import { taskCountLabel } from '@/modules/todo/taskCounts'
import { fetchTeamMembers, fetchTodo, type TeamMember, type Todo, type TodoPayload, type TodoView } from '@/services/api'
import { useAppStore } from '@/stores/app'
import { useAuthStore } from '@/stores/auth'
import { optimisticCompletedTodo, optimisticRestoredTodo, useTodoStore } from '@/stores/todos'
import { useWorkspaceStore } from '@/stores/workspace'

const todoStore = useTodoStore()
const appStore = useAppStore()
const auth = useAuthStore()
const workspaceStore = useWorkspaceStore()
const route = useRoute()
const router = useRouter()
const selectedTodoId = ref<string | null>(null)
const selectedTodoDetail = ref<Todo | null>(null)
const dialogOpen = ref(false)
const notificationState = ref<'unsupported' | NotificationPermission>('default')
const quickTodoInput = ref<{ begin: () => Promise<void> } | null>(null)
const taskDetail = ref<{
  openDatePanel: (anchor?: Pick<DOMRect, 'left' | 'bottom'>) => void
  openPriorityPanel: () => void
} | null>(null)
const searchInput = ref(typeof route.query.q === 'string' ? route.query.q : '')
const actionError = ref<string | null>(null)
const actionNotice = ref<string | null>(null)
const searchOpen = ref(Boolean(searchInput.value))
const toolbarMenuOpen = ref(false)
const taskNavigationOpen = ref(false)
const taskNavigationCollapsed = ref(false)
const taskNavigationDrawer = ref(false)
const sortReverse = ref(false)
const workspace = ref<HTMLElement | null>(null)
const taskViewSidebar = ref<HTMLElement | null>(null)
const taskListWidth = ref(420)
const resizingList = ref(false)
const teamMembers = ref<TeamMember[]>([])

const workspaceStyle = computed(() => ({ '--task-list-width': `${taskListWidth.value}px` }))
const taskNavigationButtonLabel = computed(() => taskNavigationDrawer.value
  ? (taskNavigationOpen.value ? '关闭任务导航' : '打开任务导航')
  : (taskNavigationCollapsed.value ? '展开任务导航' : '收起任务导航'))
const taskNavigationExpanded = computed(() => taskNavigationDrawer.value
  ? taskNavigationOpen.value
  : !taskNavigationCollapsed.value)
const taskNavigationButtonIcon = computed(() => taskNavigationDrawer.value || taskNavigationCollapsed.value
  ? IconLayoutSidebarLeftExpand
  : IconLayoutSidebarLeftCollapse)
let taskNavigationMedia: MediaQueryList | null = null

const baseViews = [
  { id: 'all' as TodoView, label: '所有', hint: '全部任务', icon: IconList },
  { id: 'today' as TodoView, label: '今天', hint: '今天截止', icon: IconCalendar },
  { id: 'week' as TodoView, label: '本周', hint: '周内任务', icon: IconCalendarWeek },
  { id: 'inbox' as TodoView, label: '无日期', hint: '尚未安排', icon: IconInbox },
  { id: 'month' as TodoView, label: '本月', hint: '本月计划', icon: IconCalendarMonth },
  { id: 'completed' as TodoView, label: '已完成', hint: '完成记录', icon: IconCircleCheck },
]
const taskViews = baseViews.slice(0, 5)
const recordViews = baseViews.slice(5)
const collaborationViews = [
  { id: 'collaboration' as TodoView, label: '协作任务', hint: '全部团队任务', icon: IconUsers },
  { id: 'assigned-to-me' as TodoView, label: '分配给我的', hint: '别人指派', icon: IconUsers },
  { id: 'assigned-by-me' as TodoView, label: '我分配的', hint: '跟踪进度', icon: IconSend },
]
const currentTeam = computed(() => workspaceStore.currentTeam ?? workspaceStore.teams[0] ?? null)
const hasTeam = computed(() => Boolean(currentTeam.value))
const canAssign = computed(() => currentTeam.value?.role === 'OWNER' || currentTeam.value?.role === 'ADMIN')
const views = computed(() => hasTeam.value ? [...taskViews, ...collaborationViews, ...recordViews] : baseViews)

const taskViewGroups = computed(() => [
  { label: '任务视图', items: taskViews },
  ...(hasTeam.value ? [{ label: '协作', items: collaborationViews }] : []),
  { label: '记录', items: recordViews },
])

const currentView = computed(() => views.value.find((view) => view.id === todoStore.currentView) ?? baseViews[1])
const currentListName = computed(() => typeof route.query.list === 'string' ? route.query.list.trim() : '')
const currentHeading = computed(() => currentListName.value || currentView.value.label)
const quickDefaultDueAt = computed(() => !currentListName.value && currentView.value.id === 'today'
  ? dayjs().startOf('day').format('YYYY-MM-DDTHH:mm:ss')
  : '')
const standardListNames = ['收集箱', '工作', '个人', '学习']
const listRank = (name: string) => {
  const index = standardListNames.indexOf(name)
  return index === -1 ? standardListNames.length : index
}
const listViews = computed(() => Object.entries(todoStore.listCounts)
  .sort(([first], [second]) => listRank(first) - listRank(second) || first.localeCompare(second, 'zh-CN'))
  .map(([name, count]) => ({ name, count })))
const availableTaskLists = computed(() => listViews.value.map((list) => list.name))
const availableTaskTags = computed(() => Array.from(new Set(todoStore.todos.flatMap((todo) => todo.tags))).sort((first, second) => first.localeCompare(second, 'zh-CN')))
const selectedTodo = computed(() => {
  const listed = todoStore.todos.find((todo) => todo.id === selectedTodoId.value) ?? null
  if (!listed) return selectedTodoDetail.value?.id === selectedTodoId.value ? selectedTodoDetail.value : null
  if (selectedTodoDetail.value?.id !== listed.id) return listed
  return { ...selectedTodoDetail.value, ...listed, sources: selectedTodoDetail.value.sources }
})
const weekdayNames = ['周日', '周一', '周二', '周三', '周四', '周五', '周六']

const hasVisibleTasks = computed(() => todoStore.todos.length > 0)

const currentDateLabel = computed(() => `${dayjs().format('YYYY年M月D日')} · ${weekdayNames[dayjs().day()]}`)

function viewFromRoute(): TodoView {
  const candidate = route.query.view
  return views.value.some((view) => view.id === candidate) ? candidate as TodoView : 'today'
}

async function loadView(view = viewFromRoute()) {
  const query = typeof route.query.q === 'string' ? route.query.q : ''
  const listName = typeof route.query.list === 'string' ? route.query.list.trim() : ''
  searchInput.value = query
  if (todoStore.currentView !== view || todoStore.currentListName !== listName) sortReverse.value = false
  try {
    await todoStore.load(listName ? 'all' : view, query, listName)
    await todoStore.loadCounts().catch(() => undefined)
  } catch {
    return
  }
  const requested = typeof route.query.todo === 'string' ? route.query.todo : null
  if (requested && todoStore.todos.some((todo) => todo.id === requested)) {
    selectedTodoId.value = requested
    selectedTodoDetail.value = await fetchTodo(requested).catch(() => null)
  } else {
    selectedTodoId.value = null
    selectedTodoDetail.value = null
  }

  // The home page is an aggregation surface. Its add action routes here and
  // focuses the canonical quick-add control instead of rendering a second
  // editor on the home page.
  if (route.query.add === '1') {
    await nextTick()
    await quickTodoInput.value?.begin()
    const query = { ...route.query }
    delete query.add
    void router.replace({ query })
  }
}

async function activateView(view: TodoView) {
  const routeWillChange = route.query.view !== view || Object.keys(route.query).some((key) => key !== 'view')
  await router.push({ path: '/todos', query: { view } })
  // Clicking the active smart list must still refresh it. This matters for
  // "Today" after midnight and after changes made elsewhere in the app.
  if (!routeWillChange) await loadView(view)
}

async function activateList(listName: string) {
  const routeWillChange = route.query.list !== listName || Object.keys(route.query).some((key) => key !== 'list')
  await router.push({ path: '/todos', query: { list: listName } })
  if (!routeWillChange) await loadView('all')
}

function listWidthBounds() {
  const workspaceWidth = workspace.value?.getBoundingClientRect().width ?? window.innerWidth
  const sidebarWidth = taskViewSidebar.value?.getBoundingClientRect().width ?? 220
  return { min: 340, max: Math.max(340, workspaceWidth - sidebarWidth - 395) }
}

function applyListWidth(width: number) {
  const { min, max } = listWidthBounds()
  taskListWidth.value = Math.round(Math.min(max, Math.max(min, width)))
}

function moveListDivider(event: PointerEvent) {
  if (!resizingList.value || !workspace.value || !taskViewSidebar.value) return
  const workspaceLeft = workspace.value.getBoundingClientRect().left
  const sidebarWidth = taskViewSidebar.value.getBoundingClientRect().width
  applyListWidth(event.clientX - workspaceLeft - sidebarWidth)
}

function stopListResize() {
  if (!resizingList.value) return
  resizingList.value = false
  document.body.classList.remove('task-list-resizing')
  localStorage.setItem('workfollow-task-list-width', String(taskListWidth.value))
}

function handleWorkspaceKeydown(event: KeyboardEvent) {
  if (event.key === 'Escape') {
    if (taskNavigationOpen.value) closeTaskNavigation()
    else if (selectedTodoId.value) clearSelection()
    return
  }
  if (event.key !== 'ArrowDown' && event.key !== 'ArrowUp') return
  const target = event.target as HTMLElement | null
  if (target?.closest('input, textarea, select, [contenteditable="true"], [role="dialog"]')) return
  if (!todoStore.todos.length) return
  const currentIndex = selectedTodoId.value ? todoStore.todos.findIndex((todo) => todo.id === selectedTodoId.value) : -1
  const nextIndex = event.key === 'ArrowDown'
    ? Math.min(todoStore.todos.length - 1, currentIndex + 1)
    : Math.max(0, currentIndex < 0 ? todoStore.todos.length - 1 : currentIndex - 1)
  event.preventDefault()
  selectTodo(todoStore.todos[nextIndex])
}

function startListResize(event: PointerEvent) {
  if (window.matchMedia('(max-width: 1250px)').matches) return
  event.preventDefault()
  resizingList.value = true
  document.body.classList.add('task-list-resizing')
}

function resizeListWithKeyboard(event: KeyboardEvent) {
  if (event.key === 'Home') applyListWidth(420)
  else if (event.key === 'ArrowLeft') applyListWidth(taskListWidth.value - 24)
  else if (event.key === 'ArrowRight') applyListWidth(taskListWidth.value + 24)
  else return
  event.preventDefault()
  localStorage.setItem('workfollow-task-list-width', String(taskListWidth.value))
}

onMounted(async () => {
  const storedWidth = Number(localStorage.getItem('workfollow-task-list-width'))
  if (Number.isFinite(storedWidth) && storedWidth > 0) applyListWidth(storedWidth)
  taskNavigationCollapsed.value = localStorage.getItem('workfollow-task-navigation-collapsed') === '1'
  taskNavigationMedia = window.matchMedia('(max-width: 1023px)')
  syncTaskNavigationMode()
  taskNavigationMedia.addEventListener('change', syncTaskNavigationMode)
  window.addEventListener('pointermove', moveListDivider)
  window.addEventListener('pointerup', stopListResize)
  window.addEventListener('keydown', handleWorkspaceKeydown)
  notificationState.value = 'Notification' in window ? Notification.permission : 'unsupported'
  if (currentTeam.value) teamMembers.value = await fetchTeamMembers(currentTeam.value.id).catch(() => [])
  await loadView()
})

onBeforeUnmount(() => {
  taskNavigationMedia?.removeEventListener('change', syncTaskNavigationMode)
  window.removeEventListener('pointermove', moveListDivider)
  window.removeEventListener('pointerup', stopListResize)
  window.removeEventListener('keydown', handleWorkspaceKeydown)
  document.body.classList.remove('task-list-resizing')
})

watch(() => [route.query.view, route.query.list, route.query.q] as const, () => { void loadView() })

function selectTodo(todo: Todo) {
  selectedTodoId.value = todo.id
  selectedTodoDetail.value = null
  void fetchTodo(todo.id).then((detail) => { if (selectedTodoId.value === detail.id) selectedTodoDetail.value = detail })
  void router.replace({ query: { ...route.query, todo: todo.id } })
}

function clearSelection() {
  selectedTodoId.value = null
  selectedTodoDetail.value = null
  const query = { ...route.query }
  delete query.todo
  void router.replace({ query })
}

function closeTaskNavigation() {
  taskNavigationOpen.value = false
}

function syncTaskNavigationMode(event?: MediaQueryListEvent) {
  taskNavigationDrawer.value = event?.matches ?? taskNavigationMedia?.matches ?? false
  if (!taskNavigationDrawer.value) taskNavigationOpen.value = false
}

function toggleTaskNavigation() {
  if (taskNavigationDrawer.value) {
    taskNavigationOpen.value = !taskNavigationOpen.value
    return
  }
  taskNavigationCollapsed.value = !taskNavigationCollapsed.value
  localStorage.setItem('workfollow-task-navigation-collapsed', taskNavigationCollapsed.value ? '1' : '0')
}

function openCreate() {
  dialogOpen.value = true
}

function notify(message: string) {
  actionError.value = null
  actionNotice.value = message
  window.setTimeout(() => { if (actionNotice.value === message) actionNotice.value = null }, 2600)
}

function reportActionError(message: string) {
  actionNotice.value = null
  actionError.value = message
}

async function save(payload: TodoPayload) {
  try {
    const created = await todoStore.create(payload)
    dialogOpen.value = false
    if (todoStore.todos.some((todo) => todo.id === created.id)) selectTodo(created)
    notify(created.dueAt ? '任务已创建。' : '任务已创建并放入收集箱。')
  } catch {
    reportActionError('创建失败，请检查填写内容后重试。')
  }
}

async function updateTodo(todoId: string, payload: Partial<TodoPayload>, quiet = false): Promise<boolean> {
  try {
    await todoStore.update(todoId, payload)
    if (todoStore.query && selectedTodoId.value === todoId && !todoStore.todos.some((todo) => todo.id === todoId)) clearSelection()
    if (!quiet) notify('任务已保存。')
    return true
  } catch {
    reportActionError('保存失败，请检查日期、提醒和重复设置。')
    return false
  }
}

async function updateFromRow(todo: Todo, payload: Partial<TodoPayload>) {
  await updateTodo(todo.id, payload)
}

async function duplicate(todo: Todo) {
  try {
    const created = await todoStore.create({
      title: `${todo.title} 副本`, description: todo.description, priority: todo.priority,
      dueAt: todo.dueAt, dueEndAt: todo.dueEndAt, reminderAt: todo.reminderAt,
      recurrenceType: todo.recurrenceType, recurrenceConfig: todo.recurrenceConfig,
      listName: todo.listName, tags: [...todo.tags], sourceType: todo.sourceType,
      sourceNoteId: todo.sourceNoteId, sourceExcerpt: todo.sourceExcerpt,
    })
    if (todoStore.todos.some((item) => item.id === created.id)) selectTodo(created)
    notify('任务副本已创建。')
  } catch {
    reportActionError('复制任务失败。')
  }
}

async function copyTaskLink(todo: Todo) {
  const link = `${window.location.origin}${router.resolve({ path: '/todos', query: { view: todoStore.currentView, todo: todo.id } }).href}`
  try {
    await navigator.clipboard.writeText(link)
    notify('任务链接已复制。')
  } catch {
    reportActionError('浏览器未允许写入剪贴板。')
  }
}

async function editDate(todo: Todo, clickedAnchor?: Pick<DOMRect, 'left' | 'bottom'>) {
  selectTodo(todo)
  await nextTick()
  await new Promise<void>((resolve) => window.requestAnimationFrame(() => resolve()))
  const row = document.querySelector<HTMLElement>(`[data-todo-id="${CSS.escape(todo.id)}"]`)
  const anchor = clickedAnchor ?? row?.querySelector<HTMLElement>('.todo-time')?.getBoundingClientRect()
  taskDetail.value?.openDatePanel(anchor)
}

async function editPriority(todo: Todo) {
  selectTodo(todo)
  await nextTick()
  taskDetail.value?.openPriorityPanel()
}

async function toggle(todo: Todo) {
  if (!todo.permissions.completable) return
  const previousDetail = selectedTodoDetail.value
  try {
    const executionDone = todo.myAssignment?.status === 'DONE'
    if (executionDone) {
      const optimistic = optimisticRestoredTodo(todo)
      if (selectedTodoId.value === todo.id && selectedTodoDetail.value) {
        selectedTodoDetail.value = { ...selectedTodoDetail.value, ...optimistic, sources: selectedTodoDetail.value.sources }
      }
      const restored = await todoStore.restore(todo.id)
      if (selectedTodoId.value === todo.id && selectedTodoDetail.value) {
        selectedTodoDetail.value = { ...selectedTodoDetail.value, ...restored, sources: selectedTodoDetail.value.sources }
      }
      notify('任务已恢复。')
    } else {
      const optimistic = optimisticCompletedTodo(todo)
      if (selectedTodoId.value === todo.id && selectedTodoDetail.value) {
        selectedTodoDetail.value = { ...selectedTodoDetail.value, ...optimistic, sources: selectedTodoDetail.value.sources }
      }
      const result = await todoStore.complete(todo.id)
      if (selectedTodoId.value === todo.id && selectedTodoDetail.value) {
        selectedTodoDetail.value = { ...selectedTodoDetail.value, ...result.todo, sources: selectedTodoDetail.value.sources }
      }
      appStore.showCompletionToast()
      notify(result.nextTodo ? '任务已完成，下一次任务已生成。' : '任务已完成。')
    }
  } catch {
    if (selectedTodoId.value === todo.id) selectedTodoDetail.value = previousDetail
    reportActionError('操作失败，任务状态没有改变。')
  }
}

async function abandon(todo: Todo) {
  try {
    await todoStore.abandon(todo.id)
    notify('任务已放弃，可随时恢复。')
  } catch {
    reportActionError('操作失败，任务状态没有改变。')
  }
}

async function remove(todo: Todo) {
  try {
    await todoStore.remove(todo.id)
    if (selectedTodoId.value === todo.id) clearSelection()
    notify('任务已删除。')
  } catch {
    reportActionError('删除失败，请稍后重试。')
  }
}

function submitSearch() {
  const query = { ...route.query }
  delete query.todo
  if (searchInput.value.trim()) query.q = searchInput.value.trim()
  else delete query.q
  void router.replace({ query })
}

function clearSearch() {
  searchInput.value = ''
  submitSearch()
}

async function requestNotifications() {
  if (!('Notification' in window)) {
    notificationState.value = 'unsupported'
    return
  }
  notificationState.value = await Notification.requestPermission()
}

function openSource(noteId: string, blockId?: string | null) {
  void router.push({ name: 'notes', query: { note: noteId, ...(blockId ? { block: blockId } : {}) } })
}

async function assign(todo: Todo, assigneeIds: string[]) {
  try {
    await todoStore.updateAssignees(todo.id, assigneeIds)
    notify('指派成员已更新。')
  } catch {
    reportActionError('指派失败，只能选择当前团队成员。')
  }
}
</script>

<template>
  <div class="page-content tasks-page">
    <div ref="workspace" class="tasks-workspace" :class="{ 'has-selection': Boolean(selectedTodo), resizing: resizingList, 'navigation-open': taskNavigationOpen, 'navigation-collapsed': taskNavigationCollapsed }" :style="workspaceStyle" @click="toolbarMenuOpen = false">
      <button v-if="taskNavigationOpen" class="task-navigation-scrim" type="button" aria-label="关闭任务导航" @click="closeTaskNavigation" />
      <aside
        ref="taskViewSidebar"
        class="task-view-sidebar"
        aria-label="任务视图"
        :aria-hidden="!taskNavigationDrawer && taskNavigationCollapsed"
        :inert="!taskNavigationDrawer && taskNavigationCollapsed"
      >
        <div class="task-side-head"><span>任务</span><button type="button" aria-label="关闭任务导航" @click="closeTaskNavigation"><IconX :size="17" /></button></div>
        <div v-for="group in taskViewGroups" :key="group.label" class="task-view-group">
          <h2>{{ group.label }}</h2>
          <nav class="task-view-nav" :aria-label="group.label">
            <RouterLink
              v-for="view in group.items"
              :key="view.id"
              class="task-view-item"
              :class="{ active: !currentListName && currentView.id === view.id }"
              :to="{ path: '/todos', query: { view: view.id } }"
              :aria-current="!currentListName && currentView.id === view.id ? 'page' : undefined"
              @click.prevent="activateView(view.id); closeTaskNavigation()"
            >
              <component :is="view.icon" :size="17" :stroke-width="1.8" aria-hidden="true" />
              <span class="task-view-copy"><strong>{{ view.label }}</strong><small>{{ view.hint }}</small></span>
              <span class="task-view-count" :class="{ pending: !todoStore.hasLoadedCounts }">{{ taskCountLabel(todoStore.hasLoadedCounts, todoStore.counts[view.id]) }}</span>
            </RouterLink>
          </nav>
        </div>
        <div class="task-view-group">
          <h2>清单</h2>
          <nav class="task-view-nav" aria-label="清单">
            <RouterLink
              v-for="list in listViews"
              :key="list.name"
              class="task-view-item"
              :class="{ active: currentListName === list.name }"
              :to="{ path: '/todos', query: { list: list.name } }"
              :aria-current="currentListName === list.name ? 'page' : undefined"
              @click.prevent="activateList(list.name); closeTaskNavigation()"
            >
              <IconList :size="17" :stroke-width="1.8" aria-hidden="true" />
              <span class="task-view-copy"><strong>{{ list.name }}</strong><small>任务清单</small></span>
              <span class="task-view-count" :class="{ pending: !todoStore.hasLoadedCounts }">{{ taskCountLabel(todoStore.hasLoadedCounts, list.count) }}</span>
            </RouterLink>
          </nav>
        </div>
      </aside>

      <section class="task-list-panel" aria-label="待办列表">
        <header class="list-panel-header">
          <button class="task-navigation-trigger" type="button" :aria-label="taskNavigationButtonLabel" :title="taskNavigationButtonLabel" :aria-expanded="taskNavigationExpanded" @click="toggleTaskNavigation"><component :is="taskNavigationButtonIcon" :size="19" /></button>
          <div class="list-panel-heading-copy"><span>{{ currentDateLabel }}</span><h2>{{ currentHeading }}</h2></div>
          <div class="list-panel-actions">
            <form v-if="searchOpen" class="task-search" role="search" @submit.prevent="submitSearch">
              <label class="sr-only" for="todo-search">搜索当前列表</label>
              <input id="todo-search" v-model="searchInput" placeholder="搜索任务" autocomplete="off" @keydown.enter.prevent="submitSearch" />
              <button v-if="searchInput" type="button" aria-label="清除搜索" @click="clearSearch"><IconX :size="15" /></button>
              <button class="task-search-submit" type="submit" aria-label="搜索"><IconSearch :size="16" /></button>
            </form>
            <button v-if="currentView.id !== 'all' || currentListName" class="task-header-icon" type="button" :title="sortReverse ? '恢复正序' : '倒序排列'" aria-label="切换任务排序" @click="sortReverse = !sortReverse"><IconArrowsSort :size="17" /></button>
            <div class="task-toolbar-menu-host">
              <button class="task-header-icon" type="button" title="更多" aria-label="更多列表操作" @click.stop="toolbarMenuOpen = !toolbarMenuOpen"><IconDots :size="18" /></button>
              <section v-if="toolbarMenuOpen" class="task-toolbar-menu" @click.stop>
                <button type="button" @click="openCreate(); toolbarMenuOpen = false"><IconPlus :size="16" />新建详细任务</button>
                <button v-if="notificationState === 'default'" type="button" @click="requestNotifications(); toolbarMenuOpen = false"><IconBell :size="16" />启用提醒</button>
                <span v-else>{{ notificationState === 'granted' ? '提醒已启用' : notificationState === 'denied' ? '提醒权限已拒绝' : '浏览器不支持提醒' }}</span>
              </section>
            </div>
          </div>
        </header>
        <div class="task-command-bar">
          <div class="task-quick-add-wrap"><QuickTodoInput
            ref="quickTodoInput"
            :members="teamMembers"
            :current-user-id="auth.user?.id"
            :can-assign="canAssign"
            :default-list-name="currentListName || '收集箱'"
            :default-due-at="quickDefaultDueAt"
            :available-lists="availableTaskLists"
            :available-tags="availableTaskTags"
            :calendar-todos="todoStore.todos"
            @created="notify('任务已创建。')"
          /></div>
        </div>
        <ActionFeedback :message="actionError" @dismiss="actionError = null" />
        <ActionFeedback :message="actionNotice" tone="success" @dismiss="actionNotice = null" />
        <div v-if="todoStore.error" class="state-message error" role="alert">
          <strong>任务读取失败</strong>
          <p>{{ todoStore.error }}</p>
          <button class="secondary-button" type="button" :disabled="todoStore.loading" @click="loadView()">{{ todoStore.loading ? '正在重试…' : '重新加载' }}</button>
        </div>
        <div v-else-if="todoStore.loading" class="task-list-skeleton" aria-label="正在读取待办" aria-busy="true"><span v-for="index in 7" :key="index"><i /><b /><em /></span></div>
        <div v-else-if="hasVisibleTasks" class="todo-list">
          <TaskListGrouped :items="todoStore.todos" :reverse="sortReverse" :sort-mode="currentView.id === 'all' && !currentListName ? 'due-desc' : 'grouped'" :assignment-status="currentView.id !== 'assigned-by-me'" terminal-label="已完成和已放弃">
            <template #item="{ item: todo }">
            <TodoItem
              :key="todo.id"
              :todo="todo"
              :selected="selectedTodoId === todo.id"
              :members="teamMembers"
              :current-user-id="auth.user?.id"
              @toggle="toggle"
              @edit="selectTodo"
              @edit-date="editDate"
              @edit-priority="editPriority"
              @update="updateFromRow"
              @duplicate="duplicate"
              @copy-link="copyTaskLink"
              @assign="assign"
              @abandon="abandon"
              @remove="remove"
            />
            </template>
          </TaskListGrouped>
        </div>
        <div v-else class="state-message empty">
          <IconCircleCheck :size="24" :stroke-width="1.5" aria-hidden="true" />
          <strong>这里还没有待办</strong>
          <p>{{ todoStore.query ? '没有找到匹配的任务。' : todoStore.currentView === 'inbox' ? '先写下来，稍后再安排时间。' : '当前视图没有符合条件的待办。' }}</p>
          <button v-if="todoStore.query" class="secondary-button" type="button" @click="clearSearch">清除搜索</button>
          <button v-else class="secondary-button" type="button" @click="quickTodoInput?.begin()">添加任务</button>
        </div>
      </section>

      <div
        class="task-list-resizer"
        :class="{ active: resizingList }"
        role="separator"
        aria-label="调整任务列表与详情宽度"
        aria-orientation="vertical"
        :aria-valuemin="listWidthBounds().min"
        :aria-valuemax="listWidthBounds().max"
        :aria-valuenow="taskListWidth"
        tabindex="0"
        @pointerdown="startListResize"
        @keydown="resizeListWithKeyboard"
      ><span aria-hidden="true" /></div>

      <TaskDetailPanel
        ref="taskDetail"
        :todo="selectedTodo"
        :members="teamMembers"
        :current-user-id="auth.user?.id"
        :updating="todoStore.mutating"
        @close="clearSelection"
        @toggle-personal="toggle"
        @remove-personal="remove"
        @update-personal="async (id, payload, quiet, settled) => settled?.(await updateTodo(id, payload, quiet))"
        @assign-personal="assign"
        @open-source="openSource"
      />
    </div>

    <TodoDialog
      :open="dialogOpen"
      :members="teamMembers"
      :current-user-id="auth.user?.id"
      :can-assign="canAssign"
      :initial-list-name="currentListName || '收集箱'"
      @close="dialogOpen = false"
      @save="save"
      @open-source="openSource"
    />
  </div>
</template>
