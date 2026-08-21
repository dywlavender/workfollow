<script setup lang="ts">
import { IconChevronRight } from '@tabler/icons-vue'
import { ref } from 'vue'

import PersonalTaskDetail from '@/components/todo/TaskDetail.vue'
import type { TeamMember, Todo, TodoPayload } from '@/services/api'

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
  updatePersonal: [todoId: string, payload: Partial<TodoPayload>, quiet?: boolean, settled?: (ok: boolean) => void]
  assignPersonal: [todo: Todo, userIds: string[]]
  openSource: [noteId: string, blockId?: string | null]
}>()

const personalDetail = ref<InstanceType<typeof PersonalTaskDetail> | null>(null)

function openDatePanel(anchor?: Pick<DOMRect, 'left' | 'bottom'>) { personalDetail.value?.openDatePanel(anchor) }
function openPriorityPanel() { personalDetail.value?.openPriorityPanel() }
function forwardOpenSource(noteId: string, blockId?: string | null) { emit('openSource', noteId, blockId) }
defineExpose({ openDatePanel, openPriorityPanel })
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
    @update="(id, payload, quiet, settled) => emit('updatePersonal', id, payload, quiet, settled)"
    @assign="(todo, ids) => emit('assignPersonal', todo, ids)"
    @open-source="forwardOpenSource"
  />

  <aside v-else class="task-detail task-detail-empty" aria-label="任务详情">
    <div><IconChevronRight :size="24" /><strong>选择一个任务</strong><p>任务详情会显示在这里。</p></div>
    <div class="empty-hints" aria-label="快捷键">
      <span><kbd>⌘</kbd><kbd>N</kbd> 新建任务</span>
      <span><kbd>↑</kbd><kbd>↓</kbd> 切换任务</span>
      <span><kbd>⌘</kbd><kbd>/</kbd> 查看全部</span>
    </div>
  </aside>
</template>
