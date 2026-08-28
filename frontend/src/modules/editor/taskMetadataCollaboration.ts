import * as Y from 'yjs'

import { fetchTodo, type Todo, type TodoPayload } from '@/services/api'
import { initializeCollaborativeField } from './collaborationInitialization'
import { createTaskCollaboration, type TaskCollaborationSession } from './taskCollaboration'

type MetadataField = 'priority' | 'dueAt' | 'dueEndAt' | 'reminderAt' | 'recurrenceType' | 'recurrenceConfig'
type MetadataPatch = Pick<TodoPayload, 'title' | 'priority' | 'dueAt' | 'dueEndAt' | 'reminderAt' | 'recurrenceType' | 'recurrenceConfig' | 'tags'>

export type TaskMetadataCollaborationResult = 'updated' | 'unavailable'

const metadataFields: MetadataField[] = [
  'priority', 'dueAt', 'dueEndAt', 'reminderAt', 'recurrenceType', 'recurrenceConfig',
]

function seedMetadataDocument(task: Todo, document: Y.Doc, initial?: Record<string, unknown>) {
  const metadata = document.getMap<unknown>('metadata')
  const title = document.getText('title')
  const tags = document.getArray<string>('tags')
  const source = initial && typeof initial === 'object' ? { ...task, ...initial } as Todo : task
  document.transact(() => {
    metadata.set('initialized', true)
    if (title.length === 0 && source.title) title.insert(0, source.title)
    const values: Record<MetadataField, unknown> = {
      priority: source.priority,
      dueAt: source.dueAt,
      dueEndAt: source.dueEndAt,
      reminderAt: source.reminderAt,
      recurrenceType: source.recurrenceType,
      recurrenceConfig: source.recurrenceConfig,
    }
    metadataFields.forEach((key) => {
      if (!metadata.has(key)) metadata.set(key, values[key])
    })
    if (tags.length === 0 && source.tags.length > 0) tags.push(source.tags)
  }, 'workfollow-metadata-seed')
}

function replaceText(target: Y.Text, value: string) {
  const current = target.toString()
  if (current === value) return
  let start = 0
  while (start < current.length && start < value.length && current[start] === value[start]) start += 1
  let currentEnd = current.length
  let nextEnd = value.length
  while (currentEnd > start && nextEnd > start && current[currentEnd - 1] === value[nextEnd - 1]) {
    currentEnd -= 1
    nextEnd -= 1
  }
  if (currentEnd > start) target.delete(start, currentEnd - start)
  if (nextEnd > start) target.insert(start, value.slice(start, nextEnd))
}

function applyMetadataPatch(document: Y.Doc, patch: Partial<MetadataPatch>) {
  const metadata = document.getMap<unknown>('metadata')
  document.transact(() => {
    if (patch.title !== undefined) replaceText(document.getText('title'), patch.title.trim())
    metadataFields.forEach((key) => {
      if (patch[key] !== undefined) metadata.set(key, patch[key] ?? null)
    })
    if (patch.tags !== undefined) {
      const tags = document.getArray<string>('tags')
      const normalized = [...new Set(patch.tags.map((tag) => tag.trim().replace(/^#/, '')).filter(Boolean))]
      if (tags.length > 0) tags.delete(0, tags.length)
      if (normalized.length > 0) tags.push(normalized)
    }
  }, 'workfollow-metadata-input')
}

function hasMetadataPatch(patch: Partial<TodoPayload>): boolean {
  return ['title', 'priority', 'dueAt', 'dueEndAt', 'reminderAt', 'recurrenceType', 'recurrenceConfig', 'tags']
    .some((key) => key in patch)
}

function sameDateValue(actual: string | null, expected: string | null | undefined): boolean {
  if (expected === undefined) return true
  if (actual === expected) return true
  if (actual === null || expected === null) return false
  const actualTime = Date.parse(actual)
  const expectedTime = Date.parse(expected)
  return Number.isFinite(actualTime) && Number.isFinite(expectedTime) && actualTime === expectedTime
}

function sameMetadataValue(todo: Todo, key: string, expected: unknown): boolean {
  if (key === 'title') return todo.title === String(expected ?? '').trim()
  if (key === 'dueAt' || key === 'dueEndAt' || key === 'reminderAt') {
    return sameDateValue(todo[key], expected as string | null | undefined)
  }
  if (key === 'recurrenceConfig') return JSON.stringify(todo.recurrenceConfig) === JSON.stringify(expected ?? null)
  if (key === 'tags') {
    const actual = [...new Set(todo.tags.map((tag) => tag.trim().replace(/^#/, '')))].sort()
    const wanted = [...new Set((Array.isArray(expected) ? expected : []).map((tag) => String(tag).trim().replace(/^#/, '')).filter(Boolean))].sort()
    return JSON.stringify(actual) === JSON.stringify(wanted)
  }
  return todo[key as keyof Todo] === expected
}

function metadataMatches(todo: Todo, patch: Partial<TodoPayload>): boolean {
  return Object.entries(patch).every(([key, value]) => sameMetadataValue(todo, key, value))
}

function tagOperationMatches(todo: Todo, operation: TaskTagAction, tag: string): boolean {
  const actual = todo.tags
    .map((item) => item.trim().replace(/^#/, ''))
    .filter(Boolean)
  // Verification is intentionally predicate-based rather than comparing the
  // whole array captured before the operation. Another editor may add a
  // different tag during the projection window; that must not make this
  // successful add/remove action appear to have failed.
  return operation.action === 'add' ? actual.includes(tag) : !actual.includes(tag)
}

/**
 * Apply an explicit metadata action through the same Yjs document used by the
 * task detail editor. This helper is intentionally one-shot: it opens a
 * metadata provider, waits for the authoritative state, applies the patch,
 * flushes the update, then releases the provider. It never falls back to an
 * normal task-update request, because that would reintroduce the split-brain
 * overwrite race.
 */
export async function updateTaskMetadataCollaboratively(
  task: Todo,
  patch: Partial<TodoPayload>,
  // The shared provider waits for IndexedDB hydration before opening the
  // socket.  Five seconds was shorter than that deliberate race barrier and
  // made the first date/priority edit fail on a cold browser profile.
  timeoutMs = 20_000,
): Promise<TaskMetadataCollaborationResult> {
  if (!hasMetadataPatch(patch)) return 'unavailable'
  // Read-only members may still have a live metadata document for viewing.
  // Never treat a local Y.Doc mutation as a successful metadata action when
  // the task permission says this user cannot edit task properties.
  if (!task.permissions.editable) return 'unavailable'

  let session: TaskCollaborationSession | null = null
  let finished = false
  let timeout: ReturnType<typeof setTimeout> | undefined

  return new Promise((resolve) => {
    const finish = (result: TaskMetadataCollaborationResult) => {
      if (finished) return
      finished = true
      if (timeout) clearTimeout(timeout)
      session?.destroy()
      resolve(result)
    }

    timeout = setTimeout(() => finish('unavailable'), timeoutMs)
    session = createTaskCollaboration(task.id, null, {
      onSynced: () => {
        if (!session || finished) return
        void initializeCollaborativeField(
          `task-meta:${task.id}`,
          'metadata',
          (initial) => seedMetadataDocument(task, session!.document, initial),
        ).then(() => {
          if (!session || finished) return
          applyMetadataPatch(session.document, patch)
          session.provider.flushPendingUpdates()
          // The provider flush only confirms that the browser handed the update
          // to WebSocket. Wait for the authoritative SQL projection before
          // reporting success to callers that immediately refresh their lists.
          const deadline = Date.now() + timeoutMs
          const verifyProjection = async () => {
            while (!finished && Date.now() < deadline) {
              try {
                const latest = await fetchTodo(task.id)
                if (metadataMatches(latest, patch)) {
                  finish('updated')
                  return
                }
              } catch {
                // Keep polling until the same timeout used for the collaboration
                // connection; transient reads should not create a false error.
              }
              await new Promise((resolveWait) => setTimeout(resolveWait, 180))
            }
            finish('unavailable')
          }
          void verifyProjection()
        }).catch(() => finish('unavailable'))
      },
      onError: () => finish('unavailable'),
    }, 'metadata')
  })
}

export type TaskTagAction = { action: 'add' | 'remove'; tag: string }

/**
 * Apply a tag operation against the current shared array instead of replacing
 * the whole array received from a potentially stale task-list row. This keeps
 * two quick add/remove actions composable when several tabs are open.
 */
export async function updateTaskTagCollaboratively(
  task: Todo,
  operation: TaskTagAction,
  timeoutMs = 20_000,
): Promise<TaskMetadataCollaborationResult> {
  const tag = operation.tag.trim().replace(/^#/, '')
  if (!tag || !task.permissions.editable) return 'unavailable'

  let session: TaskCollaborationSession | null = null
  let finished = false
  let timeout: ReturnType<typeof setTimeout> | undefined

  return new Promise((resolve) => {
    const finish = (result: TaskMetadataCollaborationResult) => {
      if (finished) return
      finished = true
      if (timeout) clearTimeout(timeout)
      session?.destroy()
      resolve(result)
    }
    timeout = setTimeout(() => finish('unavailable'), timeoutMs)
    session = createTaskCollaboration(task.id, null, {
      onSynced: () => {
        if (!session || finished) return
        void initializeCollaborativeField(
          `task-meta:${task.id}`,
          'metadata',
          (initial) => seedMetadataDocument(task, session!.document, initial),
        ).then(() => {
          if (!session || finished) return
          const tags = session.document.getArray<string>('tags')
          const normalized = tags.toArray().map((value) => String(value).trim().replace(/^#/, '')).filter(Boolean)
          session.document.transact(() => {
            if (operation.action === 'add') {
              if (!normalized.includes(tag)) tags.push([tag])
            } else {
              for (let index = tags.length - 1; index >= 0; index -= 1) {
                if (String(tags.get(index)).trim().replace(/^#/, '') === tag) tags.delete(index, 1)
              }
            }
          }, 'workfollow-metadata-tag-action')
          session.provider.flushPendingUpdates()
          const deadline = Date.now() + timeoutMs
          const verifyProjection = async () => {
            while (!finished && Date.now() < deadline) {
              try {
                const latest = await fetchTodo(task.id)
                if (tagOperationMatches(latest, operation, tag)) {
                  finish('updated')
                  return
                }
              } catch {
                // Continue until the bounded timeout.
              }
              await new Promise((resolveWait) => setTimeout(resolveWait, 180))
            }
            finish('unavailable')
          }
          void verifyProjection()
        }).catch(() => finish('unavailable'))
      },
      onError: () => finish('unavailable'),
    }, 'metadata')
  })
}
