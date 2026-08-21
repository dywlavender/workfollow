<script setup lang="ts">
import type { Editor } from '@tiptap/core'
import { computed } from 'vue'

import { normalizeFontSize, workFollowFontSizes } from '@/modules/editor/fontSizing'

const props = defineProps<{
  editor: Editor
  compact?: boolean
}>()

const currentFontSize = computed(() => normalizeFontSize(props.editor.getAttributes('textStyle').fontSize) ?? '')

function setFontSize(event: Event) {
  const value = normalizeFontSize((event.target as HTMLSelectElement).value)
  props.editor.chain().focus().setMark('textStyle', { fontSize: value }).run()
}
</script>

<template>
  <label class="editor-font-size" :class="{ compact }" title="字体大小">
    <span class="sr-only">字体大小</span>
    <select :value="currentFontSize" aria-label="字体大小" @change="setFontSize">
      <option v-for="option in workFollowFontSizes" :key="option.label" :value="option.value ?? ''">
        {{ option.label }}<template v-if="option.value"> · {{ option.value.replace('px', '') }}</template>
      </option>
    </select>
  </label>
</template>

<style scoped>
.editor-font-size select {
  width: 92px;
  height: 28px;
  padding: 0 22px 0 7px;
  border: 0;
  border-radius: var(--radius-xs);
  background-color: transparent;
  color: var(--color-text-secondary);
  font-family: var(--type-family-ui);
  font-size: var(--font-size-caption);
  cursor: pointer;
}

.editor-font-size select:hover,
.editor-font-size select:focus-visible {
  background-color: var(--color-accent-soft);
  color: var(--color-accent);
  outline: none;
}

.editor-font-size.compact select {
  width: 72px;
  height: 30px;
  padding-left: 6px;
}
</style>
