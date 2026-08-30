import {
  fetchFolders,
  fetchNote,
  fetchNotes,
  fetchTodoLists,
  fetchTodos,
  type Folder,
  type Note,
  type Todo,
  type TodoList,
} from './api'

/**
 * The Web → desktop hand-off is deliberately versioned.  The desktop app can
 * reject a future format instead of silently importing a partial data set.
 */
export const PERSONAL_MIGRATION_FORMAT = 'workfollow-personal-migration'
export const PERSONAL_MIGRATION_SCHEMA_VERSION = 1

export interface PersonalMigrationTask {
  id: string
  title: string
  description: string | null
  contentJson: Record<string, unknown> | null
  status: Todo['status']
  priority: Todo['priority']
  dueAt: string | null
  dueEndAt: string | null
  reminderAt: string | null
  recurrenceType: Todo['recurrenceType']
  recurrenceConfig: Todo['recurrenceConfig']
  listName: string
  tags: string[]
  createdAt: string
  updatedAt: string
  completedAt: string | null
}

export interface PersonalMigrationNote {
  id: string
  folderId: string | null
  title: string
  contentJson: Record<string, unknown>
  plainText: string
  isFavorite: boolean
  createdAt: string
  updatedAt: string
  deletedAt: string | null
}

export interface PersonalMigrationBundle {
  format: typeof PERSONAL_MIGRATION_FORMAT
  schemaVersion: typeof PERSONAL_MIGRATION_SCHEMA_VERSION
  exportedAt: string
  source: {
    product: 'workfollow-web'
    scope: 'personal'
  }
  lists: TodoList[]
  folders: Folder[]
  tasks: PersonalMigrationTask[]
  notes: PersonalMigrationNote[]
}

async function fetchAllPersonalNotes(): Promise<Note[]> {
  const pageSize = 500
  const noteItems = [] as Awaited<ReturnType<typeof fetchNotes>>
  let offset = 0
  while (true) {
    const page = await fetchNotes({ limit: pageSize, offset })
    noteItems.push(...page)
    if (page.length < pageSize) break
    offset += pageSize
  }

  // The list endpoint intentionally stays lightweight.  Fetch the editor
  // payloads only after the complete list is known, so the exported bundle is
  // self-contained and can be imported without a network connection.
  return Promise.all(noteItems.map((note) => fetchNote(note.id)))
}

function toMigrationTask(todo: Todo): PersonalMigrationTask {
  return {
    id: todo.id,
    title: todo.title,
    description: todo.description,
    contentJson: todo.contentJson,
    status: todo.status,
    priority: todo.priority,
    dueAt: todo.dueAt,
    dueEndAt: todo.dueEndAt,
    reminderAt: todo.reminderAt,
    recurrenceType: todo.recurrenceType,
    recurrenceConfig: todo.recurrenceConfig,
    listName: todo.listName,
    tags: [...todo.tags],
    createdAt: todo.createdAt,
    updatedAt: todo.updatedAt,
    completedAt: todo.completedAt,
  }
}

function toMigrationNote(note: Note): PersonalMigrationNote {
  return {
    id: note.id,
    folderId: note.folderId,
    title: note.title,
    contentJson: note.contentJson,
    plainText: note.plainText,
    isFavorite: note.isFavorite,
    createdAt: note.createdAt,
    updatedAt: note.updatedAt,
    deletedAt: note.deletedAt,
  }
}

export async function buildPersonalMigrationBundle(): Promise<PersonalMigrationBundle> {
  const [todos, lists, folders, notes] = await Promise.all([
    fetchTodos('all'),
    fetchTodoLists(),
    fetchFolders(),
    fetchAllPersonalNotes(),
  ])

  // /tasks/all is intentionally shared by the Web UI.  Filter here rather
  // than relying on a server-side view so a team task can never leak into the
  // personal desktop package.
  const personalTasks = todos.filter((todo) => !todo.teamId && todo.sourceType !== 'TEAM')

  return {
    format: PERSONAL_MIGRATION_FORMAT,
    schemaVersion: PERSONAL_MIGRATION_SCHEMA_VERSION,
    exportedAt: new Date().toISOString(),
    source: { product: 'workfollow-web', scope: 'personal' },
    lists: lists.map((list) => ({ ...list })),
    folders: folders.map((folder) => ({ ...folder })),
    tasks: personalTasks.map(toMigrationTask),
    notes: notes.map(toMigrationNote),
  }
}

export function downloadPersonalMigrationBundle(bundle: PersonalMigrationBundle): void {
  const date = new Date().toISOString().slice(0, 10)
  const blob = new Blob([JSON.stringify(bundle, null, 2)], { type: 'application/json' })
  const url = URL.createObjectURL(blob)
  const anchor = document.createElement('a')
  anchor.href = url
  anchor.download = `workfollow-personal-${date}.workfollow.json`
  document.body.appendChild(anchor)
  anchor.click()
  anchor.remove()
  window.setTimeout(() => URL.revokeObjectURL(url), 0)
}
