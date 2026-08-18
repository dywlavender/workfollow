export type TaskSaveData<T extends object> = { todoId: string; data: Partial<T>; quiet: boolean }
export type TaskSaveStatus = 'idle' | 'saving' | 'saved' | 'error'
export type TaskSaveDispatch<T extends object> = (request: TaskSaveData<T>) => Promise<boolean>

type TaskBucket<T extends object> = {
  pending: TaskSaveData<T> | null
  failed: TaskSaveData<T> | null
  inFlight: boolean
  status: TaskSaveStatus
  waiters: Array<(ok: boolean) => void>
}

/** A per-task serial queue: saves for one task stay ordered without blocking other tasks. */
export class TaskSaveQueue<T extends object> {
  private readonly buckets = new Map<string, TaskBucket<T>>()

  constructor(
    private readonly dispatch: TaskSaveDispatch<T>,
    private readonly onStatus?: (todoId: string, status: TaskSaveStatus) => void,
  ) {}

  status(todoId: string): TaskSaveStatus {
    return this.buckets.get(todoId)?.status ?? 'idle'
  }

  hasUnsaved(todoId?: string): boolean {
    const buckets = todoId ? [this.buckets.get(todoId)] : [...this.buckets.values()]
    return buckets.some((bucket) => Boolean(bucket && (bucket.inFlight || bucket.pending || bucket.failed)))
  }

  waitFor(todoId: string): Promise<boolean> {
    const bucket = this.buckets.get(todoId)
    if (!bucket || !this.hasUnsaved(todoId)) return Promise.resolve(bucket?.status !== 'error')
    return new Promise((resolve) => bucket.waiters.push(resolve))
  }

  enqueue(todoId: string, data: Partial<T>, quiet = true): void {
    const bucket = this.bucket(todoId)
    const older = bucket.failed ?? bucket.pending
    bucket.failed = null
    bucket.pending = {
      todoId,
      data: structuredClone(older ? { ...older.data, ...data } : data),
      quiet: older ? older.quiet && quiet : quiet,
    }
    void this.drain(todoId, bucket)
  }

  retry(todoId: string): void {
    const bucket = this.buckets.get(todoId)
    if (!bucket?.failed) return
    bucket.pending = bucket.pending
      ? { todoId, data: { ...bucket.failed.data, ...bucket.pending.data }, quiet: bucket.failed.quiet && bucket.pending.quiet }
      : bucket.failed
    bucket.failed = null
    void this.drain(todoId, bucket)
  }

  private bucket(todoId: string): TaskBucket<T> {
    let bucket = this.buckets.get(todoId)
    if (!bucket) {
      bucket = { pending: null, failed: null, inFlight: false, status: 'idle', waiters: [] }
      this.buckets.set(todoId, bucket)
    }
    return bucket
  }

  private setStatus(todoId: string, bucket: TaskBucket<T>, status: TaskSaveStatus): void {
    bucket.status = status
    this.onStatus?.(todoId, status)
    if (status === 'saved' || status === 'error') {
      const waiters = bucket.waiters.splice(0)
      for (const resolve of waiters) resolve(status === 'saved')
    }
  }

  private async drain(todoId: string, bucket: TaskBucket<T>): Promise<void> {
    if (bucket.inFlight || !bucket.pending) return
    const request = bucket.pending
    bucket.pending = null
    bucket.inFlight = true
    this.setStatus(todoId, bucket, 'saving')
    let ok = false
    try { ok = await this.dispatch(request) } catch { ok = false }
    bucket.inFlight = false

    if (!ok) {
      const pendingAfterRequest = this.buckets.get(todoId)?.pending ?? null
      bucket.failed = pendingAfterRequest
        ? { todoId, data: { ...request.data, ...pendingAfterRequest.data }, quiet: request.quiet && pendingAfterRequest.quiet }
        : request
      bucket.pending = null
      this.setStatus(todoId, bucket, 'error')
      return
    }

    if (bucket.pending) {
      void this.drain(todoId, bucket)
      return
    }
    this.setStatus(todoId, bucket, 'saved')
  }
}
