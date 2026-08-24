<script setup lang="ts">
import { computed, ref, watch } from 'vue'
import { useRouter } from 'vue-router'
import {
  IconArrowLeft,
  IconCheck,
  IconDeviceDesktop,
  IconMoon,
  IconPalette,
  IconSettings,
  IconSun,
  IconUserCircle,
} from '@tabler/icons-vue'

import ActionFeedback from '@/components/ActionFeedback.vue'
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
const activeSection = ref<'appearance' | 'account'>('appearance')
const nicknameDraft = ref('')
const profileSaving = ref(false)
const profileError = ref('')
const profileNotice = ref('')
const profileDirty = computed(() => nicknameDraft.value.trim() !== (authStore.user?.nickname ?? ''))
const paletteGroups = computed(() => [
  {
    label: '经典配色',
    hint: '',
    items: appearancePalettes.filter((palette) => palette.group !== 'season'),
  },
  {
    label: '四季主题',
    hint: '自带氛围背景，随明暗模式自动切换',
    items: appearancePalettes.filter((palette) => palette.group === 'season'),
  },
])

watch(() => authStore.user?.nickname, (nickname) => {
  if (!profileSaving.value) nicknameDraft.value = nickname ?? ''
}, { immediate: true })

function paletteSwatch(palette: (typeof appearancePalettes)[number]) {
  return palette.atmosphere?.light ?? palette.swatch
}

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

async function saveProfile() {
  const nickname = nicknameDraft.value.trim()
  profileError.value = ''
  profileNotice.value = ''
  if (!nickname) {
    profileError.value = '昵称不能为空。'
    return
  }
  if (!profileDirty.value) return
  profileSaving.value = true
  try {
    await authStore.updateProfile({ nickname })
    nicknameDraft.value = nickname
    profileNotice.value = '昵称已保存。'
  } catch (cause: any) {
    profileError.value = cause?.response?.data?.detail ?? '保存昵称失败，请稍后重试。'
  } finally {
    profileSaving.value = false
  }
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
        <button class="settings-navigation-item" :class="{ active: activeSection === 'appearance' }" type="button" :aria-current="activeSection === 'appearance' ? 'page' : undefined" @click="activeSection = 'appearance'">
          <IconPalette :size="18" />
          <span>外观</span>
        </button>
        <button class="settings-navigation-item" :class="{ active: activeSection === 'account' }" type="button" :aria-current="activeSection === 'account' ? 'page' : undefined" @click="activeSection = 'account'">
          <IconUserCircle :size="18" />
          <span>账号</span>
        </button>
      </aside>

      <main class="settings-content">
        <template v-if="activeSection === 'appearance'">
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
            <div v-for="group in paletteGroups" :key="group.label" class="appearance-theme-group">
              <div class="appearance-theme-group-label">
                {{ group.label }}
                <small v-if="group.hint">{{ group.hint }}</small>
              </div>
              <div class="appearance-theme-grid" role="radiogroup" :aria-label="`${group.label}颜色主题`">
                <button
                  v-for="theme in group.items"
                  :key="theme.id"
                  class="appearance-theme-option"
                  :class="{ selected: appStore.appearancePalette === theme.id }"
                  type="button"
                  role="radio"
                  :aria-checked="appStore.appearancePalette === theme.id"
                  :aria-label="`${theme.label}主题`"
                  @click="selectPalette(theme.id)"
                >
                  <span class="appearance-theme-swatch" :style="{ background: paletteSwatch(theme) }">
                    <IconCheck v-if="appStore.appearancePalette === theme.id" :size="21" :stroke-width="2.8" />
                  </span>
                  <span>{{ theme.label }}</span>
                </button>
              </div>
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
        </template>

        <section v-else class="settings-panel account-settings-panel" aria-labelledby="account-title">
          <header class="settings-panel-header">
            <div>
              <span class="section-label">ACCOUNT</span>
              <h2 id="account-title">账号</h2>
              <p>修改显示昵称；用户名用于登录，保持只读。</p>
            </div>
          </header>
          <ActionFeedback :message="profileError" @dismiss="profileError = ''" />
          <ActionFeedback :message="profileNotice" tone="success" @dismiss="profileNotice = ''" />
          <form class="account-profile-form" @submit.prevent="saveProfile">
            <label for="account-nickname">
              <span>昵称</span>
              <input id="account-nickname" v-model="nicknameDraft" type="text" maxlength="120" autocomplete="nickname" />
              <small>这个名称会显示在侧边栏和团队协作成员列表中。</small>
            </label>
            <footer>
              <span>用户名不可修改。</span>
              <button class="primary-button" type="submit" :disabled="profileSaving || !profileDirty">
                {{ profileSaving ? '保存中…' : '保存昵称' }}
              </button>
            </footer>
          </form>
          <dl class="account-details">
            <div><dt>用户名</dt><dd>@{{ authStore.user?.username || '—' }}</dd></div>
          </dl>
          <footer class="account-actions">
            <span>需要切换账号时，可以安全退出当前会话。</span>
            <button class="secondary-button" type="button" @click="signOut">退出登录</button>
          </footer>
        </section>
      </main>
    </div>
  </div>
</template>
