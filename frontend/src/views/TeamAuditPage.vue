<script setup lang="ts">
import { onMounted, ref, watch } from 'vue'
import { useRoute } from 'vue-router'
import { IconArrowLeft, IconHistory } from '@tabler/icons-vue'

import { fetchTeam, fetchTeamAuditLogs, type AuditLog, type Team } from '@/services/api'

const route = useRoute()
const team = ref<Team | null>(null)
const logs = ref<AuditLog[]>([])
const error = ref('')
const teamId = () => String(route.params.teamId ?? '')

function formatTime(value: string) {
  return new Intl.DateTimeFormat('zh-CN', { dateStyle: 'medium', timeStyle: 'short' }).format(new Date(value))
}

async function load() {
  try {
    const [loadedTeam, loadedLogs] = await Promise.all([
      fetchTeam(teamId()),
      fetchTeamAuditLogs(teamId()),
    ])
    team.value = loadedTeam
    logs.value = loadedLogs
  } catch (cause: any) {
    error.value = cause?.response?.data?.detail ?? '无法读取审计日志。'
  }
}

onMounted(load)
watch(() => route.params.teamId, load)
</script>

<template>
  <div class="team-audit-page page-content">
    <header class="workspace-heading">
      <div><span class="eyebrow">{{ team?.name ?? 'TEAM' }}</span><h1>审计日志</h1><p>记录团队权限、任务、笔记和审核动作。</p></div>
      <RouterLink class="secondary-button" :to="`/team/${teamId()}`"><IconArrowLeft :size="15" />返回团队</RouterLink>
    </header>
    <p v-if="error" class="state-message error">{{ error }}</p>
    <section v-else class="audit-list card">
      <article v-for="log in logs" :key="log.id" class="audit-row">
        <span class="audit-icon"><IconHistory :size="16" /></span>
        <div><strong>{{ log.action }}</strong><small>{{ log.resourceType }} · {{ log.resourceId || '—' }}</small></div>
        <time>{{ formatTime(log.createdAt) }}</time>
      </article>
      <p v-if="!logs.length" class="state-message empty"><IconHistory :size="24" /><span>暂无审计记录</span></p>
    </section>
  </div>
</template>
