<script setup lang="ts">
import dayjs from 'dayjs'
import { IconCheck, IconSearch, IconX } from '@tabler/icons-vue'
import { ref, watch } from 'vue'

import { useDialogEscape } from '@/composables/useDialogEscape'
import { fetchTodos, type Todo } from '@/services/api'

const props = defineProps<{ open: boolean }>()
const emit = defineEmits<{ close: []; select: [todo: Todo] }>()
useDialogEscape(() => props.open, () => emit('close'))
const query = ref('')
const tasks = ref<Todo[]>([])
const loading = ref(false)
let timer: number | undefined

async function load() {
  loading.value = true
  try {
    tasks.value = (await fetchTodos('linkable', query.value)).slice(0, 30)
  } finally {
    loading.value = false
  }
}

function dueLabel(todo: Todo): string {
  if (todo.status === 'DONE') return '已完成'
  if (!todo.dueAt) return '无日期'
  const due = dayjs(todo.dueAt)
  if (due.isSame(dayjs(), 'day')) return '今天'
  if (due.isSame(dayjs().add(1, 'day'), 'day')) return '明天'
  return due.format('M月D日')
}

watch(() => props.open, (open) => {
  if (!open) return
  query.value = ''
  void load()
})
watch(query, () => {
  window.clearTimeout(timer)
  timer = window.setTimeout(load, 220)
})
</script>

<template>
  <Teleport to="body">
    <div v-if="open" class="dialog-backdrop task-search-backdrop" @mousedown.self="emit('close')">
      <section class="task-search-dialog" role="dialog" aria-modal="true" aria-labelledby="task-search-title">
        <header>
          <div><span class="eyebrow">关联与行动</span><h2 id="task-search-title">关联已有待办</h2></div>
          <button type="button" aria-label="关闭" @click="emit('close')"><IconX :size="18" /></button>
        </header>
        <label class="task-search-input"><IconSearch :size="17" /><input v-model="query" autofocus placeholder="搜索你有权访问的待办" /></label>
        <div class="task-search-results" role="listbox" aria-label="待办搜索结果">
          <button v-for="todo in tasks" :key="todo.id" type="button" role="option" @click="emit('select', todo)">
            <span class="task-search-status" :class="{ done: todo.status === 'DONE' }"><IconCheck v-if="todo.status === 'DONE'" :size="13" /></span>
            <strong>{{ todo.title }}</strong>
            <small>{{ dueLabel(todo) }}</small>
          </button>
          <p v-if="loading">正在读取待办…</p>
          <p v-else-if="!tasks.length">没有可关联的待办</p>
        </div>
      </section>
    </div>
  </Teleport>
</template>
