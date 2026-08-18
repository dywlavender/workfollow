<script setup lang="ts">
import { computed, onBeforeUnmount, onMounted, ref, watch } from 'vue'
import {
  IconBell,
  IconCalendar,
  IconChecklist,
  IconFileText,
  IconHome,
  IconLink,
  IconSettings,
  IconUser,
  IconUsers,
} from '@tabler/icons-vue'
import { useRoute } from 'vue-router'

import { useAuthStore } from '@/stores/auth'
import { useWorkspaceStore } from '@/stores/workspace'
import { fetchNotifications } from '@/services/api'

const route = useRoute()
const auth = useAuthStore()
const workspace = useWorkspaceStore()
const unreadCount = ref(0)
let unreadTimer: number | undefined

async function refreshUnread() {
  if (!auth.user) {
    unreadCount.value = 0
    return
  }
  try {
    unreadCount.value = (await fetchNotifications(true)).length
  } catch {
    // Keep the last known count when the request fails; the badge is advisory.
  }
}

onMounted(() => {
  void refreshUnread()
  unreadTimer = window.setInterval(refreshUnread, 60_000)
})

onBeforeUnmount(() => {
  if (unreadTimer) window.clearInterval(unreadTimer)
})

watch(() => route.fullPath, () => { void refreshUnread() })

const currentTeam = computed(() => workspace.currentTeam ?? workspace.teams[0] ?? null)
interface RailItem {
  label: string
  shortLabel: string
  icon: unknown
  to: string | { path: string; query?: Record<string, string | undefined> }
  badge?: 'unread'
}

const railNavigation = computed((): RailItem[] => {
  return [
    { label: '首页', shortLabel: '首页', icon: IconHome, to: '/' },
    { label: '任务', shortLabel: '任务', icon: IconChecklist, to: '/todos' },
    { label: '日历', shortLabel: '日历', icon: IconCalendar, to: '/calendar' },
    { label: '全部笔记', shortLabel: '笔记', icon: IconFileText, to: '/notes' },
    { label: '常用', shortLabel: '常用', icon: IconLink, to: '/common' },
    { label: '通知', shortLabel: '通知', icon: IconBell, to: '/notifications', badge: 'unread' },
  ]
})

function isActive(target: string | { path: string; query?: Record<string, string | undefined> }): boolean {
  if (typeof target === 'string') {
    const [path, hash] = target.split('#')
    if (route.path !== path) return false
    // A task view is represented by the query string; the rail entry should
    // stay active for today/week/inbox/month/completed alike.
    if (path === '/todos') return true
    if (hash) return route.hash === `#${hash}`
    return Object.keys(route.query).length === 0 && !route.hash
  }
  if (route.path !== target.path) return false
  const entries = Object.entries(target.query ?? {})
  if (!entries.length) return Object.keys(route.query).length === 0
  return entries.every(([key, value]) => route.query[key] === value)
}
</script>

<template>
  <aside class="sidebar is-task-shell">
    <RouterLink class="brand" to="/" aria-label="WorkFollow 首页">
      <span class="brand-mark">W</span>
      <span class="brand-name">WorkFollow</span>
    </RouterLink>
    <nav class="navigation rail-navigation" aria-label="全局导航">
      <RouterLink
        v-for="item in railNavigation"
        :key="item.label"
        class="rail-item"
        :class="{ active: isActive(item.to) }"
        :to="item.to"
        :aria-label="item.badge === 'unread' && unreadCount ? `${item.label}，${unreadCount} 条未读` : item.label"
        :title="item.label"
      >
        <component :is="item.icon" :size="19" :stroke-width="1.8" aria-hidden="true" />
        <span class="rail-label" aria-hidden="true">{{ item.shortLabel }}</span>
        <span v-if="item.badge === 'unread' && unreadCount" class="rail-badge" aria-hidden="true">{{ unreadCount > 99 ? '99+' : unreadCount }}</span>
      </RouterLink>
    </nav>

    <div class="sidebar-bottom">
      <RouterLink class="sidebar-settings-link" :to="currentTeam ? `/team/${currentTeam.id}` : '/teams'" :class="{ active: route.path === '/teams' || route.path.startsWith('/team/') }" aria-label="团队管理" title="团队管理">
        <IconUsers :size="19" :stroke-width="1.8" aria-hidden="true" /><span>团队</span>
      </RouterLink>
      <RouterLink class="sidebar-settings-link" to="/settings" :class="{ active: route.path === '/settings' }" aria-label="设置" title="设置">
        <IconSettings :size="19" :stroke-width="1.8" aria-hidden="true" />
        <span>设置</span>
      </RouterLink>
      <div class="user-card">
        <span class="avatar"><IconUser :size="17" :stroke-width="1.8" aria-hidden="true" /></span>
        <span class="user-meta"><strong>{{ auth.user?.nickname ?? '个人空间' }}</strong><small>{{ auth.user?.username ?? '本地数据' }}</small></span>
      </div>
    </div>
  </aside>
</template>
