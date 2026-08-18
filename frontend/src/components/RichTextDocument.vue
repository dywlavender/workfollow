<script setup lang="ts">
import type { Editor as TiptapEditor } from '@tiptap/core'
import { EditorContent, useEditor } from '@tiptap/vue-3'
import { computed, nextTick, onBeforeUnmount, ref, watch } from 'vue'

import InputDialog from '@/components/InputDialog.vue'
import RichTextToolbar from '@/components/RichTextToolbar.vue'
import { workFollowSlashCommands, type WorkFollowSlashCommand } from '@/modules/editor/slashCommands'
import { createWorkFollowEditorExtensions } from '@/modules/editor/tiptap'

const props = withDefaults(defineProps<{
  modelValue: Record<string, unknown> | null
  editable?: boolean
  placeholder?: string
  slashMenu?: boolean
}>(), { editable: false, placeholder: '输入内容…', slashMenu: false })

const emit = defineEmits<{
  'update:modelValue': [value: Record<string, unknown>]
  'update:plainText': [value: string]
}>()

const emptyDocument = { type: 'doc', content: [{ type: 'paragraph' }] }
const linkDialogOpen = ref(false)
const linkValue = ref('')
const slashMenuOpen = ref(false)
const slashActiveIndex = ref(0)
const slashPosition = ref({ left: 8, top: 8 })
const slashRange = ref<{ from: number; to: number } | null>(null)
let slashDetectTimer: number | undefined

const slashCommands = computed(() => workFollowSlashCommands.filter((command) => {
  // 模板正文没有笔记附件和任务弹窗上下文，因此只提供可直接写入正文的命令。
  return !command.noteOnly && command.type !== 'attachment'
}))

const editor = useEditor({
  content: props.modelValue ?? emptyDocument,
  editable: props.editable,
  extensions: createWorkFollowEditorExtensions(props.placeholder),
  editorProps: {
    handleKeyDown: (_view, event) => {
      if (!props.slashMenu || !props.editable || !slashMenuOpen.value) return false

      if (event.key === 'ArrowDown') {
        event.preventDefault()
        moveSlashSelection(1)
        return true
      }
      if (event.key === 'ArrowUp') {
        event.preventDefault()
        moveSlashSelection(-1)
        return true
      }
      if (event.key === 'Enter') {
        event.preventDefault()
        const command = slashCommands.value[slashActiveIndex.value]
        if (command) insertSlashBlock(command.type)
        return true
      }
      if (event.key === 'Escape') {
        event.preventDefault()
        closeSlashMenu()
        return true
      }

      return false
    },
  },
  onUpdate: ({ editor: current }) => {
    emit('update:modelValue', current.getJSON())
    emit('update:plainText', current.getText())
    if (props.slashMenu && props.editable) {
      if (slashDetectTimer !== undefined) window.clearTimeout(slashDetectTimer)
      slashDetectTimer = window.setTimeout(() => detectSlashCommand(current), 0)
    }
  },
})

function closeSlashMenu() {
  slashMenuOpen.value = false
  slashRange.value = null
}

function placeSlashMenuAtCaret(currentEditor: TiptapEditor) {
  try {
    const coords = currentEditor.view.coordsAtPos(currentEditor.state.selection.from)
    const menuWidth = 260
    const menuHeight = 430
    slashPosition.value = {
      left: Math.max(8, Math.min(coords.left, window.innerWidth - menuWidth - 8)),
      top: Math.max(8, Math.min(coords.bottom + 6, window.innerHeight - menuHeight - 8)),
    }
  } catch {
    closeSlashMenu()
  }
}

function detectSlashCommand(currentEditor: TiptapEditor) {
  if (!props.slashMenu || !props.editable) {
    closeSlashMenu()
    return
  }

  const { selection } = currentEditor.state
  if (!selection.empty) {
    closeSlashMenu()
    return
  }

  const parent = selection.$from.parent
  const textBeforeCursor = parent.textBetween(0, selection.$from.parentOffset, '\n', '\n')
  if (!textBeforeCursor.endsWith('/')) {
    closeSlashMenu()
    return
  }

  slashRange.value = { from: Math.max(0, selection.from - 1), to: selection.from }
  slashActiveIndex.value = 0
  placeSlashMenuAtCaret(currentEditor)
  slashMenuOpen.value = true
}

function moveSlashSelection(delta: number) {
  const commands = slashCommands.value
  if (!commands.length) return
  slashActiveIndex.value = (slashActiveIndex.value + delta + commands.length) % commands.length
  void nextTick(() => {
    document
      .getElementById(`rich-text-slash-command-${commands[slashActiveIndex.value]?.type}`)
      ?.scrollIntoView({ block: 'nearest' })
  })
}

function insertSlashBlock(type: WorkFollowSlashCommand) {
  const currentEditor = editor.value
  if (!currentEditor) return

  const chain = currentEditor.chain().focus()
  if (slashRange.value) chain.deleteRange(slashRange.value)

  if (type === 'link') {
    chain.run()
    closeSlashMenu()
    setLink()
    return
  }

  if (type === 'h1') chain.toggleHeading({ level: 1 })
  else if (type === 'h2') chain.toggleHeading({ level: 2 })
  else if (type === 'h3') chain.toggleHeading({ level: 3 })
  else if (type === 'ul') chain.toggleBulletList()
  else if (type === 'ol') chain.toggleOrderedList()
  else if (type === 'check') chain.toggleTaskList()
  else if (type === 'quote') chain.toggleBlockquote()
  else if (type === 'code') chain.toggleCodeBlock()
  else if (type === 'hr') chain.setHorizontalRule()
  else if (type === 'table') chain.insertTable({ rows: 3, cols: 3, withHeaderRow: true })
  else if (type === 'subtask') chain.toggleTaskList().insertContent('子任务')
  else if (type === 'tag') chain.insertContent('#标签')
  else if (type === 'relation') chain.insertContent('关联任务 / 笔记')

  chain.run()
  closeSlashMenu()
}

function setLink() {
  linkValue.value = (editor.value?.getAttributes('link').href as string | undefined) ?? 'https://'
  linkDialogOpen.value = true
}

function applyLink(url: string) {
  linkDialogOpen.value = false
  if (!editor.value) return
  if (!url.trim()) editor.value.chain().focus().extendMarkRange('link').unsetLink().run()
  else editor.value.chain().focus().extendMarkRange('link').setLink({ href: url.trim() }).run()
}

watch(() => props.editable, (value) => {
  editor.value?.setEditable(value)
  if (!value) closeSlashMenu()
})
watch(() => props.slashMenu, (value) => {
  if (!value) closeSlashMenu()
})
watch(() => props.modelValue, (value) => {
  if (!editor.value) return
  const next = value ?? emptyDocument
  if (JSON.stringify(editor.value.getJSON()) !== JSON.stringify(next)) editor.value.commands.setContent(next, false)
}, { deep: true })

onBeforeUnmount(() => {
  if (slashDetectTimer !== undefined) window.clearTimeout(slashDetectTimer)
  editor.value?.destroy()
})
</script>

<template>
  <div class="rich-text-document" :class="{ readonly: !editable }">
    <RichTextToolbar v-if="editable && editor" :editor="editor" @link="setLink" />
    <EditorContent :editor="editor" />
    <InputDialog :open="linkDialogOpen" title="设置链接" label="链接地址" :initial-value="linkValue" placeholder="https://（留空可移除链接）" confirm-label="应用" :required="false" @close="linkDialogOpen = false" @submit="applyLink" />
  </div>

  <Teleport to="body">
    <section
      v-if="slashMenuOpen"
      class="task-slash-menu rich-text-slash-menu"
      :style="{ left: `${slashPosition.left}px`, top: `${slashPosition.top}px` }"
      role="menu"
      aria-label="插入格式"
      @mousedown.prevent.stop
      @click.stop
    >
      <button
        v-for="(command, index) in slashCommands"
        :id="`rich-text-slash-command-${command.type}`"
        :key="command.type"
        type="button"
        role="menuitem"
        :class="{ active: slashActiveIndex === index }"
        @mousemove="slashActiveIndex = index"
        @click="insertSlashBlock(command.type)"
      >
        <span>{{ command.mark }}</span>
        <strong>{{ command.label }}</strong>
      </button>
    </section>
  </Teleport>
</template>
