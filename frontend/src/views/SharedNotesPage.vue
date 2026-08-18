<script setup lang="ts">
import { onMounted, ref } from 'vue'
import { IconArrowLeft, IconEye, IconFileText } from '@tabler/icons-vue'

import { fetchSharedNotes, type SharedNote } from '@/services/api'

const notes = ref<SharedNote[]>([])
const selected = ref<SharedNote | null>(null)
const loading = ref(false)
const error = ref('')

async function load() {
  loading.value = true
  try {
    notes.value = await fetchSharedNotes()
    selected.value = notes.value[0] ?? null
  } catch (cause: any) {
    error.value = cause?.response?.data?.detail ?? '无法读取共享笔记。'
  } finally {
    loading.value = false
  }
}

onMounted(load)
</script>

<template>
  <div class="shared-notes-page page-content">
    <header class="workspace-heading">
      <div>
        <span class="eyebrow">READ ONLY</span>
        <h1>共享笔记</h1>
        <p>这里显示他人实时共享的个人笔记，只读且不会创建副本。</p>
      </div>
      <RouterLink class="secondary-button" to="/notes"><IconArrowLeft :size="15" />返回个人笔记</RouterLink>
    </header>
    <p v-if="loading" class="state-message">正在加载共享笔记…</p>
    <p v-else-if="error" class="state-message error">{{ error }}</p>
    <section v-else class="shared-notes-layout">
      <aside class="shared-note-index card">
        <button v-for="note in notes" :key="note.id" type="button" :class="{ active: selected?.id === note.id }" @click="selected = note">
          <IconFileText :size="15" /><span>{{ note.title }}</span>
        </button>
        <p v-if="!notes.length" class="state-message empty"><IconEye :size="22" /><span>暂时没有共享笔记</span></p>
      </aside>
      <article v-if="selected" class="shared-note-reader card">
        <div class="shared-note-badge"><IconEye :size="14" />实时只读</div>
        <h2>{{ selected.title }}</h2>
        <p>{{ selected.plainText || '（空笔记）' }}</p>
      </article>
      <article v-else class="shared-note-reader card state-message empty"><IconEye :size="24" /><span>选择一篇共享笔记</span></article>
    </section>
  </div>
</template>
