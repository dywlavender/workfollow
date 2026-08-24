<script setup lang="ts">
import { IconDots, IconEdit, IconFileText, IconPlus, IconTrash, IconX } from '@tabler/icons-vue'
import { computed, ref } from 'vue'

import { useDialogEscape } from '@/composables/useDialogEscape'
import type { NoteTemplate } from '@/services/api'

const props = defineProps<{ open: boolean; templates: NoteTemplate[] }>()
const emit = defineEmits<{
  close: []
  select: [template: NoteTemplate]
  create: []
  manage: []
  edit: [template: NoteTemplate]
  delete: [template: NoteTemplate]
}>()

const openMenuId = ref<string | null>(null)
const builtinTemplates = computed(() => props.templates.filter((template) => template.isBuiltin))
const personalTemplates = computed(() => props.templates.filter((template) => !template.isBuiltin))

useDialogEscape(() => props.open, () => emit('close'))

function preview(template: NoteTemplate): string {
  const chunks: string[] = []
  const visit = (value: unknown) => {
    if (!value || typeof value !== 'object') return
    const node = value as { type?: unknown; text?: unknown; content?: unknown }
    if (node.type === 'text' && typeof node.text === 'string') chunks.push(node.text)
    if (Array.isArray(node.content)) node.content.forEach(visit)
    if (['paragraph', 'heading', 'blockquote', 'listItem', 'taskItem'].includes(String(node.type))) chunks.push(' ')
  }
  visit(template.contentJson)
  const text = chunks.join('').replace(/\s+/g, ' ').trim()
  return text ? `${text.slice(0, 78)}${text.length > 78 ? '…' : ''}` : '空白模板，可直接开始编辑'
}

function closeMenu() {
  openMenuId.value = null
}

function selectTemplate(template: NoteTemplate) {
  closeMenu()
  emit('select', template)
}
</script>

<template>
  <Teleport to="body">
    <div v-if="open" class="dialog-backdrop" @mousedown.self="emit('close')">
      <section class="dialog-card template-dialog" role="dialog" aria-modal="true" aria-labelledby="template-title" @click="closeMenu">
        <header class="dialog-header">
          <div><span class="section-label">模板库</span><h2 id="template-title">选择笔记模板</h2></div>
          <button class="icon-action" type="button" aria-label="关闭" @click="emit('close')"><IconX :size="18" /></button>
        </header>
        <div class="template-dialog-toolbar">
          <button class="secondary-button" type="button" @click="emit('create')"><IconPlus :size="15" />新建模板</button>
          <button class="text-button" type="button" @click="emit('manage')">管理模板</button>
        </div>

        <div class="template-groups">
          <section class="template-group" aria-labelledby="builtin-template-title">
            <header><div><span class="eyebrow">SYSTEM</span><h3 id="builtin-template-title">系统模板</h3></div><span>{{ builtinTemplates.length }}</span></header>
            <div class="template-grid">
              <article v-for="template in builtinTemplates" :key="template.id" class="template-card">
                <button class="template-card-main" type="button" @click="selectTemplate(template)">
                  <div class="template-card-heading"><span class="template-icon"><IconFileText :size="20" /></span><span class="template-badge builtin">系统模板</span></div>
                  <strong>{{ template.name }}</strong>
                  <p>{{ template.description || '系统提供的通用笔记结构' }}</p>
                  <small>{{ preview(template) }}</small>
                </button>
              </article>
            </div>
          </section>

          <section class="template-group" aria-labelledby="personal-template-title">
            <header><div><span class="eyebrow">PERSONAL</span><h3 id="personal-template-title">我的模板</h3></div><span>{{ personalTemplates.length }}</span></header>
            <div v-if="personalTemplates.length" class="template-grid">
              <article v-for="template in personalTemplates" :key="template.id" class="template-card personal">
                <button class="template-card-main" type="button" @click="selectTemplate(template)">
                  <div class="template-card-heading"><span class="template-icon"><IconFileText :size="20" /></span><span class="template-badge">我的模板</span></div>
                  <strong>{{ template.name }}</strong>
                  <p>{{ template.description || '没有填写模板说明' }}</p>
                  <small>{{ preview(template) }}</small>
                </button>
                <div class="template-card-actions">
                  <button type="button" title="编辑模板" @click.stop="emit('edit', template)"><IconEdit :size="14" />编辑</button>
                  <button class="danger-text" type="button" title="删除模板" @click.stop="emit('delete', template)"><IconTrash :size="14" />删除</button>
                  <div class="template-card-more">
                    <button type="button" title="更多操作" aria-label="更多操作" @click.stop="openMenuId = openMenuId === template.id ? null : template.id"><IconDots :size="16" /></button>
                    <div v-if="openMenuId === template.id" class="template-card-menu">
                      <button type="button" @click.stop="closeMenu(); emit('manage')">调整排序</button>
                    </div>
                  </div>
                </div>
              </article>
            </div>
            <div v-else class="template-empty"><strong>还没有个人模板</strong><span>把常用笔记保存下来，下一次可以直接套用。</span><button class="text-button" type="button" @click="emit('create')">新建第一个模板</button></div>
          </section>
        </div>
      </section>
    </div>
  </Teleport>
</template>
