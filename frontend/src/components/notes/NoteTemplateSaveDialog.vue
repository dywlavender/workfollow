<script setup lang="ts">
import { IconX } from '@tabler/icons-vue'
import { ref, watch } from 'vue'

import { useDialogEscape } from '@/composables/useDialogEscape'

const props = withDefaults(defineProps<{ open: boolean; saving?: boolean }>(), { saving: false })
const emit = defineEmits<{
  close: []
  save: [payload: { name: string; description: string | null }]
}>()

const name = ref('')
const description = ref('')
useDialogEscape(() => props.open, () => emit('close'))

watch(() => props.open, (open) => {
  if (open) { name.value = ''; description.value = '' }
})

function submit() {
  const trimmedName = name.value.trim()
  if (!trimmedName || props.saving) return
  emit('save', { name: trimmedName, description: description.value.trim() || null })
}
</script>

<template>
  <Teleport to="body">
    <div v-if="open" class="dialog-backdrop" @mousedown.self="emit('close')">
      <section class="dialog-card template-save-dialog" role="dialog" aria-modal="true" aria-labelledby="template-save-title">
        <header class="dialog-header"><div><span class="section-label">SAVE AS TEMPLATE</span><h2 id="template-save-title">保存为模板</h2></div><button class="icon-action" type="button" aria-label="关闭" @click="emit('close')"><IconX :size="18" /></button></header>
        <form class="template-save-form" @submit.prevent="submit">
          <p>当前笔记正文会复制到个人模板，之后修改模板不会影响这篇笔记。</p>
          <label><span>模板名称</span><input v-model="name" maxlength="200" placeholder="例如：项目周报" autofocus /></label>
          <label><span>模板说明 <small>可选</small></span><textarea v-model="description" maxlength="2000" rows="3" placeholder="说明这个模板适合什么场景" /></label>
          <footer class="dialog-actions"><button class="secondary-button" type="button" :disabled="saving" @click="emit('close')">取消</button><button class="primary-button" type="submit" :disabled="!name.trim() || saving">{{ saving ? '保存中…' : '确认保存' }}</button></footer>
        </form>
      </section>
    </div>
  </Teleport>
</template>
