<script setup lang="ts">
import dayjs from 'dayjs'
import {
  IconBell, IconCalendar, IconCheck, IconChevronRight, IconClock, IconCopy,
  IconDots, IconFlag, IconLink, IconList, IconRepeat, IconTag, IconTrash, IconUsers, IconX,
} from '@tabler/icons-vue'
import { nextTick, onBeforeUnmount, onMounted, ref } from 'vue'

import ConfirmDialog from '@/components/ConfirmDialog.vue'
import AssigneePopover from '@/components/task/AssigneePopover.vue'
import TaskRow from '@/components/task/TaskRow.vue'
import { isDateOnlyDue, isDueOverdue } from '@/modules/todo/dueDate'
import type { TeamMember, Todo, TodoPayload } from '@/services/api'

const props = withDefaults(defineProps<{
  todo: Todo
  selected?: boolean
  members?: TeamMember[]
  currentUserId?: string
}>(), { members: () => [], currentUserId: '' })
const emit = defineEmits<{
  toggle: [todo: Todo]
  edit: [todo: Todo]
  editDate: [todo: Todo, anchor?: Pick<DOMRect, 'left' | 'bottom'>]
  editPriority: [todo: Todo]
  update: [todo: Todo, payload: Partial<TodoPayload>]
  duplicate: [todo: Todo]
  copyLink: [todo: Todo]
  assign: [todo: Todo, userIds: string[]]
  abandon: [todo: Todo]
  remove: [todo: Todo]
}>()

const removeDialogOpen = ref(false)
const contextOpen = ref(false)
const submenu = ref<'list' | 'tags' | null>(null)
const tagInput = ref<HTMLInputElement | null>(null)
const newTag = ref('')
const menuX = ref(0)
const menuY = ref(0)
const lists = ['收集箱', '工作', '个人', '学习']
const executionDone = () => props.todo.myAssignment?.status === 'DONE' || (!props.todo.myAssignment && props.todo.status === 'DONE')

function dueLabel(todo: Todo) {
  if (!todo.dueAt) return '无日期'
  const due = dayjs(todo.dueAt)
  const withTime = !isDateOnlyDue(todo.dueAt)
  let label = due.isSame(dayjs(), 'day') ? (withTime ? due.format('HH:mm') : '今天')
    : due.isSame(dayjs().subtract(1, 'day'), 'day') ? '昨天'
      : due.isSame(dayjs().add(1, 'day'), 'day') ? `明天${withTime ? ` ${due.format('HH:mm')}` : ''}`
        : due.format(withTime ? 'M月D日 HH:mm' : 'M月D日')
  if (todo.dueEndAt && !dayjs(todo.dueEndAt).isSame(due, 'day')) label += ` - ${dayjs(todo.dueEndAt).format('M月D日')}`
  return label
}

function openContext(event: MouseEvent) {
  menuX.value = Math.max(8, Math.min(window.innerWidth - 240, event.clientX))
  menuY.value = Math.max(8, Math.min(window.innerHeight - 438, event.clientY))
  contextOpen.value = true
  submenu.value = null
  emit('edit', props.todo)
}

function openMore(event: MouseEvent) {
  const rect = (event.currentTarget as HTMLElement).getBoundingClientRect()
  openContext(new MouseEvent('contextmenu', { clientX: rect.right + 4, clientY: rect.top }))
}

function closeContext() { contextOpen.value = false; submenu.value = null }
function openSubmenu(value: 'list' | 'tags') {
  submenu.value = submenu.value === value ? null : value
  if (value === 'tags') void nextTick(() => tagInput.value?.focus())
}
function setList(listName: string) { emit('update', props.todo, { listName }); closeContext() }
function addTag() {
  const value = newTag.value.trim().replace(/^#/, '')
  if (!value || props.todo.tags.includes(value)) return
  emit('update', props.todo, { tags: [...props.todo.tags, value] })
  newTag.value = ''
  closeContext()
}
function removeTag(value: string) { emit('update', props.todo, { tags: props.todo.tags.filter((tag) => tag !== value) }); closeContext() }
function confirmRemove() { removeDialogOpen.value = false; emit('remove', props.todo) }
function requestDateEdit(event: MouseEvent) {
  const anchor = (event.currentTarget as HTMLElement).getBoundingClientRect()
  emit('editDate', props.todo, anchor)
}

onMounted(() => document.addEventListener('click', closeContext))
onBeforeUnmount(() => document.removeEventListener('click', closeContext))
</script>

<template>
  <TaskRow
    class="todo-row"
    :data-todo-id="todo.id"
    :title="todo.title"
    :completed="executionDone()"
    :terminal="executionDone() || todo.status === 'ABANDONED'"
    :disabled="!todo.permissions.completable"
    :selected="selected"
    :class="{ done: todo.status === 'DONE', abandoned: todo.status === 'ABANDONED', overdue: isDueOverdue(todo.dueAt) && todo.status === 'TODO' }"
    @select="emit('edit', todo)"
    @toggle="emit('toggle', todo)"
    @context="openContext"
  >
    <template #meta>
      <span class="todo-meta">
        <span>{{ todo.listName }}</span>
        <span v-for="tag in todo.tags" :key="tag">#{{ tag }}</span>
        <span v-if="todo.priority !== 'NONE'" class="meta-chip" :class="`priority-${todo.priority.toLowerCase()}`" :title="`${todo.priority} 优先级`"><IconFlag :size="12" /></span>
        <span v-if="todo.recurrenceType !== 'NONE'" class="meta-chip" title="重复任务"><IconRepeat :size="12" /></span>
        <span v-if="todo.reminderAt" class="meta-chip" title="已设置提醒"><IconBell :size="12" /></span>
        <span v-if="todo.teamId && todo.creatorId !== currentUserId" class="team-source-label"><IconUsers :size="12" />{{ todo.creator.nickname }}分配</span>
        <span v-else-if="todo.teamId && todo.totalAssignments" class="team-source-label"><IconUsers :size="12" />{{ todo.completedAssignments }}/{{ todo.totalAssignments }}</span>
      </span>
    </template>
    <template #trailing><button class="todo-time" :class="{ today: todo.dueAt && dayjs(todo.dueAt).isSame(dayjs(), 'day') }" type="button" title="设置日期" @click.stop="requestDateEdit"><IconClock v-if="todo.dueAt" :size="13" /><IconCalendar v-else :size="13" />{{ dueLabel(todo) }}</button></template>
    <template #actions>
      <AssigneePopover
        v-if="todo.permissions.assignable && currentUserId"
        :members="members"
        :model-value="todo.assignments.map((item) => item.userId)"
        :current-user-id="currentUserId"
        compact
        @change="emit('assign', todo, $event)"
      />
      <button type="button" aria-label="更多任务操作" title="更多" @click.stop="openMore"><IconDots :size="17" /></button>
    </template>
  </TaskRow>

  <section v-if="contextOpen" class="task-row-context-menu" :style="{ left: `${menuX}px`, top: `${menuY}px` }" role="menu" aria-label="任务操作" @click.stop>
      <button v-if="todo.permissions.editable" type="button" @click="emit('editDate', todo); closeContext()"><IconCalendar :size="16" />设置日期</button>
      <button v-if="todo.permissions.editable" type="button" @click="emit('editDate', todo); closeContext()"><IconBell :size="16" />设置提醒</button>
      <button v-if="todo.permissions.editable" type="button" @click="emit('editDate', todo); closeContext()"><IconRepeat :size="16" />设置重复</button>
      <button v-if="todo.permissions.editable" type="button" @click="emit('editPriority', todo); closeContext()"><IconFlag :size="16" />优先级</button>
      <button v-if="todo.permissions.editable" type="button" @click="openSubmenu('list')"><IconList :size="16" />移动到清单<IconChevronRight class="context-chevron" :size="14" /></button>
      <div v-if="submenu === 'list'" class="task-context-submenu">
        <button v-for="list in lists" :key="list" type="button" @click="setList(list)"><IconCheck :class="{ invisible: todo.listName !== list }" :size="14" />{{ list }}</button>
      </div>
      <button v-if="todo.permissions.editable" type="button" @click="openSubmenu('tags')"><IconTag :size="16" />添加标签<IconChevronRight class="context-chevron" :size="14" /></button>
      <div v-if="submenu === 'tags'" class="task-context-submenu tag-editor">
        <button v-for="tag in todo.tags" :key="tag" type="button" :title="`移除 ${tag}`" @click="removeTag(tag)"><IconCheck :size="14" />#{{ tag }}</button>
        <form @submit.prevent="addTag"><input ref="tagInput" v-model="newTag" maxlength="24" placeholder="输入标签后回车" /></form>
      </div>
      <span />
      <button v-if="todo.permissions.completable" type="button" @click="emit('toggle', todo); closeContext()">
        <IconCheck :size="16" />{{ executionDone() ? '恢复任务' : '标记完成' }}
      </button>
      <button v-if="todo.permissions.deletable && todo.status === 'TODO'" type="button" @click="emit('abandon', todo); closeContext()"><IconX :size="16" />放弃任务</button>
      <button type="button" @click="emit('duplicate', todo); closeContext()"><IconCopy :size="16" />复制任务</button>
      <button type="button" @click="emit('copyLink', todo); closeContext()"><IconLink :size="16" />复制任务链接</button>
      <button v-if="todo.permissions.deletable" class="danger" type="button" @click="removeDialogOpen = true; closeContext()"><IconTrash :size="16" />删除任务</button>
  </section>
  <ConfirmDialog :open="removeDialogOpen" title="删除待办" :message="`确定删除“${todo.title}”吗？`" confirm-label="删除" :danger="true" @close="removeDialogOpen = false" @confirm="confirmRemove" />
</template>
