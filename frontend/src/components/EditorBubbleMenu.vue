<script setup lang="ts">
import { BubbleMenu } from '@tiptap/vue-3'
import type { Editor } from '@tiptap/core'
import {
  IconCode,
  IconLink,
  IconList,
  IconListNumbers,
  IconPaperclip,
  IconQuote,
} from '@tabler/icons-vue'

import EditorFontSizeSelect from '@/components/editor/EditorFontSizeSelect.vue'

withDefaults(
  defineProps<{
    editor: Editor
    attachment?: boolean
  }>(),
  { attachment: false },
)

defineEmits<{
  link: []
  attachment: []
}>()
</script>

<template>
  <BubbleMenu
    :editor="editor"
    :tippy-options="{ duration: 120, placement: 'top', maxWidth: 'none', theme: 'transparent' }"
  >
    <div class="editor-bubble-menu" role="toolbar" aria-label="格式工具">
      <EditorFontSizeSelect :editor="editor" compact />
      <span class="editor-bubble-divider" aria-hidden="true" />
      <button type="button" :class="{ active: editor.isActive('bold') }" title="粗体" aria-label="粗体" @mousedown.prevent @click="editor.chain().focus().toggleBold().run()"><strong>B</strong></button>
      <button type="button" :class="{ active: editor.isActive('italic') }" title="斜体" aria-label="斜体" @mousedown.prevent @click="editor.chain().focus().toggleItalic().run()"><em>I</em></button>
      <button type="button" :class="{ active: editor.isActive('underline') }" title="下划线" aria-label="下划线" @mousedown.prevent @click="editor.chain().focus().toggleUnderline().run()"><u>U</u></button>
      <span class="editor-bubble-divider" aria-hidden="true" />
      <button type="button" title="无序列表" aria-label="无序列表" :class="{ active: editor.isActive('bulletList') }" @mousedown.prevent @click="editor.chain().focus().toggleBulletList().run()"><IconList :size="16" /></button>
      <button type="button" title="有序列表" aria-label="有序列表" :class="{ active: editor.isActive('orderedList') }" @mousedown.prevent @click="editor.chain().focus().toggleOrderedList().run()"><IconListNumbers :size="16" /></button>
      <button type="button" title="引用" aria-label="引用" :class="{ active: editor.isActive('blockquote') }" @mousedown.prevent @click="editor.chain().focus().toggleBlockquote().run()"><IconQuote :size="16" /></button>
      <button type="button" title="代码块" aria-label="代码块" :class="{ active: editor.isActive('codeBlock') }" @mousedown.prevent @click="editor.chain().focus().toggleCodeBlock().run()"><IconCode :size="16" /></button>
      <span class="editor-bubble-divider" aria-hidden="true" />
      <button type="button" title="链接" aria-label="链接" @mousedown.prevent @click="$emit('link')"><IconLink :size="16" /></button>
      <button v-if="attachment" type="button" title="图片或附件" aria-label="图片或附件" @mousedown.prevent @click="$emit('attachment')"><IconPaperclip :size="16" /></button>
    </div>
  </BubbleMenu>
</template>

<style scoped>
.editor-bubble-menu {
  display: flex;
  align-items: center;
  gap: 2px;
  padding: 5px;
  border: 1px solid var(--color-border-subtle);
  border-radius: 11px;
  background: var(--color-bg-surface);
  box-shadow: var(--dialog-shadow);
}

.editor-bubble-menu button {
  min-width: 30px;
  height: 30px;
  display: inline-grid;
  place-items: center;
  padding: 0 6px;
  border: 0;
  border-radius: 7px;
  background: transparent;
  color: var(--color-text-secondary);
  font-size: var(--font-size-caption);
  font-family: var(--type-family-ui);
}

.editor-bubble-menu button:hover,
.editor-bubble-menu button:focus-visible,
.editor-bubble-menu button.active {
  background: var(--color-accent-soft);
  color: var(--color-accent);
  outline: none;
}

.editor-bubble-divider {
  width: 1px;
  height: 18px;
  margin: 0 3px;
  background: var(--color-border-subtle);
}
</style>

<style>
/* The floating panel owns its own surface; strip tippy's default chrome so
   only the toolbar's rounded card shows. */
.tippy-box[data-theme~='transparent'] {
  background: transparent;
  border: 0;
  border-radius: 0;
  box-shadow: none;
  padding: 0;
}
</style>
