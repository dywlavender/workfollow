import axios from 'axios'

export const api = axios.create({
  baseURL: import.meta.env.VITE_API_BASE_URL ?? '/api',
  headers: { Accept: 'application/json' },
  timeout: 10_000,
  withCredentials: true,
})

export interface User {
  id: string
  username: string
  nickname: string
  avatarUrl: string | null
  systemRole: 'ROOT' | 'NORMAL'
  canCreateTeam: boolean
  onboardingVersion: number
  status: 'ACTIVE' | 'DISABLED'
  createdAt: string
  lastLoginAt: string | null
}

export interface AuthResponse {
  user: User
  isFirstRun: boolean
  guideNoteId: string | null
  starterTaskId: string | null
}

export async function register(payload: { username: string; password: string }): Promise<AuthResponse> {
  const { data } = await api.post<AuthResponse>('/auth/register', payload)
  return data
}

export async function login(identifier: string, password: string): Promise<AuthResponse> {
  const { data } = await api.post<AuthResponse>('/auth/login', { identifier, password })
  return data
}

export async function logout(): Promise<void> {
  await api.post('/auth/logout')
}

export async function fetchCurrentUser(): Promise<User> {
  const { data } = await api.get<User>('/auth/me')
  return data
}

export async function fetchAdminUsers(): Promise<User[]> {
  const { data } = await api.get<User[]>('/admin/users')
  return data
}

export async function putAdminUserPermissions(userId: string, payload: { canCreateTeam: boolean }): Promise<User> {
  const { data } = await api.patch<User>(`/admin/users/${userId}/permissions`, payload)
  return data
}

export interface PasswordResetResult {
  userId: string
  initialPassword: string
}

export async function postAdminResetPassword(userId: string): Promise<PasswordResetResult> {
  const { data } = await api.post<PasswordResetResult>(`/admin/users/${userId}/reset-password`)
  return data
}

export interface HealthResponse {
  status: 'ok'
  database: 'ok'
  version: string
}

export async function fetchHealth(): Promise<HealthResponse> {
  const { data } = await api.get<HealthResponse>('/health')
  return data
}

export type TodoStatus = 'TODO' | 'DONE' | 'ABANDONED'
export type TodoPriority = 'NONE' | 'LOW' | 'MEDIUM' | 'HIGH'
export type TodoRecurrenceType = 'NONE' | 'DAILY' | 'WEEKLY' | 'MONTHLY' | 'CUSTOM'
export type TodoSourceType = 'MANUAL' | 'NOTE' | 'TEAM'
export type TodoView = 'all' | 'inbox' | 'today' | 'week' | 'month' | 'completed' | 'collaboration' | 'assigned-to-me' | 'assigned-by-me'
export type TodoAssignmentStatus = 'TODO' | 'IN_PROGRESS' | 'DONE'
export type ResourceType = 'PERSONAL_NOTE' | 'TEAM_NOTE' | 'TASK'
export type ResourceRelationType = 'CREATED_FROM' | 'REFERENCES'

export interface TaskSource {
  relationId: string
  resourceType: ResourceType
  resourceId: string | null
  blockId: string | null
  title: string | null
  excerpt: string | null
  accessible: boolean
}

export interface TodoAssignment {
  id: string
  userId: string
  assignedById: string | null
  status: TodoAssignmentStatus
  active: boolean
  assignedAt: string
  completedAt: string | null
  removedAt: string | null
  user: User
}

export interface TodoPermissions {
  editable: boolean
  deletable: boolean
  assignable: boolean
  completable: boolean
}

export interface Todo {
  id: string
  title: string
  description: string | null
  contentJson: Record<string, unknown> | null
  attachmentIds: string[]
  status: TodoStatus
  priority: TodoPriority
  dueAt: string | null
  dueEndAt: string | null
  reminderAt: string | null
  remindedAt: string | null
  recurrenceType: TodoRecurrenceType
  recurrenceConfig: Record<string, number | string> | null
  listName: string
  tags: string[]
  sourceType: TodoSourceType
  sourceNoteId: string | null
  sourceExcerpt: string | null
  sources: TaskSource[]
  recurringSeriesId: string | null
  generatedFromId: string | null
  creatorId: string
  teamId: string | null
  creator: User
  assignments: TodoAssignment[]
  myAssignment: TodoAssignment | null
  completedAssignments: number
  totalAssignments: number
  permissions: TodoPermissions
  completedAt: string | null
  createdAt: string
  updatedAt: string
}

export interface TodoPayload {
  title: string
  description?: string | null
  contentJson?: Record<string, unknown> | null
  attachmentIds?: string[]
  priority?: TodoPriority
  dueAt?: string | null
  dueEndAt?: string | null
  reminderAt?: string | null
  recurrenceType?: TodoRecurrenceType
  recurrenceConfig?: Record<string, number | string> | null
  listName?: string
  tags?: string[]
  sourceType?: TodoSourceType
  sourceNoteId?: string | null
  sourceExcerpt?: string | null
  source?: {
    resourceType: 'PERSONAL_NOTE' | 'TEAM_NOTE'
    resourceId: string
    blockId?: string | null
    excerpt?: string | null
  } | null
  assigneeIds?: string[]
}

export interface TodoCompleteResult {
  todo: Todo
  nextTodo: Todo | null
}

export async function fetchTodos(view?: TodoView | 'linkable', q?: string, listName?: string): Promise<Todo[]> {
  const params: { view?: TodoView | 'linkable'; q?: string; list?: string; limit?: number; offset?: number } = {}
  if (view) params.view = view
  if (q?.trim()) params.q = q.trim()
  if (listName?.trim()) params.list = listName.trim()
  if (view !== 'all') {
    const { data } = await api.get<Todo[]>('/tasks', { params: Object.keys(params).length ? params : undefined })
    return data
  }

  const pageSize = 500
  const todos: Todo[] = []
  let offset = 0
  while (true) {
    const { data } = await api.get<Todo[]>('/tasks', { params: { ...params, limit: pageSize, offset } })
    todos.push(...data)
    if (data.length < pageSize) return todos
    offset += pageSize
  }
}

export async function fetchTodosByDate(date: string): Promise<Todo[]> {
  const { data } = await api.get<Todo[]>('/tasks', { params: { date } })
  return data
}

export async function fetchTodo(id: string): Promise<Todo> {
  const { data } = await api.get<Todo>(`/tasks/${id}`)
  return data
}

export interface TaskBrief {
  id: string
  accessible: boolean
  deleted: boolean
  title: string | null
  status: TodoStatus | null
  priority: TodoPriority | null
  dueAt: string | null
  assignees: User[]
  permissions: { completable: boolean }
}

export async function fetchTaskBriefs(ids: string[]): Promise<TaskBrief[]> {
  if (!ids.length) return []
  const params = new URLSearchParams()
  for (const id of ids) params.append('ids', id)
  const { data } = await api.get<TaskBrief[]>('/tasks/brief', { params })
  return data
}

export interface ResourceRelation {
  id: string
  sourceType: ResourceType
  sourceId: string
  sourceBlockId: string | null
  targetType: ResourceType
  targetId: string
  relationType: ResourceRelationType
  sourceExcerpt: string | null
  createdById: string | null
  createdAt: string
}

export async function postResourceRelation(payload: {
  sourceType: ResourceType
  sourceId: string
  sourceBlockId?: string | null
  targetType: ResourceType
  targetId: string
  relationType?: ResourceRelationType
  sourceExcerpt?: string | null
}): Promise<ResourceRelation> {
  const { data } = await api.post<ResourceRelation>('/resource-relations', payload)
  return data
}

export async function postTodo(payload: TodoPayload): Promise<Todo> {
  const { data } = await api.post<Todo>('/tasks', payload)
  return data
}

export async function putTodo(id: string, payload: Partial<TodoPayload>): Promise<Todo> {
  const { data } = await api.put<Todo>(`/tasks/${id}`, payload)
  return data
}

export async function completeTodo(id: string): Promise<TodoCompleteResult> {
  const { data } = await api.post<TodoCompleteResult>(`/tasks/${id}/complete`)
  return data
}

export async function restoreTodo(id: string): Promise<Todo> {
  const { data } = await api.post<Todo>(`/tasks/${id}/restore`)
  return data
}

export async function abandonTodo(id: string): Promise<Todo> {
  const { data } = await api.post<Todo>(`/tasks/${id}/abandon`)
  return data
}

export async function deleteTodo(id: string): Promise<void> {
  await api.delete(`/tasks/${id}`)
}

export async function fetchDueReminders(): Promise<Todo[]> {
  const { data } = await api.get<Todo[]>('/tasks/reminders/due')
  return data
}

export async function acknowledgeReminder(id: string): Promise<Todo> {
  const { data } = await api.post<Todo>(`/tasks/${id}/reminded`, {})
  return data
}

export async function putTaskMyStatus(id: string, status: TodoAssignmentStatus): Promise<Todo> {
  const { data } = await api.put<Todo>(`/tasks/${id}/my-status`, { status })
  return data
}

export async function putTaskAssignees(id: string, assigneeIds: string[]): Promise<Todo> {
  const { data } = await api.put<Todo>(`/tasks/${id}/assignees`, { assigneeIds })
  return data
}

export async function uploadTaskAttachment(taskId: string, file: File): Promise<Attachment> {
  const form = new FormData()
  form.append('taskId', taskId)
  form.append('file', file)
  const { data } = await api.post<Attachment>('/attachments/task', form, {
    headers: { 'Content-Type': 'multipart/form-data' },
  })
  return data
}

export interface QuickLink {
  id: string
  scope: 'PERSONAL' | 'SYSTEM'
  name: string
  url: string
  icon: string
  groupName: string | null
  description: string | null
  sortOrder: number
  createdById: string | null
  updatedById: string | null
  createdAt: string
  updatedAt: string
}

export interface QuickLinkPayload {
  name: string
  url: string
  icon?: string | null
  groupName?: string | null
  description?: string | null
  sortOrder?: number
}

export async function fetchQuickLinks(): Promise<QuickLink[]> {
  const { data } = await api.get<QuickLink[]>('/quick-links')
  return data
}

export async function postQuickLink(payload: QuickLinkPayload): Promise<QuickLink> {
  const { data } = await api.post<QuickLink>('/quick-links', payload)
  return data
}

export async function putQuickLink(id: string, payload: Partial<QuickLinkPayload>): Promise<QuickLink> {
  const { data } = await api.put<QuickLink>(`/quick-links/${id}`, payload)
  return data
}

export async function deleteQuickLink(id: string): Promise<void> {
  await api.delete(`/quick-links/${id}`)
}

export async function fetchSystemQuickLinks(): Promise<QuickLink[]> {
  const { data } = await api.get<QuickLink[]>('/quick-links/system')
  return data
}

export async function postSystemQuickLink(payload: QuickLinkPayload): Promise<QuickLink> {
  const { data } = await api.post<QuickLink>('/quick-links/system', payload)
  return data
}

export async function putSystemQuickLink(id: string, payload: Partial<QuickLinkPayload>): Promise<QuickLink> {
  const { data } = await api.put<QuickLink>(`/quick-links/system/${id}`, payload)
  return data
}

export async function deleteSystemQuickLink(id: string): Promise<void> {
  await api.delete(`/quick-links/system/${id}`)
}

export async function reorderSystemQuickLinks(ids: string[]): Promise<QuickLink[]> {
  const { data } = await api.put<QuickLink[]>('/quick-links/system/reorder', { ids })
  return data
}

export interface Folder {
  id: string
  parentId: string | null
  name: string
  sortOrder: number
  createdAt: string
  updatedAt: string
}

export interface Note {
  id: string
  folderId: string | null
  title: string
  contentJson: Record<string, unknown>
  plainText: string
  isFavorite: boolean
  copiedFromNoteId: string | null
  copiedFromTeamNoteId: string | null
  isKnowledgeUpdateDraft: boolean
  copiedFromTeamNoteVersionNo: number | null
  copiedFromTeamNoteSnapshotHash: string | null
  createdAt: string
  updatedAt: string
  deletedAt: string | null
}

export interface NoteTemplate {
  id: string
  name: string
  contentJson: Record<string, unknown>
  isBuiltin: boolean
  sortOrder: number
  ownerId: string | null
  description: string | null
  createdAt: string
  updatedAt: string
  deletedAt: string | null
}

export interface Attachment {
  id: string
  noteId: string | null
  originalName: string
  storageName: string
  mimeType: string
  size: number
  url: string
  createdAt: string
}

export async function fetchFolders(): Promise<Folder[]> {
  const { data } = await api.get<Folder[]>('/folders')
  return data
}

export async function postFolder(payload: { name: string; parentId?: string | null; sortOrder?: number }): Promise<Folder> {
  const { data } = await api.post<Folder>('/folders', payload)
  return data
}

export async function putFolder(id: string, payload: Partial<{ name: string; parentId: string | null; sortOrder: number }>): Promise<Folder> {
  const { data } = await api.put<Folder>(`/folders/${id}`, payload)
  return data
}

export async function deleteFolder(id: string): Promise<void> {
  await api.delete(`/folders/${id}`)
}

export async function fetchNotes(params?: { folderId?: string; q?: string; favorite?: boolean; limit?: number }): Promise<Note[]> {
  const { data } = await api.get<Note[]>('/notes', { params })
  return data
}

export async function fetchNote(id: string): Promise<Note> {
  const { data } = await api.get<Note>(`/notes/${id}`)
  return data
}

export async function postNote(payload: { folderId?: string | null; title?: string; contentJson?: Record<string, unknown>; plainText?: string }): Promise<Note> {
  const { data } = await api.post<Note>('/notes', payload)
  return data
}

export async function importMarkdownNote(file: File, folderId?: string | null, title?: string): Promise<Note> {
  const body = new FormData()
  body.append('file', file)
  if (folderId) body.append('folderId', folderId)
  if (title?.trim()) body.append('title', title.trim())
  const { data } = await api.post<Note>('/notes/import-markdown', body)
  return data
}

export async function putNote(id: string, payload: Partial<{ folderId: string | null; title: string; contentJson: Record<string, unknown>; plainText: string; isFavorite: boolean }>): Promise<Note> {
  const { data } = await api.put<Note>(`/notes/${id}`, payload)
  return data
}

export async function deleteNote(id: string): Promise<void> {
  await api.delete(`/notes/${id}`)
}

export async function copyNote(id: string): Promise<Note> {
  const { data } = await api.post<Note>(`/notes/${id}/copy`)
  return data
}

export async function fetchNoteTemplates(): Promise<NoteTemplate[]> {
  const { data } = await api.get<NoteTemplate[]>('/note-templates')
  return data
}

export async function postNoteTemplate(payload: {
  name: string
  description?: string | null
  contentJson: Record<string, unknown>
  sortOrder?: number
}): Promise<NoteTemplate> {
  const { data } = await api.post<NoteTemplate>('/note-templates', payload)
  return data
}

export async function postNoteTemplateFromNote(noteId: string, payload: { name: string; description?: string | null }): Promise<NoteTemplate> {
  const { data } = await api.post<NoteTemplate>(`/note-templates/from-note/${noteId}`, payload)
  return data
}

export async function putNoteTemplate(id: string, payload: Partial<{
  name: string
  description: string | null
  contentJson: Record<string, unknown>
  sortOrder: number
}>): Promise<NoteTemplate> {
  const { data } = await api.put<NoteTemplate>(`/note-templates/${id}`, payload)
  return data
}

export async function deleteNoteTemplate(id: string): Promise<void> {
  await api.delete(`/note-templates/${id}`)
}

export async function postNoteFromTemplate(templateId: string, folderId?: string | null): Promise<Note> {
  const { data } = await api.post<Note>(`/notes/from-template/${templateId}`, null, { params: folderId ? { folderId } : undefined })
  return data
}

export async function fetchAttachments(noteId: string): Promise<Attachment[]> {
  const { data } = await api.get<Attachment[]>('/attachments', { params: { note_id: noteId } })
  return data
}

export async function uploadAttachment(noteId: string, file: File): Promise<Attachment> {
  const body = new FormData()
  body.append('noteId', noteId)
  body.append('file', file)
  const { data } = await api.post<Attachment>('/attachments', body)
  return data
}

export async function deleteAttachment(id: string): Promise<void> {
  await api.delete(`/attachments/${id}`)
}

export type TeamRole = 'OWNER' | 'ADMIN' | 'MEMBER'
export type TeamStatus = 'ACTIVE' | 'DELETED'
export type TeamMemberStatus = 'ACTIVE' | 'REMOVED'

export interface Team {
  id: string
  name: string
  description: string | null
  avatarUrl: string | null
  ownerId: string
  status: TeamStatus
  createdAt: string
  updatedAt: string
  role: TeamRole | null
}

export interface TeamMember {
  id: string
  teamId: string
  userId: string
  role: TeamRole
  status: TeamMemberStatus
  joinedAt: string
  createdAt: string
  updatedAt: string
  user: User
}

export async function fetchTeams(): Promise<Team[]> {
  const { data } = await api.get<Team[]>('/teams')
  return data
}

export async function fetchTeam(id: string): Promise<Team> {
  const { data } = await api.get<Team>(`/teams/${id}`)
  return data
}

export async function postTeam(payload: { name: string; description?: string | null }): Promise<Team> {
  const { data } = await api.post<Team>('/teams', payload)
  return data
}

export async function putTeam(id: string, payload: Partial<{ name: string; description: string | null }>): Promise<Team> {
  const { data } = await api.put<Team>(`/teams/${id}`, payload)
  return data
}

export async function deleteTeam(id: string): Promise<void> {
  await api.delete(`/teams/${id}`)
}

export async function leaveTeam(id: string): Promise<void> {
  await api.post(`/teams/${id}/leave`)
}

export async function fetchTeamMembers(teamId: string): Promise<TeamMember[]> {
  const { data } = await api.get<TeamMember[]>(`/teams/${teamId}/members`)
  return data
}

export async function postTeamMember(teamId: string, payload: { identifier: string; role: TeamRole }): Promise<TeamMember> {
  const { data } = await api.post<TeamMember>(`/teams/${teamId}/members`, payload)
  return data
}

export async function putTeamMemberRole(teamId: string, userId: string, role: TeamRole): Promise<TeamMember> {
  const { data } = await api.put<TeamMember>(`/teams/${teamId}/members/${userId}/role`, { role })
  return data
}

export async function deleteTeamMember(teamId: string, userId: string): Promise<void> {
  await api.delete(`/teams/${teamId}/members/${userId}`)
}

export async function postTeamMemberResetPassword(teamId: string, userId: string): Promise<PasswordResetResult> {
  const { data } = await api.post<PasswordResetResult>(`/teams/${teamId}/members/${userId}/reset-password`)
  return data
}

export interface TeamNote {
  id: string
  teamId: string
  title: string
  contentJson: Record<string, unknown>
  plainText: string
  attachmentIds: string[]
  attachments: Attachment[]
  categoryId: string | null
  category: KnowledgeCategory | null
  tags: string[]
  sourceType: 'ADMIN_CREATED' | 'MEMBER_SUBMISSION'
  sourceNoteId: string | null
  sourceAuthorId: string | null
  sourceAuthor: User | null
  sourceSubmissionId: string | null
  status: 'PUBLISHED' | 'ARCHIVED'
  publishedAt: string
  archivedAt: string | null
  createdById: string | null
  updatedById: string | null
  createdAt: string
  updatedAt: string
  versionNo: number
  myUpdateDraftNoteId: string | null
  myUpdateSubmissionId: string | null
  myUpdateSubmissionStatus: TeamNoteSubmissionStatus | null
  permissions: { canEdit: boolean; canCopy: boolean; canArchive: boolean }
}

export interface KnowledgeCategory {
  id: string
  teamId: string
  name: string
  sortOrder: number
  createdAt: string
  updatedAt: string
}

export type TeamNoteSubmissionStatus = 'PENDING' | 'NEEDS_REVISION' | 'APPROVED' | 'REJECTED' | 'WITHDRAWN'
export type TeamNoteSubmissionType = 'CREATE' | 'UPDATE'

export interface TeamNoteSubmission {
  id: string
  teamId: string
  sourceNoteId: string
  applicantId: string
  sourceAuthorId: string
  applicant: User
  submissionType: TeamNoteSubmissionType
  targetTeamNoteId: string | null
  baseTeamNoteVersionNo: number | null
  baseTeamNoteSnapshotHash: string | null
  snapshotTitle: string
  snapshotContentJson: Record<string, unknown>
  snapshotPlainText: string
  snapshotAttachmentIds: string[]
  snapshotAttachments: Attachment[]
  snapshotHash: string
  proposedCategoryId: string | null
  proposedTagsJson: string[]
  submissionMessage: string | null
  status: TeamNoteSubmissionStatus
  reviewerId: string | null
  reviewedAt: string | null
  reviewReason: string | null
  reviewReasonCode: string | null
  reviewComment: string | null
  revisionNo: number
  approvedTeamNoteId: string | null
  createdAt: string
  updatedAt: string
}

export interface TeamNoteVersion {
  id: string
  teamNoteId: string
  versionNo: number
  title: string
  contentJson: Record<string, unknown>
  plainText: string
  attachmentIds: string[]
  categoryId: string | null
  tags: string[]
  changeType: string
  changedById: string | null
  sourceSubmissionId: string | null
  createdAt: string
}

export interface SubmissionPayload {
  type: TeamNoteSubmissionType
  targetTeamNoteId?: string | null
  categoryId?: string | null
  tags?: string[]
  message?: string | null
}

export interface SubmissionReviewPayload {
  reason?: string | null
  reasonCode?: string | null
  title?: string | null
  categoryId?: string | null
  tags?: string[] | null
}

function teamQuery(teamId?: string) {
  return teamId ? { teamId } : undefined
}

export async function fetchKnowledge(params?: { q?: string; categoryId?: string; includeArchived?: boolean; teamId?: string }): Promise<TeamNote[]> {
  const { data } = await api.get<TeamNote[]>('/team/knowledge', { params })
  return data
}

export async function fetchKnowledgeCategories(teamId?: string): Promise<KnowledgeCategory[]> {
  const { data } = await api.get<KnowledgeCategory[]>('/team/knowledge/categories', { params: teamQuery(teamId) })
  return data
}

export async function postKnowledgeCategory(payload: { name: string; sortOrder?: number }, teamId?: string): Promise<KnowledgeCategory> {
  const { data } = await api.post<KnowledgeCategory>('/team/knowledge/categories', payload, { params: teamQuery(teamId) })
  return data
}

export async function putKnowledgeCategory(id: string, payload: { name?: string; sortOrder?: number }, teamId?: string): Promise<KnowledgeCategory> {
  const { data } = await api.put<KnowledgeCategory>(`/team/knowledge/categories/${id}`, payload, { params: teamQuery(teamId) })
  return data
}

export async function deleteKnowledgeCategory(id: string, teamId?: string): Promise<void> {
  await api.delete(`/team/knowledge/categories/${id}`, { params: teamQuery(teamId) })
}

export async function postKnowledge(payload: { title: string; contentJson?: Record<string, unknown>; plainText?: string; categoryId?: string | null; tags?: string[] }, teamId?: string): Promise<TeamNote> {
  const { data } = await api.post<TeamNote>('/team/knowledge', payload, { params: teamQuery(teamId) })
  return data
}

export async function putKnowledge(id: string, payload: Partial<{ title: string; contentJson: Record<string, unknown>; plainText: string; categoryId: string | null; tags: string[] }>, teamId?: string): Promise<TeamNote> {
  const { data } = await api.put<TeamNote>(`/team/knowledge/${id}`, payload, { params: teamQuery(teamId) })
  return data
}

export async function archiveKnowledge(id: string, teamId?: string): Promise<TeamNote> {
  const { data } = await api.post<TeamNote>(`/team/knowledge/${id}/archive`, undefined, { params: teamQuery(teamId) })
  return data
}

export async function restoreKnowledge(id: string, teamId?: string): Promise<TeamNote> {
  const { data } = await api.post<TeamNote>(`/team/knowledge/${id}/restore`, undefined, { params: teamQuery(teamId) })
  return data
}

export async function copyKnowledge(id: string, teamId?: string): Promise<Note> {
  const { data } = await api.post<Note>(`/team/knowledge/${id}/copy`, undefined, { params: teamQuery(teamId) })
  return data
}

export async function ensureKnowledgeUpdateDraft(id: string, teamId?: string): Promise<Note> {
  const { data } = await api.post<Note>(`/team/knowledge/${id}/update-draft`, undefined, { params: teamQuery(teamId) })
  return data
}

export async function fetchKnowledgeVersions(id: string, teamId?: string): Promise<TeamNoteVersion[]> {
  const { data } = await api.get<TeamNoteVersion[]>(`/team/knowledge/${id}/versions`, { params: teamQuery(teamId) })
  return data
}

export async function submitNoteToKnowledge(noteId: string, payload: SubmissionPayload, teamId?: string): Promise<TeamNoteSubmission> {
  const { data } = await api.post<TeamNoteSubmission>(`/notes/${noteId}/submissions`, payload, { params: teamQuery(teamId) })
  return data
}

export async function fetchMySubmissions(teamId?: string): Promise<TeamNoteSubmission[]> {
  const { data } = await api.get<TeamNoteSubmission[]>('/note-submissions/mine', { params: teamQuery(teamId) })
  return data
}

export async function fetchReviewSubmissions(teamId?: string): Promise<TeamNoteSubmission[]> {
  const { data } = await api.get<TeamNoteSubmission[]>('/note-submissions/review', { params: teamQuery(teamId) })
  return data
}

export async function withdrawSubmission(id: string): Promise<TeamNoteSubmission> {
  const { data } = await api.post<TeamNoteSubmission>(`/note-submissions/${id}/withdraw`)
  return data
}

export async function resubmitSubmission(id: string, payload: SubmissionPayload): Promise<TeamNoteSubmission> {
  const { data } = await api.post<TeamNoteSubmission>(`/note-submissions/${id}/resubmit`, payload)
  return data
}

export async function approveSubmission(id: string, payload: SubmissionReviewPayload = {}): Promise<TeamNote> {
  const { data } = await api.post<TeamNote>(`/note-submissions/${id}/approve`, payload)
  return data
}

export async function requestSubmissionRevision(id: string, reason: string): Promise<TeamNoteSubmission> {
  const { data } = await api.post<TeamNoteSubmission>(`/note-submissions/${id}/request-revision`, { reason })
  return data
}

export async function rejectSubmission(id: string, reason: string): Promise<TeamNoteSubmission> {
  const { data } = await api.post<TeamNoteSubmission>(`/note-submissions/${id}/reject`, { reason })
  return data
}

export async function fetchRelatedKnowledge(id: string): Promise<TeamNote[]> {
  const { data } = await api.get<TeamNote[]>(`/note-submissions/${id}/related`)
  return data
}

export async function fetchTeamNotes(teamId: string): Promise<TeamNote[]> {
  const { data } = await api.get<TeamNote[]>(`/teams/${teamId}/notes`)
  return data
}

export async function postTeamNote(teamId: string, payload: {
  title: string
  contentJson: Record<string, unknown>
  plainText?: string
  attachmentIds?: string[]
}): Promise<TeamNote> {
  const { data } = await api.post<TeamNote>(`/teams/${teamId}/notes`, payload)
  return data
}

export async function putTeamNote(teamId: string, noteId: string, payload: Partial<{
  title: string
  contentJson: Record<string, unknown>
  plainText: string
  attachmentIds: string[]
}>): Promise<TeamNote> {
  const { data } = await api.put<TeamNote>(`/teams/${teamId}/notes/${noteId}`, payload)
  return data
}

export async function deleteTeamNote(teamId: string, noteId: string): Promise<void> {
  await api.delete(`/teams/${teamId}/notes/${noteId}`)
}

export async function postTeamNoteSubmission(teamId: string, sourceNoteId: string): Promise<TeamNoteSubmission> {
  const { data } = await api.post<TeamNoteSubmission>(`/teams/${teamId}/note-submissions`, { sourceNoteId })
  return data
}

export async function fetchTeamNoteSubmissions(teamId: string): Promise<TeamNoteSubmission[]> {
  const { data } = await api.get<TeamNoteSubmission[]>(`/teams/${teamId}/note-submissions`)
  return data
}

export async function approveTeamNoteSubmission(teamId: string, submissionId: string): Promise<TeamNote> {
  const { data } = await api.post<TeamNote>(`/teams/${teamId}/note-submissions/${submissionId}/approve`)
  return data
}

export async function rejectTeamNoteSubmission(teamId: string, submissionId: string, reason?: string): Promise<TeamNoteSubmission> {
  const { data } = await api.post<TeamNoteSubmission>(`/teams/${teamId}/note-submissions/${submissionId}/reject`, { reason: reason || null })
  return data
}

export type NoteShareStatus = 'ACTIVE' | 'REVOKED'
export type NoteSharePermission = 'READ_ONLY'

export interface NoteShare {
  id: string
  noteId: string
  sharedByUserId: string
  sharedWithUserId: string
  permission: NoteSharePermission
  status: NoteShareStatus
  createdAt: string
  revokedAt: string | null
  sharedWith: User
}

export interface SharedNote extends Note {
  attachments: Attachment[]
  sharedByUserId: string
  sharedBy: User
  permission: NoteSharePermission
}

export async function postNoteShare(noteId: string, identifier: string): Promise<NoteShare> {
  const { data } = await api.post<NoteShare>(`/notes/${noteId}/shares`, { identifier, permission: 'READ_ONLY' })
  return data
}

export async function syncNoteShares(noteId: string, userIds: string[]): Promise<NoteShare[]> {
  const { data } = await api.post<NoteShare[]>(`/notes/${noteId}/shares`, { userIds })
  return data
}

export async function fetchNoteShares(noteId: string): Promise<NoteShare[]> {
  const { data } = await api.get<NoteShare[]>(`/notes/${noteId}/shares`)
  return data
}

export async function deleteNoteShare(noteId: string, shareId: string): Promise<void> {
  await api.delete(`/notes/${noteId}/shares/${shareId}`)
}

export async function fetchSharedNotes(): Promise<SharedNote[]> {
  const { data } = await api.get<SharedNote[]>('/shared/notes')
  return data
}

export async function fetchSharedNote(noteId: string): Promise<SharedNote> {
  const { data } = await api.get<SharedNote>(`/shared/notes/${noteId}`)
  return data
}

export async function copySharedNote(noteId: string): Promise<Note> {
  const { data } = await api.post<Note>(`/shared/notes/${noteId}/copy`)
  return data
}

export type NotificationType = 'TEAM_MEMBER_ADDED' | 'TEAM_TASK_ASSIGNED' | 'TEAM_TASK_UPDATED' | 'TEAM_TASK_CANCELLED' | 'TEAM_NOTE_SUBMITTED' | 'TEAM_NOTE_REVIEWED' | 'TEAM_NOTE_APPROVED' | 'TEAM_NOTE_REJECTED' | 'NOTE_SHARED'

export interface Notification {
  id: string
  actorUserId: string | null
  type: NotificationType
  title: string
  body: string
  dataJson: Record<string, unknown>
  readAt: string | null
  createdAt: string
}

export async function fetchNotifications(unreadOnly = false): Promise<Notification[]> {
  const { data } = await api.get<Notification[]>('/notifications', { params: unreadOnly ? { unreadOnly: true } : undefined })
  return data
}

export async function markNotificationRead(id: string): Promise<void> {
  await api.post(`/notifications/${id}/read`)
}

export async function markAllNotificationsRead(): Promise<void> {
  await api.post('/notifications/read-all')
}

export async function deleteNotification(id: string): Promise<void> {
  await api.delete(`/notifications/${id}`)
}

export async function deleteAllNotifications(): Promise<void> {
  await api.delete('/notifications')
}

export interface AuditLog {
  id: string
  teamId: string | null
  actorUserId: string | null
  action: string
  resourceType: string
  resourceId: string | null
  metadataJson: Record<string, unknown>
  createdAt: string
}

export async function fetchTeamAuditLogs(teamId: string, limit = 100): Promise<AuditLog[]> {
  const { data } = await api.get<AuditLog[]>(`/teams/${teamId}/audit-logs`, { params: { limit } })
  return data
}
