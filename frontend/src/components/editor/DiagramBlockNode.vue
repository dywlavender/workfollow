<script setup lang="ts">
import { NodeViewWrapper, nodeViewProps } from '@tiptap/vue-3'
import { IconPencil } from '@tabler/icons-vue'
import { computed } from 'vue'

import { normalizeImageWidth } from '@/modules/editor/imageSizing'
import { useEditorEditable } from '@/modules/editor/editorEditable'

const props = defineProps(nodeViewProps)

type DiagramEditorStorage = {
  openEditor?: (attrs: Record<string, unknown>, applyUpdate: (next: Record<string, unknown>) => void) => void
  editingPresence?: Record<string, { userName: string }> | null
}

const editable = useEditorEditable(props.editor)
const previewUrl = computed(() => {
  const previewId = props.node.attrs.previewAttachmentId
  if (!previewId) return ''
  return `/api/attachments/${previewId}?v=${props.node.attrs.revision ?? 1}`
})
const stageStyle = computed(() => {
  const width = normalizeImageWidth(props.node.attrs.width)
  return width === null ? undefined : { width: `${width}%` }
})
const canEdit = computed(() => editable.value)
/** 编辑存在感（第一档协同）：他人正在编辑这张图时显示提示徽标。 */
const editingPeer = computed(() => {
  const presence = (props.editor.storage.diagramBlock as DiagramEditorStorage | undefined)?.editingPresence
  const sourceId = props.node.attrs.sourceAttachmentId
  if (!presence || typeof sourceId !== 'string' || !sourceId) return null
  return presence[sourceId] ?? null
})

function openEditor() {
  if (!canEdit.value) return
  const storage = props.editor.storage.diagramBlock as DiagramEditorStorage | undefined
  storage?.openEditor?.(
    { ...props.node.attrs },
    (next) => props.updateAttributes(next),
  )
}
</script>

<template>
  <NodeViewWrapper class="diagram-block-node" :class="{ 'is-selected': selected }">
    <figure class="diagram-block" :style="stageStyle" @dblclick.prevent="openEditor">
      <img
        v-if="previewUrl"
        :src="previewUrl"
        :alt="String(node.attrs.title ?? '流程图')"
        :title="String(node.attrs.title ?? '流程图')"
        draggable="false"
      />
      <span v-else class="diagram-block-empty">
        <strong>{{ String(node.attrs.title ?? '流程图') }}</strong>
        <small>预览生成中或缺失，双击重新编辑</small>
      </span>
      <span v-if="editingPeer" class="diagram-block-presence">{{ editingPeer.userName }} 编辑中</span>
      <button
        v-if="canEdit"
        type="button"
        class="diagram-block-edit"
        aria-label="编辑流程图"
        title="编辑流程图"
        @click.prevent.stop="openEditor"
      >
        <IconPencil :size="13" /> 编辑
      </button>
    </figure>
  </NodeViewWrapper>
</template>
