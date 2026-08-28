import { defineStore } from 'pinia'

import { fetchUnreadNotificationCount } from '@/services/api'

export type RealtimeStatus = 'idle' | 'connecting' | 'open' | 'reconnecting'

export interface TaskChangedBrief {
  taskId: string
  title: string
  status: 'TODO' | 'DONE' | 'ABANDONED'
  priority: 'NONE' | 'LOW' | 'MEDIUM' | 'HIGH'
  dueAt: string | null
  dueEndAt: string | null
  assigneeIds: string[]
  updatedAt: string | null
  deleted: boolean
}

export interface TaskChangedEvent {
  taskId: string
  brief: Omit<TaskChangedBrief, 'taskId'>
}

export interface TeamNoteChangedEvent {
  teamId: string
  noteId: string
  title: string
  categoryId: string | null
  status: 'PUBLISHED' | 'ARCHIVED' | 'DELETED'
  updatedAt: string | null
}

export interface NoteChangedEvent {
  noteId: string
  title: string
  folderId?: string | null
  isFavorite?: boolean
  updatedAt: string | null
  deleted: boolean
}

export interface TodoListChangedEvent {
  action: 'CREATED' | 'RENAMED' | 'DELETED'
  name: string
  previousName: string | null
}

let source: EventSource | null = null
let connectedUserId: string | null = null

function eventsUrl(): string {
  const base = import.meta.env.VITE_API_BASE_URL ?? '/api'
  return new URL(`${base.replace(/\/$/, '')}/events`, window.location.origin).toString()
}

export const useRealtimeStore = defineStore('realtime', {
  state: () => ({
    status: 'idle' as RealtimeStatus,
    unreadCount: 0,
    reconnectGeneration: 0,
    lastTaskChange: null as TaskChangedEvent | null,
    lastNoteChange: null as NoteChangedEvent | null,
    lastTeamNoteChange: null as TeamNoteChangedEvent | null,
    lastTodoListChange: null as TodoListChangedEvent | null,
  }),
  actions: {
    async refreshUnreadCount() {
      try {
        this.unreadCount = await fetchUnreadNotificationCount()
      } catch {
        // The last known count is more useful than clearing the badge while offline.
      }
    },
    connect(userId: string) {
      if (connectedUserId === userId && source) return
      this.disconnect()
      connectedUserId = userId
      this.status = 'connecting'
      source = new EventSource(eventsUrl(), { withCredentials: true })
      source.addEventListener('open', () => {
        const wasOffline = this.status === 'reconnecting'
        this.status = 'open'
        if (wasOffline) this.reconnectGeneration += 1
        void this.refreshUnreadCount()
      })
      source.addEventListener('error', () => {
        if (source) this.status = 'reconnecting'
      })
      source.addEventListener('notification.count', (event) => {
        const data = JSON.parse((event as MessageEvent<string>).data) as { count?: number }
        if (typeof data.count === 'number') this.unreadCount = Math.max(0, data.count)
      })
      source.addEventListener('task.changed', (event) => {
        this.lastTaskChange = JSON.parse((event as MessageEvent<string>).data) as TaskChangedEvent
      })
      source.addEventListener('note.changed', (event) => {
        this.lastNoteChange = JSON.parse((event as MessageEvent<string>).data) as NoteChangedEvent
      })
      source.addEventListener('team_note.changed', (event) => {
        this.lastTeamNoteChange = JSON.parse((event as MessageEvent<string>).data) as TeamNoteChangedEvent
      })
      source.addEventListener('todo_list.changed', (event) => {
        this.lastTodoListChange = JSON.parse((event as MessageEvent<string>).data) as TodoListChangedEvent
      })
    },
    disconnect() {
      source?.close()
      source = null
      connectedUserId = null
      this.status = 'idle'
      this.lastTaskChange = null
      this.lastNoteChange = null
      this.lastTeamNoteChange = null
      this.lastTodoListChange = null
    },
  },
})
