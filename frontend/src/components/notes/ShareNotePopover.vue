<script setup lang="ts">
import { IconSearch, IconShare, IconX } from '@tabler/icons-vue'
import { computed, ref, watch } from 'vue'

import { useDialogEscape } from '@/composables/useDialogEscape'
import type { TeamMember } from '@/services/api'

const props = defineProps<{
  open: boolean
  members: TeamMember[]
  modelValue: string[]
  currentUserId: string
  saving?: boolean
}>()
const emit = defineEmits<{ close: []; save: [userIds: string[]] }>()
useDialogEscape(() => props.open, () => emit('close'))
const query = ref('')
const selected = ref<string[]>([])

watch(() => props.open, (open) => {
  if (open) {
    selected.value = [...props.modelValue]
    query.value = ''
  }
})

const available = computed(() => props.members.filter((member) => {
  if (member.userId === props.currentUserId || member.status !== 'ACTIVE') return false
  const needle = query.value.trim().toLowerCase()
  return !needle || member.user.nickname.toLowerCase().includes(needle) || member.user.username.toLowerCase().includes(needle)
}))

function toggle(userId: string) {
  selected.value = selected.value.includes(userId)
    ? selected.value.filter((id) => id !== userId)
    : [...selected.value, userId]
}
</script>

<template>
  <Teleport to="body">
    <div v-if="open" class="dialog-backdrop" @mousedown.self="emit('close')">
      <section class="note-collab-dialog share-note-dialog" role="dialog" aria-modal="true" aria-labelledby="share-note-title">
        <header><div><span class="eyebrow">READ ONLY</span><h2 id="share-note-title">分享笔记</h2></div><button type="button" aria-label="关闭" @click="emit('close')"><IconX :size="18" /></button></header>
        <label class="note-member-search"><IconSearch :size="16" /><input v-model="query" placeholder="搜索团队成员" autofocus /></label>
        <div class="note-member-options">
          <label v-for="member in available" :key="member.userId">
            <input type="checkbox" :checked="selected.includes(member.userId)" @change="toggle(member.userId)" />
            <span class="member-avatar">{{ member.user.nickname.slice(0, 1).toUpperCase() }}</span>
            <span><strong>{{ member.user.nickname }}</strong><small>@{{ member.user.username }}</small></span>
          </label>
          <p v-if="!available.length" class="muted-text">没有匹配的团队成员</p>
        </div>
        <footer><span>已分享给 {{ selected.length }} 人</span><div><button class="secondary-button" type="button" @click="emit('close')">取消</button><button class="primary-button" type="button" :disabled="saving" @click="emit('save', selected)"><IconShare :size="15" />确定</button></div></footer>
      </section>
    </div>
  </Teleport>
</template>
