<script setup lang="ts">
import { IconX } from '@tabler/icons-vue'
import { ref, watch } from 'vue'

import { useDialogEscape } from '@/composables/useDialogEscape'

const props = defineProps<{
  open: boolean
  mode: 'create' | 'rename' | 'delete'
  initialName: string
  parentName?: string | null
}>()

const emit = defineEmits<{
  close: []
  submit: [name: string]
  confirm: []
}>()
useDialogEscape(() => props.open, () => emit('close'))

const name = ref('')

watch(
  () => [props.open, props.mode, props.initialName] as const,
  () => {
    if (props.open) name.value = props.initialName
  },
  { immediate: true },
)

const title = () => props.mode === 'create' ? '新建文件夹' : props.mode === 'rename' ? '重命名文件夹' : '删除文件夹'
const description = () => props.mode === 'create'
  ? props.parentName ? `将在“${props.parentName}”下创建子文件夹。` : '创建一个新的顶层文件夹。'
  : `确定删除“${props.initialName}”吗？只有空文件夹可以删除。`

function submit() {
  const value = name.value.trim()
  if (value) emit('submit', value)
}
</script>

<template>
  <Teleport to="body">
    <div v-if="open" class="dialog-backdrop" @mousedown.self="emit('close')">
      <section class="dialog-card folder-dialog" role="dialog" aria-modal="true" aria-labelledby="folder-dialog-title">
        <header class="dialog-header">
          <div><span class="eyebrow">文件夹</span><h2 id="folder-dialog-title">{{ title() }}</h2></div>
          <button class="icon-action" type="button" aria-label="关闭" @click="emit('close')"><IconX :size="18" /></button>
        </header>
        <form v-if="mode !== 'delete'" class="todo-form" @submit.prevent="submit">
          <p class="dialog-description">{{ description() }}</p>
          <label>名称<input v-model="name" autofocus maxlength="200" required /></label>
          <footer class="dialog-actions">
            <button class="secondary-button" type="button" @click="emit('close')">取消</button>
            <button class="primary-button" type="submit">保存</button>
          </footer>
        </form>
        <div v-else class="todo-form">
          <p class="dialog-description">{{ description() }}</p>
          <footer class="dialog-actions">
            <button class="secondary-button" type="button" @click="emit('close')">取消</button>
            <button class="danger-button" type="button" @click="emit('confirm')">删除</button>
          </footer>
        </div>
      </section>
    </div>
  </Teleport>
</template>
