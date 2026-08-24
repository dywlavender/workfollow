import {
  fetchNotes,
  fetchTodos,
  type NoteListItem,
  type Todo,
} from '@/services/api'

// This is an intent window, not a general-purpose data cache. It only keeps
// a prefetched result long enough for a hover/focus followed by navigation.
const PREFETCH_TTL_MS = 8_000

interface PrefetchState<T> {
  value: T | null
  expiresAt: number
  promise: Promise<T> | null
}

function createState<T>(): PrefetchState<T> {
  return { value: null, expiresAt: 0, promise: null }
}

const notesState = createState<NoteListItem[]>()
const calendarTodosState = createState<Todo[]>()

function startPrefetch<T>(state: PrefetchState<T>, loader: () => Promise<T>): Promise<T> {
  if (state.promise) return state.promise
  if (state.value !== null && state.expiresAt > Date.now()) return Promise.resolve(state.value)

  const promise = loader()
    .then((value) => {
      state.value = value
      state.expiresAt = Date.now() + PREFETCH_TTL_MS
      return value
    })
    .catch((cause) => {
      state.value = null
      state.expiresAt = 0
      throw cause
    })
    .finally(() => {
      state.promise = null
    })
  state.promise = promise
  return promise
}

function consumePrefetch<T>(state: PrefetchState<T>, loader: () => Promise<T>): Promise<T> {
  if (state.value !== null && state.expiresAt > Date.now()) {
    const value = state.value
    state.value = null
    state.expiresAt = 0
    return Promise.resolve(value)
  }
  if (state.value !== null) {
    state.value = null
    state.expiresAt = 0
  }
  if (state.promise) {
    const pending = state.promise
    return pending.then((value) => {
      state.value = null
      state.expiresAt = 0
      return value
    })
  }
  return loader()
}

export function prefetchNotesList() {
  void startPrefetch(notesState, () => fetchNotes({})).catch(() => undefined)
}

export function consumePrefetchedNotesList(): Promise<NoteListItem[]> {
  return consumePrefetch(notesState, () => fetchNotes({}))
}

export function prefetchCalendarTodos() {
  void startPrefetch(calendarTodosState, () => fetchTodos()).catch(() => undefined)
}

export function consumePrefetchedCalendarTodos(): Promise<Todo[]> {
  return consumePrefetch(calendarTodosState, () => fetchTodos())
}
