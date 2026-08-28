import { createPinia, setActivePinia } from 'pinia'
import { beforeEach, describe, expect, it, vi } from 'vitest'

import { fetchTodos, moveTodoToList, type Todo } from '@/services/api'
import { taskCountLabel } from '@/modules/todo/taskCounts'
import { isCompletedForCurrentUser, useTodoStore } from '@/stores/todos'

vi.mock('@/services/api', () => ({
  abandonTodo: vi.fn(),
  completeTodo: vi.fn(),
  deleteTodo: vi.fn(),
  fetchTodos: vi.fn(),
  postTodo: vi.fn(),
  putTaskAssignees: vi.fn(),
  putTaskMyStatus: vi.fn(),
  moveTodoToList: vi.fn(),
  restoreTodo: vi.fn(),
}))

const task = {
  id: 'task-1', title: '任务', description: '<p>旧正文</p>', contentJson: null,
  attachmentIds: [], status: 'TODO', priority: 'NONE', dueAt: '2026-08-10T00:00:00',
  dueEndAt: null, reminderAt: null, remindedAt: null, recurrenceType: 'NONE',
  recurrenceConfig: null, listName: '收集箱', tags: [], sourceType: 'MANUAL',
  sourceNoteId: null, sourceExcerpt: null, sources: [], recurringSeriesId: null, generatedFromId: null,
  creatorId: 'user-1', teamId: null, creator: {} as Todo['creator'], assignments: [],
  myAssignment: null, completedAssignments: 0, totalAssignments: 1,
  permissions: { editable: true, contentEditable: true, deletable: true, assignable: false, completable: true },
  completedAt: null, createdAt: '2026-08-10T00:00:00', updatedAt: '2026-08-10T00:00:00',
} satisfies Todo

describe('todo store list transaction', () => {
  beforeEach(() => {
    setActivePinia(createPinia())
    vi.clearAllMocks()
  })

  it('moves a task to another list without refreshing the task collection', async () => {
    const store = useTodoStore()
    store.todos = [{ ...task }]
    vi.mocked(moveTodoToList).mockResolvedValue({ ...task, listName: '工作' })
    const refresh = vi.spyOn(store, 'refresh').mockResolvedValue()

    await store.moveToList(task.id, '工作')

    expect(refresh).not.toHaveBeenCalled()
    expect(store.todos[0].listName).toBe('工作')
  })

  it('removes a moved task from a list-scoped collection', async () => {
    const store = useTodoStore()
    store.currentListName = '收集箱'
    store.todos = [{ ...task }]
    vi.mocked(moveTodoToList).mockResolvedValue({ ...task, listName: '工作' })
    const refresh = vi.spyOn(store, 'refresh').mockResolvedValue()
    vi.spyOn(store, 'loadCounts').mockResolvedValue()

    await store.moveToList(task.id, '工作')

    expect(refresh).not.toHaveBeenCalled()
    expect(store.todos).toEqual([])
  })

  it('counts a shared task as completed when only my assignment is done', () => {
    const sharedTask = {
      ...task,
      teamId: 'team-1',
      myAssignment: { status: 'DONE' },
    } as unknown as Todo

    expect(sharedTask.status).toBe('TODO')
    expect(isCompletedForCurrentUser(sharedTask)).toBe(true)
  })
})

describe('todo store initial load states', () => {
  beforeEach(() => {
    setActivePinia(createPinia())
    vi.clearAllMocks()
  })

  it('starts in a truthful loading state and exposes successful data only after resolution', async () => {
    let resolveRequest!: (todos: Todo[]) => void
    vi.mocked(fetchTodos).mockReturnValue(new Promise((resolve) => { resolveRequest = resolve }))
    const store = useTodoStore()

    expect(store.loading).toBe(true)
    expect(store.hasLoaded).toBe(false)
    const request = store.load('today')
    expect(store.loading).toBe(true)

    resolveRequest([task])
    await request
    expect(store.todos).toEqual([task])
    expect(store.loading).toBe(false)
    expect(store.hasLoaded).toBe(true)
    expect(store.error).toBeNull()
  })

  it('marks an empty successful response as loaded instead of failed', async () => {
    vi.mocked(fetchTodos).mockResolvedValue([])
    const store = useTodoStore()

    await store.load('today')

    expect(store.todos).toEqual([])
    expect(store.hasLoaded).toBe(true)
    expect(store.error).toBeNull()
  })

  it('exposes a retryable error state after a failed response', async () => {
    vi.mocked(fetchTodos).mockRejectedValue(new Error('offline'))
    const store = useTodoStore()

    await expect(store.load('today')).rejects.toThrow('offline')

    expect(store.loading).toBe(false)
    expect(store.hasLoaded).toBe(true)
    expect(store.error).toContain('无法读取待办')
  })
})

describe('todo list count truthfulness', () => {
  beforeEach(() => {
    setActivePinia(createPinia())
    vi.clearAllMocks()
  })

  it('shows an initial list count as unknown instead of a fake zero', () => {
    const store = useTodoStore()

    expect(store.hasLoadedCounts).toBe(false)
    expect(taskCountLabel(store.hasLoadedCounts, store.listCounts['收集箱'])).toBe('—')
  })

  it('keeps the list count unknown when the first count request fails', async () => {
    vi.mocked(fetchTodos).mockRejectedValue(new Error('offline'))
    const store = useTodoStore()

    await expect(store.loadCounts()).rejects.toThrow('offline')

    expect(store.hasLoadedCounts).toBe(false)
    expect(taskCountLabel(store.hasLoadedCounts, store.listCounts['收集箱'])).toBe('—')
  })

  it('shows a confirmed real zero after counts load successfully', async () => {
    vi.mocked(fetchTodos).mockResolvedValue([])
    const store = useTodoStore()

    await store.loadCounts()

    expect(store.hasLoadedCounts).toBe(true)
    expect(taskCountLabel(store.hasLoadedCounts, store.listCounts['收集箱'])).toBe('0')
  })
})
