<script setup lang="ts">
import { IconArrowDown, IconArrowUp, IconEdit, IconPlus, IconTrash, IconX } from '@tabler/icons-vue'
import { computed, onMounted, reactive, ref } from 'vue'

import ActionFeedback from '@/components/ActionFeedback.vue'
import ConfirmDialog from '@/components/ConfirmDialog.vue'
import { useDialogEscape } from '@/composables/useDialogEscape'
import {
  deleteQuickLink,
  fetchQuickLinks,
  postQuickLink,
  putQuickLink,
  type QuickLink,
} from '@/services/api'


const links = ref<QuickLink[]>([])
const MAX_QUICK_LINKS = 12
const dialogOpen = ref(false)
const editingId = ref<string | null>(null)
const removeTarget = ref<QuickLink | null>(null)
const loadError = ref<string | null>(null)
const actionError = ref<string | null>(null)
const form = reactive({ name: '', url: '', icon: '', groupName: '' })
useDialogEscape(() => dialogOpen.value, () => { dialogOpen.value = false })
const atLimit = computed(() => links.value.length >= MAX_QUICK_LINKS)

async function load() {
  try {
    links.value = await fetchQuickLinks()
    loadError.value = null
  } catch {
    loadError.value = '常用网址读取失败'
  }
}

onMounted(load)

function resetForm() {
  editingId.value = null
  form.name = ''
  form.url = ''
  form.icon = ''
  form.groupName = ''
}

function edit(link: QuickLink) {
  editingId.value = link.id
  form.name = link.name
  form.url = link.url
  form.icon = link.icon
  form.groupName = link.groupName ?? ''
}

async function save() {
  if (!editingId.value && atLimit.value) {
    actionError.value = `常用网址最多只能添加 ${MAX_QUICK_LINKS} 个`
    return
  }
  const payload = {
    name: form.name.trim(),
    url: form.url.trim(),
    icon: form.icon.trim() || null,
    groupName: form.groupName.trim() || null,
    sortOrder: editingId.value
      ? links.value.find((link) => link.id === editingId.value)?.sortOrder ?? links.value.length
      : links.value.length ? Math.max(...links.value.map((link) => link.sortOrder)) + 10 : 0,
  }
  try {
    actionError.value = null
    if (editingId.value) await putQuickLink(editingId.value, payload)
    else await postQuickLink(payload)
    resetForm()
    await load()
  } catch {
    actionError.value = '保存失败，请检查名称和网址格式。'
  }
}

function remove(link: QuickLink) {
  removeTarget.value = link
}

async function confirmRemove() {
  const link = removeTarget.value
  removeTarget.value = null
  if (!link) return
  try {
    await deleteQuickLink(link.id)
    if (editingId.value === link.id) resetForm()
    await load()
  } catch {
    actionError.value = '删除失败，请稍后重试。'
  }
}

async function move(index: number, direction: -1 | 1) {
  const otherIndex = index + direction
  if (otherIndex < 0 || otherIndex >= links.value.length) return
  const current = links.value[index]
  const other = links.value[otherIndex]
  await Promise.all([
    putQuickLink(current.id, { sortOrder: other.sortOrder }),
    putQuickLink(other.id, { sortOrder: current.sortOrder }),
  ])
  await load()
}
</script>

<template>
  <section class="card quick-links-card">
    <header class="compact-card-header">
      <div><span class="section-label">工作入口</span><h2>常用网址</h2></div>
      <button class="text-button" type="button" @click="dialogOpen = true">管理</button>
    </header>
    <ActionFeedback :message="actionError" @dismiss="actionError = null" />
    <p v-if="loadError" class="inline-error" role="alert">{{ loadError }}</p>
    <div v-else class="quick-link-grid">
      <a v-for="link in links.slice(0, 12)" :key="link.id" :href="link.url" target="_blank" rel="noopener noreferrer">
        <span class="quick-link-icon">{{ link.icon }}</span>
        <span>{{ link.name }}</span>
      </a>
      <button v-if="links.length < 12" class="add-quick-link" type="button" @click="dialogOpen = true; resetForm()">
        <span class="quick-link-icon"><IconPlus :size="17" /></span><span>添加</span>
      </button>
    </div>
  </section>

  <Teleport to="body">
    <div v-if="dialogOpen" class="dialog-backdrop" @mousedown.self="dialogOpen = false">
      <section class="dialog-card quick-link-dialog" role="dialog" aria-modal="true" aria-labelledby="quick-link-title">
        <header class="dialog-header">
          <div><span class="eyebrow">QuickLink</span><h2 id="quick-link-title">管理常用网址</h2></div>
          <button class="icon-action" type="button" aria-label="关闭" @click="dialogOpen = false"><IconX :size="18" /></button>
        </header>
        <div class="quick-link-manager">
          <form class="todo-form quick-link-form" @submit.prevent="save">
            <label>名称<input v-model="form.name" required maxlength="120" placeholder="例如：GitLab" /></label>
            <label>网址<input v-model="form.url" required type="url" placeholder="https://" /></label>
            <div class="form-grid">
              <label>图标文字<input v-model="form.icon" maxlength="32" placeholder="留空自动生成" /></label>
              <label>分组<input v-model="form.groupName" maxlength="120" placeholder="可选" /></label>
            </div>
            <div class="dialog-actions">
              <button v-if="editingId" class="secondary-button" type="button" @click="resetForm">取消编辑</button>
              <button class="primary-button" type="submit" :disabled="!editingId && atLimit">{{ editingId ? '保存修改' : '新增网址' }}</button>
              <span v-if="!editingId && atLimit" class="muted-text">已达到 {{ MAX_QUICK_LINKS }} 个上限</span>
            </div>
          </form>
          <div class="managed-link-list">
            <p v-if="!links.length" class="muted-text">还没有常用网址。</p>
            <article v-for="(link, index) in links" :key="link.id">
              <span class="quick-link-icon">{{ link.icon }}</span>
              <span class="managed-link-name"><strong>{{ link.name }}</strong><small>{{ link.url }}</small></span>
              <button type="button" aria-label="上移" :disabled="index === 0" @click="move(index, -1)"><IconArrowUp :size="15" /></button>
              <button type="button" aria-label="下移" :disabled="index === links.length - 1" @click="move(index, 1)"><IconArrowDown :size="15" /></button>
              <button type="button" aria-label="编辑" @click="edit(link)"><IconEdit :size="15" /></button>
              <button type="button" aria-label="删除" @click="remove(link)"><IconTrash :size="15" /></button>
            </article>
          </div>
        </div>
      </section>
    </div>
  </Teleport>
  <ConfirmDialog
    :open="Boolean(removeTarget)"
    title="删除常用网址"
    :message="removeTarget ? `确定删除“${removeTarget.name}”吗？` : ''"
    confirm-label="删除"
    :danger="true"
    @close="removeTarget = null"
    @confirm="confirmRemove"
  />
</template>
