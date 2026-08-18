<script setup lang="ts">
import { IconCheck, IconSearch, IconUsers, IconX } from '@tabler/icons-vue'
import { computed, onBeforeUnmount, onMounted, ref, watch } from 'vue'

import type { TeamMember } from '@/services/api'

const props = withDefaults(defineProps<{
  members: TeamMember[]
  modelValue: string[]
  currentUserId: string
  disabled?: boolean
  compact?: boolean
}>(), { disabled: false, compact: false })

const emit = defineEmits<{ change: [userIds: string[]] }>()
const root = ref<HTMLElement | null>(null)
const open = ref(false)
const query = ref('')
const draft = ref<string[]>([])

const visibleMembers = computed(() => {
  const needle = query.value.trim().toLowerCase()
  if (!needle) return props.members
  return props.members.filter(({ user }) => `${user.nickname} ${user.username}`.toLowerCase().includes(needle))
})
const selectedMembers = computed(() => props.members.filter((member) => props.modelValue.includes(member.userId)))
const buttonLabel = computed(() => {
  if (!selectedMembers.value.length) return '指派给'
  if (selectedMembers.value.length === 1) {
    return selectedMembers.value[0].userId === props.currentUserId ? '我自己' : selectedMembers.value[0].user.nickname
  }
  return `${selectedMembers.value.length} 人`
})

watch(() => props.modelValue, (value) => { if (!open.value) draft.value = [...value] }, { immediate: true })

function show() {
  if (props.disabled) return
  draft.value = [...props.modelValue]
  query.value = ''
  open.value = true
}
function toggle(userId: string) {
  draft.value = draft.value.includes(userId)
    ? draft.value.filter((item) => item !== userId)
    : [...draft.value, userId]
}
function apply() {
  if (!draft.value.length) return
  emit('change', [...draft.value])
  open.value = false
}
function closeOnOutside(event: MouseEvent) {
  if (!root.value?.contains(event.target as Node)) open.value = false
}
onMounted(() => document.addEventListener('click', closeOnOutside))
onBeforeUnmount(() => document.removeEventListener('click', closeOnOutside))
</script>

<template>
  <div ref="root" class="assignee-popover-host" @click.stop>
    <button
      class="assignee-trigger"
      :class="{ compact }"
      type="button"
      :disabled="disabled"
      :aria-expanded="open"
      aria-haspopup="dialog"
      @click="open ? open = false : show()"
    ><IconUsers :size="16" /><span>{{ buttonLabel }}</span></button>
    <section v-if="open" class="assignee-popover" role="dialog" aria-label="指派团队成员">
      <header><strong>指派给</strong><button type="button" aria-label="关闭" @click="open = false"><IconX :size="15" /></button></header>
      <label class="assignee-search"><IconSearch :size="15" /><input v-model="query" placeholder="搜索团队成员" autofocus /></label>
      <div class="assignee-options" role="group" aria-label="团队成员">
        <button
          v-for="member in visibleMembers"
          :key="member.id"
          type="button"
          :class="{ selected: draft.includes(member.userId) }"
          :aria-pressed="draft.includes(member.userId)"
          @click="toggle(member.userId)"
        >
          <span class="assignee-check"><IconCheck v-if="draft.includes(member.userId)" :size="13" /></span>
          <span class="assignee-avatar">{{ member.user.nickname.slice(0, 1).toUpperCase() }}</span>
          <span><strong>{{ member.userId === currentUserId ? '我自己' : member.user.nickname }}</strong><small>@{{ member.user.username }}</small></span>
        </button>
        <p v-if="!visibleMembers.length">没有匹配的成员</p>
      </div>
      <footer><span>已选择 {{ draft.length }} 人</span><button class="primary-button" type="button" :disabled="!draft.length" @click="apply">确定</button></footer>
    </section>
  </div>
</template>
