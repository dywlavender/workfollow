<script setup lang="ts">
import Collaboration from '@tiptap/extension-collaboration'
import { Editor as TiptapEditor, EditorContent } from '@tiptap/vue-3'
import type { Editor as CoreEditor } from '@tiptap/core'
import * as Y from 'yjs'
import { computed, onBeforeUnmount, ref, shallowRef, watch } from 'vue'

import EditorLinkDialog from '@/components/editor/EditorLinkDialog.vue'
import EditorSlashMenu from '@/components/editor/EditorSlashMenu.vue'
import RichTextToolbar from '@/components/RichTextToolbar.vue'
import { workFollowSlashCommands, type WorkFollowSlashCommand } from '@/modules/editor/slashCommands'
import { useSlashMenu } from '@/modules/editor/slashMenu'
import { CollaborationInitializationError, initializeCollaborativeField } from '@/modules/editor/collaborationInitialization'
import { createWorkFollowEditorExtensions } from '@/modules/editor/tiptap'

const props = withDefaults(defineProps<{
  /** 传入 Y.Doc 即协作模式（正文以协同文档为准）；不传则为纯 JSON v-model 模式。 */
  document?: Y.Doc | null
  modelValue?: Record<string, unknown> | null
  /** 协作模式的种子内容（协同文档为空且服务端要求初始化时写入）。 */
  initialContent?: Record<string, unknown> | null
  editable?: boolean
  placeholder?: string
  slashMenu?: boolean
  seedReady?: boolean
  seedDocument?: boolean
  collaborationDocumentName?: string | null
  /** 粘贴/拖入图片时的上传钩子；未提供则不拦截图片粘贴。 */
  uploadImage?: ((file: File) => Promise<{ url: string; originalName: string; id: string }>) | null
}>(), {
  document: null,
  modelValue: null,
  initialContent: null,
  editable: false,
  placeholder: '输入内容…',
  slashMenu: false,
  seedReady: false,
  seedDocument: true,
  collaborationDocumentName: null,
  uploadImage: null,
})

const emit = defineEmits<{
  'update:modelValue': [value: Record<string, unknown>]
  'update:plainText': [value: string]
  ready: []
  initializationError: [message: string]
}>()

const emptyDocument = { type: 'doc', content: [{ type: 'paragraph' }] }
const collaborative = computed(() => props.document != null)
// 防抖节奏保持与合并前一致：协同文档变更走 Yjs 投影，稍快；纯 JSON 模式沿用 250ms。
const snapshotDelay = computed(() => (collaborative.value ? 150 : 250))

const editor = shallowRef<TiptapEditor | null>(null)
const bodyReady = ref(!props.collaborationDocumentName || !props.seedDocument)
let snapshotTimer: number | undefined
let slashDetectTimer: number | undefined
let applyingExternalDocument = false
let lastEmittedDocument: Record<string, unknown> | null = props.modelValue
let initializationPromise: Promise<boolean> = Promise.resolve(bodyReady.value)
let initializationGeneration = 0

const slashCommands = computed(() => workFollowSlashCommands.filter((command) => {
  // 模板正文没有笔记附件和任务弹窗上下文，因此只提供可直接写入正文的命令。
  return !command.noteOnly && command.type !== 'attachment'
}))

const slash = useSlashMenu({
  commands: () => slashCommands.value,
  idPrefix: 'rich-text-slash-command',
  enabled: () => Boolean(props.slashMenu && props.editable),
})

const linkDialog = ref<InstanceType<typeof EditorLinkDialog> | null>(null)
function setLink() {
  linkDialog.value?.open()
}

function emitSnapshot(currentEditor: CoreEditor | null = editor.value) {
  if (!currentEditor) return
  const snapshot = currentEditor.getJSON() as Record<string, unknown>
  lastEmittedDocument = snapshot
  emit('update:modelValue', snapshot)
  emit('update:plainText', currentEditor.getText())
}

function scheduleSnapshot(currentEditor: CoreEditor) {
  if (snapshotTimer !== undefined) window.clearTimeout(snapshotTimer)
  snapshotTimer = window.setTimeout(() => {
    if (editor.value === currentEditor) emitSnapshot(currentEditor)
    snapshotTimer = undefined
  }, snapshotDelay.value)
}

function insertSlashBlock(type: WorkFollowSlashCommand) {
  const currentEditor = editor.value
  if (!currentEditor) return

  const chain = currentEditor.chain().focus()
  slash.deleteRange(chain, currentEditor.state.selection.from)

  if (type === 'link') {
    chain.run()
    slash.close()
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
  slash.close()
}

function fieldInitialized(document: Y.Doc) {
  return document.getMap('config').get('bodyInitialized') === true
    || document.getMap('config').get('initialContentLoaded') === true
    || document.getXmlFragment('default').length > 0
}

function seedInitialContent(instance: TiptapEditor, document: Y.Doc, initial?: Record<string, unknown>) {
  if (!props.seedReady || !props.seedDocument || fieldInitialized(document)) return
  const fragment = document.getXmlFragment('default')
  const config = document.getMap('config')
  if (fragment.length > 0) {
    // An existing collaborative fragment is authoritative. Do not write a
    // marker merely by opening the document: that would create a needless
    // snapshot/notification before anyone edits the content.
    return
  }
  const initialContent = initial?.contentJson && typeof initial.contentJson === 'object'
    ? initial.contentJson as Record<string, unknown>
    : props.initialContent
  if (!initialContent) return
  applyingExternalDocument = true
  try {
    instance.commands.setContent(initialContent, false)
    config.set('bodyInitialized', true)
  } finally { applyingExternalDocument = false }
}

async function initializeDocument(instance: TiptapEditor, document: Y.Doc, generation: number): Promise<boolean> {
  bodyReady.value = false
  if (!props.seedReady || !props.seedDocument || fieldInitialized(document)) {
    bodyReady.value = true
  } else if (props.collaborationDocumentName) {
    try {
      await initializeCollaborativeField(
        props.collaborationDocumentName,
        'body',
        (initial) => {
          if (generation === initializationGeneration) seedInitialContent(instance, document, initial)
        },
      )
      // The server response is authoritative. A readonly/waiting response
      // must never trigger a second local seed on top of the Y.Doc.
      bodyReady.value = true
    } catch (error) {
      bodyReady.value = false
      instance.setEditable(false)
      if (generation === initializationGeneration) {
        const message = error instanceof CollaborationInitializationError
          ? error.message
          : error instanceof Error ? error.message : '协同正文初始化失败'
        emit('initializationError', message)
      }
      return false
    }
  } else {
    seedInitialContent(instance, document)
    bodyReady.value = fieldInitialized(document)
  }

  if (generation !== initializationGeneration) return false
  instance.setEditable(Boolean(props.editable && bodyReady.value))
  if (bodyReady.value) {
    emit('ready')
    emitSnapshot(instance)
  }
  return bodyReady.value
}

function insertUploadedImages(instance: TiptapEditor, files: File[]) {
  const upload = props.uploadImage
  if (!upload) return
  for (const file of files) {
    void upload(file).then((attachment) => {
      // The editor can be recreated while an upload is in flight; never
      // insert into a stale instance.
      if (editor.value !== instance) return
      instance.chain().focus().insertContent({
        type: 'image',
        attrs: { src: attachment.url, alt: attachment.originalName, attachmentId: attachment.id },
      }).run()
    }).catch(() => undefined)
  }
}

function imageFilesFrom(event: ClipboardEvent | DragEvent): File[] {
  const transfer = 'clipboardData' in event ? event.clipboardData : event.dataTransfer
  return Array.from(transfer?.files ?? []).filter((file) => file.type.startsWith('image/'))
}

function createEditor() {
  const document = props.document
  const instance = new TiptapEditor({
    content: document ? undefined : (props.modelValue ?? emptyDocument),
    editable: document ? Boolean(props.editable && bodyReady.value) : props.editable,
    extensions: document
      ? [
          ...createWorkFollowEditorExtensions(props.placeholder, { collaboration: true }),
          Collaboration.configure({ document, field: 'default' }),
        ]
      : createWorkFollowEditorExtensions(props.placeholder),
    editorProps: {
      handlePaste: (_view, event) => {
        if (!props.uploadImage || !props.editable || !bodyReady.value) return false
        const files = imageFilesFrom(event)
        if (!files.length) return false
        event.preventDefault()
        insertUploadedImages(instance, files)
        return true
      },
      handleDrop: (_view, event, _slice, moved) => {
        if (moved || !props.uploadImage || !props.editable || !bodyReady.value) return false
        const files = imageFilesFrom(event)
        if (!files.length) return false
        event.preventDefault()
        insertUploadedImages(instance, files)
        return true
      },
      handleKeyDown: (_view, event) => {
        if (!props.slashMenu || !props.editable || !slash.open.value) return false

        if (event.key === 'ArrowDown') {
          event.preventDefault()
          slash.moveSelection(1)
          return true
        }
        if (event.key === 'ArrowUp') {
          event.preventDefault()
          slash.moveSelection(-1)
          return true
        }
        if (event.key === 'Enter') {
          event.preventDefault()
          const command = slashCommands.value[slash.activeIndex.value]
          if (command) insertSlashBlock(command.type)
          return true
        }
        if (event.key === 'Escape') {
          event.preventDefault()
          slash.close()
          return true
        }

        return false
      },
    },
    onUpdate: ({ editor: current }) => {
      if (!applyingExternalDocument) scheduleSnapshot(current)
      if (props.slashMenu && props.editable) {
        if (slashDetectTimer !== undefined) window.clearTimeout(slashDetectTimer)
        slashDetectTimer = window.setTimeout(() => slash.detect(current), 0)
      }
    },
  })
  editor.value = instance

  if (document) {
    initializationGeneration += 1
    const generation = initializationGeneration
    initializationPromise = initializeDocument(instance, document, generation)
    void initializationPromise
  }
}

function recreateEditor() {
  editor.value?.destroy()
  editor.value = null
  createEditor()
}

async function flush() {
  if (snapshotTimer !== undefined) window.clearTimeout(snapshotTimer)
  snapshotTimer = undefined
  if (collaborative.value && !await initializationPromise) throw new Error('协同正文尚未初始化完成，请稍后重试。')
  emitSnapshot()
}

async function waitUntilReady() {
  return initializationPromise
}

defineExpose({ flush, waitUntilReady })

watch(() => props.document, () => {
  recreateEditor()
}, { immediate: true })

watch(() => props.editable, (value) => {
  editor.value?.setEditable(collaborative.value ? Boolean(value && bodyReady.value) : value)
  if (!value) slash.close()
})
watch(() => [props.seedReady, bodyReady.value] as const, ([seedReady, ready]) => {
  if (!collaborative.value) return
  editor.value?.setEditable(Boolean(props.editable && seedReady && ready))
})
watch(() => props.slashMenu, (value) => {
  if (!value) slash.close()
})
watch(() => props.modelValue, (value) => {
  if (collaborative.value) {
    // A collaborative document is the source of truth. External model updates
    // are accepted only before a Y.Doc has been attached.
    if (props.document || !editor.value || !value) return
    applyingExternalDocument = true
    editor.value.commands.setContent(value, false)
    applyingExternalDocument = false
    return
  }
  if (!editor.value) return
  if (value === lastEmittedDocument) return
  const next = value ?? emptyDocument
  applyingExternalDocument = true
  editor.value.commands.setContent(next, false)
  lastEmittedDocument = next
  applyingExternalDocument = false
})

onBeforeUnmount(() => {
  if (slashDetectTimer !== undefined) window.clearTimeout(slashDetectTimer)
  if (snapshotTimer !== undefined) window.clearTimeout(snapshotTimer)
  initializationGeneration += 1
  editor.value?.destroy()
})
</script>

<template>
  <div v-bind="$attrs" class="rich-text-document" :class="{ readonly: !editable }">
    <RichTextToolbar v-if="editable && editor" :editor="editor" @link="setLink" />
    <EditorContent :editor="editor ?? undefined" />
    <EditorLinkDialog ref="linkDialog" :editor="() => editor" />
  </div>

  <EditorSlashMenu :commands="slashCommands" :active-index="slash.activeIndex.value" :position="slash.position.value" :open="slash.open.value" id-prefix="rich-text-slash-command" @select="insertSlashBlock" @hover="slash.activeIndex.value = $event" />
</template>
