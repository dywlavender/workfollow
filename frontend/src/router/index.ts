import { createRouter, createWebHistory } from 'vue-router'

import { useAuthStore } from '@/stores/auth'
import { useWorkspaceStore } from '@/stores/workspace'

const router = createRouter({
  history: createWebHistory(),
  routes: [
    { path: '/login', name: 'login', component: () => import('@/views/AuthPage.vue'), props: { mode: 'login' }, meta: { guest: true } },
    { path: '/register', name: 'register', component: () => import('@/views/AuthPage.vue'), props: { mode: 'register' }, meta: { guest: true } },
    { path: '/', name: 'home', component: () => import('@/views/HomePage.vue'), meta: { requiresAuth: true } },
    { path: '/todos', name: 'todos', component: () => import('@/views/TodosPage.vue'), meta: { requiresAuth: true } },
    { path: '/calendar', name: 'calendar', component: () => import('@/views/CalendarPage.vue'), meta: { requiresAuth: true } },
    { path: '/notes', name: 'notes', component: () => import('@/views/NotesPage.vue'), meta: { requiresAuth: true } },
    { path: '/common', name: 'common', component: () => import('@/views/CommonLinksPage.vue'), meta: { requiresAuth: true } },
    { path: '/shared-notes', redirect: { path: '/notes', query: { view: 'shared' } } },
    { path: '/knowledge/:knowledgeId', redirect: (to) => ({ path: '/notes', query: { view: 'knowledge', knowledge: String(to.params.knowledgeId) } }) },
    { path: '/notifications', name: 'notifications', component: () => import('@/views/NotificationsPage.vue'), meta: { requiresAuth: true } },
    { path: '/settings', name: 'settings', component: () => import('@/views/SettingsPage.vue'), meta: { requiresAuth: true } },
    { path: '/admin/users', name: 'admin-users', component: () => import('@/views/AdminUsersPage.vue'), meta: { requiresAuth: true, requiresRoot: true } },
    { path: '/teams', name: 'teams', component: () => import('@/views/TeamPage.vue'), meta: { requiresAuth: true } },
    { path: '/team/:teamId', name: 'team', component: () => import('@/views/TeamPage.vue'), meta: { requiresAuth: true } },
    { path: '/team/:teamId/tasks', redirect: { path: '/todos', query: { view: 'assigned-by-me' } } },
    { path: '/team/:teamId/calendar', redirect: '/calendar' },
    { path: '/team/:teamId/notes', redirect: { path: '/notes', query: { view: 'knowledge' } } },
    { path: '/team/:teamId/audit', name: 'team-audit', component: () => import('@/views/TeamAuditPage.vue'), meta: { requiresAuth: true } },
  ],
  scrollBehavior: () => ({ top: 0 }),
})

router.beforeEach(async (to) => {
  const auth = useAuthStore()
  const workspace = useWorkspaceStore()
  await auth.initialize()
  if (to.meta.requiresAuth && !auth.user) {
    workspace.reset()
    return { name: 'login', query: { redirect: to.fullPath } }
  }
  if (to.meta.requiresRoot && auth.user?.systemRole !== 'ROOT') return { name: 'home' }
  if (to.meta.guest && auth.user) return { name: 'home' }
  if (auth.user) {
    await workspace.initialize()
    const routeTeamId = typeof to.params.teamId === 'string' ? to.params.teamId : null
    if (routeTeamId) workspace.selectTeam(routeTeamId)
  }
  return true
})

export default router
