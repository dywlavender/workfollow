<script setup lang="ts">
import { IconTrash, IconX } from '@tabler/icons-vue'
import { ref, watch } from 'vue'

import RichTextDocument from '@/components/RichTextDocument.vue'
import { useDialogEscape } from '@/composables/useDialogEscape'
import type { NoteTemplate } from '@/services/api'

const EMPTY_DOCUMENT = { type: 'doc', content: [{ type: 'paragraph' }] }

const props = withDefaults(defineProps<{
  open: boolean
  template: NoteTemplate | null
  saving?: boolean
}>(), { saving: false })
const emit = defineEmits<{
  close: []
  save: [payload: { name: string; description: string | null; contentJson: Record<string, unknown> }]
  delete: []
}>()

const name = ref('')
const description = ref('')
const contentJson = ref<Record<string, unknown>>(cloneDocument(EMPTY_DOCUMENT))

useDialogEscape(() => props.open, () => emit('close'))

function cloneDocument(value: Record<string, unknown>): Record<string, unknown> {
  return JSON.parse(JSON.stringify(value)) as Record<string, unknown>
}

watch(
  () => [props.open, props.template?.id] as const,
  () => {
    if (!props.open) return
    name.value = props.template?.name ?? ''
    description.value = props.template?.description ?? ''
    contentJson.value = cloneDocument(props.template?.contentJson ?? EMPTY_DOCUMENT)
  },
  { immediate: true },
)

function submit() {
  const trimmedName = name.value.trim()
  if (!trimmedName || props.saving) return
  emit('save', {
    name: trimmedName,
    description: description.value.trim() || null,
    contentJson: cloneDocument(contentJson.value),
  })
}
</script>

<template>
  <Teleport to="body">
    <div v-if="open" class="dialog-backdrop template-editor-backdrop" @mousedown.self="emit('close')">
      <section class="dialog-card template-editor-dialog" role="dialog" aria-modal="true" aria-labelledby="template-editor-title">
        <header class="dialog-header">
          <div><span class="section-label">{{ template ? 'EDIT TEMPLATE' : 'NEW TEMPLATE' }}</span><h2 id="template-editor-title">{{ template ? '编辑模板' : '新建模板' }}</h2></div>
          <button class="icon-action" type="button" aria-label="关闭" @click="emit('close')"><IconX :size="18" /></button>
        </header>
        <form class="template-editor-form" @submit.prevent="submit">
          <label><span>模板名称</span><input v-model="name" maxlength="200" placeholder="例如：项目周报" autofocus /></label>
          <label><span>模板说明 <small>可选</small></span><textarea v-model="description" maxlength="2000" rows="2" placeholder="说明这个模板适合什么场景" /></label>
          <div class="template-editor-body"><span>模板正文</span><RichTextDocument v-model="contentJson" :editable="true" :slash-menu="true" placeholder="输入模板正文…" /></div>
          <footer class="dialog-actions">
            <button v-if="template" class="danger-button" type="button" @click="emit('delete')"><IconTrash :size="15" />删除模板</button>
            <span />
            <button class="secondary-button" type="button" :disabled="saving" @click="emit('close')">取消</button>
            <button class="primary-button" type="submit" :disabled="!name.trim() || saving">{{ saving ? '保存中…' : '保存' }}</button>
          </footer>
        </form>
      </section>
    </div>
  </Teleport>
</template>
