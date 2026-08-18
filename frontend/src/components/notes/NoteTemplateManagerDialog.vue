<script setup lang="ts">
import { IconChevronDown, IconChevronUp, IconEdit, IconTrash, IconX } from '@tabler/icons-vue'
import { computed } from 'vue'

import { useDialogEscape } from '@/composables/useDialogEscape'
import type { NoteTemplate } from '@/services/api'

const props = defineProps<{ open: boolean; templates: NoteTemplate[] }>()
const emit = defineEmits<{
  close: []
  edit: [template: NoteTemplate]
  delete: [template: NoteTemplate]
  move: [template: NoteTemplate, direction: 'up' | 'down']
}>()

const personalTemplates = computed(() => props.templates.filter((template) => !template.isBuiltin))
useDialogEscape(() => props.open, () => emit('close'))
</script>

<template>
  <Teleport to="body">
    <div v-if="open" class="dialog-backdrop" @mousedown.self="emit('close')">
      <section class="dialog-card template-manager-dialog" role="dialog" aria-modal="true" aria-labelledby="template-manager-title">
        <header class="dialog-header">
          <div><span class="section-label">PERSONAL TEMPLATES</span><h2 id="template-manager-title">管理我的模板</h2></div>
          <button class="icon-action" type="button" aria-label="关闭" @click="emit('close')"><IconX :size="18" /></button>
        </header>
        <p class="template-manager-intro">只影响个人模板的显示顺序。系统模板顺序由系统维护。</p>
        <div v-if="personalTemplates.length" class="template-managed-list">
          <article v-for="(template, index) in personalTemplates" :key="template.id" class="template-managed-row">
            <span class="template-managed-index">{{ index + 1 }}</span>
            <div class="template-managed-copy"><strong>{{ template.name }}</strong><small>{{ template.description || '没有填写模板说明' }}</small></div>
            <div class="template-managed-actions">
              <button type="button" aria-label="上移" :disabled="index === 0" @click="emit('move', template, 'up')"><IconChevronUp :size="16" /></button>
              <button type="button" aria-label="下移" :disabled="index === personalTemplates.length - 1" @click="emit('move', template, 'down')"><IconChevronDown :size="16" /></button>
              <button type="button" title="编辑模板" @click="emit('edit', template)"><IconEdit :size="15" /></button>
              <button class="danger-text" type="button" title="删除模板" @click="emit('delete', template)"><IconTrash :size="15" /></button>
            </div>
          </article>
        </div>
        <div v-else class="template-empty manager-empty"><strong>还没有个人模板</strong><span>可以从笔记编辑器的“更多操作”中保存一个。</span></div>
        <footer class="dialog-actions"><button class="secondary-button" type="button" @click="emit('close')">关闭</button></footer>
      </section>
    </div>
  </Teleport>
</template>
