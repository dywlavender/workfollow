<script setup lang="ts">
import { NButton } from 'naive-ui'
import { nextTick, onBeforeUnmount, ref } from 'vue'

import { startDrawioSession, type DiagramEditorResult, type DrawioSession } from '@/modules/editor/drawioEmbed'

/**
 * drawio 弹窗编辑器：近全屏遮罩 + iframe（frontend/public/drawio 静态资源）。
 * 常用操作固定在头部：保存（不关闭，可连续保存）、保存并退出、退出。
 * open() 期间每次保存都会回调 onSave(result)（宿主负责成对持久化并返回
 * 反馈文案）；弹窗关闭时整个 open() Promise 以 null 结束（内容已随存随报）。
 */
const DRAWIO_EMBED_URL = '/drawio/index.html?embed=1&proto=json&spin=1&ui=min&lang=zh&saveAndExit=1&stealth=1&offline=1'

const visible = ref(false)
const error = ref('')
const statusText = ref('')
const saving = ref(false)
const iframe = ref<HTMLIFrameElement | null>(null)
const iframeKey = ref(0)
let session: DrawioSession | null = null
let onSaveHandler: ((result: DiagramEditorResult) => Promise<string | null>) | null = null
let closedResolver: (() => void) | null = null

async function persist(closeAfter: boolean) {
  if (saving.value || !session) return
  saving.value = true
  statusText.value = '正在导出并保存…'
  try {
    const result = await session.capture()
    if (!result) {
      statusText.value = '导出失败，请重试'
      return
    }
    const message = (await onSaveHandler?.(result)) ?? '已保存'
    statusText.value = message
    if (closeAfter) close(false)
  } catch (cause) {
    statusText.value = cause instanceof Error ? cause.message : '保存失败，请重试'
  } finally {
    saving.value = false
  }
}

function close(notifyExit: boolean) {
  if (notifyExit) session?.exit()
  visible.value = false
  session = null
  closedResolver?.()
  closedResolver = null
}

function open(
  options: { xml: string | null },
  handlers: { onSave: (result: DiagramEditorResult) => Promise<string | null> },
): Promise<null> {
  error.value = ''
  statusText.value = ''
  saving.value = false
  visible.value = true
  iframeKey.value += 1
  onSaveHandler = handlers.onSave
  void nextTick(() => {
    if (!iframe.value) return
    session = startDrawioSession(iframe.value, {
      xml: options.xml,
      onPhase: (phase) => {
        if (phase === 'exporting' && !saving.value) statusText.value = '正在处理…'
      },
      onError: (message) => { error.value = message },
    })
    void session.whenFinished.then(() => {
      // drawio 自身按钮触发的退出也统一走关闭路径（内容已在每次保存时持久化）。
      visible.value = false
      session = null
      closedResolver?.()
      closedResolver = null
    })
  })
  return new Promise<null>((resolve) => { closedResolver = () => resolve(null) })
}

function cancel() {
  if (saving.value) return
  if (error.value) { close(false); return }
  session?.exit()
}

function handleKeydown(event: KeyboardEvent) {
  if (event.key === 'Escape') cancel()
}

onBeforeUnmount(() => {
  closedResolver?.()
  closedResolver = null
})

defineExpose({ open })
</script>

<template>
  <Teleport to="body">
    <div v-if="visible" class="drawio-editor-overlay" role="dialog" aria-modal="true" aria-label="流程图编辑（drawio）" @keydown="handleKeydown">
      <header class="drawio-editor-header">
        <strong>流程图</strong>
        <span v-if="statusText" class="drawio-editor-status" role="status">{{ statusText }}</span>
        <span v-if="error" class="drawio-editor-error" role="alert">{{ error }}</span>
        <div class="drawio-editor-actions">
          <NButton size="small" :disabled="saving" @click="cancel">退出</NButton>
          <NButton size="small" type="primary" ghost :disabled="saving" @click="persist(false)">保存</NButton>
          <NButton size="small" type="primary" :disabled="saving" @click="persist(true)">保存并退出</NButton>
        </div>
      </header>
      <iframe
        ref="iframe"
        :key="iframeKey"
        class="drawio-editor-frame"
        :src="DRAWIO_EMBED_URL"
        title="流程图编辑器"
      />
    </div>
  </Teleport>
</template>

<style>
.drawio-editor-overlay {
  position: fixed;
  inset: 0;
  z-index: var(--layer-dialog);
  display: flex;
  flex-direction: column;
  background: var(--color-overlay);
  backdrop-filter: blur(2px);
}

.drawio-editor-header {
  min-height: 46px;
  display: flex;
  align-items: center;
  gap: 12px;
  padding: 8px 16px;
  background: var(--color-bg-surface);
  border-bottom: 1px solid var(--color-border-subtle);
}

.drawio-editor-header strong { font-size: var(--font-size-body); }

.drawio-editor-status { color: var(--color-text-secondary); font-size: var(--font-size-caption); }

.drawio-editor-error {
  color: var(--color-danger);
  font-size: var(--font-size-caption);
}

.drawio-editor-actions {
  margin-left: auto;
  display: flex;
  align-items: center;
  gap: 8px;
}

.drawio-editor-frame {
  flex: 1;
  width: 100%;
  border: 0;
  background: var(--color-bg-subtle);
}
</style>
