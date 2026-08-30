<script setup lang="ts">
import {
  IconBook, IconClock, IconDots, IconEdit, IconFileText,
  IconFolder, IconFolderPlus, IconInbox, IconPlus, IconSearch, IconSend, IconShare, IconShieldCheck,
  IconStar, IconTrash,
} from '@tabler/icons-vue'
import { computed, ref, watch } from 'vue'

import { useClickOutside } from '@/composables/useClickOutside'
import type { Folder, KnowledgeCategory } from '@/services/api'

export type NoteView = 'recent' | 'all' | 'inbox' | 'favorites' | 'shared' | 'sharedByMe' | 'knowledge' | 'submissions' | 'review'

const props = defineProps<{
  view: NoteView
  folders: Folder[]
  selectedFolderId: string | null
  hasTeam: boolean
  canReview: boolean
  categories: KnowledgeCategory[]
  selectedCategoryId: string | null
  allCount?: number
  unfiledCount?: number
  favoriteCount?: number
  folderCounts?: Record<string, number>
  sharedCount?: number
  sharedByMeCount?: number
  knowledgeCount?: number
  submissionsCount?: number
  submissionsPendingCount?: number
  reviewPendingCount?: number
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
  openSearch: []
}>()

const categoryNavOpen = ref(true)
const openCategoryActionsId = ref<string | null>(null)
const categoryNav = ref<HTMLElement | null>(null)
const categoryMenuOpen = computed(() => openCategoryActionsId.value !== null)
useClickOutside(categoryNav, categoryMenuOpen, () => { openCategoryActionsId.value = null })

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

function selectCategory(id: string | null) {
  openCategoryActionsId.value = null
  emit('category', id)
}

function toggleKnowledgeNav() {
  if (props.view === 'knowledge') {
    categoryNavOpen.value = !categoryNavOpen.value
    if (!categoryNavOpen.value) openCategoryActionsId.value = null
    return
  }
  categoryNavOpen.value = true
  emit('view', 'knowledge')
  emit('category', null)
}

function toggleCategoryActions(id: string) {
  openCategoryActionsId.value = openCategoryActionsId.value === id ? null : id
}

function renameCategory(category: KnowledgeCategory) {
  openCategoryActionsId.value = null
  emit('renameCategory', category)
}

function removeCategory(category: KnowledgeCategory) {
  openCategoryActionsId.value = null
  emit('removeCategory', category)
}

watch(() => props.view, (view) => {
  if (view === 'knowledge') categoryNavOpen.value = true
  else {
    categoryNavOpen.value = false
    openCategoryActionsId.value = null
  }
})
</script>

<template>
  <aside class="notes-column folder-column note-navigation">
    <header class="notes-column-header"><div><h2>笔记</h2></div><div class="notes-column-actions"><button class="mini-action note-global-search-trigger" type="button" aria-label="全局搜索" title="全局搜索" @click="emit('openSearch')"><IconSearch :size="16" /></button><button class="mini-action" type="button" aria-label="新建文件夹" title="新建文件夹" @click="emit('createFolder', null)"><IconFolderPlus :size="17" /></button></div></header>
    <div class="note-navigation-scroll">
    <nav class="note-primary-nav" aria-label="笔记视图">
      <button :class="{ active: view === 'recent' }" @click="emit('view', 'recent')"><IconClock :size="16" />最近</button>
      <button :class="{ active: view === 'all' && selectedFolderId === null }" @click="emit('view', 'all'); emit('folder', null)"><IconFileText :size="16" />全部<em v-if="allCount">{{ allCount > 99 ? '99+' : allCount }}</em></button>
      <button :class="{ active: view === 'inbox' }" @click="emit('view', 'inbox')"><IconInbox :size="16" /><span>收件箱</span><em v-if="unfiledCount">{{ unfiledCount }}</em></button>
      <button :class="{ active: view === 'favorites' }" @click="emit('view', 'favorites')"><IconStar :size="16" />收藏<em v-if="favoriteCount">{{ favoriteCount > 99 ? '99+' : favoriteCount }}</em></button>
    </nav>
    <div class="note-nav-section">
      <header><span>我的文件夹</span><button type="button" aria-label="新建文件夹" @click="emit('createFolder', null)"><IconPlus :size="13" /></button></header>
      <div class="folder-tree">
        <div v-for="item in flatFolders" :key="item.folder.id" class="folder-row" :style="{ '--depth': item.depth }">
          <button :class="{ active: view === 'all' && selectedFolderId === item.folder.id }" @click="emit('view', 'all'); emit('folder', item.folder.id)"><IconFolder :size="16" /><strong>{{ item.folder.name }}</strong><em v-if="folderCounts?.[item.folder.id]" class="folder-note-count">{{ folderCounts[item.folder.id] > 99 ? '99+' : folderCounts[item.folder.id] }}</em></button>
          <div class="folder-actions"><button title="新建子文件夹" @click="emit('createFolder', item.folder.id)"><IconPlus :size="13" /></button><button title="重命名" @click="emit('renameFolder', item.folder)"><IconEdit :size="13" /></button><button title="删除" @click="emit('removeFolder', item.folder)"><IconTrash :size="13" /></button></div>
        </div>
      </div>
    </div>
    <template v-if="hasTeam">
      <div class="note-nav-divider" />
      <nav class="note-collab-nav" aria-label="笔记协作">
        <button :class="{ active: view === 'shared' }" @click="emit('view', 'shared')"><IconInbox :size="16" />分享给我的<em v-if="sharedCount">{{ sharedCount > 99 ? '99+' : sharedCount }}</em></button>
        <button :class="{ active: view === 'sharedByMe' }" @click="emit('view', 'sharedByMe')"><IconShare :size="16" />我分享的<em v-if="sharedByMeCount">{{ sharedByMeCount > 99 ? '99+' : sharedByMeCount }}</em></button>
        <button :class="{ active: view === 'submissions' }" @click="emit('view', 'submissions')"><IconSend :size="16" />我的投稿<em v-if="submissionsCount !== undefined" :title="submissionsPendingCount ? `${submissionsPendingCount} 条待处理` : '暂无待处理投稿'">{{ submissionsCount > 99 ? '99+' : submissionsCount }}</em></button>
        <button v-if="canReview" :class="{ active: view === 'review' }" @click="emit('view', 'review')"><IconShieldCheck :size="16" />知识审核<em v-if="reviewPendingCount">{{ reviewPendingCount > 99 ? '99+' : reviewPendingCount }}</em></button>
        <div class="knowledge-nav-entry" :class="{ active: view === 'knowledge' }">
          <button class="knowledge-nav-main" :class="{ active: view === 'knowledge' }" type="button" aria-controls="knowledge-category-list" :aria-expanded="view === 'knowledge' && categoryNavOpen" @click="toggleKnowledgeNav"><IconBook :size="16" />团队知识库<em v-if="knowledgeCount">{{ knowledgeCount > 99 ? '99+' : knowledgeCount }}</em></button>
          <button v-if="canReview" class="knowledge-category-add" type="button" aria-label="新建知识分类" title="新建分类" @click.stop="openCategoryActionsId = null; emit('createCategory')"><IconPlus :size="14" /></button>
        </div>
      </nav>
      <div v-if="view === 'knowledge'" ref="categoryNav" class="knowledge-category-nav" @click="openCategoryActionsId = null" @keydown.esc="openCategoryActionsId = null">
        <div v-show="categoryNavOpen" id="knowledge-category-list" class="knowledge-category-list">
          <button class="knowledge-category-item knowledge-category-all" :class="{ active: selectedCategoryId === null }" @click="selectCategory(null)"><IconBook :size="15" /><span>全部知识</span><em v-if="knowledgeCount !== undefined">{{ knowledgeCount > 99 ? '99+' : knowledgeCount }}</em></button>
          <p v-if="categories.length === 0" class="knowledge-category-empty">暂无自定义分类</p>
          <div v-for="category in categories" :key="category.id" class="knowledge-category-row" :class="{ 'is-menu-open': openCategoryActionsId === category.id, 'is-selected': selectedCategoryId === category.id }">
            <button class="knowledge-category-item" :class="{ active: selectedCategoryId === category.id }" :title="category.name" @click="selectCategory(category.id)"><IconFolder :size="15" /><span>{{ category.name }}</span><em v-if="category.noteCount !== undefined">{{ category.noteCount > 99 ? '99+' : category.noteCount }}</em></button>
            <div v-if="canReview" class="knowledge-category-actions">
              <button class="knowledge-category-more" type="button" :aria-label="`${category.name}设置`" aria-haspopup="menu" :aria-expanded="openCategoryActionsId === category.id" @click.stop="toggleCategoryActions(category.id)"><IconDots :size="16" /></button>
            </div>
            <div v-if="canReview && openCategoryActionsId === category.id" class="knowledge-category-menu" role="menu" @click.stop>
              <button type="button" role="menuitem" @click="renameCategory(category)"><IconEdit :size="14" />重命名</button>
              <button class="knowledge-category-menu-danger" type="button" role="menuitem" @click="removeCategory(category)"><IconTrash :size="14" />删除</button>
            </div>
          </div>
        </div>
      </div>
    </template>
    </div>
  </aside>
</template>
