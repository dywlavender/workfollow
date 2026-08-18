<script setup lang="ts">
import { NButton, NCard, NModal } from 'naive-ui'

withDefaults(defineProps<{
  open: boolean
  title: string
  message: string
  confirmLabel?: string
  danger?: boolean
}>(), { confirmLabel: '确定', danger: false })

const emit = defineEmits<{ close: []; confirm: [] }>()
</script>

<template>
  <NModal :show="open" :mask-closable="true" @mask-click="emit('close')" @esc="emit('close')">
    <NCard class="naive-dialog-card" :title="title" role="dialog" aria-modal="true" closable @close="emit('close')">
      <p class="dialog-description">{{ message }}</p>
      <template #footer>
        <div class="naive-dialog-actions">
          <NButton @click="emit('close')">取消</NButton>
          <NButton :type="danger ? 'error' : 'primary'" @click="emit('confirm')">{{ confirmLabel }}</NButton>
        </div>
      </template>
    </NCard>
  </NModal>
</template>
