<script setup lang="ts">
import { IconEdit, IconFileText, IconFolder, IconFolderPlus, IconPlus, IconTrash } from '@tabler/icons-vue'
import { computed } from 'vue'

import type { Folder } from '@/services/api'


const props = defineProps<{ folders: Folder[]; selectedId: string | null }>()
const emit = defineEmits<{
  select: [id: string | null]
  create: [parentId: string | null]
  rename: [folder: Folder]
  remove: [folder: Folder]
}>()

interface FlatFolder { folder: Folder; depth: number }

const flatFolders = computed<FlatFolder[]>(() => {
  const result: FlatFolder[] = []
  const visit = (parentId: string | null, depth: number) => {
    props.folders.filter((folder) => folder.parentId === parentId).forEach((folder) => {
      result.push({ folder, depth })
      visit(folder.id, depth + 1)
    })
  }
  visit(null, 0)
  return result
})
</script>

<template>
  <aside class="notes-column folder-column">
    <header class="notes-column-header">
      <div><span class="eyebrow">资料库</span><h2>文件夹</h2></div>
      <button class="mini-action" type="button" aria-label="新建文件夹" title="新建文件夹" @click="emit('create', null)"><IconFolderPlus :size="17" :stroke-width="1.8" /></button>
    </header>
    <nav class="folder-tree" aria-label="笔记文件夹">
      <button :class="{ active: selectedId === null }" type="button" @click="emit('select', null)">
        <IconFileText :size="17" :stroke-width="1.8" aria-hidden="true" /><strong>全部笔记</strong>
      </button>
      <div v-for="item in flatFolders" :key="item.folder.id" class="folder-row" :style="{ '--depth': item.depth }">
        <button :class="{ active: selectedId === item.folder.id }" type="button" @click="emit('select', item.folder.id)">
          <IconFolder :size="17" :stroke-width="1.8" aria-hidden="true" /><strong>{{ item.folder.name }}</strong>
        </button>
        <div class="folder-actions">
          <button type="button" title="新建子文件夹" @click="emit('create', item.folder.id)"><IconPlus :size="14" /></button>
          <button type="button" title="重命名" @click="emit('rename', item.folder)"><IconEdit :size="14" /></button>
          <button type="button" title="删除" @click="emit('remove', item.folder)"><IconTrash :size="14" /></button>
        </div>
      </div>
    </nav>
  </aside>
</template>
