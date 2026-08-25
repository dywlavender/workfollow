import { defineStore } from 'pinia'

import {
  abandonTodo,
  completeTodo,
  deleteTodo,
  fetchTodos,
  fetchTodoLists,
  postTodo,
  postTodoList,
  putTaskAssignees,
  putTaskMyStatus,
  putTodoList,
  putTodo,
  deleteTodoList,
  restoreTodo,
  type Todo,
  type TodoList,
  type TodoListDeleteResult,
  type TodoPayload,
  type TodoView,
} from '@/services/api'

const todoViews: TodoView[] = ['all', 'today', 'week', 'inbox', 'month', 'completed', 'collaboration', 'assigned-to-me', 'assigned-by-me']
const emptyCounts = (): Record<TodoView, number> => ({
  all: 0, today: 0, week: 0, inbox: 0, month: 0, completed: 0,
  collaboration: 0, 'assigned-to-me': 0, 'assigned-by-me': 0,
})
const defaultLists = ['收集箱', '工作', '个人', '学习']
const defaultListCatalog = (): TodoList[] => defaultLists.map((name, sortOrder) => ({
  id: null, name, sortOrder, protected: true,
}))
const emptyListCounts = (): Record<string, number> => Object.fromEntries(defaultLists.map((name) => [name, 0]))

export function cloneTodo(todo: Todo): Todo {
  return {
    ...todo,
    tags: [...todo.tags],
    sources: todo.sources.map((source) => ({ ...source })),
    permissions: { ...todo.permissions },
    assignments: todo.assignments.map((assignment) => ({
      ...assignment,
      user: { ...assignment.user },
    })),
    myAssignment: todo.myAssignment
      ? { ...todo.myAssignment, user: { ...todo.myAssignment.user } }
      : null,
    recurrenceConfig: todo.recurrenceConfig ? { ...todo.recurrenceConfig } : null,
  }
}

function updateMyAssignment(todo: Todo, update: (assignment: Todo['myAssignment']) => void) {
  if (!todo.myAssignment) return
  update(todo.myAssignment)
  const assignment = todo.assignments.find((item) => item.id === todo.myAssignment?.id)
  if (assignment) update(assignment)
}

export function optimisticCompletedTodo(todo: Todo): Todo {
  const next = cloneTodo(todo)
  const now = new Date().toISOString()
  updateMyAssignment(next, (assignment) => {
    if (assignment) {
      assignment.status = 'DONE'
      assignment.completedAt = now
    }
  })
  const activeAssignments = next.assignments.filter((assignment) => assignment.active)
  next.completedAssignments = activeAssignments.filter((assignment) => assignment.status === 'DONE').length
  next.totalAssignments = activeAssignments.length
  next.status = activeAssignments.length > 0 && activeAssignments.every((assignment) => assignment.status === 'DONE') ? 'DONE' : 'TODO'
  next.completedAt = next.status === 'DONE' ? now : null
  next.updatedAt = now
  return next
}

export function optimisticRestoredTodo(todo: Todo): Todo {
  const next = cloneTodo(todo)
  updateMyAssignment(next, (assignment) => {
    if (assignment) {
      assignment.status = 'TODO'
      assignment.completedAt = null
    }
  })
  const activeAssignments = next.assignments.filter((assignment) => assignment.active)
  next.completedAssignments = activeAssignments.filter((assignment) => assignment.status === 'DONE').length
  next.totalAssignments = activeAssignments.length
  next.status = 'TODO'
  next.completedAt = null
  next.updatedAt = new Date().toISOString()
  return next
}

export function isCompletedForCurrentUser(todo: Todo): boolean {
  // Team tasks can remain globally TODO until every assignment is done. The
  // completed view is per current user, so a DONE personal Assignment counts
  // even when the aggregate task status has not changed yet.
  return todo.myAssignment?.status === 'DONE' || todo.status !== 'TODO'
}

function shouldRetainAfterCompletion(todo: Todo, view: TodoView): boolean {
  if (view === 'completed' || view === 'all' || view === 'collaboration' || view === 'assigned-to-me' || view === 'assigned-by-me' || view === 'inbox') return true
  // A shared task can remain TODO while this user's own assignment is DONE;
  // the API still returns it in the smart list and the grouped UI moves it to
  // the user's completed group. Only a task that is globally DONE follows the
  // overdue smart-list exclusion used by the backend query.
  if (todo.status !== 'DONE') return true
  if (!todo.dueAt) return true
  const due = new Date(todo.dueAt)
  const now = new Date()
  const start = new Date(now.getFullYear(), now.getMonth(), now.getDate())
  if (view === 'today') return due >= start
  if (view === 'week') {
    const weekStart = new Date(start)
    const day = weekStart.getDay()
    weekStart.setDate(weekStart.getDate() - (day === 0 ? 6 : day - 1))
    return due >= weekStart
  }
  if (view === 'month') return due >= new Date(now.getFullYear(), now.getMonth(), 1)
  return true
}

function shouldInsertGeneratedTodo(todo: Todo, view: TodoView, query: string, listName: string): boolean {
  if (listName && todo.listName !== listName) return false
  if (query && !`${todo.title}\n${todo.description ?? ''}`.toLocaleLowerCase().includes(query.toLocaleLowerCase())) return false
  if (view === 'all' || view === 'collaboration') return view !== 'collaboration' || Boolean(todo.teamId)
  if (view === 'assigned-to-me') return todo.creatorId !== todo.myAssignment?.userId
  if (view === 'assigned-by-me') return todo.assignments.some((assignment) => assignment.userId !== todo.creatorId && assignment.active)
  if (!todo.dueAt || todo.status !== 'TODO') return view === 'inbox' && !todo.dueAt

  const due = new Date(todo.dueAt)
  const now = new Date()
  const start = new Date(now.getFullYear(), now.getMonth(), now.getDate())
  if (view === 'today') return due < new Date(start.getTime() + 24 * 60 * 60 * 1000)
  if (view === 'week') {
    const monday = new Date(start)
    const day = monday.getDay()
    monday.setDate(monday.getDate() - (day === 0 ? 6 : day - 1))
    return due < new Date(monday.getTime() + 7 * 24 * 60 * 60 * 1000)
  }
  if (view === 'month') return due < new Date(now.getFullYear(), now.getMonth() + 1, 1)
  return false
}

function belongsToCurrentCollection(todo: Todo, view: TodoView, query: string, listName: string): boolean {
  if (query && !`${todo.title}\n${todo.description ?? ''}`.toLocaleLowerCase().includes(query.toLocaleLowerCase())) return false
  if (listName) return todo.listName === listName
  if (view === 'completed') return isCompletedForCurrentUser(todo)
  return shouldInsertGeneratedTodo(todo, view, '', '')
}

export const useTodoStore = defineStore('todos', {
  state: () => ({
    todos: [] as Todo[],
    currentView: 'today' as TodoView,
    currentListName: '',
    query: '',
    lists: defaultListCatalog(),
    counts: emptyCounts(),
    listCounts: emptyListCounts(),
    loading: true,
    hasLoaded: false,
    countsLoading: true,
    hasLoadedCounts: false,
    mutating: false,
    error: null as string | null,
  }),
  actions: {
    reset() {
      this.todos = []
      this.currentView = 'today'
      this.currentListName = ''
      this.query = ''
      this.lists = defaultListCatalog()
      this.counts = emptyCounts()
      this.listCounts = emptyListCounts()
      this.loading = true
      this.hasLoaded = false
      this.countsLoading = true
      this.hasLoadedCounts = false
      this.mutating = false
      this.error = null
    },
    async load(view?: TodoView, query?: string, listName?: string) {
      const targetView = view ?? this.currentView
      const targetQuery = query ?? this.query
      const targetListName = listName ?? this.currentListName
      this.currentView = targetView
      this.currentListName = targetListName
      this.query = targetQuery
      this.loading = true
      this.error = null
      try {
        this.todos = await fetchTodos(targetView, targetQuery, targetListName)
      } catch (error) {
        this.error = '无法读取待办，请确认本地服务已启动。'
        throw error
      } finally {
        this.loading = false
        this.hasLoaded = true
      }
    },
    async loadLists() {
      try {
        this.lists = await fetchTodoLists()
      } catch {
        // Keep the built-in fallback visible if an older backend is still running.
      }
    },
    async loadCounts() {
      this.countsLoading = true
      try {
        const results = await Promise.all(todoViews.map(async (view) => {
          const todos = await fetchTodos(view)
          const count = view === 'all' || view === 'collaboration' || view === 'assigned-to-me' || view === 'assigned-by-me'
            ? todos.length
            : view === 'completed'
            ? todos.filter(isCompletedForCurrentUser).length
            : todos.filter((todo) => todo.status === 'TODO').length
          return [view, count, todos] as const
        }))
        this.counts = Object.fromEntries(results.map(([view, count]) => [view, count])) as Record<TodoView, number>
        const allTodos = results.find(([view]) => view === 'all')?.[2] ?? []
        this.listCounts = allTodos.reduce((counts, todo) => {
          counts[todo.listName] = (counts[todo.listName] ?? 0) + 1
          return counts
        }, emptyListCounts())
        const known = new Set(this.lists.map((item) => item.name))
        for (const todo of allTodos) {
          if (!known.has(todo.listName)) {
            this.lists.push({ id: null, name: todo.listName, sortOrder: this.lists.length, protected: false })
            known.add(todo.listName)
          }
        }
        this.hasLoadedCounts = true
      } finally {
        this.countsLoading = false
      }
    },
    async refresh() {
      await this.load()
      await this.loadCounts().catch(() => undefined)
    },
    async create(payload: TodoPayload) {
      this.mutating = true
      try {
        const todo = await postTodo(payload)
        if (belongsToCurrentCollection(todo, this.currentView, this.query, this.currentListName)) {
          if (!this.todos.some((item) => item.id === todo.id)) this.todos.unshift(todo)
        }
        await this.loadCounts().catch(() => undefined)
        return todo
      } finally {
        this.mutating = false
      }
    },
    async createList(name: string) {
      const list = await postTodoList(name)
      if (!this.lists.some((item) => item.id === list.id || item.name === list.name)) this.lists.push(list)
      if (this.listCounts[list.name] === undefined) this.listCounts[list.name] = 0
      return list
    },
    async renameList(id: string, name: string): Promise<{ list: TodoList; previousName: string }> {
      const previous = this.lists.find((item) => item.id === id)
      const list = await putTodoList(id, name)
      const previousName = previous?.name ?? ''
      this.lists = this.lists.map((item) => item.id === id ? list : item)
      if (previousName && previousName !== list.name) {
        const nextCounts = { ...this.listCounts }
        nextCounts[list.name] = nextCounts[previousName] ?? 0
        delete nextCounts[previousName]
        this.listCounts = nextCounts
        this.todos.forEach((todo) => {
          if (todo.listName === previousName) todo.listName = list.name
        })
        if (this.currentListName === previousName) this.currentListName = list.name
      }
      return { list, previousName }
    },
    async deleteList(id: string): Promise<TodoListDeleteResult & { previousName: string }> {
      const previousName = this.lists.find((item) => item.id === id)?.name ?? ''
      const result = await deleteTodoList(id)
      this.lists = this.lists.filter((item) => item.id !== id)
      const nextCounts = { ...this.listCounts }
      const movedCount = nextCounts[previousName] ?? result.movedTaskCount
      delete nextCounts[previousName]
      nextCounts[result.fallbackListName] = (nextCounts[result.fallbackListName] ?? 0) + movedCount
      this.listCounts = nextCounts
      this.todos.forEach((todo) => {
        if (todo.listName === previousName) todo.listName = result.fallbackListName
      })
      if (this.currentListName === previousName) this.currentListName = result.fallbackListName
      return { ...result, previousName }
    },
    async update(id: string, payload: Partial<TodoPayload>) {
      this.mutating = true
      try {
        const index = this.todos.findIndex((item) => item.id === id)
        const previous = index >= 0 ? this.todos[index] : null
        const todo = await putTodo(id, payload)
        const belongs = belongsToCurrentCollection(todo, this.currentView, this.query, this.currentListName)
        if (index >= 0 && belongs) this.todos[index] = todo
        else if (index >= 0) this.todos.splice(index, 1)
        else if (belongs) this.todos.unshift(todo)
        if (!previous || previous.dueAt !== todo.dueAt || previous.listName !== todo.listName || previous.status !== todo.status) {
          await this.loadCounts().catch(() => undefined)
        }
        return todo
      } finally {
        this.mutating = false
      }
    },
    async complete(id: string) {
      this.mutating = true
      const previousTodos = this.todos.map(cloneTodo)
      const index = this.todos.findIndex((item) => item.id === id)
      const previous = index >= 0 ? this.todos[index] : null
      if (previous) this.todos[index] = optimisticCompletedTodo(previous)
      try {
        const result = await completeTodo(id)
        const resultIndex = this.todos.findIndex((item) => item.id === id)
        if (resultIndex >= 0) {
          if (shouldRetainAfterCompletion(result.todo, this.currentView)) this.todos[resultIndex] = result.todo
          else this.todos.splice(resultIndex, 1)
        }
        if (result.nextTodo && shouldInsertGeneratedTodo(result.nextTodo, this.currentView, this.query, this.currentListName)) {
          if (!this.todos.some((item) => item.id === result.nextTodo?.id)) this.todos.push(result.nextTodo)
        }
        await this.loadCounts().catch(() => undefined)
        return result
      } catch (error) {
        this.todos = previousTodos
        throw error
      } finally {
        this.mutating = false
      }
    },
    async restore(id: string) {
      this.mutating = true
      try {
        const todo = await restoreTodo(id)
        await this.refresh()
        return todo
      } finally {
        this.mutating = false
      }
    },
    async abandon(id: string) {
      this.mutating = true
      try {
        const todo = await abandonTodo(id)
        await this.refresh()
        return todo
      } finally {
        this.mutating = false
      }
    },
    async remove(id: string) {
      this.mutating = true
      try {
        await deleteTodo(id)
        await this.refresh()
      } finally {
        this.mutating = false
      }
    },
    async updateMyStatus(id: string, status: 'TODO' | 'IN_PROGRESS' | 'DONE') {
      this.mutating = true
      try {
        const todo = await putTaskMyStatus(id, status)
        await this.refresh()
        return todo
      } finally {
        this.mutating = false
      }
    },
    async updateAssignees(id: string, assigneeIds: string[]) {
      this.mutating = true
      try {
        const todo = await putTaskAssignees(id, assigneeIds)
        await this.refresh()
        return todo
      } finally {
        this.mutating = false
      }
    },
  },
})
