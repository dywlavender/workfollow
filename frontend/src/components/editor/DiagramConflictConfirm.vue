<script setup lang="ts">
import { ref } from 'vue'

import ConfirmDialog from '@/components/ConfirmDialog.vue'

/** 流程图保存冲突/他人编辑中的确认；ask() 返回用户选择。 */
const open = ref(false)
const message = ref('')
const title = ref('流程图冲突')
const confirmLabel = ref('覆盖我的版本')
const danger = ref(true)
let resolver: ((value: boolean) => void) | null = null

function ask(text: string, options?: { title?: string; confirmLabel?: string; danger?: boolean }): Promise<boolean> {
  message.value = text
  title.value = options?.title ?? '流程图冲突'
  confirmLabel.value = options?.confirmLabel ?? '覆盖我的版本'
  danger.value = options?.danger ?? true
  open.value = true
  return new Promise((resolve) => { resolver = resolve })
}

function settle(value: boolean) {
  open.value = false
  resolver?.(value)
  resolver = null
}

defineExpose({ ask })
</script>

<template>
  <ConfirmDialog
    :open="open"
    :title="title"
    :message="message"
    :confirm-label="confirmLabel"
    :danger="danger"
    @confirm="settle(true)"
    @close="settle(false)"
  />
</template>
