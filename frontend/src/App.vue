<script setup lang="ts">
import { computed, onBeforeUnmount, onMounted, watch } from 'vue'
import { useRoute } from 'vue-router'
import {
  darkTheme,
  dateZhCN,
  NConfigProvider,
  NDialogProvider,
  NMessageProvider,
  NNotificationProvider,
  zhCN,
} from 'naive-ui'
import AppSidebar from '@/components/AppSidebar.vue'
import FeedbackHost from '@/components/FeedbackHost.vue'
import GlobalCapture from '@/components/GlobalCapture.vue'
import RouteLoadingFrame from '@/components/RouteLoadingFrame.vue'
import SeasonalAtmosphere from '@/components/SeasonalAtmosphere.vue'
import ReminderScheduler from '@/components/todo/ReminderScheduler.vue'
import { preloadRoute } from '@/router'
import { useAppStore } from '@/stores/app'
import { useAuthStore } from '@/stores/auth'
import { useRealtimeStore } from '@/stores/realtime'
import { createNaiveThemeOverrides, resolveAppearanceMode } from '@/modules/theme'

const appStore = useAppStore()
const auth = useAuthStore()
const realtime = useRealtimeStore()
appStore.initializeAppearance()
const route = useRoute()
const isAuthenticatedPage = computed(() => Boolean(route.meta.requiresAuth))
const resolvedMode = computed(() => resolveAppearanceMode(appStore.appearanceMode, appStore.systemDark))
const naiveTheme = computed(() => resolvedMode.value === 'dark' ? darkTheme : null)
const themeOverrides = computed(() => createNaiveThemeOverrides(
  appStore.appearancePalette,
  resolvedMode.value,
  appStore.appearanceBackground,
))
const cachedPageNames = ['HomePage', 'TodosPage', 'NotificationsPage', 'SettingsPage', 'CommonLinksPage']
let frequentPreloadTimer: number | undefined
let deferredPreloadTimer: number | undefined

type IdleWindow = Window & {
  requestIdleCallback?: (callback: () => void, options?: { timeout: number }) => number
  cancelIdleCallback?: (handle: number) => void
}

watch(() => auth.user?.id, (userId) => {
  if (userId) realtime.connect(userId)
  else realtime.disconnect()
}, { immediate: true })

onMounted(() => {
  // Warm up the high-frequency, lightweight routes after the first paint.
  // Heavy editor and calendar chunks remain demand-loaded.
  frequentPreloadTimer = window.setTimeout(() => {
    preloadRoute('home')
    preloadRoute('todos')
    preloadRoute('notifications')
  }, 1200)

  const idleWindow = window as IdleWindow
  const preloadSecondaryRoutes = () => {
    preloadRoute('common')
    preloadRoute('settings')
  }
  if (idleWindow.requestIdleCallback) {
    deferredPreloadTimer = idleWindow.requestIdleCallback(preloadSecondaryRoutes, { timeout: 4500 })
  } else {
    deferredPreloadTimer = window.setTimeout(preloadSecondaryRoutes, 3500)
  }
})

onBeforeUnmount(() => {
  window.clearTimeout(frequentPreloadTimer)
  const idleWindow = window as IdleWindow
  if (idleWindow.cancelIdleCallback && deferredPreloadTimer !== undefined) idleWindow.cancelIdleCallback(deferredPreloadTimer)
  else window.clearTimeout(deferredPreloadTimer)
  realtime.disconnect()
})
</script>

<template>
  <NConfigProvider :locale="zhCN" :date-locale="dateZhCN" :theme="naiveTheme" :theme-overrides="themeOverrides">
    <NMessageProvider>
      <NDialogProvider>
        <NNotificationProvider>
          <SeasonalAtmosphere />
          <div v-if="isAuthenticatedPage" class="app-shell task-app-shell">
            <ReminderScheduler />
            <AppSidebar />
            <GlobalCapture />
            <FeedbackHost />
            <main class="main-area">
              <div class="route-content-frame">
                <RouterView v-slot="{ Component }">
                  <KeepAlive :include="cachedPageNames">
                    <component :is="Component" />
                  </KeepAlive>
                </RouterView>
                <RouteLoadingFrame v-if="appStore.routeLoadingVisible" :kind="appStore.routeLoadingKind" />
              </div>
            </main>
          </div>
          <div v-else class="guest-shell">
            <RouterView />
          </div>
        </NNotificationProvider>
      </NDialogProvider>
    </NMessageProvider>
  </NConfigProvider>
</template>
