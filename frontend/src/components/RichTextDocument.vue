<script setup lang="ts">
import Collaboration from '@tiptap/extension-collaboration'
import { Editor as TiptapEditor, EditorContent } from '@tiptap/vue-3'
import type { Editor as CoreEditor } from '@tiptap/core'
import * as Y from 'yjs'
import { computed, onBeforeUnmount, reactive, ref, shallowRef, watch } from 'vue'

import EditorLinkDialog from '@/components/editor/EditorLinkDialog.vue'
import EditorSlashMenu from '@/components/editor/EditorSlashMenu.vue'
import DiagramConflictConfirm from '@/components/editor/DiagramConflictConfirm.vue'
import DrawioEditorModal from '@/components/editor/DrawioEditorModal.vue'
import RichTextToolbar from '@/components/RichTextToolbar.vue'
import { workFollowSlashCommands, type WorkFollowSlashCommand } from '@/modules/editor/slashCommands'
import { useSlashMenu } from '@/modules/editor/slashMenu'
import { createDiagramEditorHandler } from '@/modules/editor/diagramEditor'
import { createDiagramPresenceBridge, type AwarenessLike, type DiagramPresenceBridge } from '@/modules/editor/diagramPresence'
import { CollaborationInitializationError, initializeCollaborativeField } from '@/modules/editor/collaborationInitialization'
import { createWorkFollowEditorExtensions, collapseAllEmptyParagraphs } from '@/modules/editor/tiptap'

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
  /** 流程图新建上传钩子（可编辑分享传入）；未提供时只能编辑已有图、不能新建。 */
  uploadFile?: ((file: File) => Promise<{ id: string }>) | null
  /** 协同服务的 awareness（可编辑分享传入）；用于流程图编辑存在感。 */
  diagramAwareness?: AwarenessLike | null
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
  uploadFile: null,
  diagramAwareness: null,
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
  // 模板正文没有笔记附件和代办弹窗上下文，因此只提供可直接写入正文的命令。
  if (command.noteOnly || command.type === 'attachment') return false
  // 流程图新建需要上传通道；无通道的视图不再列出，避免插入后无法成对保存。
  if (command.type === 'diagram' && !props.uploadFile && !props.uploadImage) return false
  return true
}))

const slash = useSlashMenu({
  commands: () => slashCommands.value,
  idPrefix: 'rich-text-slash-command',
  enabled: () => Boolean(props.slashMenu && props.editable),
})

const linkDialog = ref<InstanceType<typeof EditorLinkDialog> | null>(null)
const drawioModal = ref<InstanceType<typeof DrawioEditorModal> | null>(null)
const diagramConflict = ref<InstanceType<typeof DiagramConflictConfirm> | null>(null)
const diagramEditingPresence = reactive<Record<string, { userName: string }>>({})
const diagramPresenceBridge = shallowRef<DiagramPresenceBridge | null>(null)
const diagramNotice = ref('')
let diagramNoticeTimer: number | undefined

function showDiagramNotice(message: string) {
  diagramNotice.value = message
  if (diagramNoticeTimer !== undefined) window.clearTimeout(diagramNoticeTimer)
  diagramNoticeTimer = window.setTimeout(() => { if (diagramNotice.value === message) diagramNotice.value = '' }, 1800)
}

function openDiagramEditor(attrs: Record<string, unknown>, applyUpdate: (next: Record<string, unknown>) => void) {
  void createDiagramEditorHandler({
    uploadFile: (file) => {
      const upload = props.uploadFile ?? props.uploadImage
      if (!upload) return Promise.reject(new Error('当前视图不支持新建流程图'))
      return upload(file)
    },
    openModal: (options) => drawioModal.value?.open(options, { onSave: options.onSave }) ?? Promise.resolve(null),
    feedback: showDiagramNotice,
    confirm: (message, options) => diagramConflict.value?.ask(message, options) ?? Promise.resolve(false),
    onEditingChange: (sourceId) => diagramPresenceBridge.value?.setLocalEditing(sourceId),
    editingPeer: (sourceId) => diagramEditingPresence[sourceId] ?? null,
  })(attrs, applyUpdate)
}

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

  if (type === 'diagram') {
    chain.run()
    slash.close()
    openDiagramEditor({}, (payload) => {
      currentEditor.chain().focus().insertContent(payload).run()
    })
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
  else if (type === 'subtask') chain.toggleTaskList().insertContent('子代办')
  else if (type === 'tag') chain.insertContent('#标签')
  else if (type === 'relation') chain.insertContent('关联代办 / 笔记')

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
  // 与 NoteEditor 同因：编辑器挂载写入的默认空段落要先清掉再写种子，
  // 否则合并出两个空段落，占位符永远渲染不出来。
  const doc = instance.state.doc
  const onlyEmptyParagraphs = doc.childCount > 0
    && Array.from(doc.children).every((node) => node.type.name === 'paragraph' && node.content.size === 0)
  if (fragment.length > 0) {
    // An existing collaborative fragment is authoritative when it holds real
    // content; only the editor's own default empty paragraph may be replaced.
    if (!onlyEmptyParagraphs) return
    fragment.delete(0, fragment.length)
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
    collapseAllEmptyParagraphs(instance)
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
  instance.storage.diagramBlock.openEditor = openDiagramEditor
  instance.storage.diagramBlock.editingPresence = diagramEditingPresence

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

watch(() => props.diagramAwareness, (awareness) => {
  diagramPresenceBridge.value?.destroy()
  diagramPresenceBridge.value = awareness ? createDiagramPresenceBridge(awareness, diagramEditingPresence) : null
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
  if (diagramNoticeTimer !== undefined) window.clearTimeout(diagramNoticeTimer)
  diagramPresenceBridge.value?.destroy()
  diagramPresenceBridge.value = null
  initializationGeneration += 1
  editor.value?.destroy()
})
</script>

<template>
  <div v-bind="$attrs" class="rich-text-document" :class="{ readonly: !editable }">
    <RichTextToolbar v-if="editable && editor" :editor="editor" :diagram="Boolean(uploadFile || uploadImage)" @link="setLink" @diagram="openDiagramEditor({}, (payload) => { editor?.chain().focus().insertContent(payload).run() })" />
    <EditorContent :editor="editor ?? undefined" />
    <span v-if="diagramNotice" class="rich-text-diagram-notice" role="status">{{ diagramNotice }}</span>
    <EditorLinkDialog ref="linkDialog" :editor="() => editor" />
    <DrawioEditorModal ref="drawioModal" />
    <DiagramConflictConfirm ref="diagramConflict" />
  </div>

  <EditorSlashMenu :commands="slashCommands" :active-index="slash.activeIndex.value" :position="slash.position.value" :open="slash.open.value" id-prefix="rich-text-slash-command" @select="insertSlashBlock" @hover="slash.activeIndex.value = $event" />
</template>
