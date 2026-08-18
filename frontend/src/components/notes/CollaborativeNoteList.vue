<script setup lang="ts">
import { IconFileText, IconPlus, IconSearch } from '@tabler/icons-vue'
import dayjs from 'dayjs'

import type { SharedNote, TeamNote } from '@/services/api'

defineProps<{
  title: string
  items: Array<SharedNote | TeamNote>
  selectedId: string | null
  search: string
  canCreate?: boolean
}>()
const emit = defineEmits<{ select: [item: SharedNote | TeamNote]; search: [value: string]; create: [] }>()

function subtitle(item: SharedNote | TeamNote) {
  if ('sharedBy' in item) return `${item.sharedBy.nickname} 分享 · ${dayjs(item.updatedAt).format('M月D日')}`
  const category = item.category?.name ?? '未分类'
  const contributor = item.sourceAuthor?.nickname ?? '管理员'
  return `${category} · ${contributor}贡献 · ${dayjs(item.updatedAt).format('M月D日')}`
}
</script>

<template>
  <aside class="notes-column note-list-column collaboration-note-list">
    <header class="notes-column-header"><div><h2>{{ title }}</h2></div><button v-if="canCreate" class="mini-action" type="button" aria-label="新建知识" @click="emit('create')"><IconPlus :size="17" /></button></header>
    <label class="note-search"><IconSearch :size="16" /><input :value="search" placeholder="搜索" @input="emit('search', ($event.target as HTMLInputElement).value)" /></label>
    <div class="note-list-items">
      <article v-for="item in items" :key="item.id" :class="{ active: selectedId === item.id }">
        <button type="button" @click="emit('select', item)"><strong><IconFileText :size="14" />{{ item.title }}</strong><p>{{ subtitle(item) }}</p><small>{{ item.plainText || '空白内容' }}</small></button>
      </article>
      <p v-if="!items.length" class="notes-empty">暂无内容</p>
    </div>
  </aside>
</template>
