<script setup lang="ts">
import { IconSearch, IconShare, IconX } from '@tabler/icons-vue'
import { computed, ref, watch } from 'vue'

import { useDialogEscape } from '@/composables/useDialogEscape'
import type { NoteShare, NoteSharePermission, TeamMember } from '@/services/api'

const props = defineProps<{
  open: boolean
  members: TeamMember[]
  shares: NoteShare[]
  modelValue: string[]
  currentUserId: string
  saving?: boolean
}>()
const emit = defineEmits<{
  close: []
  save: [userIds: string[], permission: NoteSharePermission]
  changePermission: [shareId: string, permission: NoteSharePermission]
}>()
useDialogEscape(() => props.open, () => emit('close'))
const query = ref('')
const selected = ref<string[]>([])
const newMemberPermission = ref<NoteSharePermission>('READ_ONLY')

// 弹窗打开期间已分享列表可能才到位（或被刷新）：勾选要跟随 modelValue
// 重新同步，否则会停留在打开瞬间的空勾选状态。
watch(() => [props.open, props.modelValue] as const, ([open]) => {
  if (open) {
    selected.value = [...props.modelValue]
    newMemberPermission.value = 'READ_ONLY'
    query.value = ''
  }
})

const available = computed(() => props.members.filter((member) => {
  if (member.userId === props.currentUserId || member.status !== 'ACTIVE') return false
  const needle = query.value.trim().toLowerCase()
  return !needle || member.user.nickname.toLowerCase().includes(needle) || member.user.username.toLowerCase().includes(needle)
}))

const activeShareByUser = computed(() => {
  const map = new Map<string, NoteShare>()
  for (const share of props.shares) {
    if (share.status === 'ACTIVE') map.set(share.sharedWithUserId, share)
  }
  return map
})

function toggle(userId: string) {
  selected.value = selected.value.includes(userId)
    ? selected.value.filter((id) => id !== userId)
    : [...selected.value, userId]
}

function onPermissionChange(share: NoteShare, event: Event) {
  const value = (event.target as HTMLSelectElement).value as NoteSharePermission
  if (value !== share.permission) emit('changePermission', share.id, value)
}
</script>

<template>
  <Teleport to="body">
    <div v-if="open" class="dialog-backdrop" @mousedown.self="emit('close')">
      <section class="note-collab-dialog share-note-dialog" role="dialog" aria-modal="true" aria-labelledby="share-note-title">
        <header><div><span class="eyebrow">共享设置</span><h2 id="share-note-title">分享笔记</h2></div><button type="button" aria-label="关闭" @click="emit('close')"><IconX :size="18" /></button></header>
        <label class="note-member-search"><IconSearch :size="16" /><input v-model="query" placeholder="搜索团队成员" autofocus /></label>
        <div class="share-permission-radio" role="radiogroup" aria-label="新成员权限">
          <span>新成员权限</span>
          <label><input v-model="newMemberPermission" type="radio" value="READ_ONLY" />只读</label>
          <label><input v-model="newMemberPermission" type="radio" value="EDITABLE" />可编辑</label>
        </div>
        <div class="note-member-options">
          <div v-for="member in available" :key="member.userId" class="note-member-row">
            <label class="note-member-main">
              <input type="checkbox" :checked="selected.includes(member.userId)" @change="toggle(member.userId)" />
              <span class="member-avatar">{{ member.user.nickname.slice(0, 1).toUpperCase() }}</span>
              <span><strong>{{ member.user.nickname }}</strong><small>@{{ member.user.username }}</small></span>
            </label>
            <select
              v-if="activeShareByUser.get(member.userId)"
              class="share-permission-select"
              :aria-label="`${member.user.nickname} 的共享权限`"
              :value="activeShareByUser.get(member.userId)!.permission"
              @change="onPermissionChange(activeShareByUser.get(member.userId)!, $event)"
            >
              <option value="READ_ONLY">只读</option>
              <option value="EDITABLE">可编辑</option>
            </select>
          </div>
          <p v-if="!available.length" class="muted-text">没有匹配的团队成员</p>
        </div>
        <footer><span>已分享给 {{ selected.length }} 人</span><div><button class="secondary-button" type="button" @click="emit('close')">取消</button><button class="primary-button" type="button" :disabled="saving" @click="emit('save', selected, newMemberPermission)"><IconShare :size="15" />确定</button></div></footer>
      </section>
    </div>
  </Teleport>
</template>
