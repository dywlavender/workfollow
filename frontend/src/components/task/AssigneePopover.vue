<script setup lang="ts">
import { IconCheck, IconSearch, IconUsers, IconX } from '@tabler/icons-vue'
import { computed, nextTick, onBeforeUnmount, onMounted, ref, watch } from 'vue'

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
const trigger = ref<HTMLButtonElement | null>(null)
const popover = ref<HTMLElement | null>(null)
const popoverStyle = ref<Record<string, string>>({})
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

function close() {
  open.value = false
  popoverStyle.value = {}
}

function positionPopover() {
  if (!open.value || !trigger.value || !popover.value) return
  const triggerRect = trigger.value.getBoundingClientRect()
  const popoverRect = popover.value.getBoundingClientRect()
  const viewportMargin = 14
  const gap = 7
  const left = Math.max(
    viewportMargin,
    Math.min(
      triggerRect.right - popoverRect.width,
      window.innerWidth - popoverRect.width - viewportMargin,
    ),
  )
  let top = triggerRect.bottom + gap
  if (top + popoverRect.height > window.innerHeight - viewportMargin) {
    top = triggerRect.top - popoverRect.height - gap
  }
  top = Math.max(viewportMargin, Math.min(top, window.innerHeight - popoverRect.height - viewportMargin))
  // 定位完成后才显形(基础态 visibility:hidden),中间态不会闪现在视口左上角。
  popoverStyle.value = { left: `${left}px`, top: `${top}px`, visibility: 'visible' }
}

async function show() {
  if (props.disabled) return
  draft.value = [...props.modelValue]
  query.value = ''
  open.value = true
  await nextTick()
  positionPopover()
}
function toggle(userId: string) {
  draft.value = draft.value.includes(userId)
    ? draft.value.filter((item) => item !== userId)
    : [...draft.value, userId]
}
function apply() {
  if (!draft.value.length) return
  emit('change', [...draft.value])
  close()
}
function closeOnOutside(event: MouseEvent) {
  const target = event.target as Node
  if (!root.value?.contains(target) && !popover.value?.contains(target)) close()
}
function repositionOnViewportChange() {
  positionPopover()
}
watch([query, () => visibleMembers.value.length], () => {
  if (open.value) void nextTick(positionPopover)
})
onMounted(() => {
  document.addEventListener('click', closeOnOutside)
  window.addEventListener('resize', repositionOnViewportChange)
  window.addEventListener('scroll', repositionOnViewportChange, true)
})
onBeforeUnmount(() => {
  document.removeEventListener('click', closeOnOutside)
  window.removeEventListener('resize', repositionOnViewportChange)
  window.removeEventListener('scroll', repositionOnViewportChange, true)
})
</script>

<template>
  <div ref="root" class="assignee-popover-host" @click.stop>
    <button
      ref="trigger"
      class="assignee-trigger"
      :class="{ compact }"
      type="button"
      :disabled="disabled"
      :aria-expanded="open"
      aria-haspopup="dialog"
      @click="open ? close() : show()"
    ><IconUsers :size="16" /><span>{{ buttonLabel }}</span></button>
  </div>

  <Teleport to="body">
    <section v-if="open" ref="popover" class="assignee-popover" :style="popoverStyle" role="dialog" aria-label="指派团队成员" @click.stop>
      <header><strong>指派给</strong><button type="button" aria-label="关闭" @click="close"><IconX :size="15" /></button></header>
      <label class="assignee-search"><IconSearch :size="15" /><input v-model="query" placeholder="搜索团队成员" autofocus /></label>
      <div class="assignee-options" role="group" aria-label="团队成员">
        <button
          v-for="member in visibleMembers"
          :key="member.id"
          class="assignee-option"
          type="button"
          :class="{ selected: draft.includes(member.userId) }"
          :aria-pressed="draft.includes(member.userId)"
          :aria-label="`指派给 ${member.user.username}${member.user.nickname ? `（${member.user.nickname}）` : ''}`"
          @click="toggle(member.userId)"
        >
          <span class="assignee-check"><IconCheck v-if="draft.includes(member.userId)" :size="13" /></span>
          <span class="assignee-avatar">{{ member.user.nickname.slice(0, 1).toUpperCase() }}</span>
          <span class="assignee-identity" :title="`${member.user.username}${member.user.nickname ? ` · ${member.user.nickname}` : ''}`"><strong>{{ member.user.username }}</strong><small>{{ member.userId === currentUserId ? '我自己 · ' : '' }}{{ member.user.nickname || '未设置昵称' }}</small></span>
        </button>
        <p v-if="!visibleMembers.length">没有匹配的成员</p>
      </div>
      <footer><span>已选择 {{ draft.length }} 人</span><button class="primary-button" type="button" :disabled="!draft.length" @click="apply">确定</button></footer>
    </section>
  </Teleport>
</template>
