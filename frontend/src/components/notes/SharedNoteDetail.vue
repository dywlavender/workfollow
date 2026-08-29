<script setup lang="ts">
import { IconCopy, IconEye, IconPencil } from '@tabler/icons-vue'
import { computed, onBeforeUnmount, ref, shallowRef, watch } from 'vue'

import RichTextDocument from '@/components/RichTextDocument.vue'
import ReadonlyAttachmentPanel from '@/components/notes/ReadonlyAttachmentPanel.vue'
import { filterStandaloneAttachments } from '@/modules/editor/attachmentReferences'
import { formatLastSavedAt } from '@/modules/editor/saveStatus'
import { createNoteCollaboration, type DocumentCollaborationSession, type DocumentCollaborationStatus } from '@/modules/editor/documentCollaboration'
import { uploadAttachment, type SharedNote } from '@/services/api'

const props = defineProps<{ note: SharedNote | null; copying?: boolean }>()
const emit = defineEmits<{ copy: [note: SharedNote]; refresh: [] }>()
const collaborationSession = shallowRef<DocumentCollaborationSession | null>(null)
const collaborationLive = ref(false)
const collaborationStatus = ref<DocumentCollaborationStatus>('connecting')
const collaborationError = ref('')
const liveTitle = ref('')
let documentObserverCleanup: (() => void) | undefined
const canEdit = computed(() => props.note?.permission === 'EDITABLE')
const visibleAttachments = computed(() => filterStandaloneAttachments(
  props.note?.attachments ?? [],
  props.note?.contentJson,
))
const statusLabel = computed(() => ({
  connecting: '协同连接中',
  connected: '协同已连接',
  disconnected: '协同离线',
  error: collaborationError.value || '协同连接失败',
}[collaborationStatus.value]))

function disposeCollaboration() {
  documentObserverCleanup?.()
  documentObserverCleanup = undefined
  collaborationSession.value?.destroy()
  collaborationSession.value = null
  collaborationLive.value = false
  collaborationStatus.value = 'connecting'
  liveTitle.value = ''
}

// 协同认证失败 = 权限已被收回（或笔记被删）。销毁会话并清掉本地 IndexedDB
// 副本：本地优先机制会让被撤权者的浏览器继续留存内容，这里必须主动清除。
function handleCollaborationError(note: SharedNote, message: string) {
  if (props.note?.id !== note.id) return
  collaborationError.value = message
  const session = collaborationSession.value
  disposeCollaboration()
  collaborationStatus.value = 'error'
  void session?.persistence?.clearData().catch(() => undefined)
  emit('refresh')
}

function startCollaboration(note: SharedNote) {
  disposeCollaboration()
  collaborationError.value = ''
  let session: DocumentCollaborationSession | null = null
  session = createNoteCollaboration(note.id, null, {
    onStatus: (status) => {
      if (props.note?.id !== note.id) return
      collaborationStatus.value = status
    },
    onSynced: () => {
      if (props.note?.id !== note.id || !session) return
      collaborationLive.value = session.document.getXmlFragment('default').length > 0
      liveTitle.value = session.document.getText('title').toString()
    },
    onError: (message) => handleCollaborationError(note, message),
  })
  const fragment = session.document.getXmlFragment('default')
  const title = session.document.getText('title')
  const applyLiveState = () => {
    if (props.note?.id !== note.id) return
    if (fragment.length > 0) collaborationLive.value = true
    liveTitle.value = title.toString()
  }
  fragment.observeDeep(applyLiveState)
  title.observe(applyLiveState)
  documentObserverCleanup = () => {
    fragment.unobserveDeep(applyLiveState)
    title.unobserve(applyLiveState)
    documentObserverCleanup = undefined
  }
  collaborationSession.value = session
}

// 与 NoteEditor.replaceCollaborativeTitle 相同的差量写法：只替换变化区间，
// 避免整段重写放大协同事务。
function replaceTitle() {
  const session = collaborationSession.value
  if (!session || !canEdit.value) return
  const target = session.document.getText('title')
  const current = target.toString()
  const value = liveTitle.value
  if (current === value) return
  let start = 0
  while (start < current.length && start < value.length && current[start] === value[start]) start += 1
  let currentEnd = current.length
  let nextEnd = value.length
  while (currentEnd > start && nextEnd > start && current[currentEnd - 1] === value[nextEnd - 1]) {
    currentEnd -= 1
    nextEnd -= 1
  }
  session.document.transact(() => {
    if (currentEnd > start) target.delete(start, currentEnd - start)
    if (nextEnd > start) target.insert(start, value.slice(start, nextEnd))
  }, 'workfollow-shared-note-title')
}

function uploadImage(file: File) {
  const note = props.note
  if (!note) return Promise.reject(new Error('笔记不存在'))
  return uploadAttachment(note.id, file)
}

// 逐项比较 id/permission：父级刷新共享列表会用新对象替换同一笔记，数组型
// getter 会因引用不同误判变化，导致协同会话反复重建（编辑器不停抖动重挂载）。
watch([() => props.note?.id, () => props.note?.permission], ([noteId]) => {
  if (noteId && props.note) startCollaboration(props.note)
  else disposeCollaboration()
}, { immediate: true })

onBeforeUnmount(disposeCollaboration)
</script>

<template>
  <section class="notes-column editor-column collaboration-reader">
    <div v-if="!note" class="editor-empty"><IconEye :size="28" /><strong>选择一篇分享笔记</strong></div>
    <template v-else>
      <header class="editor-header readonly-note-header">
        <div>
          <span>{{ note.sharedBy.nickname }} 分享给你</span>
          <input v-if="canEdit" v-model="liveTitle" class="note-title-input" aria-label="笔记标题" maxlength="500" :disabled="collaborationStatus === 'error'" @input="replaceTitle" @blur="replaceTitle" />
          <h1 v-else>{{ liveTitle || note.title }}</h1>
        </div>
        <div>
          <span v-if="canEdit" class="task-collaboration-state" :class="collaborationStatus" role="status" :title="collaborationError || statusLabel">{{ statusLabel }}</span>
          <span v-if="canEdit" class="task-editor-save-state" aria-live="polite">{{ formatLastSavedAt(note.updatedAt) }}</span>
          <span class="readonly-badge" :title="canEdit ? '对方授予了你协作编辑权限' : undefined"><IconPencil v-if="canEdit" :size="13" /><IconEye v-else :size="13" />{{ canEdit ? '可编辑' : '只读' }}</span>
          <button class="secondary-button" type="button" :disabled="copying" @click="emit('copy', note)"><IconCopy :size="14" />复制到我的笔记</button>
        </div>
      </header>
      <ReadonlyAttachmentPanel label="文件附件" :attachments="visibleAttachments" />
      <RichTextDocument
        v-if="canEdit && collaborationSession"
        class="collaboration-document"
        :document="collaborationSession.document"
        :editable="collaborationStatus !== 'error'"
        :seed-ready="true"
        :seed-document="false"
        slash-menu
        :upload-image="uploadImage"
      />
      <RichTextDocument
        v-else-if="collaborationLive && collaborationSession"
        class="collaboration-document"
        :document="collaborationSession.document"
        :editable="false"
        :seed-ready="true"
        :seed-document="false"
      />
      <RichTextDocument v-else class="collaboration-document" :model-value="note.contentJson" :editable="false" />
    </template>
  </section>
</template>
