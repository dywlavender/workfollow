<script setup lang="ts">
import { IconCopy, IconEye } from '@tabler/icons-vue'

import RichTextDocument from '@/components/RichTextDocument.vue'
import type { SharedNote } from '@/services/api'

defineProps<{ note: SharedNote | null; copying?: boolean }>()
const emit = defineEmits<{ copy: [note: SharedNote] }>()
</script>

<template>
  <section class="notes-column editor-column collaboration-reader">
    <div v-if="!note" class="editor-empty"><IconEye :size="28" /><strong>选择一篇分享笔记</strong></div>
    <template v-else>
      <header class="editor-header readonly-note-header"><div><span>{{ note.sharedBy.nickname }} 分享给你</span><h1>{{ note.title }}</h1></div><div><span class="readonly-badge"><IconEye :size="13" />只读</span><button class="secondary-button" type="button" :disabled="copying" @click="emit('copy', note)"><IconCopy :size="14" />复制到我的笔记</button></div></header>
      <RichTextDocument class="collaboration-document" :model-value="note.contentJson" :editable="false" />
    </template>
  </section>
</template>
