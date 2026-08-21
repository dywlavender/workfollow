<script setup lang="ts">
import { IconChevronDown, IconDownload, IconFile } from '@tabler/icons-vue'
import { ref, watch } from 'vue'

import type { Attachment } from '@/services/api'

const props = withDefaults(defineProps<{
  attachments: Attachment[]
  label?: string
}>(), {
  label: '文件附件',
})
const expanded = ref(false)

watch(() => props.attachments, () => {
  expanded.value = false
})

function formatSize(size: number): string {
  if (size < 1024) return `${size} B`
  if (size < 1024 * 1024) return `${(size / 1024).toFixed(1)} KB`
  return `${(size / 1024 / 1024).toFixed(1)} MB`
}
</script>

<template>
  <section v-if="props.attachments.length" class="readonly-attachment-panel" aria-label="附件">
    <header>
      <button
        type="button"
        class="readonly-attachment-toggle"
        :aria-expanded="expanded"
        @click="expanded = !expanded"
      >
        <span><strong>{{ props.label }}</strong><span>{{ props.attachments.length }}</span></span>
        <IconChevronDown :size="15" aria-hidden="true" />
      </button>
      <small>{{ expanded ? '点击收起' : '点击展开' }}</small>
    </header>
    <div v-if="expanded" class="readonly-attachment-list">
      <a
        v-for="attachment in props.attachments"
        :key="attachment.id"
        class="readonly-attachment-item"
        :href="attachment.url"
        target="_blank"
        rel="noopener noreferrer"
      >
        <span class="readonly-attachment-icon"><IconFile :size="16" /></span>
        <span class="readonly-attachment-name"><strong>{{ attachment.originalName }}</strong><small>{{ formatSize(attachment.size) }}</small></span>
        <IconDownload :size="15" aria-hidden="true" />
      </a>
    </div>
  </section>
</template>
