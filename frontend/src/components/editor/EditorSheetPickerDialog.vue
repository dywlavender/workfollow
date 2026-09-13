<script setup lang="ts">
import { NButton, NCard, NModal } from 'naive-ui'
import { nextTick, ref, watch } from 'vue'

import type { SpreadsheetSheetMeta } from '@/modules/editor/excelImport'

/**
 * 多 sheet 工作簿的工作表选择器。只有 sheet 数 > 1 时宿主才会打开它；
 * 默认高亮第一个 sheet（Excel/WPS 的"表格1"/Sheet1），回车直接确认。
 */
const props = defineProps<{
  open: boolean
  sheets: SpreadsheetSheetMeta[]
}>()

const emit = defineEmits<{
  select: [sheetName: string]
  close: []
}>()

const activeIndex = ref(0)
const listElement = ref<HTMLElement | null>(null)

watch(() => props.open, (open) => {
  if (!open) return
  activeIndex.value = 0
  void nextTick(() => listElement.value?.focus())
})

function confirm(index: number) {
  const sheet = props.sheets[index]
  if (!sheet) return
  emit('select', sheet.name)
}

function onKeydown(event: KeyboardEvent) {
  if (event.key === 'ArrowDown' || event.key === 'ArrowUp') {
    event.preventDefault()
    const delta = event.key === 'ArrowDown' ? 1 : -1
    activeIndex.value = (activeIndex.value + delta + props.sheets.length) % props.sheets.length
    void nextTick(() => listElement.value?.querySelector<HTMLElement>('.sheet-picker-item.active')?.focus())
  } else if (event.key === 'Enter') {
    event.preventDefault()
    confirm(activeIndex.value)
  }
}
</script>

<template>
  <NModal :show="open" :mask-closable="true" @mask-click="emit('close')" @esc="emit('close')">
    <NCard class="naive-dialog-card sheet-picker-card" title="选择工作表" role="dialog" aria-modal="true" aria-label="选择要导入的工作表" closable @close="emit('close')">
      <p class="sheet-picker-hint">该文件包含多个工作表，选择要导入的一个（可多次导入不同的表）。</p>
      <div ref="listElement" class="sheet-picker-list" role="listbox" aria-label="工作表列表" tabindex="0" @keydown="onKeydown">
        <button
          v-for="(sheet, index) in sheets"
          :key="sheet.name"
          type="button"
          role="option"
          class="sheet-picker-item"
          :class="{ active: index === activeIndex }"
          :aria-selected="index === activeIndex"
          @mousemove="activeIndex = index"
          @focus="activeIndex = index"
          @click="confirm(index)"
        >
          <strong>{{ sheet.name }}</strong>
          <span>{{ sheet.rows }} 行 × {{ sheet.cols }} 列</span>
        </button>
      </div>
      <template #footer>
        <div class="naive-dialog-actions">
          <NButton @click="emit('close')">取消</NButton>
          <NButton type="primary" @click="confirm(activeIndex)">导入</NButton>
        </div>
      </template>
    </NCard>
  </NModal>
</template>
