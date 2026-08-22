<script setup lang="ts">
import { ref, watch } from 'vue'
import { IconX } from '@tabler/icons-vue'

const props = defineProps<{ open: boolean; saving?: boolean }>()
const emit = defineEmits<{
  close: []
  submit: [payload: { text: string; title?: string; tags?: string[] }]
}>()

const text = ref('')
const title = ref('')
const tagDraft = ref('')

watch(() => props.open, (open) => {
  if (open) {
    text.value = ''
    title.value = ''
    tagDraft.value = ''
  }
})

function submit() {
  const value = text.value.trim()
  if (!value || props.saving) return
  const tags = tagDraft.value.split(',').map((item) => item.trim()).filter(Boolean)
  emit('submit', { text: value, title: title.value.trim() || undefined, tags: tags.length ? tags : undefined })
}
</script>

<template>
  <Teleport to="body">
    <div v-if="open" class="dialog-backdrop" @mousedown.self="emit('close')">
      <section class="capture-dialog" role="dialog" aria-modal="true" aria-labelledby="capture-dialog-title">
        <header><div><span class="eyebrow">CAPTURE</span><h2 id="capture-dialog-title">随手记</h2></div><button type="button" aria-label="关闭随手记" @click="emit('close')"><IconX :size="18" /></button></header>
        <p class="capture-dialog-hint">先记录下来，稍后可以在收件箱中整理到文件夹。</p>
        <label>内容<textarea v-model="text" rows="8" autofocus placeholder="写下现在想到的事情、会议要点或待整理信息…" @keydown.meta.enter.prevent="submit" @keydown.ctrl.enter.prevent="submit" /></label>
        <label>标题（可选）<input v-model="title" maxlength="500" placeholder="默认使用内容首行" /></label>
        <label>标签（可选）<input v-model="tagDraft" maxlength="400" placeholder="多个标签用逗号分隔" /></label>
        <footer><button type="button" class="secondary-button" @click="emit('close')">取消</button><button type="button" class="primary-button" :disabled="saving || !text.trim()" @click="submit">{{ saving ? '保存中…' : '保存到收件箱' }}</button></footer>
      </section>
    </div>
  </Teleport>
</template>
