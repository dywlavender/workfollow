<script setup lang="ts">
import { NodeViewWrapper, nodeViewProps } from '@tiptap/vue-3'
import { computed, onBeforeUnmount, ref, watch } from 'vue'

import {
  MAX_IMAGE_WIDTH_PERCENT,
  MIN_IMAGE_WIDTH_PERCENT,
  normalizeImageWidth,
} from '@/modules/editor/imageSizing'
import { useEditorEditable } from '@/modules/editor/editorEditable'

const props = defineProps(nodeViewProps)

const rootElement = ref<HTMLElement | null>(null)
const imageElement = ref<HTMLImageElement | null>(null)
const dragging = ref(false)
const previewWidth = ref<number | null>(normalizeImageWidth(props.node.attrs.width))
const editable = useEditorEditable(props.editor)

let pointerId: number | null = null
let startX = 0
let startWidth = MIN_IMAGE_WIDTH_PERCENT
let resizeContentWidth = 1
let latestClientX = 0
let resizeFrame: number | undefined

const canResize = computed(() => editable.value && props.selected)
const activeWidth = computed(() => (
  dragging.value ? previewWidth.value : normalizeImageWidth(props.node.attrs.width)
))
const stageStyle = computed(() => (
  activeWidth.value === null ? undefined : { width: `${activeWidth.value}%` }
))
const imageStyle = computed(() => (
  activeWidth.value === null ? undefined : { width: '100%' }
))

function editorContentWidth() {
  const parent = rootElement.value?.parentElement
  if (!parent) return 1

  const styles = window.getComputedStyle(parent)
  const horizontalPadding = Number.parseFloat(styles.paddingLeft) + Number.parseFloat(styles.paddingRight)
  return Math.max(1, parent.clientWidth - (Number.isFinite(horizontalPadding) ? horizontalPadding : 0))
}

function displayedWidthPercent(contentWidth = editorContentWidth()) {
  const imageWidth = imageElement.value?.getBoundingClientRect().width ?? 0
  if (!imageWidth) return MAX_IMAGE_WIDTH_PERCENT
  return normalizeImageWidth((imageWidth / contentWidth) * 100) ?? MAX_IMAGE_WIDTH_PERCENT
}

function applyPointerPosition(clientX: number) {
  const deltaPercent = ((clientX - startX) / resizeContentWidth) * 100
  previewWidth.value = normalizeImageWidth(startWidth + deltaPercent)
}

function flushResizeFrame() {
  if (resizeFrame !== undefined) {
    window.cancelAnimationFrame(resizeFrame)
    resizeFrame = undefined
  }
}

function removePointerListeners() {
  flushResizeFrame()
  window.removeEventListener('pointermove', handlePointerMove)
  window.removeEventListener('pointerup', finishResize)
  window.removeEventListener('pointercancel', cancelResize)
  pointerId = null
}

function startResize(event: PointerEvent) {
  if (!canResize.value) return

  event.preventDefault()
  event.stopPropagation()
  pointerId = event.pointerId
  startX = event.clientX
  resizeContentWidth = editorContentWidth()
  startWidth = normalizeImageWidth(props.node.attrs.width) ?? displayedWidthPercent(resizeContentWidth)
  latestClientX = event.clientX
  previewWidth.value = startWidth
  dragging.value = true

  window.addEventListener('pointermove', handlePointerMove)
  window.addEventListener('pointerup', finishResize)
  window.addEventListener('pointercancel', cancelResize)
}

function handlePointerMove(event: PointerEvent) {
  if (!dragging.value || (pointerId !== null && event.pointerId !== pointerId)) return

  latestClientX = event.clientX
  if (resizeFrame !== undefined) return

  resizeFrame = window.requestAnimationFrame(() => {
    resizeFrame = undefined
    if (dragging.value) applyPointerPosition(latestClientX)
  })
}

function finishResize(event: PointerEvent) {
  if (!dragging.value || (pointerId !== null && event.pointerId !== pointerId)) return

  latestClientX = event.clientX
  flushResizeFrame()
  applyPointerPosition(latestClientX)
  const nextWidth = normalizeImageWidth(previewWidth.value)
  const previousWidth = normalizeImageWidth(props.node.attrs.width)
  dragging.value = false
  removePointerListeners()

  if (nextWidth !== null && nextWidth !== previousWidth) {
    props.updateAttributes({ width: nextWidth })
  }
}

function cancelResize(event: PointerEvent) {
  if (!dragging.value || (pointerId !== null && event.pointerId !== pointerId)) return

  dragging.value = false
  previewWidth.value = normalizeImageWidth(props.node.attrs.width)
  removePointerListeners()
}

watch(() => props.node.attrs.width, (value) => {
  if (!dragging.value) previewWidth.value = normalizeImageWidth(value)
})

onBeforeUnmount(() => removePointerListeners())
</script>

<template>
  <NodeViewWrapper
    ref="rootElement"
    class="resizable-image-node"
    :class="{ 'is-selected': selected, 'is-resizing': dragging }"
  >
    <div class="resizable-image-stage" :style="stageStyle">
      <img
        ref="imageElement"
        :src="String(node.attrs.src ?? '')"
        :alt="String(node.attrs.alt ?? '')"
        :title="node.attrs.title ? String(node.attrs.title) : undefined"
        :style="imageStyle"
        draggable="false"
      />
      <button
        v-if="canResize"
        type="button"
        class="image-resize-handle"
        aria-label="拖拽调整图片大小"
        :title="`拖拽调整图片大小（${MIN_IMAGE_WIDTH_PERCENT}%–${MAX_IMAGE_WIDTH_PERCENT}%）`"
        @pointerdown="startResize"
      />
    </div>
  </NodeViewWrapper>
</template>
