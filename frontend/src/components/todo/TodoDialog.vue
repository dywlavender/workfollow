<script setup lang="ts">
import dayjs from 'dayjs'
import { IconChevronRight, IconX } from '@tabler/icons-vue'
import { computed, reactive, ref, watch } from 'vue'

import { useDialogEscape } from '@/composables/useDialogEscape'
import { fetchNote, type Todo, type TodoPayload, type TodoPriority, type TodoRecurrenceType, type TodoSourceType } from '@/services/api'
import { dateOnlyDueAt, isDateOnlyDue } from '@/modules/todo/dueDate'
import AssigneePopover from '@/components/task/AssigneePopover.vue'
import type { TeamMember } from '@/services/api'


const props = defineProps<{
  open: boolean
  todo?: Todo | null
  initialTitle?: string
  sourceNoteId?: string | null
  sourceExcerpt?: string | null
  sourceBlockId?: string | null
  sourceType?: TodoSourceType
  initialDueAt?: string | null
  initialListName?: string
  members?: TeamMember[]
  currentUserId?: string
  canAssign?: boolean
}>()
const emit = defineEmits<{ close: []; save: [payload: TodoPayload]; openSource: [noteId: string] }>()
useDialogEscape(() => props.open, () => emit('close'))
const sourceTitle = ref<string | null>(null)
const assigneeIds = ref<string[]>([])

interface FormState {
  title: string
  description: string
  priority: TodoPriority
  dueAt: string
  reminderPreset: string
  customReminderAt: string
  recurrenceType: TodoRecurrenceType
  customFrequency: 'DAILY' | 'WEEKLY' | 'MONTHLY'
  customInterval: number
}

const form = reactive<FormState>({
  title: '', description: '', priority: 'NONE', dueAt: '', reminderPreset: 'NONE',
  customReminderAt: '', recurrenceType: 'NONE', customFrequency: 'WEEKLY', customInterval: 2,
})

const reminderInvalid = computed(() => {
  if (form.reminderPreset !== 'CUSTOM' || !form.dueAt) return false
  if (!form.customReminderAt) return true
  return dayjs(form.customReminderAt).isAfter(dayjs(form.dueAt))
})
const canSubmit = computed(() => form.title.trim() && (form.recurrenceType === 'NONE' || form.dueAt) && !reminderInvalid.value)
const dueDate = computed({
  get: () => form.dueAt ? dayjs(form.dueAt).format('YYYY-MM-DD') : '',
  set: (value: string) => { form.dueAt = value ? `${value}T${dueTime.value || '00:00'}` : '' },
})
const dueTime = computed({
  get: () => form.dueAt && !isDateOnlyDue(form.dueAt) ? dayjs(form.dueAt).format('HH:mm') : '',
  set: (value: string) => { form.dueAt = dueDate.value ? `${dueDate.value}T${value || '00:00'}` : '' },
})

function asInput(value: string | null): string {
  return value ? dayjs(value).format('YYYY-MM-DDTHH:mm') : ''
}

function defaultNewTodoDueAt(): string {
  return dateOnlyDueAt()
}

function detectReminder(todo: Todo): { preset: string; custom: string } {
  if (!todo.reminderAt || !todo.dueAt) return { preset: 'NONE', custom: '' }
  const minutes = dayjs(todo.dueAt).diff(dayjs(todo.reminderAt), 'minute')
  if (minutes === 0) return { preset: 'AT_DUE', custom: '' }
  if (minutes === 10) return { preset: 'MINUS_10', custom: '' }
  if (minutes === 60) return { preset: 'MINUS_60', custom: '' }
  if (minutes === 1440) return { preset: 'MINUS_1440', custom: '' }
  return { preset: 'CUSTOM', custom: asInput(todo.reminderAt) }
}

watch(
  () => [props.open, props.todo] as const,
  () => {
    if (!props.open) return
    const todo = props.todo
    const reminder = todo ? detectReminder(todo) : { preset: 'NONE', custom: '' }
    form.title = todo?.title ?? props.initialTitle ?? ''
    form.description = todo?.description ?? ''
    form.priority = todo?.priority ?? 'NONE'
    // Existing unscheduled tasks must stay unscheduled. A genuinely new task
    // receives today's default date.
    const newTaskDefault = defaultNewTodoDueAt()
    form.dueAt = asInput(todo ? todo.dueAt : (props.initialDueAt ?? newTaskDefault))
    form.reminderPreset = reminder.preset
    form.customReminderAt = reminder.custom
    form.recurrenceType = todo?.recurrenceType ?? 'NONE'
    form.customFrequency = (todo?.recurrenceConfig?.frequency as FormState['customFrequency']) ?? 'WEEKLY'
    form.customInterval = Number(todo?.recurrenceConfig?.interval ?? 2)
    assigneeIds.value = todo?.assignments.map((item) => item.userId)
      ?? (props.currentUserId ? [props.currentUserId] : [])
  },
  { immediate: true },
)

watch(
  () => [props.open, props.todo?.sourceNoteId ?? props.sourceNoteId] as const,
  async ([open, noteId]) => {
    sourceTitle.value = null
    if (!open || !noteId) return
    try {
      sourceTitle.value = (await fetchNote(noteId)).title
    } catch {
      sourceTitle.value = '来源笔记不可用'
    }
  },
  { immediate: true },
)

function buildReminderAt(): string | null {
  if (!form.dueAt || form.reminderPreset === 'NONE') return null
  if (form.reminderPreset === 'CUSTOM') return form.customReminderAt || null
  const minutes = { AT_DUE: 0, MINUS_10: 10, MINUS_60: 60, MINUS_1440: 1440 }[form.reminderPreset] ?? 0
  return dayjs(form.dueAt).subtract(minutes, 'minute').format('YYYY-MM-DDTHH:mm:ss')
}

function buildRecurrenceConfig(): Record<string, number | string> | null {
  if (form.recurrenceType === 'NONE' || !form.dueAt) return null
  if (form.recurrenceType === 'WEEKLY') return { weekday: (dayjs(form.dueAt).day() + 6) % 7 }
  if (form.recurrenceType === 'MONTHLY') return { day: dayjs(form.dueAt).date() }
  if (form.recurrenceType === 'CUSTOM') {
    return { frequency: form.customFrequency, interval: Math.max(1, form.customInterval) }
  }
  return {}
}

function submit() {
  if (!canSubmit.value) return
  const payload: TodoPayload = {
    title: form.title.trim(),
    description: form.description.trim() || null,
    priority: form.priority,
    dueAt: form.dueAt ? dayjs(form.dueAt).format('YYYY-MM-DDTHH:mm:ss') : null,
    reminderAt: buildReminderAt(),
    recurrenceType: form.recurrenceType,
    recurrenceConfig: buildRecurrenceConfig(),
    listName: props.todo?.listName ?? props.initialListName ?? '收集箱',
  }
  const sourceNoteId = props.todo?.sourceNoteId ?? props.sourceNoteId
  const sourceExcerpt = props.todo?.sourceExcerpt ?? props.sourceExcerpt
  if (!props.todo && sourceNoteId) {
    payload.sourceType = props.sourceType ?? 'NOTE'
    payload.sourceNoteId = sourceNoteId
    payload.sourceExcerpt = sourceExcerpt ?? null
    payload.source = {
      resourceType: 'PERSONAL_NOTE',
      resourceId: sourceNoteId,
      blockId: props.sourceBlockId ?? null,
      excerpt: sourceExcerpt ?? null,
    }
  }
  if (props.canAssign && assigneeIds.value.length) payload.assigneeIds = assigneeIds.value
  emit('save', payload)
}
</script>

<template>
  <Teleport to="body">
    <div v-if="open" class="dialog-backdrop" role="presentation" @mousedown.self="emit('close')">
      <section class="dialog-card" role="dialog" aria-modal="true" aria-labelledby="todo-dialog-title">
        <header class="dialog-header">
          <div>
            <span class="eyebrow">待办详情</span>
            <h2 id="todo-dialog-title">{{ todo ? '编辑待办' : '新建待办' }}</h2>
          </div>
          <button class="icon-action" type="button" aria-label="关闭" @click="emit('close')"><IconX :size="18" /></button>
        </header>
        <form class="todo-form" @submit.prevent="submit">
          <label>标题<input v-model="form.title" required maxlength="500" autofocus /></label>
          <label>描述<textarea v-model="form.description" rows="3" /></label>
          <div v-if="todo?.sourceNoteId || sourceNoteId" class="todo-source-card">
            <span>来源笔记</span>
            <button type="button" @click="emit('openSource', (todo?.sourceNoteId ?? sourceNoteId)!)">{{ sourceTitle ?? '正在读取…' }} <IconChevronRight :size="16" aria-hidden="true" /></button>
            <p v-if="todo?.sourceExcerpt || sourceExcerpt">“{{ todo?.sourceExcerpt ?? sourceExcerpt }}”</p>
          </div>
          <div class="form-grid">
            <label>截止日期<input v-model="dueDate" type="date" /></label>
            <label>时间（可选）<input v-model="dueTime" type="time" :disabled="!dueDate" /></label>
          </div>
          <div class="form-grid">
            <label>优先级
              <select v-model="form.priority">
                <option value="NONE">无</option><option value="LOW">低</option>
                <option value="MEDIUM">中</option><option value="HIGH">高</option>
              </select>
            </label>
            <label>提醒
              <select v-model="form.reminderPreset" :disabled="!form.dueAt">
                <option value="NONE">不提醒</option><option value="AT_DUE">到期时</option>
                <option value="MINUS_10">提前10分钟</option><option value="MINUS_60">提前1小时</option>
                <option value="MINUS_1440">提前1天</option><option value="CUSTOM">自定义</option>
              </select>
            </label>
          </div>
          <label>重复
              <select v-model="form.recurrenceType">
                <option value="NONE">不重复</option><option value="DAILY">每天</option>
                <option value="WEEKLY">每周</option><option value="MONTHLY">每月</option>
                <option value="CUSTOM">自定义</option>
              </select>
          </label>
          <label v-if="form.reminderPreset === 'CUSTOM'">自定义提醒时间
            <input v-model="form.customReminderAt" type="datetime-local" />
          </label>
          <p v-if="reminderInvalid" class="inline-error">提醒时间不能晚于截止时间。</p>
          <div v-if="form.recurrenceType === 'CUSTOM'" class="form-grid">
            <label>频率<select v-model="form.customFrequency"><option value="DAILY">天</option><option value="WEEKLY">周</option><option value="MONTHLY">月</option></select></label>
            <label>间隔<input v-model.number="form.customInterval" min="1" max="99" type="number" /></label>
          </div>
          <p v-if="form.recurrenceType !== 'NONE' && !form.dueAt" class="inline-error">重复待办必须设置首次执行时间。</p>
          <div v-if="canAssign && currentUserId" class="todo-assignee-field">
            <span>指派成员</span>
            <AssigneePopover :members="members ?? []" :model-value="assigneeIds" :current-user-id="currentUserId" @change="assigneeIds = $event" />
          </div>
          <footer class="dialog-actions">
            <button class="secondary-button" type="button" @click="emit('close')">取消</button>
            <button class="primary-button" type="submit" :disabled="!canSubmit">保存</button>
          </footer>
        </form>
      </section>
    </div>
  </Teleport>
</template>
