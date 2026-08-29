<script setup lang="ts">
import { computed, ref, watch } from 'vue'
import { useRoute, useRouter } from 'vue-router'
import {
  IconCheck,
  IconBan,
  IconCopy,
  IconDeviceDesktop,
  IconMoon,
  IconPalette,
  IconKey,
  IconRefresh,
  IconSettings,
  IconSun,
  IconUserCircle,
  IconUsers,
} from '@tabler/icons-vue'

import SeasonSwatch from '@/components/SeasonSwatch.vue'
import TeamManagePanel from '@/components/settings/TeamManagePanel.vue'
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
import { useFeedbackStore } from '@/stores/feedback'
import {
  disableAgentToken,
  fetchAgentTokenStatus,
  generateAgentToken,
  type AgentTokenStatus,
} from '@/services/api'

const appStore = useAppStore()
const authStore = useAuthStore()
const feedback = useFeedbackStore()
const router = useRouter()
const route = useRoute()
const selectedPalette = computed(() => getAppearancePalette(appStore.appearancePalette))
const selectedBackground = computed(() => getAppearanceBackground(appStore.appearanceBackground))
const scenePaletteActive = computed(() => !!selectedPalette.value.atmosphere)
const modeIcons = { system: IconDeviceDesktop, light: IconSun, dark: IconMoon }
// 分区支持 ?section=teams&team=<id> 直达（侧边栏、旧 /team 链接重定向都落到这里）。
const validSections = ['appearance', 'account', 'teams'] as const
type SettingsSection = typeof validSections[number]
function sectionFromQuery(): SettingsSection {
  return typeof route.query.section === 'string' && validSections.includes(route.query.section as SettingsSection)
    ? route.query.section as SettingsSection
    : 'appearance'
}
const activeSection = ref<SettingsSection>(sectionFromQuery())
const panelTeamId = ref(typeof route.query.team === 'string' ? route.query.team : '')
watch(() => [route.query.section, route.query.team] as const, ([section, teamId]) => {
  if (typeof section === 'string' && validSections.includes(section as SettingsSection)) activeSection.value = section as SettingsSection
  if (typeof teamId === 'string' && teamId) panelTeamId.value = teamId
})

function onPanelSwitch(teamId: string) {
  panelTeamId.value = teamId
  void router.replace({ query: { ...route.query, section: 'teams', team: teamId } })
}

// 点击导航时把分区写回 URL，保证刷新/分享后落在同一分区。
function selectSection(section: SettingsSection) {
  activeSection.value = section
  const query: Record<string, string> = {}
  for (const [key, value] of Object.entries(route.query)) {
    if (typeof value === 'string') query[key] = value
  }
  if (section === 'teams') {
    query.section = 'teams'
    if (panelTeamId.value) query.team = panelTeamId.value
  } else {
    delete query.section
    delete query.team
  }
  void router.replace({ query })
}
const nicknameDraft = ref('')
const profileSaving = ref(false)
const profileDirty = computed(() => nicknameDraft.value.trim() !== (authStore.user?.nickname ?? ''))
const agentTokenStatus = ref<AgentTokenStatus | null>(null)
const agentTokenLoading = ref(false)
const revealedAgentToken = ref('')
const paletteGroups = computed(() => [
  {
    label: '经典配色',
    hint: '',
    items: appearancePalettes.filter((palette) => palette.group === 'classic' || !palette.group),
  },
  {
    label: '四季主题',
    hint: '自带氛围背景，随明暗模式自动切换',
    items: appearancePalettes.filter((palette) => palette.group === 'season'),
  },
  {
    label: '山水系列',
    hint: '山水场景主题，随明暗模式自动切换',
    items: appearancePalettes.filter((palette) => palette.group === 'scenic'),
  },
])

watch(() => authStore.user?.nickname, (nickname) => {
  if (!profileSaving.value) nicknameDraft.value = nickname ?? ''
}, { immediate: true })

watch(activeSection, (section) => {
  if (section === 'account' && agentTokenStatus.value === null) void loadAgentTokenStatus()
}, { immediate: true })

async function loadAgentTokenStatus() {
  agentTokenLoading.value = true
  try {
    agentTokenStatus.value = await fetchAgentTokenStatus()
  } catch (cause: any) {
    feedback.error(cause?.response?.data?.detail ?? '加载 Agent Token 状态失败。')
  } finally {
    agentTokenLoading.value = false
  }
}

function formatAccountTime(value: string | null | undefined) {
  return value ? new Date(value).toLocaleString('zh-CN') : '—'
}

async function resetAgentToken() {
  const wasEnabled = agentTokenStatus.value?.enabled === true
  if (wasEnabled && !window.confirm('重置后，已配置在 Codex、Claude Code 和 WorkBuddy 中的旧 Token 会立即失效。继续吗？')) return
  agentTokenLoading.value = true
  try {
    const result = await generateAgentToken()
    agentTokenStatus.value = result
    revealedAgentToken.value = result.token
    feedback.success(wasEnabled ? 'Agent Token 已重置。' : 'Agent Token 已生成。')
  } catch (cause: any) {
    feedback.error(cause?.response?.data?.detail ?? '生成 Agent Token 失败。')
  } finally {
    agentTokenLoading.value = false
  }
}

async function stopAgentToken() {
  if (!window.confirm('停用后，所有已配置该 Token 的 Agent 都将立即无法访问打勾。继续吗？')) return
  agentTokenLoading.value = true
  try {
    agentTokenStatus.value = await disableAgentToken()
    revealedAgentToken.value = ''
    feedback.success('Agent Token 已停用。')
  } catch (cause: any) {
    feedback.error(cause?.response?.data?.detail ?? '停用 Agent Token 失败。')
  } finally {
    agentTokenLoading.value = false
  }
}

async function copyAgentToken() {
  if (!revealedAgentToken.value) return
  try {
    await navigator.clipboard.writeText(revealedAgentToken.value)
    feedback.success('Agent Token 已复制。')
  } catch {
    feedback.error('复制失败，请手动选中 Token。')
  }
}

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
  if (!nickname) {
    feedback.error('昵称不能为空。')
    return
  }
  if (!profileDirty.value) return
  profileSaving.value = true
  try {
    await authStore.updateProfile({ nickname })
    nicknameDraft.value = nickname
    feedback.success('昵称已保存。')
  } catch (cause: any) {
    feedback.error(cause?.response?.data?.detail ?? '保存昵称失败，请稍后重试。')
  } finally {
    profileSaving.value = false
  }
}
</script>

<template>
  <div class="settings-page">
    <div class="settings-layout">
      <aside class="settings-navigation" aria-label="设置分类">
        <div class="settings-navigation-title"><IconSettings :size="18" />设置</div>
        <button class="settings-navigation-item" :class="{ active: activeSection === 'appearance' }" type="button" :aria-current="activeSection === 'appearance' ? 'page' : undefined" @click="selectSection('appearance')">
          <IconPalette :size="18" />
          <span>外观</span>
        </button>
        <button class="settings-navigation-item" :class="{ active: activeSection === 'account' }" type="button" :aria-current="activeSection === 'account' ? 'page' : undefined" @click="selectSection('account')">
          <IconUserCircle :size="18" />
          <span>账号</span>
        </button>
        <button class="settings-navigation-item" :class="{ active: activeSection === 'teams' }" type="button" :aria-current="activeSection === 'teams' ? 'page' : undefined" @click="selectSection('teams')">
          <IconUsers :size="18" />
          <span>团队</span>
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
                    <SeasonSwatch v-if="!!theme.scene" :season="theme.id" class="season-swatch-scene" />
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
                :disabled="scenePaletteActive && background.id !== 'theme'"
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
            <p>主色、背景基调和明暗模式会在下次打开打勾时继续保留。</p>
          </div>
          <span class="settings-saved-badge"><IconCheck :size="14" />已应用</span>
        </section>
        </template>

        <section v-else-if="activeSection === 'account'" class="settings-panel account-settings-panel" aria-labelledby="account-title">
          <header class="settings-panel-header">
            <div>
              <span class="section-label">ACCOUNT</span>
              <h2 id="account-title">账号</h2>
              <p>修改显示昵称；用户名用于登录，保持只读。</p>
            </div>
          </header>
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
          <section class="agent-token-panel" aria-labelledby="agent-token-title">
            <header>
              <span class="agent-token-icon"><IconKey :size="19" /></span>
              <div>
                <h3 id="agent-token-title">Agent 接入</h3>
                <p>使 Codex、Claude Code 和 WorkBuddy 能以你的身份访问打勾。每个账号同时只有一个 Token。</p>
              </div>
              <span class="agent-token-status" :class="{ enabled: agentTokenStatus?.enabled }">
                {{ agentTokenLoading && !agentTokenStatus ? '加载中' : agentTokenStatus?.enabled ? '已启用' : '未启用' }}
              </span>
            </header>
            <dl v-if="agentTokenStatus" class="agent-token-details">
              <div><dt>生成时间</dt><dd>{{ formatAccountTime(agentTokenStatus.createdAt) }}</dd></div>
              <div><dt>最后使用</dt><dd>{{ formatAccountTime(agentTokenStatus.lastUsedAt) }}</dd></div>
            </dl>
            <div v-if="revealedAgentToken" class="agent-token-reveal" role="status">
              <div>
                <strong>请现在复制 Token</strong>
                <small>离开页面后将不再完整显示。</small>
              </div>
              <code>{{ revealedAgentToken }}</code>
              <button class="secondary-button" type="button" @click="copyAgentToken"><IconCopy :size="15" />复制 Token</button>
            </div>
            <footer>
              <span>这是打勾的访问凭证，不是大模型 API Key。</span>
              <div>
                <button class="secondary-button" type="button" :disabled="agentTokenLoading" @click="resetAgentToken">
                  <IconRefresh v-if="agentTokenStatus?.enabled" :size="15" /><IconKey v-else :size="15" />
                  {{ agentTokenStatus?.enabled ? '重置 Token' : '生成 Token' }}
                </button>
                <button v-if="agentTokenStatus?.enabled" class="danger-outline-button" type="button" :disabled="agentTokenLoading" @click="stopAgentToken"><IconBan :size="15" />停用</button>
              </div>
            </footer>
          </section>
          <footer class="account-actions">
            <span>需要切换账号时，可以安全退出当前会话。</span>
            <button class="secondary-button" type="button" @click="signOut">退出登录</button>
          </footer>
        </section>

        <template v-else>
          <TeamManagePanel :team-id="panelTeamId" @switch="onPanelSwitch" />
        </template>
      </main>
    </div>
  </div>
</template>
