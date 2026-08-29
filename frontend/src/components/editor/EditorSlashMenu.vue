<script setup lang="ts">
import type { WorkFollowSlashCommand, WorkFollowSlashCommandItem } from '@/modules/editor/slashCommands'

defineProps<{
  open: boolean
  commands: WorkFollowSlashCommandItem[]
  activeIndex: number
  position: { left: number; top: number }
  idPrefix: string
  ariaLabel?: string
}>()

const emit = defineEmits<{
  select: [type: WorkFollowSlashCommand]
  hover: [index: number]
}>()
</script>

<template>
  <Teleport to="body">
    <section
      v-if="open && commands.length"
      class="task-slash-menu"
      :style="{ left: `${position.left}px`, top: `${position.top}px` }"
      role="menu"
      :aria-label="ariaLabel ?? '插入格式'"
      @mousedown.prevent.stop
      @click.stop
    >
      <button
        v-for="(command, index) in commands"
        :id="`${idPrefix}-${command.type}`"
        :key="command.type"
        type="button"
        role="menuitem"
        :class="{ active: activeIndex === index }"
        :aria-current="activeIndex === index ? 'true' : undefined"
        @mousemove="emit('hover', index)"
        @click="emit('select', command.type)"
      ><span>{{ command.mark }}</span><strong>{{ command.label }}</strong></button>
    </section>
  </Teleport>
</template>
