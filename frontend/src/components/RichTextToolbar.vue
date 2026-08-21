<script setup lang="ts">
import type { Editor } from '@tiptap/core'
import {
  IconCode,
  IconHighlight,
  IconLink,
  IconList,
  IconListCheck,
  IconListNumbers,
  IconMinus,
  IconPaperclip,
  IconPlus,
  IconQuote,
  IconTable,
  IconTableColumn,
  IconTableRow,
  IconTrash,
} from '@tabler/icons-vue'
import { computed, nextTick, onBeforeUnmount, onMounted, ref } from 'vue'

import EditorFontSizeSelect from '@/components/editor/EditorFontSizeSelect.vue'
import { workFollowHighlightColors, workFollowTextColors } from '@/modules/editor/tiptap'
import { tableColumnLimit } from '@/modules/editor/tableSizing'

const props = withDefaults(defineProps<{
  editor: Editor
  attachment?: boolean
}>(), { attachment: false })

const emit = defineEmits<{
  link: []
  attachment: []
}>()

const colorMenuOpen = ref<'text' | 'highlight' | null>(null)
const tableMenuOpen = ref(false)
const tableActive = ref(false)
const tableRows = Array.from({ length: 8 }, (_, index) => index + 1)
const editorContentWidth = ref(0)
const hoveredTableSize = ref({ rows: 3, cols: 3 })
const maxTableColumns = computed(() => tableColumnLimit(editorContentWidth.value))
const tableColumns = computed(() => Array.from({ length: maxTableColumns.value }, (_, index) => index + 1))
const tableCells = computed(() => tableRows.flatMap((row) => tableColumns.value.map((col) => ({ row, col }))))
const selectedTableSize = computed(() => ({
  rows: hoveredTableSize.value.rows,
  cols: Math.min(hoveredTableSize.value.cols, maxTableColumns.value),
}))
let editorResizeObserver: ResizeObserver | undefined

function setTextColor(editor: Editor, color: string | null) {
  editor.chain().focus().setMark('textStyle', { color }).run()
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
  tableMenuOpen.value = false
}

function measureEditorWidth() {
  const editorElement = props.editor.view.dom
  const styles = window.getComputedStyle(editorElement)
  editorContentWidth.value = Math.max(
    0,
    editorElement.clientWidth - Number.parseFloat(styles.paddingLeft || '0') - Number.parseFloat(styles.paddingRight || '0'),
  )
}

function refreshTableState() {
  tableActive.value = props.editor.isActive('table')
}

function toggleTableMenu() {
  colorMenuOpen.value = null
  tableMenuOpen.value = !tableMenuOpen.value
  if (!tableMenuOpen.value) return
  measureEditorWidth()
  hoveredTableSize.value = { rows: 3, cols: Math.min(3, maxTableColumns.value) }
}

function insertTable(rows: number, cols: number) {
  props.editor.chain().focus().insertTable({ rows, cols, withHeaderRow: true }).run()
  tableMenuOpen.value = false
}

function runTableCommand(command: 'addRowAfter' | 'deleteRow' | 'addColumnAfter' | 'deleteColumn' | 'deleteTable') {
  props.editor.chain().focus()[command]().run()
}

onMounted(() => {
  document.addEventListener('click', closeColorMenu)
  props.editor.on('transaction', refreshTableState)
  refreshTableState()
  void nextTick(() => {
    measureEditorWidth()
    editorResizeObserver = new ResizeObserver(measureEditorWidth)
    editorResizeObserver.observe(props.editor.view.dom)
  })
})
onBeforeUnmount(() => {
  document.removeEventListener('click', closeColorMenu)
  props.editor.off('transaction', refreshTableState)
  editorResizeObserver?.disconnect()
})
</script>

<template>
  <div class="editor-toolbar" role="toolbar" aria-label="编辑工具栏">
    <button type="button" :class="{ active: editor.isActive('heading', { level: 2 }) }" title="标题" aria-label="二级标题" @mousedown.prevent @click="editor.chain().focus().toggleHeading({ level: 2 }).run()">H2</button>
    <EditorFontSizeSelect :editor="editor" />
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
    <div class="table-insert-host" @click.stop>
      <button type="button" :class="{ active: tableMenuOpen }" title="插入表格" aria-label="插入表格" aria-haspopup="dialog" :aria-expanded="tableMenuOpen" @mousedown.prevent @click="toggleTableMenu"><IconTable :size="16" /></button>
      <section v-if="tableMenuOpen" class="table-size-picker" role="dialog" aria-label="选择表格大小">
        <strong>{{ selectedTableSize.rows }} 行 × {{ selectedTableSize.cols }} 列</strong>
        <div class="table-size-grid" :style="{ '--table-picker-columns': maxTableColumns }" role="grid">
          <button
            v-for="cell in tableCells"
            :key="`${cell.row}-${cell.col}`"
            type="button"
            role="gridcell"
            :class="{ selected: cell.row <= selectedTableSize.rows && cell.col <= selectedTableSize.cols }"
            :aria-label="`插入 ${cell.row} 行 ${cell.col} 列表格`"
            @mouseenter="hoveredTableSize = { rows: cell.row, cols: cell.col }"
            @focus="hoveredTableSize = { rows: cell.row, cols: cell.col }"
            @mousedown.prevent
            @click="insertTable(cell.row, cell.col)"
          />
        </div>
        <small>最多可选 {{ maxTableColumns }} 列，已按编辑区宽度调整</small>
      </section>
    </div>
    <div v-if="tableActive" class="table-edit-controls" role="group" aria-label="调整表格行列">
      <button type="button" title="在下方添加一行" aria-label="在下方添加一行" @mousedown.prevent @click="runTableCommand('addRowAfter')"><IconTableRow :size="15" /><IconPlus class="table-control-sign" :size="9" /></button>
      <button type="button" title="删除当前行" aria-label="删除当前行" @mousedown.prevent @click="runTableCommand('deleteRow')"><IconTableRow :size="15" /><IconMinus class="table-control-sign" :size="9" /></button>
      <button type="button" title="在右侧添加一列" aria-label="在右侧添加一列" @mousedown.prevent @click="runTableCommand('addColumnAfter')"><IconTableColumn :size="15" /><IconPlus class="table-control-sign" :size="9" /></button>
      <button type="button" title="删除当前列" aria-label="删除当前列" @mousedown.prevent @click="runTableCommand('deleteColumn')"><IconTableColumn :size="15" /><IconMinus class="table-control-sign" :size="9" /></button>
      <button class="table-delete-button" type="button" title="删除整个表格" aria-label="删除整个表格" @mousedown.prevent @click="runTableCommand('deleteTable')"><IconTrash :size="15" /></button>
    </div>
    <button v-if="attachment" type="button" title="图片或附件" aria-label="图片或附件" @mousedown.prevent @click="emit('attachment')"><IconPaperclip :size="16" /></button>
  </div>
</template>
