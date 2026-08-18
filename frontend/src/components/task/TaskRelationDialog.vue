<script setup lang="ts">
import { IconLink, IconSearch, IconX } from '@tabler/icons-vue'
import { ref, watch } from 'vue'

import { useDialogEscape } from '@/composables/useDialogEscape'
import { fetchNotes, fetchTodos, type Note, type Todo } from '@/services/api'

const props = defineProps<{ open: boolean; currentTaskId: string }>()
const emit = defineEmits<{ close: []; selectTask: [todo: Todo]; selectNote: [note: Note] }>()
useDialogEscape(() => props.open, () => emit('close'))
const query = ref('')
const tasks = ref<Todo[]>([])
const notes = ref<Note[]>([])
const loading = ref(false)
let timer: number | undefined

async function load() {
  loading.value = true
  try {
    const [taskItems, noteItems] = await Promise.all([fetchTodos('linkable', query.value), fetchNotes({ q: query.value, limit: 20 })])
    tasks.value = taskItems.filter((item) => item.id !== props.currentTaskId).slice(0, 20)
    notes.value = noteItems.slice(0, 20)
  } finally { loading.value = false }
}
watch(() => props.open, (open) => { if (open) { query.value = ''; void load() } })
watch(query, () => { window.clearTimeout(timer); timer = window.setTimeout(load, 180) })
</script>

<template>
  <Teleport to="body">
    <div v-if="open" class="dialog-backdrop task-relation-backdrop" @mousedown.self="emit('close')">
      <section class="task-relation-dialog" role="dialog" aria-modal="true" aria-labelledby="task-relation-title">
        <header><div><h2 id="task-relation-title">关联任务或笔记</h2><p>只显示你有权访问的内容</p></div><button type="button" aria-label="关闭" @click="emit('close')"><IconX :size="18" /></button></header>
        <label class="task-relation-search"><IconSearch :size="17" /><input v-model="query" autofocus placeholder="搜索标题或正文" /></label>
        <div class="task-relation-results">
          <section><h3>任务</h3><button v-for="todo in tasks" :key="todo.id" type="button" @click="emit('selectTask', todo)"><IconLink :size="15" /><span><strong>{{ todo.title }}</strong><small>{{ todo.listName }}</small></span></button><p v-if="!loading && !tasks.length">没有匹配任务</p></section>
          <section><h3>笔记</h3><button v-for="note in notes" :key="note.id" type="button" @click="emit('selectNote', note)"><IconLink :size="15" /><span><strong>{{ note.title || '无标题笔记' }}</strong><small>{{ note.plainText.slice(0, 48) || '暂无正文' }}</small></span></button><p v-if="!loading && !notes.length">没有匹配笔记</p></section>
        </div>
        <p v-if="loading" class="task-relation-loading">正在读取…</p>
      </section>
    </div>
  </Teleport>
</template>
