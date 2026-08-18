<script setup lang="ts" generic="T extends GroupableTask">
import dayjs from 'dayjs'
import { IconChevronDown } from '@tabler/icons-vue'
import { computed } from 'vue'

import { isDueOverdue } from '@/modules/todo/dueDate'

export interface GroupableTask {
  id: string
  dueAt: string | null
  status: string
  updatedAt: string
  myAssignment?: { status: string } | null
}

type GroupTone = 'overdue' | 'normal' | 'terminal'
type TaskGroup = { key: string; label: string; tone: GroupTone; items: T[] }

const props = withDefaults(defineProps<{
  items: T[]
  activeStatuses?: string[]
  terminalLabel?: string
  reverse?: boolean
  assignmentStatus?: boolean
  sortMode?: 'grouped' | 'due-desc'
}>(), {
  activeStatuses: () => ['TODO', 'ACTIVE'],
  terminalLabel: '已完成',
  reverse: false,
  assignmentStatus: false,
  sortMode: 'grouped',
})

defineSlots<{
  item(props: { item: T; group: TaskGroup }): unknown
  empty(): unknown
}>()

const groups = computed<TaskGroup[]>(() => {
  if (props.sortMode === 'due-desc') {
    const items = [...props.items].sort((a, b) => {
      if (!a.dueAt && !b.dueAt) return dayjs(b.updatedAt).valueOf() - dayjs(a.updatedAt).valueOf()
      if (!a.dueAt) return 1
      if (!b.dueAt) return -1
      const dueDifference = dayjs(b.dueAt).valueOf() - dayjs(a.dueAt).valueOf()
      return dueDifference || dayjs(b.updatedAt).valueOf() - dayjs(a.updatedAt).valueOf()
    })
    return [{ key: 'all', label: '所有任务', tone: 'normal', items: props.reverse ? items.reverse() : items }]
  }
  const itemStatus = (item: T) => props.assignmentStatus && item.myAssignment
    ? (item.myAssignment.status === 'DONE' ? 'DONE' : 'TODO')
    : item.status
  const active = props.items.filter((item) => props.activeStatuses.includes(itemStatus(item)))
  const terminal = props.items.filter((item) => !props.activeStatuses.includes(itemStatus(item)))
  const tomorrow = dayjs().add(1, 'day')
  const buckets: TaskGroup[] = [
    { key: 'overdue', label: '逾期', tone: 'overdue', items: active.filter((item) => isDueOverdue(item.dueAt)) },
    { key: 'today', label: '今天', tone: 'normal', items: active.filter((item) => item.dueAt && !isDueOverdue(item.dueAt) && dayjs(item.dueAt).isSame(dayjs(), 'day')) },
    { key: 'tomorrow', label: '明天', tone: 'normal', items: active.filter((item) => item.dueAt && dayjs(item.dueAt).isSame(tomorrow, 'day')) },
    { key: 'future', label: '未来', tone: 'normal', items: active.filter((item) => item.dueAt && dayjs(item.dueAt).isAfter(tomorrow, 'day')) },
    { key: 'unscheduled', label: '未安排', tone: 'normal', items: active.filter((item) => !item.dueAt) },
  ]
  if (terminal.length) {
    buckets.push({
      key: 'terminal',
      label: props.terminalLabel,
      tone: 'terminal',
      items: [...terminal].sort((a, b) => dayjs(b.updatedAt).valueOf() - dayjs(a.updatedAt).valueOf()),
    })
  }
  return buckets.filter((group) => group.items.length).map((group) => ({
    ...group,
    items: props.reverse ? [...group.items].reverse() : group.items,
  }))
})
</script>

<template>
  <div v-if="groups.length" class="task-list-grouped">
    <section v-for="group in groups" :key="group.key" class="task-date-group" :class="`task-group-${group.tone}`">
      <header class="task-date-heading" :class="group.tone">
        <IconChevronDown :size="15" :stroke-width="1.8" aria-hidden="true" />
        <strong>{{ group.label }}</strong>
        <span>{{ group.items.length }}</span>
      </header>
      <template v-for="item in group.items" :key="item.id"><slot name="item" :item="item" :group="group" /></template>
    </section>
  </div>
  <slot v-else name="empty" />
</template>
