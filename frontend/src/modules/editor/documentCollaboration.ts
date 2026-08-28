import { HocuspocusProvider, HocuspocusProviderWebsocket, type WebSocketStatus } from '@hocuspocus/provider'
import * as Y from 'yjs'
import { IndexeddbPersistence } from 'y-indexeddb'

import type { User } from '@/services/api'

export type DocumentCollaborationStatus = 'connecting' | 'connected' | 'disconnected' | 'error'

export interface DocumentCollaborationCallbacks {
  onStatus?: (status: DocumentCollaborationStatus) => void
  onSynced?: () => void
  onError?: (message: string) => void
  onUnsyncedChanges?: (count: number) => void
}

export interface DocumentCollaborationSession {
  document: Y.Doc
  provider: HocuspocusProvider
  persistence: IndexeddbPersistence | null
  destroy: () => void
}

// The first collaboration rollout persisted local seed transactions before
// the server-authoritative initialization handshake existed.  Reusing those
// updates can recreate the exact duplicate/overwrite race we are trying to
// remove, so personal notes need the same versioned cache namespace as tasks.
// Bump this namespace whenever the SQL -> Y.Doc bootstrap contract changes.
// Old caches may contain a pre-authoritative seed and must not be merged into
// the corrected server document on the first load after an upgrade.
const COLLABORATION_CACHE_VERSION = 'v3'
const PERSISTENCE_WAIT_TIMEOUT_MS = 15000

function websocketUrl(): string {
  const configured = String(import.meta.env.VITE_COLLABORATION_URL ?? '').trim()
  if (configured) {
    if (/^wss?:\/\//i.test(configured)) return configured
    return `${window.location.protocol === 'https:' ? 'wss:' : 'ws:'}//${window.location.host}${configured.startsWith('/') ? configured : `/${configured}`}`
  }
  if (import.meta.env.DEV) {
    return `${window.location.protocol === 'https:' ? 'wss:' : 'ws:'}//${window.location.host}/collaboration`
  }
  const target = new URL(window.location.href)
  target.port = String(import.meta.env.VITE_COLLABORATION_PORT ?? '8124')
  return `${target.protocol === 'https:' ? 'wss:' : 'ws:'}//${target.host}/collaboration`
}

function normalizeStatus(status: WebSocketStatus | string): DocumentCollaborationStatus {
  if (status === 'connected') return 'connected'
  if (status === 'connecting') return 'connecting'
  return 'disconnected'
}

export function createDocumentCollaboration(
  documentName: string,
  persistenceName: string,
  user: User | null | undefined,
  callbacks: DocumentCollaborationCallbacks = {},
): DocumentCollaborationSession {
  const document = new Y.Doc()
  let persistence: IndexeddbPersistence | null = null
  if (typeof indexedDB !== 'undefined') persistence = new IndexeddbPersistence(persistenceName, document)

  // Hydrate the local document before opening the socket. Otherwise a stale
  // local seed can race the server snapshot and become a second Yjs insert.
  const websocketProvider = new HocuspocusProviderWebsocket({
    url: websocketUrl(),
    autoConnect: false,
  })
  const provider = new HocuspocusProvider({
    websocketProvider,
    name: documentName,
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
    persistenceWaitTimer = setTimeout(startConnection, PERSISTENCE_WAIT_TIMEOUT_MS)
  } else {
    startConnection()
  }

  if (user) {
    provider.setAwarenessField('user', { id: user.id, name: user.nickname || user.username })
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
      websocketProvider.destroy()
      document.destroy()
    },
  }
}

export function createNoteCollaboration(
  noteId: string,
  user: User | null | undefined,
  callbacks: DocumentCollaborationCallbacks = {},
): DocumentCollaborationSession {
  return createDocumentCollaboration(
    `note:${noteId}`,
    `workfollow-note-${COLLABORATION_CACHE_VERSION}-${noteId}`,
    user,
    callbacks,
  )
}

export function createKnowledgeDraftCollaboration(
  noteId: string,
  user: User | null | undefined,
  callbacks: DocumentCollaborationCallbacks = {},
  baseVersion?: number,
): DocumentCollaborationSession {
  // A knowledge draft is reset when a published version is committed. Keep
  // IndexedDB names version-scoped so a browser that last opened V1 cannot
  // merge that old draft into the server's V2 document during the next load.
  // The Hocuspocus document name remains stable; this only scopes local cache.
  const versionKey = Number.isFinite(baseVersion) ? `-${Math.max(0, Math.trunc(baseVersion as number))}` : ''
  return createDocumentCollaboration(
    `knowledge-draft:${noteId}`,
    `workfollow-knowledge-draft-${COLLABORATION_CACHE_VERSION}-${noteId}${versionKey}`,
    user,
    callbacks,
  )
}
