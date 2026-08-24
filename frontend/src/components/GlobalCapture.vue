<script setup lang="ts">
import { computed, onBeforeUnmount, onMounted, ref } from 'vue'
import { useRouter } from 'vue-router'
import { IconPlus } from '@tabler/icons-vue'

import CaptureDialog from '@/components/notes/CaptureDialog.vue'
import { captureNote } from '@/services/api'

const router = useRouter()
const open = ref(false)
const saving = ref(false)
const error = ref<string | null>(null)
const host = ref<HTMLElement | null>(null)
const position = ref({ left: 24, top: 24 })
const dragging = ref(false)
const suppressClick = ref(false)
const dragState = ref<{ pointerId: number; startX: number; startY: number; left: number; top: number; moved: boolean } | null>(null)
const positionStyle = computed(() => ({ left: `${position.value.left}px`, top: `${position.value.top}px` }))
const POSITION_KEY = 'workfollow.global-capture-position'

function clampPosition(left: number, top: number) {
  // Use the actual rendered host size. A fixed width here leaves an overly
  // large invisible gutter and prevents the launcher from reaching the edge.
  const width = host.value?.offsetWidth || 112
  const height = host.value?.offsetHeight || 56
  position.value = {
    left: Math.min(Math.max(12, left), Math.max(12, window.innerWidth - width - 12)),
    top: Math.min(Math.max(12, top), Math.max(12, window.innerHeight - height - 12)),
  }
}

function savePosition() {
  try { localStorage.setItem(POSITION_KEY, JSON.stringify(position.value)) } catch { /* local storage may be unavailable */ }
}

function restorePosition() {
  try {
    const raw = localStorage.getItem(POSITION_KEY)
    if (raw) {
      const saved = JSON.parse(raw)
      if (Number.isFinite(saved?.left) && Number.isFinite(saved?.top)) {
        clampPosition(saved.left, saved.top)
        return
      }
    }
  } catch { /* use the default position */ }
  clampPosition(window.innerWidth - 178, window.innerHeight - 68)
}

function handleResize() { clampPosition(position.value.left, position.value.top) }

function beginDrag(event: PointerEvent) {
  if (event.button !== 0) return
  dragState.value = {
    pointerId: event.pointerId,
    startX: event.clientX,
    startY: event.clientY,
    left: position.value.left,
    top: position.value.top,
    moved: false,
  }
  dragging.value = true
  window.addEventListener('pointermove', moveDrag)
  window.addEventListener('pointerup', endDrag, { once: true })
  window.addEventListener('pointercancel', endDrag, { once: true })
}

function moveDrag(event: PointerEvent) {
  const state = dragState.value
  if (!state || state.pointerId !== event.pointerId) return
  const deltaX = event.clientX - state.startX
  const deltaY = event.clientY - state.startY
  if (Math.abs(deltaX) > 4 || Math.abs(deltaY) > 4) state.moved = true
  clampPosition(state.left + deltaX, state.top + deltaY)
}

function endDrag(event: PointerEvent) {
  const state = dragState.value
  if (!state || state.pointerId !== event.pointerId) return
  suppressClick.value = state.moved
  dragState.value = null
  dragging.value = false
  window.removeEventListener('pointermove', moveDrag)
  window.removeEventListener('pointerup', endDrag)
  window.removeEventListener('pointercancel', endDrag)
  if (state.moved) savePosition()
}

async function openCapture() {
  if (suppressClick.value) {
    suppressClick.value = false
    return
  }
  error.value = null
  open.value = true
}

async function capture(payload: { text: string; title?: string }) {
  if (saving.value) return
  saving.value = true
  error.value = null
  try {
    const note = await captureNote(payload)
    open.value = false
    await router.push({ path: '/notes', query: { view: 'inbox', note: note.id } })
  } catch (cause: any) {
    error.value = cause?.response?.data?.detail ?? '保存随手记失败，请稍后重试。'
  } finally {
    saving.value = false
  }
}

onMounted(() => {
  restorePosition()
  window.addEventListener('resize', handleResize)
})

onBeforeUnmount(() => {
  window.removeEventListener('resize', handleResize)
  window.removeEventListener('pointermove', moveDrag)
  window.removeEventListener('pointerup', endDrag)
  window.removeEventListener('pointercancel', endDrag)
})
</script>

<template>
  <div ref="host" class="global-capture-host" :class="{ dragging }" :style="positionStyle">
    <button class="global-capture-launcher" type="button" @pointerdown="beginDrag" @click="openCapture"><IconPlus :size="17" />随手记</button>
    <p v-if="error" class="global-capture-error" role="status">{{ error }}</p>
    <CaptureDialog :open="open" :saving="saving" @close="open = false" @submit="capture" />
  </div>
</template>
