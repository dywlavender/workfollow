<script setup lang="ts">
import { IconCopy, IconEye } from '@tabler/icons-vue'
import { computed, onBeforeUnmount, ref, shallowRef, watch } from 'vue'

import RichTextDocument from '@/components/RichTextDocument.vue'
import CollaborativeRichTextDocument from '@/components/notes/CollaborativeRichTextDocument.vue'
import ReadonlyAttachmentPanel from '@/components/notes/ReadonlyAttachmentPanel.vue'
import { filterStandaloneAttachments } from '@/modules/editor/attachmentReferences'
import { createNoteCollaboration, type DocumentCollaborationSession } from '@/modules/editor/documentCollaboration'
import type { SharedNote } from '@/services/api'

const props = defineProps<{ note: SharedNote | null; copying?: boolean }>()
const emit = defineEmits<{ copy: [note: SharedNote] }>()
const collaborationSession = shallowRef<DocumentCollaborationSession | null>(null)
const collaborationLive = ref(false)
const liveTitle = ref('')
let documentObserverCleanup: (() => void) | undefined
const visibleAttachments = computed(() => filterStandaloneAttachments(
  props.note?.attachments ?? [],
  props.note?.contentJson,
))

function disposeCollaboration() {
  documentObserverCleanup?.()
  documentObserverCleanup = undefined
  collaborationSession.value?.destroy()
  collaborationSession.value = null
  collaborationLive.value = false
  liveTitle.value = ''
}

function startCollaboration(note: SharedNote) {
  disposeCollaboration()
  let session: DocumentCollaborationSession | null = null
  session = createNoteCollaboration(note.id, null, {
    onSynced: () => {
      if (props.note?.id !== note.id || !session) return
      collaborationLive.value = session.document.getXmlFragment('default').length > 0
      liveTitle.value = session.document.getText('title').toString()
    },
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

watch(() => props.note?.id, (noteId) => {
  if (noteId && props.note) startCollaboration(props.note)
  else disposeCollaboration()
}, { immediate: true })

onBeforeUnmount(disposeCollaboration)
</script>

<template>
  <section class="notes-column editor-column collaboration-reader">
    <div v-if="!note" class="editor-empty"><IconEye :size="28" /><strong>选择一篇分享笔记</strong></div>
    <template v-else>
      <header class="editor-header readonly-note-header"><div><span>{{ note.sharedBy.nickname }} 分享给你</span><h1>{{ liveTitle || note.title }}</h1></div><div><span class="readonly-badge"><IconEye :size="13" />只读</span><button class="secondary-button" type="button" :disabled="copying" @click="emit('copy', note)"><IconCopy :size="14" />复制到我的笔记</button></div></header>
      <ReadonlyAttachmentPanel label="文件附件" :attachments="visibleAttachments" />
      <CollaborativeRichTextDocument
        v-if="collaborationLive && collaborationSession"
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
