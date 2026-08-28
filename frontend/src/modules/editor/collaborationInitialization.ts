export type CollaborationInitializationField = 'body' | 'metadata'

export type CollaborationInitializationResult =
  | { status: 'initialized' }
  | { status: 'waiting' }
  | { status: 'readonly' }
  | { status: 'claim'; token: string; initial?: Record<string, unknown> }

export class CollaborationInitializationError extends Error {
  readonly kind: 'auth' | 'network' | 'server'

  constructor(message: string, kind: 'auth' | 'network' | 'server') {
    super(message)
    this.name = 'CollaborationInitializationError'
    this.kind = kind
  }
}

function collaborationHttpBase(): string {
  const configured = String(import.meta.env.VITE_COLLABORATION_URL ?? '').trim()
  if (configured) {
    if (/^wss?:\/\//i.test(configured)) return configured.replace(/^ws/i, 'http')
    return `${window.location.protocol}//${window.location.host}${configured.startsWith('/') ? configured : `/${configured}`}`
  }
  if (import.meta.env.DEV) return `${window.location.protocol}//${window.location.host}/collaboration`
  const target = new URL(window.location.href)
  target.port = String(import.meta.env.VITE_COLLABORATION_PORT ?? '8124')
  return `${target.protocol}//${target.host}`
}

function wait(milliseconds: number): Promise<void> {
  return new Promise((resolve) => window.setTimeout(resolve, milliseconds))
}

async function claimOnce(
  documentName: string,
  field: CollaborationInitializationField,
): Promise<CollaborationInitializationResult> {
  let response: Response
  try {
    response = await fetch(`${collaborationHttpBase()}/initialize`, {
      method: 'POST',
      credentials: 'include',
      headers: { 'content-type': 'application/json' },
      body: JSON.stringify({ documentName, field }),
    })
  } catch {
    throw new CollaborationInitializationError('协同初始化服务不可达', 'network')
  }

  if (response.status === 401 || response.status === 403) {
    throw new CollaborationInitializationError('协同初始化认证失败', 'auth')
  }
  if (response.status === 409) return { status: 'waiting' }
  if (!response.ok) {
    throw new CollaborationInitializationError(`协同初始化失败（${response.status}）`, 'server')
  }
  try {
    return await response.json() as CollaborationInitializationResult
  } catch {
    throw new CollaborationInitializationError('协同初始化响应无效', 'server')
  }
}

/**
 * Serialize the one-time SQL -> Y.Doc bootstrap. Exactly one editable client
 * receives `claim`; all other clients wait for that claimer's Yjs update. The
 * callback must seed only the requested field and should use the returned SQL
 * snapshot when one is provided.
 */
export async function initializeCollaborativeField(
  documentName: string,
  field: CollaborationInitializationField,
  seed: (initial: Record<string, unknown> | undefined) => void,
  // The server claim is intentionally longer than a normal request so a
  // second client can take over only after the first claimant has genuinely
  // disappeared.  Match that bounded hand-off window here.
  timeoutMs = 20_000,
): Promise<'initialized' | 'seeded'> {
  const deadline = Date.now() + timeoutMs
  while (Date.now() < deadline) {
    const result = await claimOnce(documentName, field)
    if (result.status === 'initialized') return 'initialized'
    if (result.status === 'readonly') return 'initialized'
    if (result.status === 'claim') {
      seed(result.initial)
      return 'seeded'
    }
    await wait(180)
  }
  throw new CollaborationInitializationError('协同初始化等待超时', 'server')
}
