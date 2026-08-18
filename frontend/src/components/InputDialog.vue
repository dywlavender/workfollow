<script setup lang="ts">
import { NButton, NCard, NFormItem, NInput, NModal } from 'naive-ui'
import { nextTick, ref, watch } from 'vue'

const props = withDefaults(defineProps<{
  open: boolean
  title: string
  label: string
  initialValue?: string
  placeholder?: string
  confirmLabel?: string
  required?: boolean
}>(), { initialValue: '', placeholder: '', confirmLabel: '保存', required: true })

const emit = defineEmits<{ close: []; submit: [value: string] }>()
const value = ref('')
const input = ref<InstanceType<typeof NInput> | null>(null)

watch(
  () => [props.open, props.initialValue] as const,
  () => {
    if (props.open) {
      value.value = props.initialValue
      void nextTick(() => input.value?.focus())
    }
  },
  { immediate: true },
)

function submit() {
  const trimmed = value.value.trim()
  if (props.required && !trimmed) return
  emit('submit', trimmed)
}
</script>

<template>
  <NModal :show="open" :mask-closable="true" @mask-click="emit('close')" @esc="emit('close')">
    <NCard class="naive-dialog-card" :title="title" role="dialog" aria-modal="true" closable @close="emit('close')">
      <form @submit.prevent="submit">
        <NFormItem :label="label" :show-feedback="false">
          <NInput ref="input" v-model:value="value" :placeholder="placeholder" @keydown.enter.prevent="submit" />
        </NFormItem>
      </form>
      <template #footer>
        <div class="naive-dialog-actions">
          <NButton @click="emit('close')">取消</NButton>
          <NButton type="primary" :disabled="required && !value.trim()" @click="submit">{{ confirmLabel }}</NButton>
        </div>
      </template>
    </NCard>
  </NModal>
</template>
