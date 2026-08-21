<script setup lang="ts">
import { computed } from 'vue'
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
import ReminderScheduler from '@/components/todo/ReminderScheduler.vue'
import { useAppStore } from '@/stores/app'
import { createNaiveThemeOverrides, resolveAppearanceMode } from '@/modules/theme'

const appStore = useAppStore()
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
</script>

<template>
  <NConfigProvider :locale="zhCN" :date-locale="dateZhCN" :theme="naiveTheme" :theme-overrides="themeOverrides">
    <NMessageProvider>
      <NDialogProvider>
        <NNotificationProvider>
          <div v-if="isAuthenticatedPage" class="app-shell task-app-shell">
            <ReminderScheduler />
            <AppSidebar />
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
