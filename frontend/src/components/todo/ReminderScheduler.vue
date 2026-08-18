<script setup lang="ts">
import { onBeforeUnmount, onMounted } from 'vue'

import { acknowledgeReminder, fetchDueReminders } from '@/services/api'


let timer: number | undefined

async function pollReminders() {
  if (!('Notification' in window) || Notification.permission !== 'granted') return
  try {
    const todos = await fetchDueReminders()
    for (const todo of todos) {
      new Notification(todo.title, { body: todo.description ?? 'WorkFollow 待办提醒', tag: todo.id })
      await acknowledgeReminder(todo.id)
    }
  } catch {
    // The next poll retries; transient API failures must not mark reminders as delivered.
  }
}

onMounted(() => {
  void pollReminders()
  timer = window.setInterval(pollReminders, 30_000)
})
onBeforeUnmount(() => window.clearInterval(timer))
</script>

<template><span hidden aria-hidden="true" /></template>

