<script setup lang="ts">
import type { Editor } from '@tiptap/core'
import {
  IconCode,
  IconHighlight,
  IconLink,
  IconList,
  IconListCheck,
  IconListNumbers,
  IconPaperclip,
  IconQuote,
  IconTable,
} from '@tabler/icons-vue'
import { onBeforeUnmount, onMounted, ref } from 'vue'

import { workFollowHighlightColors, workFollowTextColors } from '@/modules/editor/tiptap'

withDefaults(defineProps<{
  editor: Editor
  attachment?: boolean
}>(), { attachment: false })

const emit = defineEmits<{
  link: []
  attachment: []
}>()

const colorMenuOpen = ref<'text' | 'highlight' | null>(null)

function setTextColor(editor: Editor, color: string | null) {
  const chain = editor.chain().focus()
  if (color) chain.setMark('textStyle', { color }).run()
  else chain.unsetMark('textStyle').run()
  colorMenuOpen.value = null
}

function setHighlightColor(editor: Editor, color: string | null) {
  const chain = editor.chain().focus()
  if (color) chain.setHighlight({ color }).run()
  else chain.unsetHighlight().run()
  colorMenuOpen.value = null
}

function closeColorMenu() {
  colorMenuOpen.value = null
}

onMounted(() => document.addEventListener('click', closeColorMenu))
onBeforeUnmount(() => document.removeEventListener('click', closeColorMenu))
</script>

<template>
  <div class="editor-toolbar" role="toolbar" aria-label="编辑工具栏">
    <button type="button" :class="{ active: editor.isActive('heading', { level: 2 }) }" title="标题" aria-label="二级标题" @mousedown.prevent @click="editor.chain().focus().toggleHeading({ level: 2 }).run()">H2</button>
    <button type="button" :class="{ active: editor.isActive('bold') }" title="粗体" aria-label="粗体" @mousedown.prevent @click="editor.chain().focus().toggleBold().run()"><strong>B</strong></button>
    <button type="button" :class="{ active: editor.isActive('italic') }" title="斜体" aria-label="斜体" @mousedown.prevent @click="editor.chain().focus().toggleItalic().run()"><em>I</em></button>
    <button type="button" :class="{ active: editor.isActive('underline') }" title="下划线" aria-label="下划线" @mousedown.prevent @click="editor.chain().focus().toggleUnderline().run()"><u>U</u></button>
    <button type="button" title="无序列表" aria-label="无序列表" :class="{ active: editor.isActive('bulletList') }" @mousedown.prevent @click="editor.chain().focus().toggleBulletList().run()"><IconList :size="16" /></button>
    <button type="button" title="有序列表" aria-label="有序列表" :class="{ active: editor.isActive('orderedList') }" @mousedown.prevent @click="editor.chain().focus().toggleOrderedList().run()"><IconListNumbers :size="16" /></button>
    <button type="button" title="任务列表" aria-label="任务列表" :class="{ active: editor.isActive('taskList') }" @mousedown.prevent @click="editor.chain().focus().toggleTaskList().run()"><IconListCheck :size="16" /></button>
    <div class="note-color-host" @click.stop>
      <button type="button" class="note-color-trigger" title="文字颜色" aria-label="文字颜色" @mousedown.prevent @click="colorMenuOpen = colorMenuOpen === 'text' ? null : 'text'"><strong>A</strong></button>
      <section v-if="colorMenuOpen === 'text'" class="note-color-palette" aria-label="选择文字颜色">
        <button v-for="color in workFollowTextColors" :key="color.label" type="button" class="note-color-swatch" :class="{ default: !color.value }" :style="{ '--swatch-color': color.swatch }" :title="color.label" :aria-label="color.label" @mousedown.prevent @click="setTextColor(editor, color.value)"><span /></button>
      </section>
    </div>
    <div class="note-color-host" @click.stop>
      <button type="button" class="note-color-trigger" title="背景颜色" aria-label="背景颜色" @mousedown.prevent @click="colorMenuOpen = colorMenuOpen === 'highlight' ? null : 'highlight'"><IconHighlight :size="16" /></button>
      <section v-if="colorMenuOpen === 'highlight'" class="note-color-palette" aria-label="选择背景颜色">
        <button v-for="color in workFollowHighlightColors" :key="color.label" type="button" class="note-color-swatch" :class="{ default: !color.value }" :style="{ '--swatch-color': color.swatch }" :title="color.label" :aria-label="color.label" @mousedown.prevent @click="setHighlightColor(editor, color.value)"><span /></button>
      </section>
    </div>
    <button type="button" title="引用" aria-label="引用" :class="{ active: editor.isActive('blockquote') }" @mousedown.prevent @click="editor.chain().focus().toggleBlockquote().run()"><IconQuote :size="16" /></button>
    <button type="button" title="代码块" aria-label="代码块" :class="{ active: editor.isActive('codeBlock') }" @mousedown.prevent @click="editor.chain().focus().toggleCodeBlock().run()"><IconCode :size="16" /></button>
    <button type="button" title="链接" aria-label="链接" @mousedown.prevent @click="emit('link')"><IconLink :size="16" /></button>
    <button type="button" title="表格" aria-label="表格" @mousedown.prevent @click="editor.chain().focus().insertTable({ rows: 3, cols: 3, withHeaderRow: true }).run()"><IconTable :size="16" /></button>
    <button v-if="attachment" type="button" title="图片或附件" aria-label="图片或附件" @mousedown.prevent @click="emit('attachment')"><IconPaperclip :size="16" /></button>
  </div>
</template>
