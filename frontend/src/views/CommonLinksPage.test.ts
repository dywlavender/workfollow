import { afterEach, beforeAll, beforeEach, describe, expect, it, vi } from 'vitest'

const { mountedCallbacks, onMountedMock } = vi.hoisted(() => {
  const callbacks: Array<() => void> = []
  return {
    mountedCallbacks: callbacks,
    onMountedMock: vi.fn((callback: () => void) => callbacks.push(callback)),
  }
})

vi.mock('vue', async () => {
  const actual = await vi.importActual<typeof import('vue')>('vue')
  return { ...actual, onMounted: onMountedMock, useSSRContext: () => ({ modules: new Set<string>() }) }
})

vi.mock('@/services/api', () => ({
  deleteSystemQuickLink: vi.fn(),
  fetchSystemQuickLinks: vi.fn(),
  postSystemQuickLink: vi.fn(),
  putSystemQuickLink: vi.fn(),
  reorderSystemQuickLinks: vi.fn(),
}))

vi.mock('@/components/ConfirmDialog.vue', () => ({
  default: { name: 'ConfirmDialogStub', setup: () => () => null },
}))

vi.mock('@/stores/auth', () => ({
  useAuthStore: () => ({ user: { systemRole: 'NORMAL' } }),
}))

vi.mock('@/stores/feedback', () => ({
  useFeedbackStore: () => ({}),
}))

let CommonLinksPage: typeof import('./CommonLinksPage.vue').default
let fetchSystemQuickLinks: typeof import('@/services/api').fetchSystemQuickLinks

type SetupComponent = {
  setup: (props: Record<string, never>, context: { expose: (exposed?: Record<string, unknown>) => void }) => unknown
}

describe('CommonLinksPage', () => {
  beforeAll(async () => {
    CommonLinksPage = (await import('./CommonLinksPage.vue')).default
    fetchSystemQuickLinks = (await import('@/services/api')).fetchSystemQuickLinks
  })

  beforeEach(() => {
    mountedCallbacks.length = 0
    onMountedMock.mockClear()
    vi.mocked(fetchSystemQuickLinks).mockResolvedValue([])
  })

  afterEach(() => {
    vi.clearAllMocks()
  })

  it('loads system links when the page is mounted', () => {
    const component = CommonLinksPage as unknown as SetupComponent
    component.setup({}, { expose: vi.fn() })

    expect(onMountedMock).toHaveBeenCalledOnce()
    mountedCallbacks[0]?.()
    expect(fetchSystemQuickLinks).toHaveBeenCalledOnce()
  })
})
