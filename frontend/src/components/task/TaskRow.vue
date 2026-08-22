<script setup lang="ts">
import { IconCheck } from '@tabler/icons-vue'

withDefaults(defineProps<{
  title: string
  description?: string | null
  completed?: boolean
  disabled?: boolean
  selected?: boolean
  terminal?: boolean
  cancelled?: boolean
}>(), {
  completed: false,
  disabled: false,
  selected: false,
  terminal: false,
  cancelled: false,
})

const emit = defineEmits<{
  select: []
  toggle: []
  context: [event: MouseEvent]
}>()
</script>

<template>
  <article
    class="task-row"
    :class="{ selected, terminal, cancelled }"
    tabindex="0"
    :aria-selected="selected ? 'true' : 'false'"
    @click="emit('select')"
    @keydown.enter="emit('select')"
    @contextmenu.prevent.stop="emit('context', $event)"
  >
    <button
      class="task-row-check"
      type="button"
      :disabled="disabled"
      :aria-label="completed ? `恢复 ${title}` : `完成 ${title}`"
      @click.stop="emit('toggle')"
    >
      <IconCheck v-if="completed" :size="13" :stroke-width="2.4" />
    </button>
    <div class="task-row-content">
      <strong>{{ title }}</strong>
      <p v-if="description" class="task-row-description">{{ description }}</p>
      <span v-if="$slots.meta" class="task-row-meta"><slot name="meta" /></span>
    </div>
    <div v-if="$slots.trailing" class="task-row-trailing"><slot name="trailing" /></div>
    <div v-if="$slots.actions" class="task-row-actions" @click.stop><slot name="actions" /></div>
  </article>
</template>
