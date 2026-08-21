<script setup lang="ts">
import { computed } from 'vue'
import { useRouter } from 'vue-router'
import {
  IconArrowLeft,
  IconCheck,
  IconDeviceDesktop,
  IconMoon,
  IconPalette,
  IconSettings,
  IconSun,
} from '@tabler/icons-vue'

import {
  appearanceModes,
  appearanceBackgrounds,
  appearancePalettes,
  getAppearanceBackground,
  getAppearancePalette,
  type AppearanceBackground,
  type AppearanceMode,
  type AppearancePalette,
} from '@/modules/theme'
import { useAppStore } from '@/stores/app'
import { useAuthStore } from '@/stores/auth'

const appStore = useAppStore()
const authStore = useAuthStore()
const router = useRouter()
const selectedPalette = computed(() => getAppearancePalette(appStore.appearancePalette))
const selectedBackground = computed(() => getAppearanceBackground(appStore.appearanceBackground))
const modeIcons = { system: IconDeviceDesktop, light: IconSun, dark: IconMoon }

function selectPalette(palette: AppearancePalette) {
  appStore.setAppearancePalette(palette)
}

function selectMode(mode: AppearanceMode) {
  appStore.setAppearanceMode(mode)
}

function selectBackground(background: AppearanceBackground) {
  appStore.setAppearanceBackground(background)
}

function backgroundSwatch(background: AppearanceBackground) {
  if (background === 'theme') {
    return `linear-gradient(145deg, ${selectedPalette.value.light.rail}, ${selectedPalette.value.light.detail})`
  }
  return getAppearanceBackground(background).swatch
}

async function signOut() {
  await authStore.signOut()
  await router.replace({ name: 'login' })
}
</script>

<template>
  <div class="settings-page">
    <header class="settings-page-header">
      <div>
        <span class="eyebrow">WORKFOLLOW</span>
        <h1>设置</h1>
        <p>调整应用的外观与使用偏好。</p>
      </div>
      <RouterLink class="secondary-button" to="/">
        <IconArrowLeft :size="15" />
        返回工作台
      </RouterLink>
    </header>

    <div class="settings-layout">
      <aside class="settings-navigation" aria-label="设置分类">
        <div class="settings-navigation-title"><IconSettings :size="18" />设置</div>
        <button class="settings-navigation-item active" type="button" aria-current="page">
          <IconPalette :size="18" />
          <span>外观</span>
        </button>
      </aside>

      <main class="settings-content">
        <section class="settings-panel" aria-labelledby="appearance-title">
          <header class="settings-panel-header">
            <div>
              <span class="section-label">APPEARANCE</span>
              <h2 id="appearance-title">外观</h2>
              <p>主色负责交互状态，背景基调负责区域层次，也可以让背景跟随主题配色。</p>
            </div>
            <span class="settings-current-theme">当前：{{ selectedPalette.label }} · {{ selectedBackground.label }}</span>
          </header>

          <div class="appearance-section">
            <h3>界面模式</h3>
            <div class="appearance-mode-grid" role="radiogroup" aria-label="界面模式">
              <button
                v-for="mode in appearanceModes"
                :key="mode.id"
                class="appearance-mode-option"
                :class="{ selected: appStore.appearanceMode === mode.id }"
                type="button"
                role="radio"
                :aria-checked="appStore.appearanceMode === mode.id"
                @click="selectMode(mode.id)"
              >
                <component :is="modeIcons[mode.id]" :size="20" :stroke-width="1.8" />
                <span><strong>{{ mode.label }}</strong><small>{{ mode.description }}</small></span>
                <IconCheck v-if="appStore.appearanceMode === mode.id" class="mode-check" :size="17" />
              </button>
            </div>
          </div>

          <div class="appearance-section">
            <h3>主题配色</h3>
            <div class="appearance-theme-grid" role="radiogroup" aria-label="颜色主题">
            <button
              v-for="theme in appearancePalettes"
              :key="theme.id"
              class="appearance-theme-option"
              :class="{ selected: appStore.appearancePalette === theme.id }"
              type="button"
              role="radio"
              :aria-checked="appStore.appearancePalette === theme.id"
              :aria-label="`${theme.label}主题`"
              @click="selectPalette(theme.id)"
            >
              <span class="appearance-theme-swatch" :style="{ background: theme.swatch }">
                <IconCheck v-if="appStore.appearancePalette === theme.id" :size="21" :stroke-width="2.8" />
              </span>
              <span>{{ theme.label }}</span>
            </button>
            </div>
          </div>

          <div class="appearance-section">
            <h3>背景基调</h3>
            <div class="appearance-background-grid" role="radiogroup" aria-label="背景基调">
              <button
                v-for="background in appearanceBackgrounds"
                :key="background.id"
                class="appearance-background-option"
                :class="{ selected: appStore.appearanceBackground === background.id }"
                type="button"
                role="radio"
                :aria-checked="appStore.appearanceBackground === background.id"
                :aria-label="`${background.label}背景`"
                @click="selectBackground(background.id)"
              >
                <span class="appearance-background-swatch" :style="{ background: backgroundSwatch(background.id) }">
                  <IconCheck v-if="appStore.appearanceBackground === background.id" :size="19" :stroke-width="2.8" />
                </span>
                <span>
                  <strong>{{ background.label }}</strong>
                  <small>{{ background.description }}</small>
                </span>
              </button>
            </div>
          </div>
        </section>

        <section class="settings-info-row">
          <div>
            <strong>外观设置会自动保存</strong>
            <p>主色、背景基调和明暗模式会在下次打开 WorkFollow 时继续保留。</p>
          </div>
          <span class="settings-saved-badge"><IconCheck :size="14" />已应用</span>
        </section>

        <section class="settings-info-row">
          <div>
            <strong>{{ authStore.user?.nickname }}</strong>
            <p>@{{ authStore.user?.username }}</p>
          </div>
          <button class="secondary-button" type="button" @click="signOut">退出登录</button>
        </section>
      </main>
    </div>
  </div>
</template>
