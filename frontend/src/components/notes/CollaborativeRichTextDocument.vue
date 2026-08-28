<script setup lang="ts">
import Collaboration from '@tiptap/extension-collaboration'
import { Editor as TiptapEditor, EditorContent } from '@tiptap/vue-3'
import type { Editor as CoreEditor } from '@tiptap/core'
import * as Y from 'yjs'
import { onBeforeUnmount, ref, shallowRef, watch } from 'vue'

import RichTextToolbar from '@/components/RichTextToolbar.vue'
import InputDialog from '@/components/InputDialog.vue'
import { CollaborationInitializationError, initializeCollaborativeField } from '@/modules/editor/collaborationInitialization'
import { createWorkFollowEditorExtensions } from '@/modules/editor/tiptap'

const props = withDefaults(defineProps<{
  document: Y.Doc | null
  modelValue?: Record<string, unknown> | null
  initialContent?: Record<string, unknown> | null
  editable?: boolean
  seedReady?: boolean
  seedDocument?: boolean
  collaborationDocumentName?: string | null
  placeholder?: string
}>(), { modelValue: null, initialContent: null, editable: true, seedReady: false, seedDocument: true, collaborationDocumentName: null, placeholder: '输入内容…' })

const emit = defineEmits<{
  'update:modelValue': [value: Record<string, unknown>]
  'update:plainText': [value: string]
  ready: []
  initializationError: [message: string]
}>()

const editor = shallowRef<TiptapEditor | null>(null)
const linkDialogOpen = ref(false)
const linkValue = ref('')
const bodyReady = ref(!props.collaborationDocumentName || !props.seedDocument)
let snapshotTimer: number | undefined
let applyingExternalDocument = false
let initializationPromise: Promise<boolean> = Promise.resolve(bodyReady.value)
let initializationGeneration = 0

function emitSnapshot(current: CoreEditor | null = editor.value) {
  if (!current) return
  emit('update:modelValue', current.getJSON() as Record<string, unknown>)
  emit('update:plainText', current.getText())
}

function scheduleSnapshot(current: CoreEditor) {
  if (snapshotTimer !== undefined) window.clearTimeout(snapshotTimer)
  snapshotTimer = window.setTimeout(() => {
    if (editor.value === current) emitSnapshot(current)
    snapshotTimer = undefined
  }, 150)
}

function setLink() {
  linkValue.value = (editor.value?.getAttributes('link').href as string | undefined) ?? 'https://'
  linkDialogOpen.value = true
}

function applyLink(value: string) {
  linkDialogOpen.value = false
  if (!editor.value) return
  if (!value.trim()) editor.value.chain().focus().extendMarkRange('link').unsetLink().run()
  else editor.value.chain().focus().extendMarkRange('link').setLink({ href: value.trim() }).run()
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

function createEditor(document: Y.Doc) {
  const instance = new TiptapEditor({
    extensions: [
      ...createWorkFollowEditorExtensions(props.placeholder, { collaboration: true }),
      Collaboration.configure({ document, field: 'default' }),
    ],
    editable: props.editable && bodyReady.value,
    onUpdate: ({ editor: current }) => {
      if (!applyingExternalDocument) scheduleSnapshot(current)
    },
  })
  editor.value = instance
  initializationGeneration += 1
  const generation = initializationGeneration
  initializationPromise = initializeDocument(instance, document, generation)
  void initializationPromise
}

function recreateEditor(document: Y.Doc | null) {
  editor.value?.destroy()
  editor.value = null
  if (document) createEditor(document)
}

async function flush() {
  if (snapshotTimer !== undefined) window.clearTimeout(snapshotTimer)
  snapshotTimer = undefined
  if (!await initializationPromise) throw new Error('协同正文尚未初始化完成，请稍后重试。')
  emitSnapshot()
}

async function waitUntilReady() {
  return initializationPromise
}

defineExpose({ flush, waitUntilReady })

watch(() => [props.document, props.seedReady, props.collaborationDocumentName] as const, ([document], previous) => {
  if (document !== previous?.[0]) recreateEditor(document)
  else if (document && props.seedReady && editor.value) {
    initializationGeneration += 1
    initializationPromise = initializeDocument(editor.value, document, initializationGeneration)
  }
}, { immediate: true })
watch(() => [props.editable, props.seedReady, bodyReady.value] as const, ([editable, seedReady, ready]) => editor.value?.setEditable(Boolean(editable && seedReady && ready)))
watch(() => props.modelValue, (value) => {
  // A collaborative document is the source of truth. External model updates
  // are accepted only before a Y.Doc has been attached.
  if (props.document || !editor.value || !value) return
  applyingExternalDocument = true
  editor.value.commands.setContent(value, false)
  applyingExternalDocument = false
})

onBeforeUnmount(() => {
  if (snapshotTimer !== undefined) window.clearTimeout(snapshotTimer)
  initializationGeneration += 1
  editor.value?.destroy()
})
</script>

<template>
  <div v-bind="$attrs" class="rich-text-document collaborative-rich-text-document" :class="{ readonly: !editable }">
    <RichTextToolbar v-if="editable && editor" :editor="editor" @link="setLink" />
    <EditorContent :editor="editor ?? undefined" />
    <InputDialog :open="linkDialogOpen" title="设置链接" label="链接地址" :initial-value="linkValue" placeholder="https://（留空可移除链接）" confirm-label="应用" :required="false" @close="linkDialogOpen = false" @submit="applyLink" />
  </div>
</template>
