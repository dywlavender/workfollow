<script setup lang="ts">
import { computed } from 'vue'
import { IconAlertCircle, IconCheck, IconX } from '@tabler/icons-vue'

const props = withDefaults(defineProps<{
  message?: string | null
  tone?: 'error' | 'success'
}>(), {
  message: null,
  tone: 'error',
})

const emit = defineEmits<{ dismiss: [] }>()
const role = computed(() => props.tone === 'error' ? 'alert' : 'status')
</script>

<template>
  <Teleport to="body">
    <div v-if="message" class="action-feedback" :class="tone" :role="role" :aria-live="tone === 'error' ? 'assertive' : 'polite'">
      <IconAlertCircle v-if="tone === 'error'" :size="17" aria-hidden="true" />
      <IconCheck v-else :size="17" aria-hidden="true" />
      <span>{{ message }}</span>
      <button type="button" :aria-label="tone === 'error' ? '关闭错误提示' : '关闭操作提示'" @click="emit('dismiss')">
        <IconX :size="15" aria-hidden="true" />
      </button>
    </div>
  </Teleport>
</template>
