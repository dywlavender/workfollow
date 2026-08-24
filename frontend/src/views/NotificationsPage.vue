<script setup lang="ts">
import { onActivated, onMounted, ref } from 'vue'
import { useRouter } from 'vue-router'
import { IconBell, IconCheck, IconTrash } from '@tabler/icons-vue'

import ActionFeedback from '@/components/ActionFeedback.vue'
import { deleteAllNotifications, deleteNotification, fetchNotifications, markAllNotificationsRead, markNotificationRead, type Notification } from '@/services/api'
import { useWorkspaceStore } from '@/stores/workspace'

const notifications = ref<Notification[]>([])
const router = useRouter()
const workspace = useWorkspaceStore()
const loading = ref(true)
const hasLoaded = ref(false)
const error = ref('')
const actionError = ref('')
const bulkBusy = ref(false)

function formatTime(value: string) {
  return new Intl.DateTimeFormat('zh-CN', { month: 'short', day: 'numeric', hour: '2-digit', minute: '2-digit' }).format(new Date(value))
}

async function load() {
  loading.value = true
  error.value = ''
  try {
    notifications.value = await fetchNotifications()
  } catch (cause: any) {
    error.value = cause?.response?.data?.detail ?? '无法读取通知。'
  } finally {
    loading.value = false
    hasLoaded.value = true
  }
}

async function read(notification: Notification) {
  try {
    actionError.value = ''
    if (!notification.readAt) {
      await markNotificationRead(notification.id)
      notification.readAt = new Date().toISOString()
    }
    const taskId = typeof notification.dataJson.taskId === 'string'
      ? notification.dataJson.taskId
      : typeof notification.dataJson.teamTaskId === 'string' ? notification.dataJson.teamTaskId : null
    if (taskId) await router.push({ path: '/todos', query: { view: 'assigned-to-me', todo: taskId } })
    const submissionId = typeof notification.dataJson.submissionId === 'string' ? notification.dataJson.submissionId : null
    if (submissionId) {
      const teamId = typeof notification.dataJson.teamId === 'string' ? notification.dataJson.teamId : null
      if (teamId) workspace.selectTeam(teamId)
      const review = notification.type === 'TEAM_NOTE_SUBMITTED'
      await router.push({ path: '/notes', query: { view: review ? 'review' : 'submissions', submission: submissionId } })
    }
  } catch (cause: any) {
    actionError.value = cause?.response?.data?.detail ?? '通知处理失败，请稍后重试。'
  }
}

async function readAll() {
  if (bulkBusy.value) return
  bulkBusy.value = true
  try {
    actionError.value = ''
    await markAllNotificationsRead()
    notifications.value.forEach((notification) => { notification.readAt = notification.readAt ?? new Date().toISOString() })
  } catch (cause: any) {
    actionError.value = cause?.response?.data?.detail ?? '标记已读失败。'
  } finally {
    bulkBusy.value = false
  }
}

async function remove(notification: Notification) {
  try {
    actionError.value = ''
    await deleteNotification(notification.id)
    notifications.value = notifications.value.filter((item) => item.id !== notification.id)
  } catch (cause: any) {
    actionError.value = cause?.response?.data?.detail ?? '删除通知失败。'
  }
}

async function clearAll() {
  if (!notifications.value.length || !window.confirm('确定清空全部通知吗？清空后无法恢复。')) return
  if (bulkBusy.value) return
  bulkBusy.value = true
  try {
    actionError.value = ''
    await deleteAllNotifications()
    notifications.value = []
  } catch (cause: any) {
    actionError.value = cause?.response?.data?.detail ?? '清空通知失败。'
  } finally {
    bulkBusy.value = false
  }
}

onMounted(load)
onActivated(() => {
  if (hasLoaded.value) void load()
})
</script>

<template>
  <div class="notifications-page page-content">
    <header class="workspace-heading">
      <div><span class="eyebrow">INBOX</span><h1>通知</h1><p>团队协作、投稿审核和共享笔记的权限事件都会在这里记录。</p></div>
      <div class="notification-header-actions"><button class="secondary-button" type="button" :disabled="bulkBusy || !notifications.some((item) => !item.readAt)" @click="readAll"><IconCheck :size="15" />{{ bulkBusy ? '处理中…' : '全部标为已读' }}</button><button class="secondary-button" type="button" :disabled="bulkBusy || !notifications.length" @click="clearAll"><IconTrash :size="15" />清空通知</button></div>
    </header>
    <ActionFeedback :message="actionError" @dismiss="actionError = ''" />
    <p v-if="loading && !notifications.length" class="state-message">正在加载通知…</p>
    <p v-else-if="error && !notifications.length" class="state-message error">{{ error }}</p>
    <template v-else>
      <p v-if="error" class="state-message error notification-refresh-error">{{ error }}</p>
      <section class="notification-list card" :class="{ 'is-refreshing': loading }" :aria-busy="loading">
        <article v-for="notification in notifications" :key="notification.id" class="notification-row" :class="{ unread: !notification.readAt, actionable: notification.dataJson.taskId || notification.dataJson.teamTaskId || notification.dataJson.submissionId }" tabindex="0" @click="read(notification)" @keydown.enter="read(notification)">
          <span class="notification-icon"><IconBell :size="16" /></span>
          <div><strong>{{ notification.title }}</strong><p>{{ notification.body }}</p><time>{{ formatTime(notification.createdAt) }}</time></div>
          <span v-if="!notification.readAt" class="notification-unread-dot" aria-label="未读" />
          <button class="notification-delete" type="button" aria-label="删除通知" title="删除通知" @click.stop="remove(notification)"><IconTrash :size="15" /></button>
        </article>
        <p v-if="!notifications.length" class="state-message empty"><IconBell :size="24" /><span>暂无通知</span></p>
      </section>
    </template>
  </div>
</template>
