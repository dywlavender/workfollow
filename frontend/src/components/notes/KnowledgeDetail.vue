<script setup lang="ts">
import { IconArchive, IconCopy, IconEye, IconHistory, IconLink, IconRefresh } from '@tabler/icons-vue'
import { ref, watch } from 'vue'

import RichTextDocument from '@/components/RichTextDocument.vue'
import type { KnowledgeCategory, TeamNote } from '@/services/api'

const props = defineProps<{ note: TeamNote | null; categories: KnowledgeCategory[]; saving?: boolean }>()
const emit = defineEmits<{
  save: [note: TeamNote, payload: { title: string; contentJson: Record<string, unknown>; plainText: string; categoryId: string | null; tags: string[] }]
  copy: [note: TeamNote]
  archive: [note: TeamNote]
  restore: [note: TeamNote]
  updateRequest: [note: TeamNote]
  versions: [note: TeamNote]
}>()
const title = ref('')
const contentJson = ref<Record<string, unknown>>({ type: 'doc', content: [] })
const plainText = ref('')
const categoryId = ref('')
const tags = ref('')
const linkCopied = ref(false)

watch(() => props.note, (note) => {
  title.value = note?.title ?? ''
  contentJson.value = note ? JSON.parse(JSON.stringify(note.contentJson)) : { type: 'doc', content: [] }
  plainText.value = note?.plainText ?? ''
  categoryId.value = note?.categoryId ?? ''
  tags.value = note?.tags.join(' ') ?? ''
}, { immediate: true })

function save() {
  if (!props.note) return
  emit('save', props.note, {
    title: title.value.trim(), contentJson: contentJson.value, plainText: plainText.value,
    categoryId: categoryId.value || null,
    tags: tags.value.split(/[,，\s]+/).filter(Boolean),
  })
}

async function copyStableLink() {
  if (!props.note) return
  await navigator.clipboard.writeText(`${window.location.origin}/knowledge/${props.note.id}`)
  linkCopied.value = true
  window.setTimeout(() => { linkCopied.value = false }, 1600)
}
</script>

<template>
  <section class="notes-column editor-column collaboration-reader knowledge-detail">
    <div v-if="!note" class="editor-empty"><IconEye :size="28" /><strong>选择一篇团队知识</strong></div>
    <template v-else>
      <header class="editor-header knowledge-header">
        <div class="knowledge-title-block"><span>{{ note.category?.name ?? '未分类' }} · {{ note.sourceAuthor?.nickname ?? '管理员' }}贡献</span><input v-if="note.permissions.canEdit" v-model="title" aria-label="知识标题" /><h1 v-else>{{ note.title }}</h1></div>
        <div class="knowledge-actions"><span v-if="!note.permissions.canEdit" class="readonly-badge"><IconEye :size="13" />只读</span><button class="secondary-button" type="button" @click="copyStableLink"><IconLink :size="14" />{{ linkCopied ? '已复制链接' : '复制链接' }}</button><button class="secondary-button" type="button" @click="emit('copy', note)"><IconCopy :size="14" />复制到我的笔记</button><button v-if="!note.permissions.canEdit" class="secondary-button" type="button" @click="emit('updateRequest', note)">申请更新</button><button class="mini-action" type="button" title="版本历史" @click="emit('versions', note)"><IconHistory :size="16" /></button></div>
      </header>
      <div v-if="note.permissions.canEdit" class="knowledge-metadata-edit"><select v-model="categoryId"><option value="">未分类</option><option v-for="category in categories" :key="category.id" :value="category.id">{{ category.name }}</option></select><input v-model="tags" placeholder="团队标签" /><button class="primary-button" :disabled="saving || !title.trim()" @click="save">保存知识</button><button v-if="note.status === 'PUBLISHED'" class="secondary-button" @click="emit('archive', note)"><IconArchive :size="14" />归档</button><button v-else class="secondary-button" @click="emit('restore', note)"><IconRefresh :size="14" />恢复</button></div>
      <RichTextDocument v-model="contentJson" class="collaboration-document" :editable="note.permissions.canEdit" @update:plain-text="plainText = $event" />
      <footer class="knowledge-provenance"><span>稳定链接：/knowledge/{{ note.id }}</span><span v-if="note.sourceAuthor">贡献者：{{ note.sourceAuthor.nickname }}</span></footer>
    </template>
  </section>
</template>
