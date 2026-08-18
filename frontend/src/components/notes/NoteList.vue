<script setup lang="ts">
import { IconFilePlus, IconLayoutGrid, IconSearch, IconTrash } from '@tabler/icons-vue'
import dayjs from 'dayjs'

import type { Note } from '@/services/api'


defineProps<{ notes: Note[]; selectedId: string | null; search: string }>()
const emit = defineEmits<{ select: [note: Note]; create: []; templates: []; search: [value: string]; remove: [note: Note] }>()
</script>

<template>
  <aside class="notes-column note-list-column">
    <header class="notes-column-header">
      <div><span class="eyebrow">内容</span><h2>笔记</h2></div>
      <button class="mini-action" type="button" aria-label="新建笔记" @click="emit('create')"><IconFilePlus :size="17" :stroke-width="1.8" /></button>
    </header>
    <label class="note-search"><IconSearch :size="16" :stroke-width="1.8" aria-hidden="true" /><input :value="search" placeholder="搜索笔记" @input="emit('search', ($event.target as HTMLInputElement).value)" /></label>
    <button class="template-entry" type="button" @click="emit('templates')"><IconLayoutGrid :size="16" :stroke-width="1.8" /><span>从模板创建</span></button>
    <div class="note-list-items">
      <p v-if="!notes.length" class="notes-empty">还没有笔记</p>
      <article v-for="note in notes" :key="note.id" :class="{ active: selectedId === note.id }">
        <button type="button" @click="emit('select', note)">
          <strong>{{ note.title }}</strong>
          <p>{{ note.plainText || '空白笔记' }}</p>
          <small>{{ dayjs(note.updatedAt).format('M月D日 HH:mm') }}</small>
        </button>
        <button class="note-delete" type="button" aria-label="删除笔记" @click="emit('remove', note)"><IconTrash :size="15" /></button>
      </article>
    </div>
  </aside>
</template>
