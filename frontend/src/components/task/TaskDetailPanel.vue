<script setup lang="ts">
import { IconChevronRight } from '@tabler/icons-vue'
import { defineAsyncComponent, ref } from 'vue'

import type { TeamMember, Todo } from '@/services/api'

const PersonalTaskDetail = defineAsyncComponent(() => import('@/components/todo/TaskDetail.vue'))

const props = defineProps<{
  todo?: Todo | null
  updating?: boolean
  members?: TeamMember[]
  currentUserId?: string
}>()

const emit = defineEmits<{
  close: []
  togglePersonal: [todo: Todo]
  removePersonal: [todo: Todo]
  assignPersonal: [todo: Todo, userIds: string[]]
  openSource: [noteId: string, blockId?: string | null]
  openTask: [taskId: string]
}>()

const personalDetail = ref<InstanceType<typeof PersonalTaskDetail> | null>(null)

function openDatePanel(anchor?: Pick<DOMRect, 'left' | 'bottom'>) { personalDetail.value?.openDatePanel(anchor) }
function openPriorityPanel() { personalDetail.value?.openPriorityPanel() }
function flushAndWaitForProjection(timeoutMs?: number) { return personalDetail.value?.flushAndWaitForProjection(timeoutMs) }
function forwardOpenSource(noteId: string, blockId?: string | null) { emit('openSource', noteId, blockId) }
function forwardOpenTask(taskId: string) { emit('openTask', taskId) }
defineExpose({ openDatePanel, openPriorityPanel, flushAndWaitForProjection })
</script>

<template>
  <PersonalTaskDetail
    v-if="todo"
    ref="personalDetail"
    :todo="todo ?? null"
    :updating="updating"
    :members="members ?? []"
    :current-user-id="currentUserId ?? ''"
    @close="emit('close')"
    @toggle="emit('togglePersonal', $event)"
    @remove="emit('removePersonal', $event)"
    @assign="(todo, ids) => emit('assignPersonal', todo, ids)"
    @open-source="forwardOpenSource"
    @open-task="forwardOpenTask"
  />

  <aside v-else class="task-detail task-detail-empty" aria-label="任务详情">
    <div><IconChevronRight :size="24" /><strong>选择一个任务</strong><p>任务详情会显示在这里。</p></div>
  </aside>
</template>
