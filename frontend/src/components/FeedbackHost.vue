<script setup lang="ts">
import { IconAlertCircle, IconCheck, IconX } from '@tabler/icons-vue'

import { useFeedbackStore } from '@/stores/feedback'

// 全局唯一反馈出口:右上角操作反馈(success/error)+ 底部居中完成提示。
// 由 App.vue 挂载一次,业务代码只调用 feedback store,不再自建横幅。
const feedback = useFeedbackStore()
</script>

<template>
  <Teleport to="body">
    <TransitionGroup name="feedback" tag="div" class="feedback-host">
      <div
        v-for="message in feedback.messages"
        :key="message.id"
        class="action-feedback"
        :class="message.tone"
        :role="message.tone === 'error' ? 'alert' : 'status'"
        :aria-live="message.tone === 'error' ? 'assertive' : 'polite'"
      >
        <IconAlertCircle v-if="message.tone === 'error'" :size="17" aria-hidden="true" />
        <IconCheck v-else :size="17" aria-hidden="true" />
        <span>{{ message.text }}</span>
        <button type="button" :aria-label="message.tone === 'error' ? '关闭错误提示' : '关闭操作提示'" @click="feedback.dismiss(message.id)">
          <IconX :size="15" aria-hidden="true" />
        </button>
      </div>
    </TransitionGroup>
    <Transition name="completion-toast">
      <div v-if="feedback.completionVisible" class="completion-toast" role="status" aria-live="polite">
        <span class="completion-toast-icon" aria-hidden="true"><IconCheck :size="14" :stroke-width="2.7" /></span>
        <span>{{ feedback.completionText }}</span>
      </div>
    </Transition>
  </Teleport>
</template>
