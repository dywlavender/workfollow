import { describe, expect, it, vi } from 'vitest'

const mocks = vi.hoisted(() => ({
  fetchFolders: vi.fn(),
  fetchNote: vi.fn(),
  fetchNotes: vi.fn(),
  fetchTodoLists: vi.fn(),
  fetchTodos: vi.fn(),
}))

vi.mock('./api', () => mocks)

import { buildPersonalMigrationBundle } from './migration'

describe('personal migration export', () => {
  it('keeps personal tasks and excludes team tasks', async () => {
    mocks.fetchTodos.mockResolvedValue([
      { id: 'personal-1', teamId: null, sourceType: 'MANUAL', title: '个人任务', tags: [] },
      { id: 'team-1', teamId: 'team-1', sourceType: 'TEAM', title: '团队任务', tags: [] },
      { id: 'legacy-personal', sourceType: 'MANUAL', title: '无 teamId 的旧任务', tags: [] },
    ])
    mocks.fetchTodoLists.mockResolvedValue([{ id: null, name: '收集箱', sortOrder: 0, protected: true }])
    mocks.fetchFolders.mockResolvedValue([])
    mocks.fetchNotes.mockResolvedValue([])

    const bundle = await buildPersonalMigrationBundle()

    expect(bundle.source.scope).toBe('personal')
    expect(bundle.tasks.map((task) => task.id)).toEqual(['personal-1', 'legacy-personal'])
    expect(mocks.fetchTodos).toHaveBeenCalledWith('all')
  })

  it('fetches full note payloads after paging the note index', async () => {
    mocks.fetchTodos.mockResolvedValue([])
    mocks.fetchTodoLists.mockResolvedValue([])
    mocks.fetchFolders.mockResolvedValue([])
    mocks.fetchNotes.mockResolvedValue([{ id: 'note-1' }])
    mocks.fetchNote.mockResolvedValue({
      id: 'note-1',
      folderId: null,
      title: '个人笔记',
      contentJson: {},
      plainText: '正文',
      isFavorite: false,
      createdAt: '2026-08-30T00:00:00Z',
      updatedAt: '2026-08-30T00:00:00Z',
      deletedAt: null,
    })

    const bundle = await buildPersonalMigrationBundle()

    expect(bundle.notes).toHaveLength(1)
    expect(mocks.fetchNote).toHaveBeenCalledWith('note-1')
    expect(mocks.fetchNotes).toHaveBeenCalledWith({ limit: 500, offset: 0 })
  })
})
