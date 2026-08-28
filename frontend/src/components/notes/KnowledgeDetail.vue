<script setup lang="ts">
import { IconArchive, IconCopy, IconEye, IconHistory, IconLink, IconRefresh, IconSettings, IconTrash, IconX } from '@tabler/icons-vue'
import * as Y from 'yjs'
import { computed, nextTick, onBeforeUnmount, onMounted, ref, shallowRef, watch } from 'vue'

import CollaborativeRichTextDocument from '@/components/notes/CollaborativeRichTextDocument.vue'
import RichTextDocument from '@/components/RichTextDocument.vue'
import ReadonlyAttachmentPanel from '@/components/notes/ReadonlyAttachmentPanel.vue'
import { filterStandaloneAttachments } from '@/modules/editor/attachmentReferences'
import { formatLastSavedAt } from '@/modules/editor/saveStatus'
import { createKnowledgeDraftCollaboration, type DocumentCollaborationSession, type DocumentCollaborationStatus } from '@/modules/editor/documentCollaboration'
import { CollaborationInitializationError, initializeCollaborativeField } from '@/modules/editor/collaborationInitialization'
import type { KnowledgeCategory, TeamNote } from '@/services/api'

const props = defineProps<{
  note: TeamNote | null
  categories: KnowledgeCategory[]
  saving?: boolean
  updateState?: 'none' | 'draft' | 'pending' | 'needs-revision'
}>()
const emit = defineEmits<{
  commit: [note: TeamNote, payload: { title: string; contentJson: Record<string, unknown>; plainText: string; categoryId: string | null; tags: string[]; baseVersion: number }, settled?: (versionNo: number) => void]
  copy: [note: TeamNote]
  archive: [note: TeamNote]
  restore: [note: TeamNote]
  delete: [note: TeamNote]
  updateRequest: [note: TeamNote]
  versions: [note: TeamNote]
}>()
const title = ref('')
const contentJson = ref<Record<string, unknown>>({ type: 'doc', content: [] })
const plainText = ref('')
const categoryId = ref('')
const tags = ref('')
const documentRef = ref<{ flush: () => void | Promise<void> } | null>(null)
const collaborationSession = shallowRef<DocumentCollaborationSession | null>(null)
const collaborationStatus = ref<DocumentCollaborationStatus>('connecting')
const collaborationPendingChanges = ref(0)
const lastSavedAt = ref<string | null>(props.note?.updatedAt ?? props.note?.createdAt ?? null)
const collaborationContentReady = ref(false)
const collaborationBodyReady = ref(false)
const collaborationInitializationAuthFailed = ref(false)
const collaborationError = ref('')
const staleDraftVersion = ref(false)
let collaborationSeedTimer: number | undefined
let projectionConfirmTimer: number | undefined
const OFFLINE_SEED_DELAY_MS = 10000
let metadataObserverCleanup: (() => void) | undefined
const linkCopied = ref(false)
const settingsOpen = ref(false)
const settingsHost = ref<HTMLElement | null>(null)
const settingsTrigger = ref<HTMLButtonElement | null>(null)
const settingsMenu = ref<HTMLElement | null>(null)
const settingsMenuStyle = ref<Record<string, string> | null>(null)
const SETTINGS_MENU_EDGE = 12
const SETTINGS_MENU_GAP = 8
const SETTINGS_MENU_FALLBACK_HEIGHT = 320
const visibleAttachments = computed(() => filterStandaloneAttachments(
  props.note?.attachments ?? [],
  contentJson.value,
))

const collaborationStatusLabel = computed(() => {
  if (!collaborationSession.value) return ''
  if (collaborationStatus.value === 'error') return '协同连接失败'
  if (collaborationStatus.value === 'disconnected') return '协同离线，正在重连…'
  if (collaborationStatus.value === 'connecting') return '连接协同…'
  if (collaborationPendingChanges.value > 0) return '协同保存中…'
  if (staleDraftVersion.value) return '草稿版本已过期'
  return '协同已连接'
})

function replaceText(target: Y.Text, value: string) {
  const current = target.toString()
  if (current === value) return
  let start = 0
  while (start < current.length && start < value.length && current[start] === value[start]) start += 1
  let currentEnd = current.length
  let nextEnd = value.length
  while (currentEnd > start && nextEnd > start && current[currentEnd - 1] === value[nextEnd - 1]) {
    currentEnd -= 1
    nextEnd -= 1
  }
  if (currentEnd > start) target.delete(start, currentEnd - start)
  if (nextEnd > start) target.insert(start, value.slice(start, nextEnd))
}

function normalizeTags(value: string): string[] {
  return [...new Set(value.split(/[,，\s]+/).map((tag) => tag.trim().replace(/^#/, '')).filter(Boolean))]
}

function seedMetadataDocument(note: TeamNote, document: Y.Doc, initial?: Record<string, unknown>) {
  const config = document.getMap('config')
  const titleText = document.getText('title')
  const metadata = document.getMap('metadata')
  const tagArray = document.getArray<string>('tags')
  if (config.get('metadataInitialized') === true) return
  const source = initial && typeof initial === 'object' ? { ...note, ...initial } : note
  const sourceVersion = Number(initial?.versionNo ?? initial?.baseVersion ?? note.versionNo)
  document.transact(() => {
    config.set('metadataInitialized', true)
    if (Number.isFinite(sourceVersion)) config.set('baseVersion', sourceVersion)
    if (!titleText.length && source.title) titleText.insert(0, String(source.title))
    if (!metadata.has('categoryId')) metadata.set('categoryId', source.categoryId ?? null)
    const sourceTags = Array.isArray(source.tags) ? source.tags.map(String) : []
    if (tagArray.length === 0 && sourceTags.length) tagArray.push(sourceTags)
    metadata.set('initialized', true)
  }, 'workfollow-knowledge-seed')
}

function inspectDraftVersion(note: TeamNote, document: Y.Doc) {
  const config = document.getMap('config')
  const baseVersion = Number(config.get('baseVersion'))
  staleDraftVersion.value = Number.isFinite(baseVersion) && baseVersion !== Number(note.versionNo)
}

function scheduleProjectionConfirmation() {
  window.clearTimeout(projectionConfirmTimer)
  projectionConfirmTimer = window.setTimeout(() => {
    projectionConfirmTimer = undefined
    if (!collaborationSession.value || collaborationPendingChanges.value > 0 || !collaborationBodyReady.value) return
    void Promise.resolve(documentRef.value?.flush()).catch(() => undefined)
  }, 260)
}

function applyMetadata(document: Y.Doc) {
  if (document !== collaborationSession.value?.document) return
  title.value = document.getText('title').toString()
  const metadata = document.getMap('metadata')
  categoryId.value = String(metadata.get('categoryId') ?? '')
  tags.value = document.getArray<unknown>('tags').toArray().map(String).join(' ')
}

function bindMetadata(document: Y.Doc) {
  metadataObserverCleanup?.()
  const metadata = document.getMap('metadata')
  const titleText = document.getText('title')
  const tagArray = document.getArray('tags')
  const update = () => applyMetadata(document)
  metadata.observe(update)
  titleText.observe(update)
  tagArray.observe(update)
  metadataObserverCleanup = () => {
    metadata.unobserve(update)
    titleText.unobserve(update)
    tagArray.unobserve(update)
    metadataObserverCleanup = undefined
  }
  update()
}

async function flushAndWaitForProjection(timeoutMs = 6000) {
  // Published knowledge is rendered read-only for regular members. They do
  // not open a draft Yjs session, but the page-level navigation barrier still
  // calls this exposed method before switching articles or leaving the page.
  // A read-only view has no local edits to project, so it must be a no-op
  // instead of blocking navigation with an "协同尚未就绪" error.
  if (!props.note?.permissions.canEdit && !collaborationSession.value) return
  if (!collaborationSession.value || !collaborationContentReady.value) {
    throw new Error('知识协同尚未就绪，请稍后重试。')
  }
  await documentRef.value?.flush()
  collaborationSession.value.provider.flushPendingUpdates()
  const deadline = Date.now() + timeoutMs
  while (collaborationPendingChanges.value > 0 || !collaborationBodyReady.value) {
    if (Date.now() >= deadline) throw new Error('知识内容尚未同步完成，请稍后重试。')
    await new Promise((resolve) => window.setTimeout(resolve, 120))
  }
}

function startCollaboration(note: TeamNote) {
  disposeCollaboration()
  collaborationStatus.value = 'connecting'
  collaborationContentReady.value = false
  collaborationBodyReady.value = false
  collaborationInitializationAuthFailed.value = false
  collaborationError.value = ''
  staleDraftVersion.value = false
  let session: DocumentCollaborationSession | null = null
  session = createKnowledgeDraftCollaboration(note.id, null, {
    onStatus: (status) => {
      if (props.note?.id === note.id) collaborationStatus.value = status
      if (status === 'connected') window.clearTimeout(collaborationSeedTimer)
      else if (status === 'disconnected' || (status === 'error' && !collaborationInitializationAuthFailed.value)) scheduleOfflineSeed(note)
    },
    onSynced: () => {
      if (props.note?.id !== note.id || !session) return
      collaborationStatus.value = 'connected'
      window.clearTimeout(collaborationSeedTimer)
      void initializeCollaborativeField(
        `knowledge-draft:${note.id}`,
        'metadata',
        (initial) => seedMetadataDocument(note, session!.document, initial),
      ).then(() => {
        if (props.note?.id !== note.id || !session) return
        inspectDraftVersion(note, session.document)
        bindMetadata(session.document)
        collaborationContentReady.value = true
      }).catch((error) => {
        collaborationContentReady.value = false
        if (error instanceof CollaborationInitializationError && error.kind === 'auth') collaborationInitializationAuthFailed.value = true
        collaborationStatus.value = 'error'
        collaborationError.value = error instanceof Error ? error.message : '协同元数据初始化失败'
      })
    },
    onUnsyncedChanges: (count) => {
      if (props.note?.id !== note.id) return
      collaborationPendingChanges.value = count
      if (count === 0) scheduleProjectionConfirmation()
    },
    onError: (message) => {
      collaborationInitializationAuthFailed.value = /认证|权限|登录|unauthor/i.test(message)
      collaborationStatus.value = 'error'
      collaborationError.value = message
    },
  }, note.versionNo)
  collaborationSession.value = session
}

function scheduleOfflineSeed(note: TeamNote) {
  window.clearTimeout(collaborationSeedTimer)
  collaborationSeedTimer = window.setTimeout(() => {
    const session = collaborationSession.value
    if (
      props.note?.id === note.id
      && session
      && !session.provider.isSynced
      && (collaborationStatus.value === 'disconnected' || collaborationStatus.value === 'error')
    ) {
      void initializeCollaborativeField(
        `knowledge-draft:${note.id}`,
        'metadata',
        (initial) => seedMetadataDocument(note, session!.document, initial),
      ).then(() => {
        if (props.note?.id !== note.id || !session) return
        inspectDraftVersion(note, session.document)
        bindMetadata(session.document)
        collaborationContentReady.value = true
      }).catch((error) => {
        collaborationStatus.value = 'error'
        collaborationError.value = error instanceof Error ? error.message : '协同元数据初始化失败'
      })
    }
  }, OFFLINE_SEED_DELAY_MS)
}

function disposeCollaboration() {
  window.clearTimeout(collaborationSeedTimer)
  collaborationSeedTimer = undefined
  window.clearTimeout(projectionConfirmTimer)
  projectionConfirmTimer = undefined
  metadataObserverCleanup?.()
  collaborationSession.value?.destroy()
  collaborationSession.value = null
  collaborationPendingChanges.value = 0
  collaborationContentReady.value = false
  collaborationBodyReady.value = false
  collaborationError.value = ''
  staleDraftVersion.value = false
  collaborationStatus.value = 'connecting'
}

function getSettingsMenuStyle(menuHeight = SETTINGS_MENU_FALLBACK_HEIGHT) {
  const triggerRect = settingsTrigger.value?.getBoundingClientRect()
  if (!triggerRect) return null
  const preferredTop = Math.round(triggerRect.bottom + SETTINGS_MENU_GAP)
  const maxTop = Math.max(SETTINGS_MENU_EDGE, window.innerHeight - menuHeight - SETTINGS_MENU_EDGE)
  const top = Math.min(Math.max(SETTINGS_MENU_EDGE, preferredTop), maxTop)
  const menuWidth = Math.min(310, Math.max(0, window.innerWidth - SETTINGS_MENU_EDGE * 2))
  const maxRight = Math.max(SETTINGS_MENU_EDGE, window.innerWidth - menuWidth - SETTINGS_MENU_EDGE)
  const right = Math.min(maxRight, Math.max(SETTINGS_MENU_EDGE, Math.round(window.innerWidth - triggerRect.right)))
  return {
    position: 'fixed',
    top: `${top}px`,
    right: `${right}px`,
    left: 'auto',
    maxHeight: `calc(100dvh - ${top + SETTINGS_MENU_EDGE}px)`,
  }
}

function positionSettingsMenu() {
  const menuHeight = settingsMenu.value?.getBoundingClientRect().height ?? SETTINGS_MENU_FALLBACK_HEIGHT
  const nextStyle = getSettingsMenuStyle(menuHeight)
  if (nextStyle) settingsMenuStyle.value = nextStyle
}

function closeSettings() {
  settingsOpen.value = false
  settingsMenuStyle.value = null
}

function openSettings() {
  settingsMenuStyle.value = getSettingsMenuStyle()
  settingsOpen.value = true
  void nextTick(positionSettingsMenu)
}

function toggleSettings() {
  if (settingsOpen.value) closeSettings()
  else openSettings()
}

function handleSettingsPointerDown(event: PointerEvent) {
  if (!settingsOpen.value) return
  const eventTarget = event.target
  if (!(eventTarget instanceof Node)) return
  if (settingsHost.value?.contains(eventTarget) || settingsMenu.value?.contains(eventTarget)) return
  closeSettings()
}

function handleSettingsViewportChange() {
  if (settingsOpen.value) positionSettingsMenu()
}

watch(() => props.note?.id, (noteId) => {
  const note = props.note
  title.value = note?.title ?? ''
  lastSavedAt.value = note?.updatedAt ?? note?.createdAt ?? null
  contentJson.value = note ? JSON.parse(JSON.stringify(note.contentJson)) : { type: 'doc', content: [] }
  plainText.value = note?.plainText ?? ''
  categoryId.value = note?.categoryId ?? ''
  tags.value = note?.tags.join(' ') ?? ''
  closeSettings()
  if (noteId && note?.permissions.canEdit) startCollaboration(note)
  else disposeCollaboration()
}, { immediate: true })

watch(() => props.note?.updatedAt, (updatedAt) => {
  if (updatedAt && props.note?.id) lastSavedAt.value = updatedAt
})

function replaceTitle() {
  const document = collaborationSession.value?.document
  if (!collaborationContentReady.value || staleDraftVersion.value || !document || !title.value.trim()) return
  document.transact(() => replaceText(document.getText('title'), title.value.trim()), 'workfollow-knowledge-title')
}

function onCategoryChange() {
  if (!collaborationContentReady.value || staleDraftVersion.value) return
  const metadata = collaborationSession.value?.document.getMap('metadata')
  if (metadata) metadata.set('categoryId', categoryId.value || null)
}

function onTagsInput() {
  const document = collaborationSession.value?.document
  if (!collaborationContentReady.value || staleDraftVersion.value || !document) return
  const next = normalizeTags(tags.value)
  const values = document.getArray<string>('tags')
  document.transact(() => {
    if (values.length) values.delete(0, values.length)
    if (next.length) values.push(next)
  }, 'workfollow-knowledge-tags')
}

async function commit() {
  if (!props.note || !collaborationContentReady.value || staleDraftVersion.value) return
  try {
    await flushAndWaitForProjection()
  } catch (error) {
    collaborationError.value = error instanceof Error ? error.message : '知识内容尚未同步完成，请稍后重试。'
    return
  }
  const baseVersion = Number(collaborationSession.value?.document.getMap('config').get('baseVersion') ?? props.note.versionNo)
  emit('commit', props.note, {
    title: title.value.trim(), contentJson: contentJson.value, plainText: plainText.value,
    categoryId: categoryId.value || null,
    tags: normalizeTags(tags.value),
    baseVersion,
  }, (versionNo) => {
    collaborationSession.value?.document.getMap('config').set('baseVersion', versionNo)
    collaborationSession.value?.provider.flushPendingUpdates()
  })
}

function saveFromSettings() {
  void commit()
  closeSettings()
}

function archiveOrRestoreFromSettings() {
  if (!props.note) return
  closeSettings()
  if (props.note.status === 'PUBLISHED') emit('archive', props.note)
  else emit('restore', props.note)
}

function deleteFromSettings() {
  if (!props.note) return
  closeSettings()
  emit('delete', props.note)
}

async function copyStableLink() {
  if (!props.note) return
  await navigator.clipboard.writeText(`${window.location.origin}/knowledge/${props.note.id}`)
  linkCopied.value = true
  window.setTimeout(() => { linkCopied.value = false }, 1600)
}

// Navigation flushes pending collaboration updates without waiting for the
// SQL projection; only explicit content-reading actions use the strict
// barrier in flushAndWaitForProjection.
function flushCollaboration() {
  collaborationSession.value?.provider.flushPendingUpdates()
}

defineExpose({ collaborationSession, flushCollaboration, flushAndWaitForProjection })
onMounted(() => {
  document.addEventListener('pointerdown', handleSettingsPointerDown)
  window.addEventListener('resize', handleSettingsViewportChange)
  window.addEventListener('scroll', handleSettingsViewportChange, true)
})
onBeforeUnmount(() => {
  document.removeEventListener('pointerdown', handleSettingsPointerDown)
  window.removeEventListener('resize', handleSettingsViewportChange)
  window.removeEventListener('scroll', handleSettingsViewportChange, true)
})
onBeforeUnmount(disposeCollaboration)

watch(() => props.note?.versionNo, (versionNo) => {
  const note = props.note
  const session = collaborationSession.value
  if (!note || !session || versionNo === undefined) return
  inspectDraftVersion(note, session.document)
})
</script>

<template>
  <section class="notes-column editor-column collaboration-reader knowledge-detail" @click="closeSettings">
    <div v-if="!note" class="editor-empty"><IconEye :size="28" /><strong>选择一篇团队知识</strong></div>
    <template v-else>
      <header class="editor-header knowledge-header">
        <div class="knowledge-title-block"><span>{{ note.category?.name ?? '未分类' }} · {{ note.sourceAuthor?.nickname ?? '管理员' }}贡献</span><input v-if="note.permissions.canEdit" v-model="title" aria-label="知识标题" :disabled="!collaborationContentReady || staleDraftVersion" @input="replaceTitle" @blur="replaceTitle" /><h1 v-else>{{ note.title }}</h1></div>
        <div class="knowledge-actions"><span v-if="note.permissions.canEdit && collaborationSession" class="task-collaboration-state" :class="collaborationStatus" role="status" :title="collaborationError || collaborationStatusLabel">{{ collaborationStatusLabel }}</span><span v-if="staleDraftVersion" class="readonly-badge">草稿基于旧版本，请刷新后再编辑</span><span class="task-editor-save-state" aria-live="polite">{{ formatLastSavedAt(lastSavedAt) }}</span><span v-if="!note.permissions.canEdit" class="readonly-badge"><IconEye :size="13" />只读</span><span v-if="!note.permissions.canEdit && updateState === 'pending'" class="readonly-badge">更新审核中</span><span v-else-if="!note.permissions.canEdit && updateState === 'needs-revision'" class="readonly-badge">更新需修改</span><button class="secondary-button" type="button" @click="copyStableLink"><IconLink :size="14" />{{ linkCopied ? '已复制链接' : '复制链接' }}</button><button class="secondary-button" type="button" @click="emit('copy', note)"><IconCopy :size="14" />复制到我的笔记</button><button v-if="!note.permissions.canEdit" class="secondary-button" type="button" :disabled="updateState === 'pending'" @click="emit('updateRequest', note)">{{ updateState === 'draft' ? '继续编辑更新' : updateState === 'needs-revision' ? '继续修改更新' : updateState === 'pending' ? '更新审核中' : '复制并编辑更新' }}</button><button class="mini-action" type="button" title="版本历史" @click="emit('versions', note)"><IconHistory :size="16" /></button><div v-if="note.permissions.canEdit || note.permissions.canDelete" ref="settingsHost" class="knowledge-settings-host" @click.stop><button ref="settingsTrigger" class="mini-action" type="button" title="知识设置" aria-label="知识设置" :aria-expanded="settingsOpen" @click="toggleSettings"><IconSettings :size="16" /></button><Teleport to="body"><section v-if="settingsOpen" ref="settingsMenu" class="knowledge-settings-menu" role="dialog" aria-label="知识设置" :style="settingsMenuStyle ?? undefined" @click.stop><header><strong>知识设置</strong><button class="knowledge-settings-close" type="button" aria-label="关闭知识设置" @click="closeSettings"><IconX :size="15" /></button></header><div v-if="note.permissions.canEdit" class="knowledge-settings-fields"><label><span>知识分类</span><select v-model="categoryId" :disabled="!collaborationContentReady || staleDraftVersion" @change="onCategoryChange"><option value="">未分类</option><option v-for="category in categories" :key="category.id" :value="category.id">{{ category.name }}</option></select></label><label><span>团队标签</span><input v-model="tags" :disabled="!collaborationContentReady || staleDraftVersion" placeholder="输入标签，空格分隔" @input="onTagsInput" /></label></div><div v-if="note.permissions.canEdit" class="knowledge-settings-actions"><button class="primary-button" type="button" :disabled="saving || !title.trim() || !collaborationContentReady || !collaborationBodyReady || staleDraftVersion" @click="saveFromSettings">保存修改</button><button class="secondary-button" type="button" @click="archiveOrRestoreFromSettings"><IconArchive v-if="note.status === 'PUBLISHED'" :size="14" /><IconRefresh v-else :size="14" />{{ note.status === 'PUBLISHED' ? '归档知识' : '恢复发布' }}</button></div><button v-if="note.permissions.canDelete" class="knowledge-settings-delete" type="button" @click="deleteFromSettings"><IconTrash :size="14" />彻底删除</button></section></Teleport></div></div>
      </header>
      <ReadonlyAttachmentPanel label="文件附件" :attachments="visibleAttachments" />
      <CollaborativeRichTextDocument v-if="note.permissions.canEdit && collaborationSession && collaborationContentReady" ref="documentRef" v-model="contentJson" :document="collaborationSession.document" :initial-content="note.contentJson" :collaboration-document-name="`knowledge-draft:${note.id}`" class="collaboration-document" :editable="!staleDraftVersion" :seed-ready="collaborationContentReady" @ready="collaborationBodyReady = true" @initialization-error="collaborationBodyReady = false; collaborationStatus = 'error'; collaborationError = $event" @update:plain-text="plainText = $event" />
      <RichTextDocument v-else ref="documentRef" v-model="contentJson" class="collaboration-document" :editable="false" />
      <footer class="knowledge-provenance"><span>稳定链接：/knowledge/{{ note.id }}</span><span v-if="note.sourceAuthor">贡献者：{{ note.sourceAuthor.nickname }}</span></footer>
    </template>
  </section>
</template>
