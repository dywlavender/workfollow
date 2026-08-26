import { createRouter, createWebHistory } from 'vue-router'

import { useAppStore, type RouteLoadingKind } from '@/stores/app'
import { useAuthStore } from '@/stores/auth'
import { useWorkspaceStore } from '@/stores/workspace'

const routeLoaders = {
  auth: () => import('@/views/AuthPage.vue'),
  home: () => import('@/views/HomePage.vue'),
  todos: () => import('@/views/TodosPage.vue'),
  calendar: () => import('@/views/CalendarPage.vue'),
  notes: () => import('@/views/NotesPage.vue'),
  common: () => import('@/views/CommonLinksPage.vue'),
  notifications: () => import('@/views/NotificationsPage.vue'),
  settings: () => import('@/views/SettingsPage.vue'),
  adminUsers: () => import('@/views/AdminUsersPage.vue'),
  teamAudit: () => import('@/views/TeamAuditPage.vue'),
}
const preloadedRoutes = new Set<string>()

export function preloadRoute(name: string) {
  if (preloadedRoutes.has(name)) return
  const loader = routeLoaders[name as keyof typeof routeLoaders]
  if (!loader) return
  preloadedRoutes.add(name)
  void loader().catch(() => { preloadedRoutes.delete(name) })
}

function routeLoadingKind(to: { meta: Record<string, unknown> }): RouteLoadingKind {
  const kind = to.meta.loadingKind
  return kind === 'dashboard' || kind === 'workspace' || kind === 'list' ? kind : 'workspace'
}

const router = createRouter({
  history: createWebHistory(),
  routes: [
    { path: '/login', name: 'login', component: routeLoaders.auth, props: { mode: 'login' }, meta: { guest: true } },
    { path: '/register', name: 'register', component: routeLoaders.auth, props: { mode: 'register' }, meta: { guest: true } },
    { path: '/', name: 'home', component: routeLoaders.home, meta: { requiresAuth: true, loadingKind: 'dashboard' } },
    { path: '/todos', name: 'todos', component: routeLoaders.todos, meta: { requiresAuth: true, loadingKind: 'workspace' } },
    { path: '/calendar', name: 'calendar', component: routeLoaders.calendar, meta: { requiresAuth: true, loadingKind: 'workspace' } },
    { path: '/notes', name: 'notes', component: routeLoaders.notes, meta: { requiresAuth: true, loadingKind: 'workspace' } },
    { path: '/common', name: 'common', component: routeLoaders.common, meta: { requiresAuth: true, loadingKind: 'list' } },
    { path: '/shared-notes', redirect: { path: '/notes', query: { view: 'shared' } } },
    { path: '/knowledge/:knowledgeId', redirect: (to) => ({ path: '/notes', query: { view: 'knowledge', knowledge: String(to.params.knowledgeId) } }) },
    { path: '/notifications', name: 'notifications', component: routeLoaders.notifications, meta: { requiresAuth: true, loadingKind: 'list' } },
    { path: '/settings', name: 'settings', component: routeLoaders.settings, meta: { requiresAuth: true, loadingKind: 'list' } },
    { path: '/admin/users', name: 'admin-users', component: routeLoaders.adminUsers, meta: { requiresAuth: true, requiresRoot: true, loadingKind: 'list' } },
    { path: '/teams', redirect: { path: '/settings', query: { section: 'teams' } } },
    { path: '/team/:teamId', redirect: (to) => ({ path: '/settings', query: { section: 'teams', team: String(to.params.teamId) } }) },
    { path: '/team/:teamId/tasks', redirect: { path: '/todos', query: { view: 'assigned-by-me' } } },
    { path: '/team/:teamId/calendar', redirect: '/calendar' },
    { path: '/team/:teamId/notes', redirect: { path: '/notes', query: { view: 'knowledge' } } },
    { path: '/team/:teamId/audit', name: 'team-audit', component: routeLoaders.teamAudit, meta: { requiresAuth: true, loadingKind: 'list' } },
  ],
  scrollBehavior: () => ({ top: 0 }),
})

router.beforeEach(async (to, from) => {
  const appStore = useAppStore()
  const auth = useAuthStore()
  const workspace = useWorkspaceStore()
  if (to.name !== from.name && to.meta.requiresAuth) appStore.beginRouteLoading(routeLoadingKind(to))
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

router.afterEach(() => useAppStore().endRouteLoading())
router.onError(() => useAppStore().endRouteLoading())

export default router
