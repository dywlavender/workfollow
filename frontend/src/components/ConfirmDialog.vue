<script setup lang="ts">
import { NButton, NCard, NModal } from 'naive-ui'
import { nextTick, ref, watch } from 'vue'

const props = withDefaults(defineProps<{
  open: boolean
  title: string
  message: string
  confirmLabel?: string
  danger?: boolean
}>(), { confirmLabel: '确定', danger: false })

const emit = defineEmits<{ close: []; confirm: [] }>()
// NButton 的 ref 是组件实例,原生按钮在 $el 上。
const confirmButton = ref<{ $el: HTMLButtonElement } | null>(null)

// 打开时把焦点落到确认按钮,支持回车直接确认。
watch(() => props.open, async (open) => {
  if (!open) return
  await nextTick()
  confirmButton.value?.$el?.focus()
})
</script>

<template>
  <NModal :show="open" :mask-closable="true" @mask-click="emit('close')" @esc="emit('close')">
    <NCard class="naive-dialog-card" :title="title" role="dialog" aria-modal="true" closable @close="emit('close')">
      <p class="dialog-description">{{ message }}</p>
      <template #footer>
        <div class="naive-dialog-actions">
          <NButton @click="emit('close')">取消</NButton>
          <NButton ref="confirmButton" :type="danger ? 'error' : 'primary'" @click="emit('confirm')">{{ confirmLabel }}</NButton>
        </div>
      </template>
    </NCard>
  </NModal>
</template>
