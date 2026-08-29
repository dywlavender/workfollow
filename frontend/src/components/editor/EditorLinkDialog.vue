<script setup lang="ts">
import type { Editor as CoreEditor } from '@tiptap/core'
import { ref } from 'vue'

import InputDialog from '@/components/InputDialog.vue'

const props = defineProps<{
  editor: () => CoreEditor | null
}>()

const open = ref(false)
const value = ref('https://')

function openDialog() {
  value.value = (props.editor()?.getAttributes('link').href as string | undefined) ?? 'https://'
  open.value = true
}

function apply(url: string) {
  open.value = false
  const editor = props.editor()
  if (!editor) return
  if (!url.trim()) editor.chain().focus().extendMarkRange('link').unsetLink().run()
  else editor.chain().focus().extendMarkRange('link').setLink({ href: url.trim() }).run()
}

defineExpose({ open: openDialog })
</script>

<template>
  <InputDialog :open="open" title="设置链接" label="链接地址" :initial-value="value" placeholder="https://（留空可移除链接）" confirm-label="应用" :required="false" @close="open = false" @submit="apply" />
</template>
