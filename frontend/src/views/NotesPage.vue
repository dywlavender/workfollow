<script setup lang="ts">
import { IconSearch, IconX } from '@tabler/icons-vue'
import { computed, nextTick, onMounted, ref, watch } from 'vue'
import { onBeforeRouteLeave, onBeforeRouteUpdate, useRoute, useRouter } from 'vue-router'

import ConfirmDialog from '@/components/ConfirmDialog.vue'
import InputDialog from '@/components/InputDialog.vue'
import CollaborativeNoteList from '@/components/notes/CollaborativeNoteList.vue'
import FolderDialog from '@/components/notes/FolderDialog.vue'
import KnowledgeDetail from '@/components/notes/KnowledgeDetail.vue'
import MarkdownImportDialog from '@/components/notes/MarkdownImportDialog.vue'
import NoteEditor from '@/components/notes/NoteEditor.vue'
import NoteList from '@/components/notes/NoteList.vue'
import NoteNavigation, { type NoteView } from '@/components/notes/NoteNavigation.vue'
import SearchResults from '@/components/notes/SearchResults.vue'
import NoteTemplateDialog from '@/components/notes/NoteTemplateDialog.vue'
import NoteTemplateEditorDialog from '@/components/notes/NoteTemplateEditorDialog.vue'
import NoteTemplateManagerDialog from '@/components/notes/NoteTemplateManagerDialog.vue'
import NoteTemplateSaveDialog from '@/components/notes/NoteTemplateSaveDialog.vue'
import PublishToKnowledgeDialog from '@/components/notes/PublishToKnowledgeDialog.vue'
import ShareNotePopover from '@/components/notes/ShareNotePopover.vue'
import SharedNoteDetail from '@/components/notes/SharedNoteDetail.vue'
import SubmissionWorkspace from '@/components/notes/SubmissionWorkspace.vue'
import { useDialogEscape } from '@/composables/useDialogEscape'
import {
  approveSubmission, archiveKnowledge, copyKnowledge, copyNote, copySharedNote, deleteAttachment, deleteFolder, deleteKnowledge, deleteKnowledgeCategory, deleteNote,
  fetchAttachments, fetchFolders, fetchKnowledge, fetchKnowledgeCategories, fetchKnowledgeNote, fetchKnowledgeVersions, fetchNote,
  deleteNoteTemplate, fetchMySubmissions, fetchNoteNavigationCounts, fetchNoteShares, fetchNotes, fetchNoteTemplates, fetchRelatedKnowledge,
  fetchReviewSubmissions, fetchSearch, fetchSharedNote, fetchSharedNotes, fetchNotesSharedByMe, fetchTeamMembers, importMarkdownNote, postFolder, postKnowledge, postNote,
  postKnowledgeCategory,
  commitKnowledge, moveNoteToFolder, postNoteFromTemplate, postNoteTemplate, putFolder, putKnowledgeCategory, putNoteTemplate, rejectSubmission, setNoteFavorite,
  requestSubmissionRevision, resubmitSubmission, restoreKnowledge, submitNoteToKnowledge, syncNoteShares, updateNoteSharePermission, ensureKnowledgeUpdateDraft,
  uploadAttachment, withdrawSubmission,
  type Attachment, type Folder, type KnowledgeCategory, type Note, type NoteListItem, type NoteNavigationCounts, type NoteShare, type NoteSharePermission, type SearchItem,
  type NoteTemplate, type SharedByMeNote, type SharedNote, type SubmissionPayload, type SubmissionReviewPayload, type TeamMember, type TeamNote,
  type TeamNoteListItem, type TeamNoteSubmission, type TeamNoteVersion,
} from '@/services/api'
import { useAuthStore } from '@/stores/auth'
import { useFeedbackStore } from '@/stores/feedback'
import { useRealtimeStore } from '@/stores/realtime'
import { useWorkspaceStore } from '@/stores/workspace'
import { noteToMarkdown } from '@/modules/editor/markdownExport'
import { consumePrefetchedNotesList } from '@/services/prefetch'

const route = useRoute()
const router = useRouter()
const auth = useAuthStore()
const realtime = useRealtimeStore()
const workspace = useWorkspaceStore()
const feedback = useFeedbackStore()
const currentTeam = computed(() => workspace.currentTeam ?? workspace.teams[0] ?? null)
const selectedTeamId = computed(() => currentTeam.value?.id)
const hasTeam = computed(() => Boolean(currentTeam.value))
const isRoot = computed(() => auth.user?.systemRole === 'ROOT')
const canReview = computed(() => isRoot.value || currentTeam.value?.role === 'OWNER' || currentTeam.value?.role === 'ADMIN')

const folders = ref<Folder[]>([])
const notes = ref<NoteListItem[]>([])
const sharedNotes = ref<SharedNote[]>([])
const sharedByMeNotes = ref<SharedByMeNote[]>([])
const knowledge = ref<TeamNoteListItem[]>([])
const archivedKnowledge = ref<TeamNoteListItem[]>([])
const knowledgeDetails = ref<TeamNote[]>([])
const categories = ref<KnowledgeCategory[]>([])
const members = ref<TeamMember[]>([])
const shareMembers = ref<TeamMember[]>([])
const submissions = ref<TeamNoteSubmission[]>([])
const mySubmissions = ref<TeamNoteSubmission[]>([])
const relatedKnowledge = ref<TeamNote[]>([])
const versions = ref<TeamNoteVersion[]>([])
const selectedFolderId = ref<string | null>(null)
const selectedCategoryId = ref<string | null>(null)
const selectedNote = ref<Note | null>(null)
type NoteEditorActionSnapshot = {
  note: Note
  title: string
  contentJson: Record<string, unknown>
  plainText: string
}
const noteEditor = ref<{ flushCollaboration: () => void; flushAndWaitForProjection: (timeoutMs?: number) => Promise<NoteEditorActionSnapshot> } | null>(null)
const knowledgeDetail = ref<{ flushCollaboration: () => void; flushAndWaitForProjection: (timeoutMs?: number) => Promise<void> } | null>(null)
const selectedShared = ref<SharedNote | null>(null)
const selectedKnowledge = ref<TeamNote | null>(null)
const selectedSubmission = ref<TeamNoteSubmission | null>(null)
const attachments = ref<Attachment[]>([])
const shares = ref<NoteShare[]>([])
const search = ref('')
const navigationCounts = ref<NoteNavigationCounts>({
  all: 0,
  unfiled: 0,
  favorites: 0,
  folders: {},
  shared: 0,
  sharedByMe: 0,
  knowledge: 0,
  submissionsTotal: 0,
  submissionsPending: 0,
  reviewPending: 0,
})
const globalSearchQuery = ref('')
const globalSearchItems = ref<SearchItem[]>([])
const globalSearchLoading = ref(false)
const globalSearchError = ref<string | null>(null)
const globalSearchOpen = ref(false)
const globalSearchInput = ref<HTMLInputElement | null>(null)
const knowledgeStatusFilter = ref<'published' | 'archived'>('published')
const busy = ref(false)
const viewLoading = ref(false)
const validViews: NoteView[] = ['recent', 'all', 'inbox', 'favorites', 'shared', 'sharedByMe', 'knowledge', 'submissions', 'review']
const currentView = computed<NoteView>(() => {
  const requested = typeof route.query.view === 'string' ? route.query.view as NoteView : 'all'
  if (!validViews.includes(requested)) return 'all'
  if (!hasTeam.value && ['shared', 'sharedByMe', 'knowledge', 'submissions', 'review'].includes(requested)) return 'all'
  if (requested === 'review' && !canReview.value) return 'submissions'
  return requested
})
const onboarding = computed(() => route.query.onboarding === '1')
const personalView = computed(() => ['recent', 'all', 'inbox', 'favorites'].includes(currentView.value))
const noteListHeading = computed(() => {
  if (currentView.value === 'recent') return '最近'
  if (currentView.value === 'inbox') return '收件箱'
  if (currentView.value === 'favorites') return '收藏'
  if (currentView.value === 'all' && selectedFolderId.value) {
    return folders.value.find((folder) => folder.id === selectedFolderId.value)?.name ?? '全部'
  }
  return '全部'
})
const visibleKnowledge = computed(() => knowledgeStatusFilter.value === 'archived' ? archivedKnowledge.value : knowledge.value)
const visibleSharedNotes = computed(() => sharedNotes.value)
const selectedPublishedKnowledge = computed(() => selectedNote.value
  ? knowledge.value.find((item) => item.sourceNoteId === selectedNote.value?.id && item.status === 'PUBLISHED') ?? null
  : null)
const selectedUpdateSubmission = computed(() => selectedNote.value
  ? mySubmissions.value.find((item) => (
    item.sourceNoteId === selectedNote.value?.id
    && item.submissionType === 'UPDATE'
    && (item.status === 'PENDING' || item.status === 'NEEDS_REVISION')
  )) ?? null
  : null)
const selectedKnowledgeForNote = computed(() => {
  const targetId = selectedNote.value?.isKnowledgeUpdateDraft
    ? selectedNote.value.copiedFromTeamNoteId
    : selectedUpdateSubmission.value?.targetTeamNoteId
  return targetId
    ? knowledge.value.find((item) => item.id === targetId) ?? null
    : selectedPublishedKnowledge.value
})
const selectedKnowledgeState = computed<'none' | 'published' | 'update-draft' | 'update-pending' | 'update-needs-revision'>(() => {
  if (selectedUpdateSubmission.value?.status === 'PENDING') return 'update-pending'
  if (selectedUpdateSubmission.value?.status === 'NEEDS_REVISION') return 'update-needs-revision'
  if (selectedNote.value?.isKnowledgeUpdateDraft) return 'update-draft'
  if (selectedPublishedKnowledge.value) return 'published'
  return 'none'
})
const selectedKnowledgeUpdateState = computed<'none' | 'draft' | 'pending' | 'needs-revision'>(() => {
  if (selectedKnowledge.value?.myUpdateSubmissionStatus === 'PENDING') return 'pending'
  if (selectedKnowledge.value?.myUpdateSubmissionStatus === 'NEEDS_REVISION') return 'needs-revision'
  if (selectedKnowledge.value?.myUpdateDraftNoteId) return 'draft'
  return 'none'
})

const templateDialogOpen = ref(false)
const templateManagerOpen = ref(false)
const templateEditorOpen = ref(false)
const templateSaveDialogOpen = ref(false)
const templates = ref<NoteTemplate[]>([])
const templateEditorTarget = ref<NoteTemplate | null>(null)
const templateDeleteTarget = ref<NoteTemplate | null>(null)
const templateSaving = ref(false)
const templateSource = ref<{ noteId: string; contentJson: Record<string, unknown>; plainText: string } | null>(null)
const markdownImportOpen = ref(false)
const markdownImportSaving = ref(false)
const markdownImportError = ref<string | null>(null)
const shareDialogOpen = ref(false)
const publishDialogOpen = ref(false)
const publishType = ref<'CREATE' | 'UPDATE'>('CREATE')
const publishTargetId = ref<string | null>(null)
const publishTargetLocked = ref(false)
const versionsOpen = ref(false)
useDialogEscape(() => versionsOpen.value, () => { versionsOpen.value = false })
const categoryDialogOpen = ref(false)
const knowledgeCreateDialogOpen = ref(false)
const categoryDialogMode = ref<'create' | 'rename'>('create')
const categoryDialogTarget = ref<KnowledgeCategory | null>(null)
const categoryDialogName = ref('')
const folderDialogOpen = ref(false)
const folderDialogMode = ref<'create' | 'rename' | 'delete'>('create')
const folderDialogName = ref('')
const folderDialogParentId = ref<string | null>(null)
const folderDialogParentName = ref<string | null>(null)
const folderDialogTarget = ref<Folder | null>(null)
const confirmDialogOpen = ref(false)
const confirmDialogKind = ref<'note' | 'attachment' | 'category' | 'template' | null>(null)
const confirmDialogNote = ref<NoteListItem | Note | null>(null)
const confirmDialogAttachment = ref<Attachment | null>(null)
const confirmDialogCategory = ref<KnowledgeCategory | null>(null)
const archiveConfirmOpen = ref(false)
const archiveConfirmTarget = ref<TeamNote | null>(null)
const knowledgeDeleteConfirmOpen = ref(false)
const knowledgeDeleteTarget = ref<TeamNote | null>(null)
let searchTimer: number | undefined
let globalSearchTimer: number | undefined
let globalSearchRequest = 0
let activeViewLoad: Promise<void> | null = null
let viewLoadQueued = false
let personalSelectionRequest = 0
let knowledgeSelectionRequest = 0

// 操作反馈统一走全局 feedback 服务;fail 保留后端 detail 提取。
function notify(message: string) { feedback.success(message) }
function fail(cause: any, fallback: string) { feedback.error(cause?.response?.data?.detail ?? fallback) }

function toNoteListItem(note: Note): NoteListItem {
  return {
    id: note.id,
    folderId: note.folderId,
    title: note.title,
    isFavorite: note.isFavorite,
    copiedFromNoteId: note.copiedFromNoteId,
    copiedFromTeamNoteId: note.copiedFromTeamNoteId,
    isKnowledgeUpdateDraft: note.isKnowledgeUpdateDraft,
    copiedFromTeamNoteVersionNo: note.copiedFromTeamNoteVersionNo,
    copiedFromTeamNoteSnapshotHash: note.copiedFromTeamNoteSnapshotHash,
    createdAt: note.createdAt,
    updatedAt: note.updatedAt,
    deletedAt: note.deletedAt,
  }
}

function toTeamNoteListItem(note: TeamNote): TeamNoteListItem {
  return {
    id: note.id,
    teamId: note.teamId,
    title: note.title,
    categoryId: note.categoryId,
    category: note.category,
    tags: note.tags,
    sourceType: note.sourceType,
    sourceNoteId: note.sourceNoteId,
    sourceAuthorId: note.sourceAuthorId,
    sourceAuthor: note.sourceAuthor,
    sourceSubmissionId: note.sourceSubmissionId,
    status: note.status,
    publishedAt: note.publishedAt,
    archivedAt: note.archivedAt,
    createdAt: note.createdAt,
    updatedAt: note.updatedAt,
    permissions: note.permissions,
  }
}

function upsertNoteListItem(note: Note) {
  const summary = toNoteListItem(note)
  const index = notes.value.findIndex((item) => item.id === note.id)
  if (index >= 0) notes.value[index] = summary
  else notes.value.unshift(summary)
}

function insertByUpdatedAt<T extends { id: string; updatedAt: string }>(items: T[], item: T) {
  const currentIndex = items.findIndex((entry) => entry.id === item.id)
  if (currentIndex >= 0) items.splice(currentIndex, 1)
  const updatedAt = Date.parse(item.updatedAt)
  const insertIndex = items.findIndex((entry) => Date.parse(entry.updatedAt) < updatedAt)
  if (insertIndex < 0) items.push(item)
  else items.splice(insertIndex, 0, item)
}

function sharedNoteMatchesSearch(note: SharedNote, value = search.value) {
  const query = value.trim().toLocaleLowerCase()
  return !query || `${note.title}\n${note.plainText}`.toLocaleLowerCase().includes(query)
}

function removeSharedNoteListItem(noteId: string) {
  const index = sharedNotes.value.findIndex((item) => item.id === noteId)
  if (index >= 0) sharedNotes.value.splice(index, 1)
}

function upsertSharedNoteListItem(note: SharedNote): boolean {
  if (!sharedNoteMatchesSearch(note)) {
    removeSharedNoteListItem(note.id)
    return false
  }
  insertByUpdatedAt(sharedNotes.value, note)
  return true
}

function applySharedByMeChange(change: NonNullable<typeof realtime.lastNoteChange>) {
  if (change.deleted) {
    const index = sharedByMeNotes.value.findIndex((item) => item.id === change.noteId)
    if (index >= 0) sharedByMeNotes.value.splice(index, 1)
    return
  }
  const existing = sharedByMeNotes.value.find((item) => item.id === change.noteId)
  if (!existing) {
    // A newly shared note is not represented in the current list. Keep this
    // rare discovery path as a full load; edits to an existing note stay local.
    void loadView()
    return
  }
  insertByUpdatedAt(sharedByMeNotes.value, {
    ...existing,
    title: change.title,
    folderId: change.folderId !== undefined ? change.folderId : existing.folderId,
    isFavorite: change.isFavorite !== undefined ? change.isFavorite : existing.isFavorite,
    updatedAt: change.updatedAt ?? existing.updatedAt,
  })
}

function applyCollaborativeNoteChange(payload: { title: string; contentJson: Record<string, unknown>; plainText: string }) {
  if (!selectedNote.value) return
  const updated: Note = {
    ...selectedNote.value,
    title: payload.title,
    contentJson: payload.contentJson,
    plainText: payload.plainText,
    // The SQL projection owns the timestamp. A local Yjs observer must not
    // make opening a note look like a fresh save.
    updatedAt: selectedNote.value.updatedAt,
  }
  selectedNote.value = updated
  upsertNoteListItem(updated)
}

function applyNoteChange(change: NonNullable<typeof realtime.lastNoteChange>) {
  const existing = notes.value.find((item) => item.id === change.noteId)
  if (change.deleted) {
    removeNoteListItem(change.noteId)
    if (selectedNote.value?.id === change.noteId) {
      selectedNote.value = null
      attachments.value = []
      shares.value = []
    }
    return
  }
  if (!existing) {
    if (personalView.value) void loadView()
    return
  }
  const updated: NoteListItem = {
    ...existing,
    title: change.title,
    // ``null`` and ``false`` are meaningful event values.  Nullish fallback
    // would keep stale list state when a note is moved to the inbox or
    // un-favorited in another tab.
    folderId: change.folderId !== undefined ? change.folderId : existing.folderId,
    isFavorite: change.isFavorite !== undefined ? change.isFavorite : existing.isFavorite,
    updatedAt: change.updatedAt ?? existing.updatedAt,
  }
  const index = notes.value.findIndex((item) => item.id === change.noteId)
  if (index >= 0) notes.value[index] = updated
  if (selectedNote.value?.id === change.noteId) {
    selectedNote.value = {
      ...selectedNote.value,
      title: change.title,
      folderId: updated.folderId,
      isFavorite: updated.isFavorite,
      updatedAt: updated.updatedAt,
    }
  }
}

async function syncSelectedNoteForAction(noteId = selectedNote.value?.id): Promise<NoteEditorActionSnapshot | null> {
  if (!selectedNote.value || selectedNote.value.id !== noteId) return null
  if (!noteEditor.value) return {
    note: selectedNote.value,
    title: selectedNote.value.title,
    contentJson: selectedNote.value.contentJson,
    plainText: selectedNote.value.plainText,
  }
  try {
    const snapshot = await noteEditor.value.flushAndWaitForProjection()
    selectedNote.value = snapshot.note
    upsertNoteListItem(snapshot.note)
    return snapshot
  } catch (cause: any) {
    fail(cause, '笔记内容尚未同步完成，请稍后重试。')
    return null
  }
}

function upsertKnowledgeListItem(note: TeamNote) {
  const summary = toTeamNoteListItem(note)
  const target = note.status === 'ARCHIVED' ? archivedKnowledge : knowledge
  const other = note.status === 'ARCHIVED' ? knowledge : archivedKnowledge
  const index = target.value.findIndex((item) => item.id === note.id)
  if (index >= 0) target.value[index] = summary
  else target.value.unshift(summary)
  const otherIndex = other.value.findIndex((item) => item.id === note.id)
  if (otherIndex >= 0) other.value.splice(otherIndex, 1)
}

function upsertKnowledgeDetail(note: TeamNote) {
  const index = knowledgeDetails.value.findIndex((item) => item.id === note.id)
  if (index >= 0) knowledgeDetails.value[index] = note
  else knowledgeDetails.value.push(note)
}

function removeNoteListItem(noteId: string) {
  const index = notes.value.findIndex((item) => item.id === noteId)
  if (index >= 0) notes.value.splice(index, 1)
}

function removeKnowledgeListItem(noteId: string) {
  for (const list of [knowledge, archivedKnowledge]) {
    const index = list.value.findIndex((item) => item.id === noteId)
    if (index >= 0) list.value.splice(index, 1)
  }
  const detailIndex = knowledgeDetails.value.findIndex((item) => item.id === noteId)
  if (detailIndex >= 0) knowledgeDetails.value.splice(detailIndex, 1)
}

function replaceSubmission(item: TeamNoteSubmission) {
  for (const list of [submissions, mySubmissions]) {
    const index = list.value.findIndex((current) => current.id === item.id)
    if (index >= 0) list.value[index] = item
  }
  if (selectedSubmission.value?.id === item.id) selectedSubmission.value = item
}

function removeSubmission(itemId: string) {
  for (const list of [submissions, mySubmissions]) {
    const index = list.value.findIndex((item) => item.id === itemId)
    if (index >= 0) list.value.splice(index, 1)
  }
  if (selectedSubmission.value?.id === itemId) {
    selectedSubmission.value = null
    relatedKnowledge.value = []
  }
}

async function refreshNoteMeta() {
  navigationCounts.value = await fetchNoteNavigationCounts(selectedTeamId.value)
}

async function refreshKnowledgeCategories() {
  categories.value = selectedTeamId.value
    ? await fetchKnowledgeCategories(selectedTeamId.value)
    : []
}

function updateGlobalSearch(value: string) {
  globalSearchQuery.value = value
  const requestId = ++globalSearchRequest
  window.clearTimeout(globalSearchTimer)
  if (!value.trim()) {
    globalSearchItems.value = []
    globalSearchLoading.value = false
    globalSearchError.value = null
    return
  }
  globalSearchError.value = null
  globalSearchLoading.value = true
  globalSearchTimer = window.setTimeout(async () => {
    try {
      const result = await fetchSearch({ q: value.trim() })
      if (requestId !== globalSearchRequest) return
      globalSearchItems.value = result.items
    } catch (cause: any) {
      if (requestId !== globalSearchRequest) return
      const message = cause?.response?.data?.detail ?? '统一搜索失败，请确认后端已更新并重新启动。'
      globalSearchError.value = message
      fail(cause, message)
      globalSearchItems.value = []
    } finally {
      if (requestId === globalSearchRequest) globalSearchLoading.value = false
    }
  }, 280)
}

async function openGlobalSearch() {
  globalSearchOpen.value = true
  await nextTick()
  globalSearchInput.value?.focus()
}

function closeGlobalSearch() {
  globalSearchOpen.value = false
  globalSearchQuery.value = ''
  globalSearchItems.value = []
  globalSearchLoading.value = false
  globalSearchError.value = null
  globalSearchRequest += 1
  window.clearTimeout(globalSearchTimer)
}

async function selectSearchResult(item: SearchItem) {
  closeGlobalSearch()
  search.value = ''
  try {
    if (item.source === 'personal') {
      selectedFolderId.value = null
      await router.push({ path: '/notes', query: { view: 'all', note: item.id } })
    } else if (item.source === 'shared') {
      await router.push({ path: '/notes', query: { view: 'shared', shared: item.id } })
    } else {
      if (item.teamId && item.teamId !== selectedTeamId.value) workspace.selectTeam(item.teamId)
      await router.push({ path: '/notes', query: { view: 'knowledge', knowledge: item.id } })
    }
  } catch (cause: any) {
    fail(cause, '打开搜索结果失败，请稍后重试。')
  }
}

async function loadPersonal() {
  const isDefaultPersonalList = currentView.value === 'all' && !selectedFolderId.value && !search.value.trim()
  notes.value = isDefaultPersonalList
    ? await consumePrefetchedNotesList()
    : await fetchNotes({
      folderId: currentView.value === 'all' ? selectedFolderId.value ?? undefined : undefined,
      q: search.value.trim() || undefined,
      favorite: currentView.value === 'favorites' ? true : undefined,
      unfiled: currentView.value === 'inbox',
      limit: currentView.value === 'recent' ? 30 : undefined,
    })
  const requestedNoteId = typeof route.query.note === 'string' ? route.query.note : null
  // 与待办视图一致：进入列表不自动打开第一条。只有深链指定的笔记、或已选中
  // 且仍在本视图列表内的笔记保持打开，其余展示空态，省去进页时的详情/附件请求。
  const selectedId = requestedNoteId && notes.value.some((item) => item.id === requestedNoteId)
    ? requestedNoteId
    : selectedNote.value && notes.value.some((item) => item.id === selectedNote.value?.id)
      ? selectedNote.value.id
      : null
  const summary = selectedId ? notes.value.find((item) => item.id === selectedId) ?? null : null
  if (summary && summary.id !== selectedNote.value?.id) await selectPersonal(summary)
  else if (!summary) {
    selectedNote.value = null
    attachments.value = []
    shares.value = []
  }
}

async function loadCollaboration() {
  if (!hasTeam.value) return
  const membersRequest = currentTeam.value
    ? fetchTeamMembers(currentTeam.value.id)
    : Promise.resolve([] as TeamMember[])
  const [loadedKnowledge, loadedCategories, loadedMySubmissions, loadedMembers] = await Promise.all([
    fetchKnowledge({ q: currentView.value === 'knowledge' ? search.value.trim() || undefined : undefined, categoryId: selectedCategoryId.value ?? undefined, includeArchived: canReview.value ? true : undefined, teamId: selectedTeamId.value }),
    fetchKnowledgeCategories(selectedTeamId.value),
    fetchMySubmissions(selectedTeamId.value),
    membersRequest,
  ])
  knowledge.value = loadedKnowledge.filter((item) => item.status === 'PUBLISHED')
  archivedKnowledge.value = loadedKnowledge.filter((item) => item.status === 'ARCHIVED')
  knowledgeDetails.value = knowledgeDetails.value.filter((item) => loadedKnowledge.some((summary) => summary.id === item.id))
  categories.value = loadedCategories
  mySubmissions.value = loadedMySubmissions
  members.value = loadedMembers
}

async function performLoadView() {
  viewLoading.value = true
  try {
    if (personalView.value) await loadPersonal()
    else if (currentView.value === 'shared') {
      sharedNotes.value = await fetchSharedNotes(search.value.trim() || undefined)
      const requested = typeof route.query.shared === 'string' ? route.query.shared : selectedShared.value?.id
      // 深链或已有选中才打开，否则空态（同待办视图）。
      selectedShared.value = visibleSharedNotes.value.find((item) => item.id === requested) ?? null
    } else if (currentView.value === 'sharedByMe') {
      sharedByMeNotes.value = await fetchNotesSharedByMe()
      const requested = typeof route.query.note === 'string' ? route.query.note : selectedNote.value?.id
      const summary = sharedByMeNotes.value.find((item) => item.id === requested) ?? null
      if (summary && summary.id !== selectedNote.value?.id) await selectPersonal(summary)
      else if (!summary) {
        selectedNote.value = null
        attachments.value = []
        shares.value = []
      }
    } else if (currentView.value === 'knowledge') {
      await loadCollaboration()
      const requested = typeof route.query.knowledge === 'string' ? route.query.knowledge : selectedKnowledge.value?.id
      const summary = visibleKnowledge.value.find((item) => item.id === requested) ?? null
      if (summary && summary.id !== selectedKnowledge.value?.id) await selectKnowledge(summary)
      else if (!summary) selectedKnowledge.value = null
    } else {
      if (!hasTeam.value || !selectedTeamId.value) {
        submissions.value = []
        selectedSubmission.value = null
        relatedKnowledge.value = []
        return
      }
      submissions.value = currentView.value === 'review' ? await fetchReviewSubmissions(selectedTeamId.value) : await fetchMySubmissions(selectedTeamId.value)
      const requestedSubmission = typeof route.query.submission === 'string' ? route.query.submission : selectedSubmission.value?.id
      const nextSubmission = submissions.value.find((item) => item.id === requestedSubmission) ?? null
      const submissionChanged = nextSubmission?.id !== selectedSubmission.value?.id
      selectedSubmission.value = nextSubmission
      if (nextSubmission && (submissionChanged || currentView.value === 'review')) {
        const relatedRequest = currentView.value === 'review'
          ? fetchRelatedKnowledge(nextSubmission.id)
          : Promise.resolve([] as TeamNote[])
        await Promise.all([
          ensureSubmissionTarget(nextSubmission),
          relatedRequest.then((loadedRelated) => { relatedKnowledge.value = loadedRelated }),
        ])
      }
    }
  } catch (cause: any) {
    fail(cause, '笔记服务读取失败。')
  } finally { viewLoading.value = false }
}

async function loadView() {
  if (activeViewLoad) {
    viewLoadQueued = true
    return activeViewLoad
  }
  do {
    viewLoadQueued = false
    const request = performLoadView()
    activeViewLoad = request
    try {
      await request
    } finally {
      if (activeViewLoad === request) activeViewLoad = null
    }
  } while (viewLoadQueued)
}

async function activateView(view: NoteView) {
  search.value = ''
  await router.push({ path: '/notes', query: { view } })
}

async function selectFolder(id: string | null) {
  selectedFolderId.value = id
  if (currentView.value !== 'all') await router.push({ path: '/notes', query: { view: 'all' } })
  else await loadView()
}
async function selectCategory(id: string | null) { selectedCategoryId.value = id; if (currentView.value === 'knowledge') await loadView() }

async function selectPersonal(item: NoteListItem | Note) {
  const request = ++personalSelectionRequest
  const switchingNote = Boolean(selectedNote.value && selectedNote.value.id !== item.id)
  const noteRequest = 'contentJson' in item ? Promise.resolve(item) : fetchNote(item.id)
  // Navigation must not wait for the previous note's SQL projection: flushing
  // here plus the collaboration teardown is enough for the server to project
  // the old note in the background, and the resulting note.changed event
  // refreshes the list entry. Only content-reading actions need the strict
  // barrier inside syncSelectedNoteForAction.
  // The note id is already present in both list and detail DTOs, so the
  // attachment request does not need to wait for the full note payload and
  // runs in parallel with it.
  const attachmentsRequest = fetchAttachments(item.id).catch(() => [])
  if (switchingNote) noteEditor.value?.flushCollaboration()
  const note = await noteRequest
  if (request !== personalSelectionRequest) return

  // Commit the note as soon as its detail is ready. Attachments and sharing
  // metadata are secondary data and must not hold the editor replacement
  // behind another network request.
  selectedNote.value = note
  attachments.value = []
  shares.value = []
  void attachmentsRequest.then((loadedAttachments) => {
    if (request === personalSelectionRequest && selectedNote.value?.id === note.id) {
      attachments.value = loadedAttachments
    }
  })
  if (shareDialogOpen.value) {
    void fetchNoteShares(note.id)
      .then((loadedShares) => {
        if (request === personalSelectionRequest && selectedNote.value?.id === note.id) shares.value = loadedShares
      })
      .catch(() => undefined)
  }
}

async function selectKnowledge(item: TeamNoteListItem | TeamNote): Promise<TeamNote> {
  const request = ++knowledgeSelectionRequest
  if (
    selectedKnowledge.value?.permissions.canEdit
    && selectedKnowledge.value.id !== item.id
    && knowledgeDetail.value
  ) {
    try {
      await knowledgeDetail.value.flushAndWaitForProjection()
    } catch (cause: any) {
      fail(cause, '知识内容尚未同步完成，请稍后重试。')
      return selectedKnowledge.value ?? ('contentJson' in item ? item : await fetchKnowledgeNote(item.id, selectedTeamId.value))
    }
  }
  const cached = knowledgeDetails.value.find((detail) => detail.id === item.id)
  const note = 'contentJson' in item ? item : cached ?? await fetchKnowledgeNote(item.id, selectedTeamId.value)
  if (request !== knowledgeSelectionRequest) return note
  selectedKnowledge.value = note
  upsertKnowledgeDetail(note)
  return note
}

// The selected editor is conditionally rendered by the current route. A
// navigation that bypasses the list click handlers (Back/Forward, a deep
// link, or opening a task from a note) must still wait for the latest Yjs
// projection before Vue tears that editor down.
function flushEditorsForNavigation(): boolean {
  // Route changes must not block on the SQL projection barrier either. Flush
  // pending collaboration updates and let the server project in the
  // background, exactly like a note-to-note switch.
  noteEditor.value?.flushCollaboration()
  knowledgeDetail.value?.flushCollaboration()
  return true
}

async function selectCollaborationItem(item: SharedNote | TeamNoteListItem) {
  if ('sharedBy' in item) selectedShared.value = item
  else await selectKnowledge(item)
}

function selectShared(item: SharedNote | TeamNoteListItem) {
  if (!('sharedBy' in item)) return
  selectedShared.value = item
  // A list row may carry an older permission after the owner changes sharing
  // settings. Refresh only the selected note instead of reloading the list.
  void refreshSharedNoteById(item.id)
}

async function refreshKnowledgeDetail(noteId: string) {
  if (!selectedTeamId.value) return
  try {
    const updated = await fetchKnowledgeNote(noteId, selectedTeamId.value)
    upsertKnowledgeDetail(updated)
    if (selectedKnowledge.value?.id === noteId) selectedKnowledge.value = updated
  } catch {
    // Access can disappear between the event and the targeted read.
  }
}

function applyTeamNoteChange(change: NonNullable<typeof realtime.lastTeamNoteChange>) {
  if (change.teamId !== selectedTeamId.value) return
  if (change.status === 'DELETED') {
    void refreshNoteMeta()
    void refreshKnowledgeCategories()
    removeKnowledgeListItem(change.noteId)
    if (selectedKnowledge.value?.id === change.noteId) {
      selectedKnowledge.value = null
    }
    return
  }
  const source = [...knowledge.value, ...archivedKnowledge.value].find((item) => item.id === change.noteId)
  if (!source) {
    void refreshNoteMeta()
    void refreshKnowledgeCategories()
    if (currentView.value === 'knowledge') void loadView()
    return
  }
  if (source.status !== change.status) void refreshNoteMeta()
  if (source.status !== change.status || source.categoryId !== change.categoryId) void refreshKnowledgeCategories()
  const updated: TeamNoteListItem = {
    ...source,
    title: change.title,
    categoryId: change.categoryId,
    status: change.status,
    archivedAt: change.status === 'ARCHIVED' ? source.archivedAt ?? change.updatedAt : null,
    updatedAt: change.updatedAt ?? source.updatedAt,
  }
  const target = change.status === 'ARCHIVED' ? archivedKnowledge : knowledge
  const other = change.status === 'ARCHIVED' ? knowledge : archivedKnowledge
  const index = target.value.findIndex((item) => item.id === updated.id)
  if (index >= 0) target.value[index] = updated
  else target.value.unshift(updated)
  const otherIndex = other.value.findIndex((item) => item.id === updated.id)
  if (otherIndex >= 0) other.value.splice(otherIndex, 1)
  if (selectedKnowledge.value?.id === change.noteId) void refreshKnowledgeDetail(change.noteId)
}

async function ensureSubmissionTarget(item: TeamNoteSubmission) {
  if (!item.targetTeamNoteId || !selectedTeamId.value) return
  if (knowledgeDetails.value.some((note) => note.id === item.targetTeamNoteId)) return
  try {
    upsertKnowledgeDetail(await fetchKnowledgeNote(item.targetTeamNoteId, selectedTeamId.value))
  } catch {
    // The target may have been archived or removed after the submission was made.
  }
}

async function openShareDialog() {
  if (!selectedNote.value) return
  try {
    // 先取已分享列表再开弹窗：否则弹窗以空列表渲染，勾选框初始化后不会
    // 随后到的数据补勾（表现为“看不到已分享的人”）。
    shares.value = await fetchNoteShares(selectedNote.value.id)
    // 成员列表合并“我在的所有团队”：分享可以授予任何与我存在共同团队的
    // 成员，只看当前选中团队会漏掉其他团队里的已分享者（多团队管理员场景）。
    const teamIds = workspace.teams.map((team) => team.id)
    const memberLists = await Promise.all(teamIds.map((id) => fetchTeamMembers(id).catch(() => [] as TeamMember[])))
    const byUser = new Map<string, TeamMember>()
    for (const list of memberLists) {
      for (const member of list) {
        if (member.status !== 'ACTIVE') continue
        const existing = byUser.get(member.userId)
        if (!existing || member.role === 'OWNER') byUser.set(member.userId, member)
      }
    }
    shareMembers.value = [...byUser.values()]
    shareDialogOpen.value = true
  } catch (cause: any) {
    fail(cause, '分享权限读取失败。')
  }
}
async function selectSubmission(item: TeamNoteSubmission) {
  selectedSubmission.value = item
  const relatedRequest = currentView.value === 'review'
    ? fetchRelatedKnowledge(item.id)
    : Promise.resolve([] as TeamNote[])
  await Promise.all([
    ensureSubmissionTarget(item),
    relatedRequest.then((loadedRelated) => { relatedKnowledge.value = loadedRelated }),
  ])
}

async function createBlankNote() {
  const note = await postNote({
    folderId: currentView.value === 'all' ? selectedFolderId.value : null,
  })
  upsertNoteListItem(note)
  await refreshNoteMeta()
  await selectPersonal(note)
}
function openMarkdownImport() { markdownImportError.value = null; markdownImportOpen.value = true }
async function importMarkdown(payload: { file: File; title: string; folderId: string | null }) {
  markdownImportSaving.value = true
  markdownImportError.value = null
  try {
    const note = await importMarkdownNote(payload.file, payload.folderId, payload.title)
    markdownImportOpen.value = false
    selectedFolderId.value = note.folderId
    search.value = ''
    if (currentView.value !== 'all') await router.push({ path: '/notes', query: { view: 'all' } })
    await refreshNoteMeta()
    upsertNoteListItem(note)
    await selectPersonal(note)
    notify('Markdown 已导入为新笔记。')
  } catch (cause: any) {
    markdownImportError.value = cause?.response?.data?.detail ?? 'Markdown 导入失败。'
  } finally { markdownImportSaving.value = false }
}
async function moveSelectedNote(folderId: string | null) {
  if (!selectedNote.value) return
  const noteId = selectedNote.value.id
  try {
    const updated = await moveNoteToFolder(noteId, folderId)
    selectedNote.value = updated
    upsertNoteListItem(updated)
    await refreshNoteMeta()
  } catch (cause: any) { fail(cause, '移动笔记失败，请稍后重试。') }
}
async function prepareSaveAsTemplate(payload: { note: Note; title: string; folderId: string | null; contentJson: Record<string, unknown>; plainText: string }) {
  templateSource.value = { noteId: payload.note.id, contentJson: payload.contentJson, plainText: payload.plainText }
  templateSaveDialogOpen.value = true
}
async function toggleFavorite(value: boolean) {
  if (!selectedNote.value) return
  try {
    selectedNote.value = await setNoteFavorite(selectedNote.value.id, value)
    if (currentView.value === 'favorites' && !value) removeNoteListItem(selectedNote.value.id)
    else upsertNoteListItem(selectedNote.value)
    await refreshNoteMeta()
  } catch (cause: any) { fail(cause, '更新收藏状态失败，请稍后重试。') }
}

async function handleUpload(file: File) {
  if (!selectedNote.value) throw new Error('No note selected')
  const attachment = await uploadAttachment(selectedNote.value.id, file)
  attachments.value = await fetchAttachments(selectedNote.value.id)
  return attachment
}

function requestDeleteNote(note: NoteListItem | Note) { confirmDialogKind.value = 'note'; confirmDialogNote.value = note; confirmDialogOpen.value = true }
function requestDeleteAttachment(item: Attachment) { confirmDialogKind.value = 'attachment'; confirmDialogAttachment.value = item; confirmDialogOpen.value = true }
function requestDeleteCategory(item: KnowledgeCategory) { confirmDialogKind.value = 'category'; confirmDialogCategory.value = item; confirmDialogOpen.value = true }
async function confirmDelete() {
  const kind = confirmDialogKind.value
  try {
    if (kind === 'note' && confirmDialogNote.value) await deleteNote(confirmDialogNote.value.id)
    if (kind === 'attachment' && confirmDialogAttachment.value) {
      // The current Yjs body is authoritative for embedded image references.
      // Flush it before deleting the binary, otherwise a just-inserted image
      // that has not reached SQL yet could be deleted successfully and leave
      // a broken reference in the collaborative document.
      const attachment = confirmDialogAttachment.value
      if (attachment.noteId && selectedNote.value?.id === attachment.noteId) {
        if (!await syncSelectedNoteForAction(attachment.noteId)) return
      }
      await deleteAttachment(attachment.id)
    }
    if (kind === 'category' && confirmDialogCategory.value && selectedTeamId.value) await deleteKnowledgeCategory(confirmDialogCategory.value.id, selectedTeamId.value)
    if (kind === 'template' && templateDeleteTarget.value) await deleteNoteTemplate(templateDeleteTarget.value.id)
    confirmDialogOpen.value = false
    if (kind === 'note') {
      const deletedId = confirmDialogNote.value?.id
      if (deletedId) removeNoteListItem(deletedId)
      if (selectedNote.value?.id === deletedId) {
        selectedNote.value = null
        attachments.value = []
        shares.value = []
      }
      await refreshNoteMeta()
    }
    else if (kind === 'attachment' && selectedNote.value) attachments.value = await fetchAttachments(selectedNote.value.id)
    if (kind === 'template') {
      if (templateEditorTarget.value?.id === templateDeleteTarget.value?.id) {
        templateEditorOpen.value = false
        templateEditorTarget.value = null
      }
      templateDeleteTarget.value = null
      await refreshTemplates()
    }
    if (kind === 'category') {
      if (selectedCategoryId.value === confirmDialogCategory.value?.id) selectedCategoryId.value = null
      categories.value = await fetchKnowledgeCategories(selectedTeamId.value)
      await loadView()
    }
  } catch (cause: any) { fail(cause, '删除失败。') }
}

async function saveShares(userIds: string[], permission: NoteSharePermission) {
  if (!selectedNote.value) return
  busy.value = true
  try {
    shares.value = await syncNoteShares(selectedNote.value.id, userIds, permission)
    shareDialogOpen.value = false
    notify('分享权限已更新。')
    void refreshNoteMeta()
    if (currentView.value === 'sharedByMe') sharedByMeNotes.value = await fetchNotesSharedByMe()
  } catch (cause: any) { fail(cause, '分享失败。') }
  finally { busy.value = false }
}

async function changeSharePermission(shareId: string, permission: NoteSharePermission) {
  if (!selectedNote.value) return
  try {
    const updated = await updateNoteSharePermission(selectedNote.value.id, shareId, permission)
    shares.value = shares.value.map((item) => (item.id === updated.id ? updated : item))
    notify(updated.permission === 'EDITABLE' ? '已允许对方协作编辑。' : '已调整为只读共享。')
    if (currentView.value === 'sharedByMe') sharedByMeNotes.value = await fetchNotesSharedByMe()
  } catch (cause: any) { fail(cause, '权限调整失败。') }
}

// note.changed 在每次投影后都会到达（包括自己打字触发的），防抖避免请求风暴；
// 选中的分享笔记只重取自身详情，不再重取整个分享列表。
let sharedRefreshTimer: number | undefined
function refreshSelectedShared() {
  if (sharedRefreshTimer !== undefined) window.clearTimeout(sharedRefreshTimer)
  sharedRefreshTimer = window.setTimeout(() => { void refreshSelectedSharedNow() }, 400)
}

async function refreshSharedNoteById(noteId: string) {
  try {
    const fresh = await fetchSharedNote(noteId)
    const visible = upsertSharedNoteListItem(fresh)
    if (selectedShared.value?.id !== noteId) return
    if (visible) selectedShared.value = fresh
    else selectedShared.value = null
  } catch {
    // 权限已被收回：详情与对应列表条目一并移除，避免继续展示拿不到的内容。
    removeSharedNoteListItem(noteId)
    if (selectedShared.value?.id === noteId) selectedShared.value = null
  }
}

async function refreshSelectedSharedNow() {
  const noteId = selectedShared.value?.id
  if (!noteId) return
  await refreshSharedNoteById(noteId)
}

function applySharedNoteChange(change: NonNullable<typeof realtime.lastNoteChange>) {
  if (change.deleted) {
    removeSharedNoteListItem(change.noteId)
    if (selectedShared.value?.id === change.noteId) selectedShared.value = null
    return
  }
  const existing = sharedNotes.value.find((item) => item.id === change.noteId)
  if (!existing) {
    void refreshSharedNoteById(change.noteId)
    return
  }
  const updated: SharedNote = {
    ...existing,
    title: change.title,
    folderId: change.folderId !== undefined ? change.folderId : existing.folderId,
    isFavorite: change.isFavorite !== undefined ? change.isFavorite : existing.isFavorite,
    updatedAt: change.updatedAt ?? existing.updatedAt,
  }
  upsertSharedNoteListItem(updated)
  if (selectedShared.value?.id === change.noteId) {
    selectedShared.value = { ...selectedShared.value, ...updated }
    refreshSelectedShared()
  } else if (search.value.trim()) {
    // The event does not carry plainText, so a filtered list needs one
    // targeted read to confirm that a body edit still matches the query.
    void refreshSharedNoteById(change.noteId)
  }
}

async function openPublish(type?: 'CREATE' | 'UPDATE', targetId?: string | null) {
  if (!(await syncSelectedNoteForAction())) return
  const linkedTargetId = selectedKnowledgeForNote.value?.id ?? null
  const resolvedTargetId = targetId ?? linkedTargetId
  publishType.value = type ?? (resolvedTargetId ? 'UPDATE' : 'CREATE')
  publishTargetId.value = resolvedTargetId
  publishTargetLocked.value = Boolean(resolvedTargetId)
  publishDialogOpen.value = true
}
async function publish(payload: SubmissionPayload) {
  const snapshot = await syncSelectedNoteForAction()
  if (!snapshot) return
  busy.value = true
  try {
    const submission = await submitNoteToKnowledge(snapshot.note.id, payload, selectedTeamId.value)
    mySubmissions.value.unshift(submission)
    publishDialogOpen.value = false
    await refreshNoteMeta()
    notify('已生成审核快照，可在“我的投稿”查看进度。')
  }
  catch (cause: any) { fail(cause, '提交审核失败。') }
  finally { busy.value = false }
}

async function copyShared(note: SharedNote) {
  const copied = await copySharedNote(note.id)
  await activateView('all')
  upsertNoteListItem(copied)
  await refreshNoteMeta()
  await selectPersonal(copied)
}
async function copyTeamKnowledge(note: TeamNote) {
  const copied = await copyKnowledge(note.id, selectedTeamId.value)
  await activateView('all')
  upsertNoteListItem(copied)
  await refreshNoteMeta()
  await selectPersonal(copied)
}
async function duplicatePersonal(note: Note) {
  const snapshot = note.id === selectedNote.value?.id ? await syncSelectedNoteForAction(note.id) : null
  const copied = await copyNote(snapshot?.note.id ?? note.id)
  upsertNoteListItem(copied)
  await refreshNoteMeta()
  await selectPersonal(copied)
}
async function exportPersonal(note: Note) {
  const snapshot = note.id === selectedNote.value?.id ? await syncSelectedNoteForAction(note.id) : null
  const source = snapshot?.note ?? note
  const payload = snapshot
    ? noteToMarkdown({ ...source, title: snapshot.title, contentJson: snapshot.contentJson }, attachments.value)
    : noteToMarkdown(source, attachments.value)
  const url = URL.createObjectURL(new Blob([payload], { type: 'text/markdown;charset=utf-8' }))
  const anchor = document.createElement('a')
  anchor.href = url
  anchor.download = `${source.title.replace(/[\\/:*?"<>|]/g, '_') || '笔记'}.md`
  anchor.click()
  URL.revokeObjectURL(url)
}
async function requestKnowledgeUpdate(note: TeamNote) {
  busy.value = true
  try {
    const draft = await ensureKnowledgeUpdateDraft(note.id, selectedTeamId.value)
    await activateView('all')
    await refreshNoteMeta()
    upsertNoteListItem(draft)
    await selectPersonal(draft)
    if (note.myUpdateSubmissionStatus === 'PENDING') notify('这篇知识已有待审核更新，已打开对应笔记。')
    else if (note.myUpdateSubmissionStatus === 'NEEDS_REVISION') notify('这篇知识的更新需要修改，已打开对应笔记。')
    else notify('已打开更新草稿，修改完成后请提交更新申请。')
  } catch (cause: any) { fail(cause, '更新草稿创建失败。') }
  finally { busy.value = false }
}

async function createKnowledge(title: string) {
  const item = await postKnowledge({ title }, selectedTeamId.value)
  knowledgeCreateDialogOpen.value = false
  upsertKnowledgeListItem(item)
  upsertKnowledgeDetail(item)
  selectedKnowledge.value = item
  await refreshNoteMeta()
  await refreshKnowledgeCategories()
}
async function openKnowledge(note: TeamNote | TeamNoteListItem) {
  await router.push({ path: '/notes', query: { view: 'knowledge', knowledge: note.id } })
}
function selectKnowledgeStatus(value: 'published' | 'archived') {
  knowledgeStatusFilter.value = value
  const requested = typeof route.query.knowledge === 'string' ? route.query.knowledge : selectedKnowledge.value?.id
  const summary = visibleKnowledge.value.find((item) => item.id === requested) ?? null
  if (summary && summary.id !== selectedKnowledge.value?.id) void selectKnowledge(summary)
  else if (!summary) selectedKnowledge.value = null
}
function openCreateCategory() { categoryDialogMode.value = 'create'; categoryDialogTarget.value = null; categoryDialogName.value = ''; categoryDialogOpen.value = true }
function openRenameCategory(category: KnowledgeCategory) { categoryDialogMode.value = 'rename'; categoryDialogTarget.value = category; categoryDialogName.value = category.name; categoryDialogOpen.value = true }
async function saveCategory(name: string) {
  if (categoryDialogMode.value === 'create') await postKnowledgeCategory({ name, sortOrder: categories.value.length * 10 }, selectedTeamId.value)
  else if (categoryDialogTarget.value) await putKnowledgeCategory(categoryDialogTarget.value.id, { name }, selectedTeamId.value)
  categoryDialogOpen.value = false
  categories.value = await fetchKnowledgeCategories(selectedTeamId.value)
}
async function saveKnowledge(
  note: TeamNote,
  payload: { title: string; contentJson: Record<string, unknown>; plainText: string; categoryId: string | null; tags: string[]; baseVersion: number },
  settled?: (versionNo: number) => void,
) {
  busy.value = true
  try {
    const updated = await commitKnowledge(note.id, payload, selectedTeamId.value)
    selectedKnowledge.value = updated
    upsertKnowledgeDetail(updated)
    upsertKnowledgeListItem(updated)
    settled?.(updated.versionNo)
    if (note.categoryId !== updated.categoryId) await refreshKnowledgeCategories()
  } catch (cause: any) { fail(cause, '保存团队知识失败，请稍后重试。') }
  finally { busy.value = false }
}
async function setArchived(note: TeamNote, archived: boolean) {
  busy.value = true
  try {
    const updated = archived
      ? await archiveKnowledge(note.id, selectedTeamId.value)
      : await restoreKnowledge(note.id, selectedTeamId.value)
    upsertKnowledgeDetail(updated)
    upsertKnowledgeListItem(updated)
    selectedKnowledge.value = updated
    knowledgeStatusFilter.value = archived ? 'archived' : 'published'
    await refreshNoteMeta()
    await refreshKnowledgeCategories()
  } catch (cause: any) { fail(cause, archived ? '归档知识失败。' : '恢复知识失败。') }
  finally { busy.value = false }
}
function requestArchiveKnowledge(note: TeamNote) {
  archiveConfirmTarget.value = note
  archiveConfirmOpen.value = true
}
async function confirmArchiveKnowledge() {
  const target = archiveConfirmTarget.value
  archiveConfirmOpen.value = false
  archiveConfirmTarget.value = null
  if (target) await setArchived(target, true)
}
function requestDeleteKnowledge(note: TeamNote) {
  knowledgeDeleteTarget.value = note
  knowledgeDeleteConfirmOpen.value = true
}
async function confirmDeleteKnowledge() {
  const target = knowledgeDeleteTarget.value
  knowledgeDeleteConfirmOpen.value = false
  knowledgeDeleteTarget.value = null
  if (!target || !selectedTeamId.value) return
  busy.value = true
  try {
    await deleteKnowledge(target.id, selectedTeamId.value)
    selectedKnowledge.value = null
    removeKnowledgeListItem(target.id)
    await refreshNoteMeta()
    await refreshKnowledgeCategories()
    notify('团队知识已彻底删除。')
  } catch (cause: any) {
    fail(cause, '彻底删除团队知识失败。')
  } finally {
    busy.value = false
  }
}
async function showVersions(note: TeamNote) { versions.value = await fetchKnowledgeVersions(note.id, selectedTeamId.value); versionsOpen.value = true }

async function withdraw(item: TeamNoteSubmission) { replaceSubmission(await withdrawSubmission(item.id)); await refreshNoteMeta() }
async function resubmit(item: TeamNoteSubmission) {
  replaceSubmission(await resubmitSubmission(item.id, { type: item.submissionType, targetTeamNoteId: item.targetTeamNoteId, categoryId: item.proposedCategoryId, tags: item.proposedTagsJson, message: item.submissionMessage }))
  await refreshNoteMeta()
}
async function approve(item: TeamNoteSubmission, payload: SubmissionReviewPayload) {
  const approved = await approveSubmission(item.id, payload)
  upsertKnowledgeDetail(approved)
  upsertKnowledgeListItem(approved)
  removeSubmission(item.id)
  await refreshNoteMeta()
  await refreshKnowledgeCategories()
}
async function revision(item: TeamNoteSubmission, reason: string) { replaceSubmission(await requestSubmissionRevision(item.id, reason)); await refreshNoteMeta() }
async function reject(item: TeamNoteSubmission, reason: string) { replaceSubmission(await rejectSubmission(item.id, reason)); await refreshNoteMeta() }
async function openSource(noteId: string) {
  await router.push({ path: '/notes', query: { view: 'all', note: noteId } })
}

function updateSearch(value: string) { search.value = value; window.clearTimeout(searchTimer); searchTimer = window.setTimeout(loadView, 300) }
async function refreshTemplates() { templates.value = await fetchNoteTemplates() }
async function openTemplates() {
  try {
    await refreshTemplates()
    templateDialogOpen.value = true
  } catch (cause: any) { fail(cause, '模板读取失败。') }
}
async function createFromTemplate(template: NoteTemplate) {
  try {
    const note = await postNoteFromTemplate(template.id, selectedFolderId.value)
    templateDialogOpen.value = false
    await refreshNoteMeta()
    upsertNoteListItem(note)
    await selectPersonal(note)
  } catch (cause: any) { fail(cause, '从模板创建笔记失败。') }
}
function openNewTemplate() {
  templateDialogOpen.value = false
  templateManagerOpen.value = false
  templateEditorTarget.value = null
  templateEditorOpen.value = true
}
function openEditTemplate(template: NoteTemplate) {
  if (template.isBuiltin) return
  templateDialogOpen.value = false
  templateManagerOpen.value = false
  templateEditorTarget.value = template
  templateEditorOpen.value = true
}
function openTemplateManager() {
  templateDialogOpen.value = false
  templateManagerOpen.value = true
}
async function saveTemplate(payload: { name: string; description: string | null; contentJson: Record<string, unknown> }) {
  templateSaving.value = true
  try {
    if (templateEditorTarget.value) await putNoteTemplate(templateEditorTarget.value.id, payload)
    else await postNoteTemplate({ ...payload, sortOrder: nextTemplateSortOrder() })
    await refreshTemplates()
    templateEditorOpen.value = false
    templateEditorTarget.value = null
  } catch (cause: any) { fail(cause, '模板保存失败。') }
  finally { templateSaving.value = false }
}
async function saveNoteAsTemplate(payload: { name: string; description: string | null }) {
  const source = templateSource.value
  if (!source) return
  templateSaving.value = true
  try {
    await postNoteTemplate({ ...payload, contentJson: source.contentJson, sortOrder: nextTemplateSortOrder() })
    await refreshTemplates()
    templateSaveDialogOpen.value = false
    templateSource.value = null
  } catch (cause: any) { fail(cause, '保存为模板失败。') }
  finally { templateSaving.value = false }
}
function requestDeleteTemplate(template: NoteTemplate) {
  if (template.isBuiltin) return
  templateDeleteTarget.value = template
  confirmDialogKind.value = 'template'
  confirmDialogOpen.value = true
}
function nextTemplateSortOrder(): number {
  const personal = templates.value.filter((template) => !template.isBuiltin)
  return personal.length ? Math.max(...personal.map((template) => template.sortOrder)) + 10 : 100
}
async function moveTemplate(template: NoteTemplate, direction: 'up' | 'down') {
  const personal = templates.value.filter((item) => !item.isBuiltin)
  const index = personal.findIndex((item) => item.id === template.id)
  const targetIndex = direction === 'up' ? index - 1 : index + 1
  if (index < 0 || targetIndex < 0 || targetIndex >= personal.length) return
  const reordered = [...personal]
  const [moved] = reordered.splice(index, 1)
  reordered.splice(targetIndex, 0, moved)
  templateSaving.value = true
  try {
    await Promise.all(reordered.map((item, order) => putNoteTemplate(item.id, { sortOrder: (order + 1) * 10 })))
    await refreshTemplates()
  } catch (cause: any) { fail(cause, '模板排序保存失败。') }
  finally { templateSaving.value = false }
}
function createFolder(parentId: string | null) { folderDialogMode.value = 'create'; folderDialogName.value = ''; folderDialogParentId.value = parentId; folderDialogParentName.value = folders.value.find((item) => item.id === parentId)?.name ?? null; folderDialogTarget.value = null; folderDialogOpen.value = true }
function renameFolder(folder: Folder) { folderDialogMode.value = 'rename'; folderDialogName.value = folder.name; folderDialogTarget.value = folder; folderDialogOpen.value = true }
function removeFolder(folder: Folder) { folderDialogMode.value = 'delete'; folderDialogName.value = folder.name; folderDialogTarget.value = folder; folderDialogOpen.value = true }
async function submitFolder(name: string) {
  if (folderDialogMode.value === 'create') {
    folders.value.push(await postFolder({ name, parentId: folderDialogParentId.value }))
  } else if (folderDialogTarget.value) {
    const updated = await putFolder(folderDialogTarget.value.id, { name })
    const index = folders.value.findIndex((item) => item.id === updated.id)
    if (index >= 0) folders.value[index] = updated
  }
  folderDialogOpen.value = false
}
async function confirmRemoveFolder() {
  const target = folderDialogTarget.value
  if (target) {
    await deleteFolder(target.id)
    folders.value = folders.value.filter((item) => item.id !== target.id)
    if (selectedFolderId.value === target.id) {
      selectedFolderId.value = null
      await router.push({ path: '/notes', query: { view: 'all' } })
    }
  }
  folderDialogOpen.value = false
}

async function openTask(taskId: string) {
  await router.push({ path: '/todos', query: { view: 'all', todo: taskId } })
}

async function finishOnboarding() {
  await router.replace('/')
}

watch(() => workspace.currentTeamId, () => {
  void refreshNoteMeta()
})

watch(() => [route.query.view, route.query.note] as const, ([view, note], [previousView, previousNote]) => {
  // 随手记保存后会把当前路由切到收件箱；此时页面仍然挂载，需同步更新徽标。
  if (view === 'inbox' && (view !== previousView || note !== previousNote)) void refreshNoteMeta()
})

watch(() => [route.query.view, route.query.note, route.query.shared, route.query.submission, route.query.knowledge, workspace.currentTeamId] as const, () => {
  void loadView()
})

watch(() => realtime.lastTeamNoteChange, (change) => {
  if (change) applyTeamNoteChange(change)
})

watch(() => realtime.lastNoteChange, (change) => {
  if (!change) return
  applyNoteChange(change)
  if (currentView.value === 'sharedByMe') applySharedByMeChange(change)
  if (currentView.value === 'shared') applySharedNoteChange(change)
})

onMounted(async () => {
  const metadataRequests = [
    fetchFolders()
      .then((loadedFolders) => { folders.value = loadedFolders })
      .catch((cause: any) => { fail(cause, '文件夹读取失败。') }),
    refreshNoteMeta().catch((cause: any) => { fail(cause, '笔记统计读取失败。') }),
    currentTeam.value
      ? fetchTeamMembers(currentTeam.value.id)
        .then((loadedMembers) => { members.value = loadedMembers })
        .catch(() => undefined)
      : Promise.resolve(),
  ]
  await Promise.all([loadView(), ...metadataRequests])
})

onBeforeRouteUpdate(() => flushEditorsForNavigation())
onBeforeRouteLeave(() => flushEditorsForNavigation())
</script>

<template>
  <div class="notes-page unified-notes-page">
    <section v-if="onboarding" class="onboarding-banner" aria-label="新手指引">
      <div><span class="eyebrow">FIRST RUN</span><strong>欢迎来到备忘录</strong><p>先阅读这份使用指南，再开始安排你的工作。</p></div>
      <button class="primary-button" type="button" @click="finishOnboarding">开始使用</button>
    </section>
    <div class="notes-workspace card" :aria-busy="viewLoading">
      <NoteNavigation :view="currentView" :folders="folders" :selected-folder-id="selectedFolderId" :all-count="navigationCounts.all" :unfiled-count="navigationCounts.unfiled" :favorite-count="navigationCounts.favorites" :folder-counts="navigationCounts.folders" :shared-count="navigationCounts.shared" :shared-by-me-count="navigationCounts.sharedByMe" :knowledge-count="navigationCounts.knowledge" :submissions-count="navigationCounts.submissionsTotal" :submissions-pending-count="navigationCounts.submissionsPending" :review-pending-count="navigationCounts.reviewPending" :has-team="hasTeam" :can-review="canReview" :categories="categories" :selected-category-id="selectedCategoryId" @view="activateView" @folder="selectFolder" @category="selectCategory" @create-category="openCreateCategory" @rename-category="openRenameCategory" @remove-category="requestDeleteCategory" @create-folder="createFolder" @rename-folder="renameFolder" @remove-folder="removeFolder" @open-search="openGlobalSearch" />
      <template v-if="personalView || currentView === 'sharedByMe'">
        <NoteList :notes="currentView === 'sharedByMe' ? sharedByMeNotes : notes" :selected-id="selectedNote?.id ?? null" :search="search" :heading="currentView === 'sharedByMe' ? '我分享的' : noteListHeading" :loading="viewLoading" :empty-state="currentView === 'sharedByMe' ? { title: '还没有分享出去的笔记', description: '打开一篇笔记，点右上角 ⋯ → 分享，勾选团队成员即可；取消分享也在同一个弹窗里。', actions: false } : null" @select="selectPersonal" @create="createBlankNote" @templates="openTemplates" @import="openMarkdownImport" @search="updateSearch" @remove="requestDeleteNote" />
        <NoteEditor
          ref="noteEditor"
          :key="selectedNote?.id ?? 'empty-note'"
          :note="selectedNote"
          :folders="folders"
          :attachments="attachments"
          :upload-file="handleUpload"
          :collaboration="hasTeam"
          :knowledge-state="selectedKnowledgeState"
          :knowledge-target-title="selectedKnowledgeForNote?.title ?? null"
          :task-members="members"
          :task-team-id="selectedTeamId ?? null"
          :current-user-id="auth.user?.id"
          :can-assign-tasks="canReview"
          :focus-block-id="typeof route.query.block === 'string' ? route.query.block : null"
          @move-folder="moveSelectedNote"
          @delete-attachment="requestDeleteAttachment"
          @open-task="openTask"
          @share="openShareDialog"
          @publish="openPublish()"
          @favorite="toggleFavorite"
          @duplicate="duplicatePersonal"
          @export="exportPersonal"
          @change="applyCollaborativeNoteChange"
          @save-as-template="prepareSaveAsTemplate"
          @remove="selectedNote && requestDeleteNote(selectedNote)"
        />
      </template>
      <template v-else-if="currentView === 'shared'">
        <CollaborativeNoteList title="分享给我的" :items="visibleSharedNotes" :selected-id="selectedShared?.id ?? null" :search="search" :loading="viewLoading" @select="selectShared" @search="updateSearch" />

        <SharedNoteDetail :note="selectedShared" :copying="busy" @copy="copyShared" @refresh="refreshSelectedShared" />
      </template>
      <template v-else-if="currentView === 'knowledge'">
        <CollaborativeNoteList title="团队知识库" :items="visibleKnowledge" :selected-id="selectedKnowledge?.id ?? null" :search="search" :loading="viewLoading" :can-create="canReview" :can-manage-archived="canReview" :status-filter="knowledgeStatusFilter" @select="selectCollaborationItem" @search="updateSearch" @create="knowledgeCreateDialogOpen = true" @status-filter="selectKnowledgeStatus" />
        <KnowledgeDetail ref="knowledgeDetail" :note="selectedKnowledge" :categories="categories" :saving="busy" :update-state="selectedKnowledgeUpdateState" @commit="saveKnowledge" @copy="copyTeamKnowledge" @archive="requestArchiveKnowledge" @restore="setArchived($event, false)" @delete="requestDeleteKnowledge" @update-request="requestKnowledgeUpdate" @versions="showVersions" />
      </template>
      <SubmissionWorkspace v-else :mode="currentView === 'review' ? 'review' : 'mine'" :submissions="submissions" :selected="selectedSubmission" :related="relatedKnowledge" :knowledge="knowledgeDetails" :categories="categories" :busy="busy" @select="selectSubmission" @withdraw="withdraw" @resubmit="resubmit" @open-source="openSource" @open-knowledge="openKnowledge" @approve="approve" @revision="revision" @reject="reject" />
    </div>

    <ShareNotePopover :open="shareDialogOpen" :members="shareMembers.length ? shareMembers : members" :shares="shares" :model-value="shares.map((item) => item.sharedWithUserId)" :current-user-id="auth.user?.id ?? ''" :saving="busy" @close="shareDialogOpen = false" @save="saveShares" @change-permission="changeSharePermission" />
    <PublishToKnowledgeDialog :open="publishDialogOpen" :note="selectedNote" :categories="categories" :knowledge="knowledge" :default-type="publishType" :default-target-id="publishTargetId" :target-locked="publishTargetLocked" :saving="busy" @close="publishDialogOpen = false" @submit="publish" />
    <NoteTemplateDialog :open="templateDialogOpen" :templates="templates" @close="templateDialogOpen = false" @select="createFromTemplate" @create="openNewTemplate" @manage="openTemplateManager" @edit="openEditTemplate" @delete="requestDeleteTemplate" />
    <NoteTemplateManagerDialog :open="templateManagerOpen" :templates="templates" @close="templateManagerOpen = false" @edit="openEditTemplate" @delete="requestDeleteTemplate" @move="moveTemplate" />
    <NoteTemplateEditorDialog :open="templateEditorOpen" :template="templateEditorTarget" :saving="templateSaving" @close="templateEditorOpen = false" @save="saveTemplate" @delete="templateEditorTarget && requestDeleteTemplate(templateEditorTarget)" />
    <NoteTemplateSaveDialog :open="templateSaveDialogOpen" :saving="templateSaving" @close="templateSaveDialogOpen = false" @save="saveNoteAsTemplate" />
    <MarkdownImportDialog :open="markdownImportOpen" :folders="folders" :initial-folder-id="selectedFolderId" :saving="markdownImportSaving" :error="markdownImportError" @close="markdownImportOpen = false" @clear-error="markdownImportError = null" @submit="importMarkdown" />
    <FolderDialog :open="folderDialogOpen" :mode="folderDialogMode" :initial-name="folderDialogName" :parent-name="folderDialogParentName" @close="folderDialogOpen = false" @submit="submitFolder" @confirm="confirmRemoveFolder" />
    <InputDialog :open="categoryDialogOpen" :title="categoryDialogMode === 'create' ? '新建知识分类' : '重命名知识分类'" label="分类名称" placeholder="例如：技术、流程、规范" :initial-value="categoryDialogName" :confirm-label="categoryDialogMode === 'create' ? '创建' : '保存'" @close="categoryDialogOpen = false" @submit="saveCategory" />
    <InputDialog :open="knowledgeCreateDialogOpen" title="新建团队知识" label="知识标题" placeholder="输入清晰、可检索的标题" confirm-label="创建并编辑" @close="knowledgeCreateDialogOpen = false" @submit="createKnowledge" />
    <ConfirmDialog :open="archiveConfirmOpen" title="归档团队知识" :message="archiveConfirmTarget ? `确认归档“${archiveConfirmTarget.title}”吗？归档后团队成员将无法在知识库中查看，正文、附件和版本历史都会保留，可在“已归档”中恢复。` : ''" confirm-label="归档" :danger="true" @close="archiveConfirmOpen = false" @confirm="confirmArchiveKnowledge" />
    <ConfirmDialog :open="knowledgeDeleteConfirmOpen" title="彻底删除团队知识" :message="knowledgeDeleteTarget ? `确认彻底删除“${knowledgeDeleteTarget.title}”吗？正文、版本历史和团队附件授权将永久移除，已经复制到个人笔记的副本不受影响。仍有待处理的更新申请时无法删除。` : ''" confirm-label="彻底删除" :danger="true" @close="knowledgeDeleteConfirmOpen = false" @confirm="confirmDeleteKnowledge" />
    <ConfirmDialog :open="confirmDialogOpen" title="确认删除" :message="confirmDialogKind === 'template' ? '删除模板不会删除已经通过该模板创建的笔记。' : confirmDialogKind === 'category' ? '删除分类后，分类下的知识会保留并变为未分类。' : '删除后无法继续通过分享访问，已发布团队知识不受影响。'" :danger="true" confirm-label="删除" @close="confirmDialogOpen = false" @confirm="confirmDelete" />
    <Teleport to="body"><div v-if="globalSearchOpen" class="dialog-backdrop global-search-backdrop" @mousedown.self="closeGlobalSearch"><section class="global-search-dialog" role="dialog" aria-modal="true" aria-labelledby="global-search-title" @keydown.esc="closeGlobalSearch"><header><div><span class="eyebrow">SEARCH</span><h2 id="global-search-title">全局搜索</h2><p>搜索个人笔记、分享内容和团队知识</p></div><button type="button" aria-label="关闭全局搜索" @click="closeGlobalSearch"><IconX :size="18" /></button></header><label class="notes-global-search global-search-input"><IconSearch :size="17" aria-hidden="true" /><input ref="globalSearchInput" :value="globalSearchQuery" autofocus placeholder="输入标题或正文…" @input="updateGlobalSearch(($event.target as HTMLInputElement).value)" /><button v-if="globalSearchQuery" type="button" aria-label="清空搜索" @click="updateGlobalSearch('')"><IconX :size="15" /></button></label><p v-if="globalSearchError" class="global-search-error" role="alert">{{ globalSearchError }}</p><SearchResults :items="globalSearchItems" :query="globalSearchQuery" :loading="globalSearchLoading" @select="selectSearchResult" /></section></div></Teleport>
    <Teleport to="body"><div v-if="versionsOpen" class="dialog-backdrop" @mousedown.self="versionsOpen = false"><section class="note-collab-dialog version-dialog" role="dialog" aria-modal="true" aria-labelledby="version-dialog-title"><header><div><span class="eyebrow">HISTORY</span><h2 id="version-dialog-title">知识版本</h2></div><button type="button" aria-label="关闭知识版本" @click="versionsOpen = false"><IconX :size="18" /></button></header><div class="version-list"><article v-for="item in versions" :key="item.id"><strong>V{{ item.versionNo }} · {{ item.changeType }}</strong><span>{{ new Date(item.createdAt).toLocaleString('zh-CN') }}</span></article></div></section></div></Teleport>
  </div>
</template>
