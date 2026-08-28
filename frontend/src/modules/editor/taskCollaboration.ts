import { HocuspocusProvider, HocuspocusProviderWebsocket, type WebSocketStatus } from '@hocuspocus/provider'
import * as Y from 'yjs'
import { IndexeddbPersistence } from 'y-indexeddb'

import type { User } from '@/services/api'

export type TaskCollaborationStatus = 'connecting' | 'connected' | 'disconnected' | 'error'
export type TaskCollaborationDocumentKind = 'body' | 'metadata'

export interface TaskCollaborationCallbacks {
  onStatus?: (status: TaskCollaborationStatus) => void
  onSynced?: () => void
  onError?: (message: string) => void
  onUnsyncedChanges?: (count: number) => void
}

export interface TaskCollaborationSession {
  document: Y.Doc
  provider: HocuspocusProvider
  persistence: IndexeddbPersistence | null
  destroy: () => void
}

// The previous cache namespace was created before collaboration startup was
// gated on IndexedDB.  A fresh namespace prevents stale initialization
// updates from being merged into the server document after this fix.
// v3 invalidates caches written before the authoritative initialization and
// projection barriers were in place. Reusing those updates can make a task
// opening look like a user edit and reintroduce the overwrite race.
const COLLABORATION_CACHE_VERSION = 'v3'
// A slow IndexedDB transaction must not race the authoritative server state.
// Fifteen seconds is long enough for a cold browser profile while still
// leaving a bounded fallback if IndexedDB is unavailable altogether.
const PERSISTENCE_WAIT_TIMEOUT_MS = 15000

function websocketUrl(): string {
  const configured = String(import.meta.env.VITE_COLLABORATION_URL ?? '').trim()
  if (configured) {
    if (/^wss?:\/\//i.test(configured)) return configured
    return `${window.location.protocol === 'https:' ? 'wss:' : 'ws:'}//${window.location.host}${configured.startsWith('/') ? configured : `/${configured}`}`
  }
  if (import.meta.env.DEV) {
    // The Vite dev server proxies this same-origin path to Hocuspocus. Using a
    // same-origin URL also lets the browser attach the existing HttpOnly
    // session cookie without exposing it to JavaScript.
    return `${window.location.protocol === 'https:' ? 'wss:' : 'ws:'}//${window.location.host}/collaboration`
  }

  // The packaged SPA is served by FastAPI on one port while the local
  // Hocuspocus process listens on the collaboration port. Cookies are scoped
  // to the host rather than the port, so the existing session is still sent.
  const target = new URL(window.location.href)
  target.port = String(import.meta.env.VITE_COLLABORATION_PORT ?? '8124')
  return `${target.protocol === 'https:' ? 'wss:' : 'ws:'}//${target.host}/collaboration`
}

function normalizeStatus(status: WebSocketStatus | string): TaskCollaborationStatus {
  if (status === 'connected') return 'connected'
  if (status === 'connecting') return 'connecting'
  return 'disconnected'
}

export function createTaskCollaboration(
  taskId: string,
  user: User | null | undefined,
  callbacks: TaskCollaborationCallbacks = {},
  kind: TaskCollaborationDocumentKind = 'body',
): TaskCollaborationSession {
  const document = new Y.Doc()
  let persistence: IndexeddbPersistence | null = null
  if (typeof indexedDB !== 'undefined') {
    persistence = new IndexeddbPersistence(`workfollow-task-${COLLABORATION_CACHE_VERSION}-${kind}-${taskId}`, document)
  }

  // Do not let the websocket handshake race IndexedDB hydration.  If both
  // happen at once, a stale local seed and the trusted server seed become two
  // independent Y.Text/Y.Array inserts, which looks like a user edit and is
  // projected back to SQL when the task is merely opened or switched away.
  const websocketProvider = new HocuspocusProviderWebsocket({
    url: websocketUrl(),
    autoConnect: false,
  })
  const provider = new HocuspocusProvider({
    websocketProvider,
    name: kind === 'metadata' ? `task-meta:${taskId}` : `task:${taskId}`,
    document,
    token: null,
    sessionAwareness: false,
    flushDelay: 120,
    onStatus: ({ status }) => callbacks.onStatus?.(normalizeStatus(status)),
    onSynced: () => callbacks.onSynced?.(),
    onAuthenticationFailed: ({ reason }) => {
      callbacks.onStatus?.('error')
      callbacks.onError?.(reason || '协同认证失败')
    },
    onUnsyncedChanges: ({ number }) => callbacks.onUnsyncedChanges?.(number),
  })

  let destroyed = false
  let connectionStarted = false
  let persistenceWaitTimer: ReturnType<typeof setTimeout> | undefined
  const startConnection = () => {
    if (destroyed || connectionStarted) return
    connectionStarted = true
    if (persistenceWaitTimer) clearTimeout(persistenceWaitTimer)
    provider.attach()
    void websocketProvider.connect().catch(() => undefined)
  }
  if (persistence) {
    void persistence.whenSynced.then(startConnection).catch(startConnection)
    // IndexedDB should hydrate quickly.  This fallback keeps a blocked or
    // unavailable browser database from preventing collaboration forever.
    persistenceWaitTimer = setTimeout(startConnection, PERSISTENCE_WAIT_TIMEOUT_MS)
  } else {
    startConnection()
  }

  if (user) {
    provider.setAwarenessField('user', {
      id: user.id,
      name: user.nickname || user.username,
    })
  }

  return {
    document,
    provider,
    persistence,
    destroy: () => {
      destroyed = true
      if (persistenceWaitTimer) clearTimeout(persistenceWaitTimer)
      provider.flushPendingUpdates()
      provider.destroy()
      // A custom websocket provider is not owned by HocuspocusProvider, so it
      // must be closed explicitly after the provider detaches.
      websocketProvider.destroy()
      // IndexeddbPersistence listens to the Y.Doc destroy event and closes
      // its database there; destroying it twice can race a tab switch.
      document.destroy()
    },
  }
}
