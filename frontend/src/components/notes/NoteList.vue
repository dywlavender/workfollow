<script setup lang="ts">
import { ref } from 'vue'
import { IconFilePlus, IconFileText, IconLayoutGrid, IconPlus, IconTrash, IconUpload } from '@tabler/icons-vue'
import dayjs from 'dayjs'

import { useClickOutside } from '@/composables/useClickOutside'
import { useDialogEscape } from '@/composables/useDialogEscape'
import type { NoteListItem } from '@/services/api'


const props = defineProps<{
  notes: NoteListItem[]
  selectedId: string | null
  search: string
  heading: string
  loading?: boolean
}>()
const emit = defineEmits<{
  select: [note: NoteListItem]
  create: []
  templates: []
  import: []
  search: [value: string]
  remove: [note: NoteListItem]
}>()

const createMenuOpen = ref(false)
const createMenuHost = ref<HTMLElement | null>(null)
useClickOutside(createMenuHost, createMenuOpen, () => { createMenuOpen.value = false })
useDialogEscape(() => createMenuOpen.value, () => { createMenuOpen.value = false })

type CreateAction = 'blank' | 'template' | 'import'

function chooseCreateAction(action: CreateAction) {
  createMenuOpen.value = false
  if (action === 'blank') emit('create')
  else if (action === 'template') emit('templates')
  else emit('import')
}
</script>

<template>
  <aside class="notes-column note-list-column" @click="createMenuOpen = false">
    <header class="notes-column-header">
      <div><h2>{{ heading }}</h2></div>
      <div class="notes-column-actions">
        <div ref="createMenuHost" class="notes-create-menu-host" @click.stop>
          <button class="mini-action" type="button" aria-label="新建笔记" title="新建笔记" aria-haspopup="menu" :aria-expanded="createMenuOpen" @click="createMenuOpen = !createMenuOpen"><IconPlus :size="18" :stroke-width="1.8" /></button>
          <div v-if="createMenuOpen" class="notes-create-menu" role="menu" aria-label="新建笔记方式">
            <button type="button" role="menuitem" @click="chooseCreateAction('blank')"><IconFilePlus :size="16" /><span>新建空白笔记</span></button>
            <button type="button" role="menuitem" @click="chooseCreateAction('template')"><IconLayoutGrid :size="16" /><span>从模板创建</span></button>
            <button type="button" role="menuitem" @click="chooseCreateAction('import')"><IconUpload :size="16" /><span>导入 Markdown</span></button>
          </div>
        </div>
      </div>
    </header>
    <div class="note-list-items" :class="{ 'is-refreshing': props.loading }" :aria-busy="props.loading">
      <div v-if="props.loading && !notes.length" class="notes-list-skeleton" aria-label="正在读取笔记" aria-busy="true">
        <span v-for="index in 5" :key="index"><i /><b /><em /></span>
      </div>
      <template v-else>
        <section v-if="!notes.length && !search.trim()" class="notes-empty-guide" aria-label="开始创建笔记">
          <span class="notes-empty-guide-icon"><IconFileText :size="22" /></span>
          <strong>从一条笔记开始</strong>
          <p>把想法、会议记录和临时信息先保存下来，之后再慢慢整理。</p>
          <div class="notes-empty-guide-actions">
            <button class="primary-button" type="button" @click="chooseCreateAction('blank')"><IconFilePlus :size="15" />新建空白笔记</button>
            <button class="secondary-button" type="button" @click="chooseCreateAction('template')"><IconLayoutGrid :size="15" />从模板创建</button>
            <button class="secondary-button" type="button" @click="chooseCreateAction('import')"><IconUpload :size="15" />导入 Markdown</button>
          </div>
        </section>
        <p v-else-if="!notes.length" class="notes-empty">没有匹配的笔记</p>
        <article v-for="note in notes" :key="note.id" :class="{ active: selectedId === note.id }">
          <button type="button" @click="emit('select', note)">
            <strong>{{ note.title }}</strong>
            <small>{{ dayjs(note.updatedAt).format('M月D日 HH:mm') }}</small>
          </button>
          <button class="note-delete" type="button" aria-label="删除笔记" @click="emit('remove', note)"><IconTrash :size="15" /></button>
        </article>
      </template>
    </div>
  </aside>
</template>
