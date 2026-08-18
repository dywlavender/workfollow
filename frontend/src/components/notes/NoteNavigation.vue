<script setup lang="ts">
import {
  IconBook, IconClock, IconEdit, IconFileText, IconFolder, IconFolderPlus,
  IconInbox, IconPlus, IconSend, IconShieldCheck, IconStar, IconTrash,
} from '@tabler/icons-vue'
import { computed } from 'vue'

import type { Folder, KnowledgeCategory } from '@/services/api'

export type NoteView = 'recent' | 'all' | 'favorites' | 'shared' | 'knowledge' | 'submissions' | 'review'

const props = defineProps<{
  view: NoteView
  folders: Folder[]
  selectedFolderId: string | null
  hasTeam: boolean
  canReview: boolean
  categories: KnowledgeCategory[]
  selectedCategoryId: string | null
}>()
const emit = defineEmits<{
  view: [view: NoteView]
  folder: [id: string | null]
  category: [id: string | null]
  createCategory: []
  renameCategory: [category: KnowledgeCategory]
  removeCategory: [category: KnowledgeCategory]
  createFolder: [parentId: string | null]
  renameFolder: [folder: Folder]
  removeFolder: [folder: Folder]
}>()

interface FlatFolder { folder: Folder; depth: number }
const flatFolders = computed<FlatFolder[]>(() => {
  const result: FlatFolder[] = []
  const visit = (parentId: string | null, depth: number) => {
    props.folders.filter((folder) => folder.parentId === parentId).forEach((folder) => {
      result.push({ folder, depth }); visit(folder.id, depth + 1)
    })
  }
  visit(null, 0)
  return result
})
</script>

<template>
  <aside class="notes-column folder-column note-navigation">
    <header class="notes-column-header"><div><h2>笔记</h2></div><button class="mini-action" type="button" aria-label="新建文件夹" @click="emit('createFolder', null)"><IconFolderPlus :size="17" /></button></header>
    <nav class="note-primary-nav" aria-label="笔记视图">
      <button :class="{ active: view === 'recent' }" @click="emit('view', 'recent')"><IconClock :size="16" />最近</button>
      <button :class="{ active: view === 'all' && selectedFolderId === null }" @click="emit('view', 'all'); emit('folder', null)"><IconFileText :size="16" />全部</button>
      <button :class="{ active: view === 'favorites' }" @click="emit('view', 'favorites')"><IconStar :size="16" />收藏</button>
    </nav>
    <div class="note-nav-section">
      <header><span>我的文件夹</span><button type="button" aria-label="新建文件夹" @click="emit('createFolder', null)"><IconPlus :size="13" /></button></header>
      <div class="folder-tree">
        <div v-for="item in flatFolders" :key="item.folder.id" class="folder-row" :style="{ '--depth': item.depth }">
          <button :class="{ active: view === 'all' && selectedFolderId === item.folder.id }" @click="emit('view', 'all'); emit('folder', item.folder.id)"><IconFolder :size="16" /><strong>{{ item.folder.name }}</strong></button>
          <div class="folder-actions"><button title="新建子文件夹" @click="emit('createFolder', item.folder.id)"><IconPlus :size="13" /></button><button title="重命名" @click="emit('renameFolder', item.folder)"><IconEdit :size="13" /></button><button title="删除" @click="emit('removeFolder', item.folder)"><IconTrash :size="13" /></button></div>
        </div>
      </div>
    </div>
    <template v-if="hasTeam">
      <div class="note-nav-divider" />
      <nav class="note-collab-nav" aria-label="笔记协作">
        <button :class="{ active: view === 'shared' }" @click="emit('view', 'shared')"><IconInbox :size="16" />分享给我的</button>
        <button :class="{ active: view === 'knowledge' }" @click="emit('view', 'knowledge'); emit('category', null)"><IconBook :size="16" />团队知识库</button>
        <button :class="{ active: view === 'submissions' }" @click="emit('view', 'submissions')"><IconSend :size="16" />我的投稿</button>
        <button v-if="canReview" :class="{ active: view === 'review' }" @click="emit('view', 'review')"><IconShieldCheck :size="16" />知识审核</button>
      </nav>
      <div v-if="view === 'knowledge'" class="knowledge-category-nav">
        <span>知识分类 <button v-if="canReview" type="button" aria-label="新建知识分类" @click="emit('createCategory')"><IconPlus :size="12" /></button></span>
        <button :class="{ active: selectedCategoryId === null }" @click="emit('category', null)">全部知识</button>
        <div v-for="category in categories" :key="category.id" class="knowledge-category-row">
          <button :class="{ active: selectedCategoryId === category.id }" @click="emit('category', category.id)">{{ category.name }}</button>
          <div v-if="canReview" class="knowledge-category-actions"><button type="button" :aria-label="`重命名${category.name}`" @click="emit('renameCategory', category)"><IconEdit :size="12" /></button><button type="button" :aria-label="`删除${category.name}`" @click="emit('removeCategory', category)"><IconTrash :size="12" /></button></div>
        </div>
      </div>
    </template>
  </aside>
</template>
