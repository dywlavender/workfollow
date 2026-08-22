<script setup lang="ts">
import { computed, onBeforeUnmount, watch } from 'vue'
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
import CompletionToast from '@/components/CompletionToast.vue'
import GlobalCapture from '@/components/GlobalCapture.vue'
import ReminderScheduler from '@/components/todo/ReminderScheduler.vue'
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

watch(() => auth.user?.id, (userId) => {
  if (userId) realtime.connect(userId)
  else realtime.disconnect()
}, { immediate: true })

onBeforeUnmount(() => realtime.disconnect())
</script>

<template>
  <NConfigProvider :locale="zhCN" :date-locale="dateZhCN" :theme="naiveTheme" :theme-overrides="themeOverrides">
    <NMessageProvider>
      <NDialogProvider>
        <NNotificationProvider>
          <div v-if="isAuthenticatedPage" class="app-shell task-app-shell">
            <ReminderScheduler />
            <AppSidebar />
            <GlobalCapture />
            <CompletionToast />
            <main class="main-area">
              <RouterView />
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
