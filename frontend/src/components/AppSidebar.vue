<script setup lang="ts">
import { computed, onMounted } from 'vue'
import {
  IconBell,
  IconCalendar,
  IconChecklist,
  IconFileText,
  IconHome,
  IconLink,
  IconSettings,
  IconUser,
} from '@tabler/icons-vue'
import { useRoute } from 'vue-router'

import { preloadRoute } from '@/router'
import { prefetchCalendarTodos, prefetchNotesList } from '@/services/prefetch'
import { useAuthStore } from '@/stores/auth'
import { useRealtimeStore } from '@/stores/realtime'

const route = useRoute()
const auth = useAuthStore()
const realtime = useRealtimeStore()
const unreadCount = computed(() => realtime.unreadCount)

onMounted(() => { void realtime.refreshUnreadCount() })

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
    { label: '代办', shortLabel: '代办', icon: IconChecklist, to: '/todos' },
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

function preloadTarget(target: string | { path: string; query?: Record<string, string | undefined> }) {
  const path = typeof target === 'string' ? target : target.path
  if (path === route.path) return
  const routeName = path === '/' ? 'home'
    : path === '/todos' ? 'todos'
    : path === '/calendar' ? 'calendar'
    : path === '/notes' ? 'notes'
    : path === '/common' ? 'common'
    : path === '/notifications' ? 'notifications'
    : null
  if (routeName) preloadRoute(routeName)
  if (routeName === 'calendar') prefetchCalendarTodos()
  if (routeName === 'notes') prefetchNotesList()
}
</script>

<template>
  <aside class="sidebar is-task-shell">
    <RouterLink class="brand" to="/" aria-label="备忘录 首页">
      <span class="brand-mark" aria-hidden="true">
        <svg viewBox="0 0 24 24" width="16" height="16"><path d="M5.5 4.2h7.8l3.4 3.4v10.4a1.9 1.9 0 0 1-1.9 1.9H5.5a1.9 1.9 0 0 1-1.9-1.9V6.1a1.9 1.9 0 0 1 1.9-1.9z" fill="currentColor" opacity=".14"/><path d="M13.3 4.2l3.4 3.4h-2.7a.7.7 0 0 1-.7-.7z" fill="currentColor" opacity=".4"/><path d="M6.6 8.3h3.4M6.6 11.2h2.6" stroke="currentColor" stroke-width="1.4" stroke-linecap="round" opacity=".45"/><path d="M5.9 14.5 L9.2 17.7 L17.4 8.5" fill="none" stroke="currentColor" stroke-width="2.6" stroke-linecap="round" stroke-linejoin="round"/></svg>
      </span>
      <span class="brand-name">备忘录</span>
    </RouterLink>
    <nav class="navigation rail-navigation" aria-label="全局导航">
      <RouterLink
        v-for="item in railNavigation"
        :key="item.label"
        class="rail-item"
        :class="{ active: isActive(item.to) }"
        :to="item.to"
        :aria-label="item.badge === 'unread' && unreadCount ? `${item.label}，${unreadCount} 条未读` : item.label"
        @pointerenter="preloadTarget(item.to)"
        @focus="preloadTarget(item.to)"
      >
        <component :is="item.icon" :size="19" :stroke-width="1.8" aria-hidden="true" />
        <span class="rail-label" aria-hidden="true">{{ item.shortLabel }}</span>
        <span v-if="item.badge === 'unread' && unreadCount" class="rail-badge" aria-hidden="true">{{ unreadCount > 99 ? '99+' : unreadCount }}</span>
      </RouterLink>
    </nav>

    <div class="sidebar-bottom">
      <RouterLink class="sidebar-settings-link" to="/settings" :class="{ active: route.path === '/settings' }" aria-label="设置" @pointerenter="preloadRoute('settings')" @focus="preloadRoute('settings')">
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
