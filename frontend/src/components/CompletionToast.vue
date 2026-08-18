<script setup lang="ts">
import { IconCheck } from '@tabler/icons-vue'

import { useAppStore } from '@/stores/app'

const app = useAppStore()
</script>

<template>
  <div v-if="app.completionToastVisible" class="completion-toast" role="status" aria-live="polite">
    <span class="completion-toast-icon" aria-hidden="true"><IconCheck :size="14" :stroke-width="2.7" /></span>
    <span>任务已完成</span>
  </div>
</template>
