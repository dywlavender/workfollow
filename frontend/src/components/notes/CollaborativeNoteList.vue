<script setup lang="ts">
import { IconFileText, IconPlus } from '@tabler/icons-vue'
import dayjs from 'dayjs'

import type { SharedNote, TeamNoteListItem } from '@/services/api'

const props = defineProps<{
  title: string
  items: Array<SharedNote | TeamNoteListItem>
  selectedId: string | null
  search: string
  loading?: boolean
  canCreate?: boolean
  canManageArchived?: boolean
  statusFilter?: 'published' | 'archived'
}>()
const emit = defineEmits<{
  select: [item: SharedNote | TeamNoteListItem]
  search: [value: string]
  create: []
  statusFilter: [value: 'published' | 'archived']
}>()

function subtitle(item: SharedNote | TeamNoteListItem) {
  if ('sharedBy' in item) return `${item.sharedBy.nickname} 分享 · ${dayjs(item.updatedAt).format('M月D日')}`
  const category = item.category?.name ?? '未分类'
  const contributor = item.sourceAuthor?.nickname ?? '管理员'
  return `${category} · ${contributor}贡献 · ${dayjs(item.updatedAt).format('M月D日')}`
}

// This list is also used for shared notes; the parent handles the two detail paths.
</script>

<template>
  <aside class="notes-column note-list-column collaboration-note-list">
    <header class="notes-column-header"><div><h2>{{ title }}</h2></div><button v-if="canCreate" class="mini-action" type="button" aria-label="新建知识" title="新建知识" @click="emit('create')"><IconPlus :size="17" /></button></header>
    <div v-if="canManageArchived" class="collaboration-status-filter" role="tablist" aria-label="知识状态">
      <button type="button" role="tab" :aria-selected="statusFilter === 'published'" :class="{ active: statusFilter === 'published' }" @click="emit('statusFilter', 'published')">已发布</button>
      <button type="button" role="tab" :aria-selected="statusFilter === 'archived'" :class="{ active: statusFilter === 'archived' }" @click="emit('statusFilter', 'archived')">已归档</button>
    </div>
    <div class="note-list-items" :class="{ 'is-refreshing': props.loading }" :aria-busy="props.loading">
      <div v-if="props.loading && !items.length" class="notes-list-skeleton" aria-label="正在读取列表" aria-busy="true">
        <span v-for="index in 5" :key="index"><i /><b /><em /></span>
      </div>
      <template v-else>
        <article v-for="item in items" :key="item.id" :class="{ active: selectedId === item.id }">
          <button type="button" @click="emit('select', item)"><strong><IconFileText :size="14" />{{ item.title }}</strong><p>{{ subtitle(item) }}</p></button>
        </article>
        <p v-if="!items.length" class="notes-empty">暂无内容</p>
      </template>
    </div>
  </aside>
</template>
