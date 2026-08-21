<script setup lang="ts">
import { IconFileText, IconUpload, IconX } from '@tabler/icons-vue'
import { ref, watch } from 'vue'

import { useDialogEscape } from '@/composables/useDialogEscape'
import type { Folder } from '@/services/api'

const props = withDefaults(defineProps<{
  open: boolean
  folders: Folder[]
  initialFolderId?: string | null
  saving?: boolean
  error?: string | null
}>(), { initialFolderId: null, saving: false, error: null })

const emit = defineEmits<{
  close: []
  clearError: []
  submit: [payload: { file: File; title: string; folderId: string | null }]
}>()

const fileInput = ref<HTMLInputElement | null>(null)
const file = ref<File | null>(null)
const title = ref('')
const titleEdited = ref(false)
const folderId = ref<string | null>(null)
const fileError = ref<string | null>(null)

useDialogEscape(() => props.open, () => emit('close'))

watch(
  () => [props.open, props.initialFolderId] as const,
  () => {
    if (!props.open) return
    file.value = null
    title.value = ''
    titleEdited.value = false
    folderId.value = props.initialFolderId ?? null
    fileError.value = null
    if (fileInput.value) fileInput.value.value = ''
  },
  { immediate: true },
)

function filenameTitle(name: string): string {
  const value = name.replace(/\.(?:md|markdown)$/i, '').trim()
  return value || '未命名笔记'
}

function cleanTitle(value: string): string {
  return value
    .replace(/^\s*[-*_`]+|[-*_`]+\s*$/g, '')
    .replace(/\[([^\]]+)\]\([^)]*\)/g, '$1')
    .replace(/\s+/g, ' ')
    .trim()
}

async function deriveTitle(selected: File): Promise<string> {
  try {
    const sample = await selected.slice(0, 64 * 1024).text()
    const frontMatter = sample.match(/^---\s*\n([\s\S]*?)(?:\n|\r\n)(?:---|\.\.\.)\s*(?:\n|$)/)
    const frontTitle = frontMatter?.[1].match(/^\s*title\s*:\s*(.+?)\s*$/im)?.[1]
    if (frontTitle?.trim()) return cleanTitle(frontTitle.trim().replace(/^['"]|['"]$/g, ''))
    const h1 = sample.match(/^\s{0,3}#\s+(.+?)\s*#*\s*$/m)?.[1]
    if (h1?.trim()) return cleanTitle(h1)
  } catch {
    // The backend remains authoritative for encoding validation and title extraction.
  }
  return filenameTitle(selected.name)
}

async function selectFile(selected: File | undefined) {
  emit('clearError')
  fileError.value = null
  if (!selected) return
  if (!/\.(?:md|markdown)$/i.test(selected.name)) {
    file.value = null
    title.value = ''
    titleEdited.value = false
    fileError.value = '请选择 .md 或 .markdown 文件。'
    if (fileInput.value) fileInput.value.value = ''
    return
  }
  file.value = selected
  titleEdited.value = false
  title.value = await deriveTitle(selected)
}

function submit() {
  if (!file.value || !title.value.trim() || props.saving) return
  emit('submit', { file: file.value, title: titleEdited.value ? title.value.trim() : '', folderId: folderId.value })
}
</script>

<template>
  <Teleport to="body">
    <div v-if="open" class="dialog-backdrop" @mousedown.self="emit('close')">
      <section class="dialog-card markdown-import-dialog" role="dialog" aria-modal="true" aria-labelledby="markdown-import-title">
        <header class="dialog-header">
          <div><span class="eyebrow">IMPORT</span><h2 id="markdown-import-title">导入 Markdown</h2></div>
          <button class="icon-action" type="button" aria-label="关闭" :disabled="saving" @click="emit('close')"><IconX :size="18" /></button>
        </header>
        <form class="todo-form" @submit.prevent="submit">
          <p class="dialog-description">Markdown 会转换为一篇新的可编辑笔记，不会覆盖当前笔记。</p>
          <label class="markdown-file-picker">
            <input ref="fileInput" class="sr-only" type="file" accept=".md,.markdown,text/markdown" @change="selectFile(($event.target as HTMLInputElement).files?.[0])" />
            <span class="markdown-file-picker-icon"><IconUpload :size="19" /></span>
            <span v-if="file"><strong>{{ file.name }}</strong><small>点击重新选择文件</small></span>
            <span v-else><strong>选择 Markdown 文件</strong><small>支持 .md 和 .markdown，最大 5MB</small></span>
          </label>
          <p v-if="fileError" class="markdown-import-error" role="alert">{{ fileError }}</p>
          <p v-if="error" class="markdown-import-error" role="alert">{{ error }}</p>
          <template v-if="file">
            <label>笔记标题<input v-model="title" maxlength="500" required @input="titleEdited = true" /></label>
            <label>目标文件夹
              <select v-model="folderId">
                <option :value="null">未分类</option>
                <option v-for="folder in folders" :key="folder.id" :value="folder.id">{{ folder.name }}</option>
              </select>
            </label>
            <p class="markdown-import-note"><IconFileText :size="15" />导入后正文仍可在富文本编辑器中继续修改。</p>
          </template>
          <footer class="dialog-actions">
            <button class="secondary-button" type="button" :disabled="saving" @click="emit('close')">取消</button>
            <button class="primary-button" type="submit" :disabled="!file || !title.trim() || saving">{{ saving ? '导入中…' : '导入并创建' }}</button>
          </footer>
        </form>
      </section>
    </div>
  </Teleport>
</template>
