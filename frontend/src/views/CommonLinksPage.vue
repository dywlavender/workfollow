<script setup lang="ts">
import { IconArrowDown, IconArrowUp, IconEdit, IconExternalLink, IconFolder, IconLink, IconPlus, IconSearch, IconTrash, IconX } from '@tabler/icons-vue'
import { computed, onMounted, reactive, ref } from 'vue'

import ConfirmDialog from '@/components/ConfirmDialog.vue'
import InputDialog from '@/components/InputDialog.vue'
import { useDialogEscape } from '@/composables/useDialogEscape'
import {
  deleteSystemQuickLink,
  fetchSystemQuickLinks,
  postSystemQuickLink,
  putSystemQuickLink,
  reorderSystemQuickLinks,
  type QuickLink,
  type QuickLinkPayload,
} from '@/services/api'
import { useAuthStore } from '@/stores/auth'
import { useFeedbackStore } from '@/stores/feedback'

const auth = useAuthStore()
const feedback = useFeedbackStore()
const links = ref<QuickLink[]>([])
const search = ref('')
const loading = ref(true)
const busy = ref(false)
// 分组输入可从已有分组中选择（datalist），也可直接输入新名称。
const knownGroupNames = computed(() => Array.from(new Set(links.value
  .map((link) => link.groupName?.trim())
  .filter((name): name is string => Boolean(name)))))
const loadError = ref<string | null>(null)
const managerOpen = ref(false)
const editingId = ref<string | null>(null)
const removeTarget = ref<QuickLink | null>(null)
const removeGroupTarget = ref<string | null>(null)
const groupDialogOpen = ref(false)
const groupDialogMode = ref<'create' | 'rename'>('create')
const groupRenameSource = ref('')
const draggingId = ref<string | null>(null)
const form = reactive({
  name: '',
  url: '',
  icon: '',
  description: '',
  groupName: '',
})
useDialogEscape(() => managerOpen.value, () => { managerOpen.value = false })

const isRoot = computed(() => auth.user?.systemRole === 'ROOT')

function sortLinks(items: QuickLink[]): QuickLink[] {
  return [...items].sort((a, b) => a.sortOrder - b.sortOrder || a.createdAt.localeCompare(b.createdAt))
}

async function load() {
  loading.value = true
  try {
    links.value = sortLinks(await fetchSystemQuickLinks())
    loadError.value = null
  } catch (cause: any) {
    loadError.value = cause?.response?.data?.detail ?? '常用网站读取失败，请稍后重试。'
  } finally {
    loading.value = false
  }
}

onMounted(() => {
  void load()
})

const filteredGroups = computed(() => {
  const query = search.value.trim().toLocaleLowerCase()
  const grouped = new Map<string, QuickLink[]>()
  for (const link of sortLinks(links.value)) {
    const haystack = [link.name, link.url, link.description ?? '', link.groupName ?? '']
      .join(' ')
      .toLocaleLowerCase()
    if (query && !haystack.includes(query)) continue
    const group = link.groupName?.trim() || '未分组'
    const current = grouped.get(group) ?? []
    current.push(link)
    grouped.set(group, current)
  }
  return Array.from(grouped.entries()).map(([name, items]) => ({ name, items }))
})

function domainOf(url: string): string {
  try { return new URL(url).hostname }
  catch { return url }
}

function resetForm() {
  editingId.value = null
  form.name = ''
  form.url = ''
  form.icon = ''
  form.description = ''
  form.groupName = ''
}

function openCreate() {
  resetForm()
  managerOpen.value = true
}

function editLink(link: QuickLink) {
  editingId.value = link.id
  form.name = link.name
  form.url = link.url
  form.icon = link.icon
  form.description = link.description ?? ''
  form.groupName = link.groupName ?? ''
  managerOpen.value = true
}

function payloadFor(link?: QuickLink): QuickLinkPayload {
  return {
    name: form.name.trim(),
    url: form.url.trim(),
    icon: form.icon.trim() || null,
    description: form.description.trim() || null,
    groupName: form.groupName.trim() || null,
    sortOrder: link?.sortOrder ?? (links.value.length ? Math.max(...links.value.map((item) => item.sortOrder)) + 10 : 0),
  }
}

async function saveLink() {
  if (!form.name.trim() || !form.url.trim()) {
    feedback.error('请填写网站名称和网址。')
    return
  }
  busy.value = true
  try {
    if (editingId.value) {
      const current = links.value.find((item) => item.id === editingId.value)
      const updated = await putSystemQuickLink(editingId.value, payloadFor(current))
      const index = links.value.findIndex((item) => item.id === updated.id)
      if (index >= 0) links.value[index] = updated
    } else {
      links.value.push(await postSystemQuickLink(payloadFor()))
    }
    links.value = sortLinks(links.value)
    resetForm()
  } catch (cause: any) {
    feedback.error(cause?.response?.data?.detail ?? '保存失败，请检查网址是否为 http 或 https。')
  } finally {
    busy.value = false
  }
}

async function confirmRemove() {
  const target = removeTarget.value
  removeTarget.value = null
  if (!target) return
  busy.value = true
  try {
    await deleteSystemQuickLink(target.id)
    links.value = links.value.filter((item) => item.id !== target.id)
    if (editingId.value === target.id) resetForm()
  } catch (cause: any) {
    feedback.error(cause?.response?.data?.detail ?? '删除失败，请稍后重试。')
  } finally {
    busy.value = false
  }
}

async function persistOrder(next: QuickLink[]) {
  const previous = links.value
  links.value = next
  busy.value = true
  try {
    links.value = sortLinks(await reorderSystemQuickLinks(next.map((item) => item.id)))
  } catch (cause: any) {
    links.value = previous
    feedback.error(cause?.response?.data?.detail ?? '排序保存失败，请稍后重试。')
  } finally {
    busy.value = false
  }
}

function moveLink(link: QuickLink, direction: -1 | 1) {
  const index = links.value.findIndex((item) => item.id === link.id)
  const otherIndex = index + direction
  if (index < 0 || otherIndex < 0 || otherIndex >= links.value.length) return
  const next = [...links.value]
  ;[next[index], next[otherIndex]] = [next[otherIndex], next[index]]
  void persistOrder(next)
}

function startDrag(link: QuickLink) { draggingId.value = link.id }

function dropLink(target: QuickLink) {
  const sourceId = draggingId.value
  draggingId.value = null
  if (!sourceId || sourceId === target.id) return
  const sourceIndex = links.value.findIndex((item) => item.id === sourceId)
  const targetIndex = links.value.findIndex((item) => item.id === target.id)
  if (sourceIndex < 0 || targetIndex < 0) return
  const next = [...links.value]
  const [moved] = next.splice(sourceIndex, 1)
  next.splice(targetIndex, 0, moved)
  void persistOrder(next)
}

function prepareGroup() {
  groupDialogMode.value = 'create'
  groupDialogOpen.value = true
}

function openRenameGroup(groupName: string) {
  groupDialogMode.value = 'rename'
  groupRenameSource.value = groupName
  groupDialogOpen.value = true
}

async function confirmGroupDialog(nextName: string) {
  groupDialogOpen.value = false
  if (groupDialogMode.value === 'create') {
    form.groupName = nextName
    return
  }
  if (nextName === groupRenameSource.value) return
  const targets = links.value.filter((item) => item.groupName === groupRenameSource.value)
  busy.value = true
  try {
    const updated = await Promise.all(targets.map((item) => putSystemQuickLink(item.id, { groupName: nextName })))
    for (const link of updated) {
      const index = links.value.findIndex((item) => item.id === link.id)
      if (index >= 0) links.value[index] = link
    }
  } catch (cause: any) {
    feedback.error(cause?.response?.data?.detail ?? '分组重命名失败。')
    await load()
  } finally {
    busy.value = false
  }
}

async function confirmRemoveGroup() {
  const groupName = removeGroupTarget.value
  removeGroupTarget.value = null
  if (!groupName) return
  const targets = links.value.filter((item) => item.groupName === groupName)
  busy.value = true
  try {
    const updated = await Promise.all(targets.map((item) => putSystemQuickLink(item.id, { groupName: null })))
    for (const link of updated) {
      const index = links.value.findIndex((item) => item.id === link.id)
      if (index >= 0) links.value[index] = link
    }
  } catch (cause: any) {
    feedback.error(cause?.response?.data?.detail ?? '删除分组失败。')
    await load()
  } finally {
    busy.value = false
  }
}
</script>

<template>
  <main class="unified-page common-links-page">
    <header class="app-page-header common-links-header">
      <div>
        <span class="eyebrow">WORKSPACE</span>
        <h1>常用</h1>
      </div>
      <div class="common-links-header-actions">
        <label class="common-search" aria-label="搜索常用网站">
          <IconSearch :size="17" aria-hidden="true" />
          <input v-model="search" type="search" placeholder="搜索网站" />
        </label>
        <button v-if="isRoot" class="primary-button" type="button" @click="openCreate">
          <IconPlus :size="16" aria-hidden="true" />管理常用网站
        </button>
      </div>
    </header>

    <section class="common-links-body">
      <div v-if="loading" class="common-links-empty">正在加载常用网站…</div>
      <div v-else-if="loadError" class="common-links-empty" role="alert">{{ loadError }}</div>
      <div v-else-if="!filteredGroups.length" class="common-links-empty">
        <IconLink :size="28" aria-hidden="true" />
        <strong>{{ search ? '没有匹配的网站' : '还没有配置常用网站' }}</strong>
        <span>{{ isRoot && !search ? '点击右上角添加第一个网站。' : '系统管理员配置后会显示在这里。' }}</span>
      </div>
      <div v-else class="common-link-groups">
        <section v-for="group in filteredGroups" :key="group.name" class="common-link-group">
          <header>
            <div><IconFolder :size="17" aria-hidden="true" /><h2>{{ group.name }}</h2><span>{{ group.items.length }}</span></div>
            <div v-if="isRoot && group.name !== '未分组'" class="common-group-actions">
              <button type="button" @click="openRenameGroup(group.name)">重命名</button>
              <button type="button" @click="removeGroupTarget = group.name">删除分组</button>
            </div>
          </header>
          <div class="common-link-grid">
            <a v-for="link in group.items" :key="link.id" class="common-link-card" :href="link.url" target="_blank" rel="noopener noreferrer">
              <span class="common-link-icon" aria-hidden="true">{{ link.icon }}</span>
              <span class="common-link-copy"><strong>{{ link.name }}</strong><small v-if="link.description">{{ link.description }}</small><small>{{ domainOf(link.url) }}</small></span>
              <IconExternalLink class="common-link-external" :size="16" aria-hidden="true" />
            </a>
          </div>
        </section>
      </div>
    </section>

    <Teleport to="body">
      <div v-if="managerOpen && isRoot" class="dialog-backdrop" @mousedown.self="managerOpen = false">
        <section class="dialog-card common-manager-dialog" role="dialog" aria-modal="true" aria-labelledby="common-manager-title">
          <header class="dialog-header">
            <div><span class="eyebrow">SYSTEM LINKS</span><h2 id="common-manager-title">管理常用网站</h2></div>
            <button class="icon-action" type="button" aria-label="关闭" @click="managerOpen = false"><IconX :size="18" /></button>
          </header>
          <div class="common-manager-grid">
            <form class="todo-form common-link-form" @submit.prevent="saveLink">
              <label>名称<input v-model="form.name" required maxlength="120" placeholder="例如：GitLab" /></label>
              <label>网址<input v-model="form.url" required type="url" inputmode="url" placeholder="https://" /></label>
              <label>简短说明<textarea v-model="form.description" maxlength="500" rows="3" placeholder="可选，用一句话说明用途" /></label>
              <div class="form-grid">
                <label>图标文字<input v-model="form.icon" maxlength="32" placeholder="留空自动生成" /></label>
                <label>分组<input v-model="form.groupName" maxlength="120" placeholder="例如：开发工具" list="known-group-names" /><datalist id="known-group-names"><option v-for="name in knownGroupNames" :key="name" :value="name" /></datalist></label>
              </div>
              <div class="common-form-actions">
                <button class="secondary-button" type="button" @click="prepareGroup">新建分组</button>
                <span class="spacer" />
                <button v-if="editingId" class="secondary-button" type="button" @click="resetForm">取消编辑</button>
                <button class="primary-button" type="submit" :disabled="busy">{{ editingId ? '保存修改' : '添加网站' }}</button>
              </div>
            </form>
            <div class="common-managed-list">
              <header><strong>网站与顺序</strong><small>拖动或使用箭头调整顺序</small></header>
              <p v-if="!links.length" class="muted-text">还没有常用网站。</p>
              <article v-for="(link, index) in links" :key="link.id" draggable="true" @dragstart="startDrag(link)" @dragover.prevent @drop="dropLink(link)">
                <span class="common-link-icon small" aria-hidden="true">{{ link.icon }}</span>
                <span class="managed-link-name"><strong>{{ link.name }}</strong><small>{{ link.groupName || '未分组' }} · {{ domainOf(link.url) }}</small></span>
                <button type="button" aria-label="上移" :disabled="index === 0 || busy" @click="moveLink(link, -1)"><IconArrowUp :size="15" /></button>
                <button type="button" aria-label="下移" :disabled="index === links.length - 1 || busy" @click="moveLink(link, 1)"><IconArrowDown :size="15" /></button>
                <button type="button" aria-label="编辑" :disabled="busy" @click="editLink(link)"><IconEdit :size="15" /></button>
                <button type="button" aria-label="删除" :disabled="busy" @click="removeTarget = link"><IconTrash :size="15" /></button>
              </article>
            </div>
          </div>
        </section>
      </div>
    </Teleport>

    <ConfirmDialog :open="Boolean(removeTarget)" title="删除常用网站" :message="`确定删除“${removeTarget?.name ?? ''}”吗？`" :danger="true" confirm-label="删除" @close="removeTarget = null" @confirm="confirmRemove" />
    <ConfirmDialog :open="Boolean(removeGroupTarget)" title="删除分组" :message="`删除“${removeGroupTarget ?? ''}”分组后，网站会保留并移到未分组。`" :danger="true" confirm-label="删除分组" @close="removeGroupTarget = null" @confirm="confirmRemoveGroup" />
    <InputDialog
      :open="groupDialogOpen"
      :title="groupDialogMode === 'create' ? '新建分组' : '重命名分组'"
      :label="groupDialogMode === 'create' ? '分组名称' : '新名称'"
      :initial-value="groupDialogMode === 'rename' ? groupRenameSource : ''"
      placeholder="例如：开发工具"
      @close="groupDialogOpen = false"
      @submit="confirmGroupDialog"
    />
  </main>
</template>
