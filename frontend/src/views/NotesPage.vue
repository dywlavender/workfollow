<script setup lang="ts">
import { IconX } from '@tabler/icons-vue'
import { computed, onMounted, ref, watch } from 'vue'
import { useRoute, useRouter } from 'vue-router'

import ConfirmDialog from '@/components/ConfirmDialog.vue'
import InputDialog from '@/components/InputDialog.vue'
import CollaborativeNoteList from '@/components/notes/CollaborativeNoteList.vue'
import FolderDialog from '@/components/notes/FolderDialog.vue'
import KnowledgeDetail from '@/components/notes/KnowledgeDetail.vue'
import MarkdownImportDialog from '@/components/notes/MarkdownImportDialog.vue'
import NoteEditor from '@/components/notes/NoteEditor.vue'
import NoteList from '@/components/notes/NoteList.vue'
import NoteNavigation, { type NoteView } from '@/components/notes/NoteNavigation.vue'
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
  approveSubmission, archiveKnowledge, copyKnowledge, copyNote, copySharedNote, deleteAttachment, deleteFolder, deleteKnowledgeCategory, deleteNote,
  fetchAttachments, fetchFolders, fetchKnowledge, fetchKnowledgeCategories, fetchKnowledgeVersions,
  deleteNoteTemplate, fetchMySubmissions, fetchNoteShares, fetchNotes, fetchNoteTemplates, fetchRelatedKnowledge,
  fetchReviewSubmissions, fetchSharedNotes, fetchTeamMembers, importMarkdownNote, postFolder, postKnowledge, postNote,
  postKnowledgeCategory,
  postNoteFromTemplate, postNoteTemplate, postNoteTemplateFromNote, putFolder, putKnowledge, putKnowledgeCategory, putNote, putNoteTemplate, rejectSubmission,
  requestSubmissionRevision, resubmitSubmission, restoreKnowledge, submitNoteToKnowledge, syncNoteShares, ensureKnowledgeUpdateDraft,
  uploadAttachment, withdrawSubmission,
  type Attachment, type Folder, type KnowledgeCategory, type Note, type NoteShare,
  type NoteTemplate, type SharedNote, type SubmissionPayload, type SubmissionReviewPayload, type TeamMember, type TeamNote,
  type TeamNoteSubmission, type TeamNoteVersion,
} from '@/services/api'
import { useAuthStore } from '@/stores/auth'
import { useWorkspaceStore } from '@/stores/workspace'

const route = useRoute()
const router = useRouter()
const auth = useAuthStore()
const workspace = useWorkspaceStore()
const currentTeam = computed(() => workspace.currentTeam ?? workspace.teams[0] ?? null)
const selectedTeamId = computed(() => currentTeam.value?.id)
const hasTeam = computed(() => Boolean(currentTeam.value))
const isRoot = computed(() => auth.user?.systemRole === 'ROOT')
const canReview = computed(() => isRoot.value || currentTeam.value?.role === 'OWNER' || currentTeam.value?.role === 'ADMIN')

const folders = ref<Folder[]>([])
const notes = ref<Note[]>([])
const sharedNotes = ref<SharedNote[]>([])
const knowledge = ref<TeamNote[]>([])
const archivedKnowledge = ref<TeamNote[]>([])
const categories = ref<KnowledgeCategory[]>([])
const members = ref<TeamMember[]>([])
const submissions = ref<TeamNoteSubmission[]>([])
const mySubmissions = ref<TeamNoteSubmission[]>([])
const relatedKnowledge = ref<TeamNote[]>([])
const versions = ref<TeamNoteVersion[]>([])
const selectedFolderId = ref<string | null>(null)
const selectedCategoryId = ref<string | null>(null)
const selectedNote = ref<Note | null>(null)
const selectedShared = ref<SharedNote | null>(null)
const selectedKnowledge = ref<TeamNote | null>(null)
const selectedSubmission = ref<TeamNoteSubmission | null>(null)
const attachments = ref<Attachment[]>([])
const shares = ref<NoteShare[]>([])
const search = ref('')
const knowledgeStatusFilter = ref<'published' | 'archived'>('published')
const pageError = ref<string | null>(null)
const busy = ref(false)
const validViews: NoteView[] = ['recent', 'all', 'favorites', 'shared', 'knowledge', 'submissions', 'review']
const currentView = computed<NoteView>(() => {
  const requested = typeof route.query.view === 'string' ? route.query.view as NoteView : 'all'
  if (!validViews.includes(requested)) return 'all'
  if (!hasTeam.value && ['shared', 'knowledge', 'submissions', 'review'].includes(requested)) return 'all'
  if (requested === 'review' && !canReview.value) return 'submissions'
  return requested
})
const onboarding = computed(() => route.query.onboarding === '1')
const personalView = computed(() => ['recent', 'all', 'favorites'].includes(currentView.value))
const visibleKnowledge = computed(() => knowledgeStatusFilter.value === 'archived' ? archivedKnowledge.value : knowledge.value)
const visibleSharedNotes = computed(() => {
  const query = search.value.trim().toLocaleLowerCase()
  if (!query) return sharedNotes.value
  return sharedNotes.value.filter((item) => [item.title, item.plainText, item.sharedBy.nickname, item.sharedBy.username]
    .some((value) => value.toLocaleLowerCase().includes(query)))
})
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
const confirmDialogNote = ref<Note | null>(null)
const confirmDialogAttachment = ref<Attachment | null>(null)
const confirmDialogCategory = ref<KnowledgeCategory | null>(null)
const archiveConfirmOpen = ref(false)
const archiveConfirmTarget = ref<TeamNote | null>(null)
let searchTimer: number | undefined

function notify(message: string) { pageError.value = message }
function fail(cause: any, fallback: string) { pageError.value = cause?.response?.data?.detail ?? fallback }

async function loadPersonal() {
  notes.value = await fetchNotes({
    folderId: currentView.value === 'all' ? selectedFolderId.value ?? undefined : undefined,
    q: search.value.trim() || undefined,
    favorite: currentView.value === 'favorites' ? true : undefined,
    limit: currentView.value === 'recent' ? 30 : undefined,
  })
  const requestedNoteId = typeof route.query.note === 'string' ? route.query.note : null
  if (requestedNoteId) {
    selectedNote.value = notes.value.find((item) => item.id === requestedNoteId) ?? selectedNote.value
  }
  if (!selectedNote.value || !notes.value.some((item) => item.id === selectedNote.value?.id)) {
    selectedNote.value = notes.value[0] ?? null
  }
  if (selectedNote.value) await selectPersonal(selectedNote.value)
}

async function loadCollaboration() {
  if (!hasTeam.value) return
  const [loadedKnowledge, loadedCategories, loadedMySubmissions] = await Promise.all([
    fetchKnowledge({ q: currentView.value === 'knowledge' ? search.value.trim() || undefined : undefined, categoryId: selectedCategoryId.value ?? undefined, includeArchived: canReview.value ? true : undefined, teamId: selectedTeamId.value }),
    fetchKnowledgeCategories(selectedTeamId.value),
    fetchMySubmissions(selectedTeamId.value),
  ])
  knowledge.value = loadedKnowledge.filter((item) => item.status === 'PUBLISHED')
  archivedKnowledge.value = loadedKnowledge.filter((item) => item.status === 'ARCHIVED')
  categories.value = loadedCategories
  mySubmissions.value = loadedMySubmissions
  if (currentTeam.value) members.value = await fetchTeamMembers(currentTeam.value.id)
}

async function loadView() {
  busy.value = true
  try {
    if (personalView.value) await loadPersonal()
    else if (currentView.value === 'shared') {
      sharedNotes.value = await fetchSharedNotes()
      selectedShared.value = visibleSharedNotes.value.find((item) => item.id === selectedShared.value?.id) ?? visibleSharedNotes.value[0] ?? null
    } else if (currentView.value === 'knowledge') {
      await loadCollaboration()
      const requested = typeof route.query.knowledge === 'string' ? route.query.knowledge : selectedKnowledge.value?.id
      selectedKnowledge.value = visibleKnowledge.value.find((item) => item.id === requested) ?? visibleKnowledge.value[0] ?? null
    } else {
      if (!hasTeam.value || !selectedTeamId.value) {
        submissions.value = []
        selectedSubmission.value = null
        relatedKnowledge.value = []
        return
      }
      submissions.value = currentView.value === 'review' ? await fetchReviewSubmissions(selectedTeamId.value) : await fetchMySubmissions(selectedTeamId.value)
      const requestedSubmission = typeof route.query.submission === 'string' ? route.query.submission : selectedSubmission.value?.id
      selectedSubmission.value = submissions.value.find((item) => item.id === requestedSubmission) ?? submissions.value[0] ?? null
      if (currentView.value === 'review' && selectedSubmission.value) relatedKnowledge.value = await fetchRelatedKnowledge(selectedSubmission.value.id)
    }
  } catch (cause: any) {
    fail(cause, '笔记服务读取失败。')
  } finally { busy.value = false }
}

async function activateView(view: NoteView) {
  search.value = ''
  await router.push({ path: '/notes', query: { view } })
}

async function selectFolder(id: string | null) {
  selectedFolderId.value = id
  if (currentView.value !== 'all') await router.push({ path: '/notes', query: { view: 'all' } })
  else await loadPersonal()
}
async function selectCategory(id: string | null) { selectedCategoryId.value = id; if (currentView.value === 'knowledge') await loadView() }

async function selectPersonal(note: Note) {
  selectedNote.value = note
  ;[attachments.value, shares.value] = await Promise.all([fetchAttachments(note.id), fetchNoteShares(note.id)])
}
async function selectSubmission(item: TeamNoteSubmission) {
  selectedSubmission.value = item
  relatedKnowledge.value = currentView.value === 'review' ? await fetchRelatedKnowledge(item.id) : []
}

async function createBlankNote() { const note = await postNote({ folderId: selectedFolderId.value }); await loadPersonal(); await selectPersonal(note) }
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
    await loadPersonal()
    await selectPersonal(note)
    notify('Markdown 已导入为新笔记。')
  } catch (cause: any) {
    markdownImportError.value = cause?.response?.data?.detail ?? 'Markdown 导入失败。'
  } finally { markdownImportSaving.value = false }
}
async function saveNote(payload: { noteId: string; title: string; folderId: string | null; contentJson?: Record<string, unknown>; plainText?: string }) {
  const { noteId, ...changes } = payload
  const updated = await putNote(noteId, changes)
  selectedNote.value = updated
  const index = notes.value.findIndex((item) => item.id === noteId)
  if (index >= 0) notes.value[index] = updated
}
async function prepareSaveAsTemplate(payload: { note: Note; title: string; folderId: string | null; contentJson: Record<string, unknown>; plainText: string }) {
  try {
    const updated = await putNote(payload.note.id, {
      title: payload.title,
      folderId: payload.folderId,
      contentJson: payload.contentJson,
      plainText: payload.plainText,
    })
    selectedNote.value = updated
    const index = notes.value.findIndex((item) => item.id === updated.id)
    if (index >= 0) notes.value[index] = updated
    templateSaveDialogOpen.value = true
  } catch (cause: any) { fail(cause, '保存当前笔记失败。') }
}
async function toggleFavorite(value: boolean) {
  if (!selectedNote.value) return
  selectedNote.value = await putNote(selectedNote.value.id, { isFavorite: value })
  if (currentView.value === 'favorites' && !value) await loadPersonal()
}

async function handleUpload(file: File) {
  if (!selectedNote.value) throw new Error('No note selected')
  const attachment = await uploadAttachment(selectedNote.value.id, file)
  attachments.value = await fetchAttachments(selectedNote.value.id)
  return attachment
}

function requestDeleteNote(note: Note) { confirmDialogKind.value = 'note'; confirmDialogNote.value = note; confirmDialogOpen.value = true }
function requestDeleteAttachment(item: Attachment) { confirmDialogKind.value = 'attachment'; confirmDialogAttachment.value = item; confirmDialogOpen.value = true }
function requestDeleteCategory(item: KnowledgeCategory) { confirmDialogKind.value = 'category'; confirmDialogCategory.value = item; confirmDialogOpen.value = true }
async function confirmDelete() {
  const kind = confirmDialogKind.value
  try {
    if (kind === 'note' && confirmDialogNote.value) await deleteNote(confirmDialogNote.value.id)
    if (kind === 'attachment' && confirmDialogAttachment.value) await deleteAttachment(confirmDialogAttachment.value.id)
    if (kind === 'category' && confirmDialogCategory.value && selectedTeamId.value) await deleteKnowledgeCategory(confirmDialogCategory.value.id, selectedTeamId.value)
    if (kind === 'template' && templateDeleteTarget.value) await deleteNoteTemplate(templateDeleteTarget.value.id)
    confirmDialogOpen.value = false
    if (kind === 'note') { selectedNote.value = null; await loadPersonal() }
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

async function saveShares(userIds: string[]) {
  if (!selectedNote.value) return
  busy.value = true
  try { shares.value = await syncNoteShares(selectedNote.value.id, userIds); shareDialogOpen.value = false; notify('分享权限已更新。') }
  catch (cause: any) { fail(cause, '分享失败。') }
  finally { busy.value = false }
}

function openPublish(type?: 'CREATE' | 'UPDATE', targetId?: string | null) {
  const linkedTargetId = selectedKnowledgeForNote.value?.id ?? null
  const resolvedTargetId = targetId ?? linkedTargetId
  publishType.value = type ?? (resolvedTargetId ? 'UPDATE' : 'CREATE')
  publishTargetId.value = resolvedTargetId
  publishTargetLocked.value = Boolean(resolvedTargetId)
  publishDialogOpen.value = true
}
async function publish(payload: SubmissionPayload) {
  if (!selectedNote.value) return
  busy.value = true
  try {
    await submitNoteToKnowledge(selectedNote.value.id, payload, selectedTeamId.value)
    await loadCollaboration()
    publishDialogOpen.value = false
    notify('已生成审核快照，可在“我的投稿”查看进度。')
  }
  catch (cause: any) { fail(cause, '提交审核失败。') }
  finally { busy.value = false }
}

async function copyShared(note: SharedNote) { const copied = await copySharedNote(note.id); await activateView('all'); await loadPersonal(); await selectPersonal(copied) }
async function copyTeamKnowledge(note: TeamNote) { const copied = await copyKnowledge(note.id, selectedTeamId.value); await activateView('all'); await loadPersonal(); await selectPersonal(copied) }
async function duplicatePersonal(note: Note) { const copied = await copyNote(note.id); await loadPersonal(); await selectPersonal(copied) }
function exportPersonal(note: Note) {
  const payload = JSON.stringify({
    title: note.title,
    contentJson: note.contentJson,
    plainText: note.plainText,
    attachments: attachments.value.map(({ id, originalName, mimeType, size }) => ({ id, originalName, mimeType, size })),
    exportedAt: new Date().toISOString(),
  }, null, 2)
  const url = URL.createObjectURL(new Blob([payload], { type: 'application/json;charset=utf-8' }))
  const anchor = document.createElement('a')
  anchor.href = url
  anchor.download = `${note.title.replace(/[\\/:*?"<>|]/g, '_') || '笔记'}.json`
  anchor.click()
  URL.revokeObjectURL(url)
}
async function requestKnowledgeUpdate(note: TeamNote) {
  busy.value = true
  try {
    const draft = await ensureKnowledgeUpdateDraft(note.id, selectedTeamId.value)
    await activateView('all')
    await loadPersonal()
    await selectPersonal(draft)
    await loadCollaboration()
    if (note.myUpdateSubmissionStatus === 'PENDING') notify('这篇知识已有待审核更新，已打开对应笔记。')
    else if (note.myUpdateSubmissionStatus === 'NEEDS_REVISION') notify('这篇知识的更新需要修改，已打开对应笔记。')
    else notify('已打开更新草稿，修改完成后请提交更新申请。')
  } catch (cause: any) { fail(cause, '更新草稿创建失败。') }
  finally { busy.value = false }
}

async function createKnowledge(title: string) { const item = await postKnowledge({ title }, selectedTeamId.value); knowledgeCreateDialogOpen.value = false; await loadView(); selectedKnowledge.value = item }
async function openKnowledge(note: TeamNote) { await router.push({ path: '/notes', query: { view: 'knowledge', knowledge: note.id } }); await loadView() }
function selectKnowledgeStatus(value: 'published' | 'archived') {
  knowledgeStatusFilter.value = value
  const requested = typeof route.query.knowledge === 'string' ? route.query.knowledge : null
  selectedKnowledge.value = visibleKnowledge.value.find((item) => item.id === requested) ?? visibleKnowledge.value[0] ?? null
}
function openCreateCategory() { categoryDialogMode.value = 'create'; categoryDialogTarget.value = null; categoryDialogName.value = ''; categoryDialogOpen.value = true }
function openRenameCategory(category: KnowledgeCategory) { categoryDialogMode.value = 'rename'; categoryDialogTarget.value = category; categoryDialogName.value = category.name; categoryDialogOpen.value = true }
async function saveCategory(name: string) {
  if (categoryDialogMode.value === 'create') await postKnowledgeCategory({ name, sortOrder: categories.value.length * 10 }, selectedTeamId.value)
  else if (categoryDialogTarget.value) await putKnowledgeCategory(categoryDialogTarget.value.id, { name }, selectedTeamId.value)
  categoryDialogOpen.value = false
  categories.value = await fetchKnowledgeCategories(selectedTeamId.value)
}
async function saveKnowledge(note: TeamNote, payload: { title: string; contentJson: Record<string, unknown>; plainText: string; categoryId: string | null; tags: string[] }) { selectedKnowledge.value = await putKnowledge(note.id, payload, selectedTeamId.value); await loadCollaboration() }
async function setArchived(note: TeamNote, archived: boolean) {
  busy.value = true
  try {
    if (archived) await archiveKnowledge(note.id, selectedTeamId.value)
    else await restoreKnowledge(note.id, selectedTeamId.value)
    knowledgeStatusFilter.value = archived ? 'archived' : 'published'
    await loadView()
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
async function showVersions(note: TeamNote) { versions.value = await fetchKnowledgeVersions(note.id, selectedTeamId.value); versionsOpen.value = true }

async function withdraw(item: TeamNoteSubmission) { await withdrawSubmission(item.id); await loadView() }
async function resubmit(item: TeamNoteSubmission) { await resubmitSubmission(item.id, { type: item.submissionType, targetTeamNoteId: item.targetTeamNoteId, categoryId: item.proposedCategoryId, tags: item.proposedTagsJson, message: item.submissionMessage }); await loadView() }
async function approve(item: TeamNoteSubmission, payload: SubmissionReviewPayload) { await approveSubmission(item.id, payload); await loadView() }
async function revision(item: TeamNoteSubmission, reason: string) { await requestSubmissionRevision(item.id, reason); await loadView() }
async function reject(item: TeamNoteSubmission, reason: string) { await rejectSubmission(item.id, reason); await loadView() }
async function openSource(noteId: string) { await activateView('all'); await loadPersonal(); const note = notes.value.find((item) => item.id === noteId); if (note) await selectPersonal(note) }

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
    await loadPersonal()
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
  if (!selectedNote.value) return
  templateSaving.value = true
  try {
    await postNoteTemplateFromNote(selectedNote.value.id, payload)
    await refreshTemplates()
    templateSaveDialogOpen.value = false
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
async function submitFolder(name: string) { if (folderDialogMode.value === 'create') await postFolder({ name, parentId: folderDialogParentId.value }); else if (folderDialogTarget.value) await putFolder(folderDialogTarget.value.id, { name }); folderDialogOpen.value = false; folders.value = await fetchFolders() }
async function confirmRemoveFolder() { if (folderDialogTarget.value) await deleteFolder(folderDialogTarget.value.id); folderDialogOpen.value = false; folders.value = await fetchFolders(); await loadPersonal() }

async function openTask(taskId: string) {
  await router.push({ path: '/todos', query: { view: 'all', todo: taskId } })
}

async function finishOnboarding() {
  await router.replace('/')
}

watch(() => [route.query.view, route.query.note, route.query.submission, workspace.currentTeamId] as const, () => { void loadView() })

onMounted(async () => {
  try {
    folders.value = await fetchFolders()
    if (hasTeam.value) await loadCollaboration()
    await loadView()
    const requested = typeof route.query.note === 'string' ? route.query.note : null
    if (requested && personalView.value) { const note = notes.value.find((item) => item.id === requested); if (note) await selectPersonal(note) }
  } catch (cause: any) { fail(cause, '笔记服务连接失败，请确认后端已启动。') }
})
</script>

<template>
  <div class="notes-page unified-notes-page">
    <p v-if="pageError" class="notes-page-error" role="status">{{ pageError }}<button type="button" aria-label="关闭提示" @click="pageError = null"><IconX :size="16" /></button></p>
    <section v-if="onboarding" class="onboarding-banner" aria-label="新手指引">
      <div><span class="eyebrow">FIRST RUN</span><strong>欢迎来到 WorkFollow</strong><p>先阅读这份使用指南，再开始安排你的工作。</p></div>
      <button class="primary-button" type="button" @click="finishOnboarding">开始使用</button>
    </section>
    <div class="notes-workspace card">
      <NoteNavigation :view="currentView" :folders="folders" :selected-folder-id="selectedFolderId" :has-team="hasTeam" :can-review="canReview" :categories="categories" :selected-category-id="selectedCategoryId" @view="activateView" @folder="selectFolder" @category="selectCategory" @create-category="openCreateCategory" @rename-category="openRenameCategory" @remove-category="requestDeleteCategory" @create-folder="createFolder" @rename-folder="renameFolder" @remove-folder="removeFolder" />
      <template v-if="personalView">
        <NoteList :notes="notes" :selected-id="selectedNote?.id ?? null" :search="search" @select="selectPersonal" @create="createBlankNote" @templates="openTemplates" @import="openMarkdownImport" @search="updateSearch" @remove="requestDeleteNote" />
        <NoteEditor
          :note="selectedNote"
          :folders="folders"
          :attachments="attachments"
          :upload-file="handleUpload"
          :collaboration="hasTeam"
          :knowledge-state="selectedKnowledgeState"
          :knowledge-target-title="selectedKnowledgeForNote?.title ?? null"
          :task-members="members"
          :current-user-id="auth.user?.id"
          :can-assign-tasks="canReview"
          :focus-block-id="typeof route.query.block === 'string' ? route.query.block : null"
          @save="saveNote"
          @delete-attachment="requestDeleteAttachment"
          @open-task="openTask"
          @share="shareDialogOpen = true"
          @publish="openPublish()"
          @favorite="toggleFavorite"
          @duplicate="duplicatePersonal"
          @export="exportPersonal"
          @save-as-template="prepareSaveAsTemplate"
          @remove="selectedNote && requestDeleteNote(selectedNote)"
        />
      </template>
      <template v-else-if="currentView === 'shared'">
        <CollaborativeNoteList title="分享给我的" :items="visibleSharedNotes" :selected-id="selectedShared?.id ?? null" :search="search" @select="selectedShared = $event as SharedNote" @search="updateSearch" />
        <SharedNoteDetail :note="selectedShared" :copying="busy" @copy="copyShared" />
      </template>
      <template v-else-if="currentView === 'knowledge'">
        <CollaborativeNoteList title="团队知识库" :items="visibleKnowledge" :selected-id="selectedKnowledge?.id ?? null" :search="search" :can-create="canReview" :can-manage-archived="canReview" :status-filter="knowledgeStatusFilter" @select="selectedKnowledge = $event as TeamNote" @search="updateSearch" @create="knowledgeCreateDialogOpen = true" @status-filter="selectKnowledgeStatus" />
        <KnowledgeDetail :note="selectedKnowledge" :categories="categories" :saving="busy" :update-state="selectedKnowledgeUpdateState" @save="saveKnowledge" @copy="copyTeamKnowledge" @archive="requestArchiveKnowledge" @restore="setArchived($event, false)" @update-request="requestKnowledgeUpdate" @versions="showVersions" />
      </template>
      <SubmissionWorkspace v-else :mode="currentView === 'review' ? 'review' : 'mine'" :submissions="submissions" :selected="selectedSubmission" :related="relatedKnowledge" :knowledge="knowledge" :categories="categories" :busy="busy" @select="selectSubmission" @withdraw="withdraw" @resubmit="resubmit" @open-source="openSource" @open-knowledge="openKnowledge" @approve="approve" @revision="revision" @reject="reject" />
    </div>

    <ShareNotePopover :open="shareDialogOpen" :members="members" :model-value="shares.map((item) => item.sharedWithUserId)" :current-user-id="auth.user?.id ?? ''" :saving="busy" @close="shareDialogOpen = false" @save="saveShares" />
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
    <ConfirmDialog :open="confirmDialogOpen" title="确认删除" :message="confirmDialogKind === 'template' ? '删除模板不会删除已经通过该模板创建的笔记。' : confirmDialogKind === 'category' ? '删除分类后，分类下的知识会保留并变为未分类。' : '删除后无法继续通过分享访问，已发布团队知识不受影响。'" :danger="true" confirm-label="删除" @close="confirmDialogOpen = false" @confirm="confirmDelete" />
    <Teleport to="body"><div v-if="versionsOpen" class="dialog-backdrop" @mousedown.self="versionsOpen = false"><section class="note-collab-dialog version-dialog" role="dialog" aria-modal="true" aria-labelledby="version-dialog-title"><header><div><span class="eyebrow">HISTORY</span><h2 id="version-dialog-title">知识版本</h2></div><button type="button" aria-label="关闭知识版本" @click="versionsOpen = false"><IconX :size="18" /></button></header><div class="version-list"><article v-for="item in versions" :key="item.id"><strong>V{{ item.versionNo }} · {{ item.changeType }}</strong><span>{{ new Date(item.createdAt).toLocaleString('zh-CN') }}</span></article></div></section></div></Teleport>
  </div>
</template>
