<script setup lang="ts">
import { computed, reactive, ref, watch } from 'vue'
import { IconArrowRight, IconCheck, IconEye, IconEyeOff, IconLock, IconUser } from '@tabler/icons-vue'
import { useRoute, useRouter } from 'vue-router'

import { useAuthStore } from '@/stores/auth'

const props = defineProps<{ mode: 'login' | 'register' }>()
const route = useRoute()
const router = useRouter()
const auth = useAuthStore()
const form = reactive({ identifier: '', username: '', password: '' })
const error = ref('')
const passwordVisible = ref(false)
const isRegister = computed(() => props.mode === 'register')
const targetPath = computed(() => typeof route.query.redirect === 'string' && route.query.redirect.startsWith('/') ? route.query.redirect : '/')

watch(isRegister, () => { passwordVisible.value = false })

async function submit() {
  error.value = ''
  try {
    const result = isRegister.value
      ? await auth.signUp({ username: form.username, password: form.password })
      : await auth.signIn(form.identifier, form.password)
    if (result.isFirstRun && result.guideNoteId) {
      await router.replace({ path: '/notes', query: { note: result.guideNoteId, onboarding: '1' } })
    } else {
      await router.replace(targetPath.value)
    }
  } catch (requestError: unknown) {
    const detail = (requestError as { response?: { data?: { detail?: string } } }).response?.data?.detail
    error.value = detail ?? (isRegister.value ? '创建账号失败，请检查填写内容。' : '登录失败，请检查用户名和密码。')
  }
}
</script>

<template>
  <main class="auth-page">
    <div class="auth-orb auth-orb-one" aria-hidden="true" />
    <div class="auth-orb auth-orb-two" aria-hidden="true" />

    <section class="auth-layout">
      <aside class="auth-story" aria-label="备忘录 产品介绍">
        <div class="auth-story-brand">
          <span aria-hidden="true">
            <svg viewBox="0 0 24 24" width="17" height="17"><path d="M5.5 4.2h7.8l3.4 3.4v10.4a1.9 1.9 0 0 1-1.9 1.9H5.5a1.9 1.9 0 0 1-1.9-1.9V6.1a1.9 1.9 0 0 1 1.9-1.9z" fill="currentColor" opacity=".14"/><path d="M13.3 4.2l3.4 3.4h-2.7a.7.7 0 0 1-.7-.7z" fill="currentColor" opacity=".4"/><path d="M6.6 8.3h3.4M6.6 11.2h2.6" stroke="currentColor" stroke-width="1.4" stroke-linecap="round" opacity=".45"/><path d="M5.9 14.5 L9.2 17.7 L17.4 8.5" fill="none" stroke="currentColor" stroke-width="2.6" stroke-linecap="round" stroke-linejoin="round"/></svg>
          </span>
          <strong>备忘录</strong>
        </div>
        <div class="auth-story-copy">
          <span class="auth-kicker">FOCUS · ORGANIZE · DELIVER</span>
          <h2>把今天要做的事，<br />安静地推进。</h2>
          <p>代办、笔记与团队协作汇聚在一个清晰的工作空间里。</p>
        </div>
        <ul class="auth-benefits">
          <li><IconCheck :size="15" />个人代办与团队代办统一查看</li>
          <li><IconCheck :size="15" />富文本笔记沉淀过程与结论</li>
          <li><IconCheck :size="15" />清晰权限让协作保持边界</li>
        </ul>
        <div class="auth-story-decoration" aria-hidden="true">
          <span /><span /><span />
        </div>
      </aside>

      <section class="auth-panel">
        <header class="auth-heading">
          <span class="auth-mode-label">{{ isRegister ? '创建账号' : '欢迎回来' }}</span>
          <h1>{{ isRegister ? '开始你的工作空间' : '登录备忘录' }}</h1>
          <p>{{ isRegister ? '只需要用户名和密码，十秒内即可开始。' : '输入账号信息，继续今天的工作。' }}</p>
        </header>

        <form class="auth-form" @submit.prevent="submit">
          <label class="auth-field">
            <span>用户名</span>
            <span class="auth-input-wrap">
              <IconUser :size="18" aria-hidden="true" />
              <input
                v-if="isRegister"
                v-model="form.username"
                required
                minlength="3"
                maxlength="80"
                autocomplete="username"
                placeholder="至少 3 个字符"
                autofocus
              />
              <input
                v-else
                v-model="form.identifier"
                required
                autocomplete="username"
                placeholder="输入用户名"
                autofocus
              />
            </span>
          </label>

          <label class="auth-field">
            <span>密码</span>
            <span class="auth-input-wrap">
              <IconLock :size="18" aria-hidden="true" />
              <input
                v-model="form.password"
                required
                minlength="8"
                maxlength="128"
                :type="!isRegister && passwordVisible ? 'text' : 'password'"
                :autocomplete="isRegister ? 'new-password' : 'current-password'"
                placeholder="至少 8 个字符"
              />
              <button
                v-if="!isRegister"
                class="auth-password-toggle"
                type="button"
                :aria-label="passwordVisible ? '隐藏密码' : '显示密码'"
                :title="passwordVisible ? '隐藏密码' : '显示密码'"
                @click="passwordVisible = !passwordVisible"
              >
                <IconEyeOff v-if="passwordVisible" :size="18" aria-hidden="true" />
                <IconEye v-else :size="18" aria-hidden="true" />
              </button>
            </span>
          </label>

          <p
            class="auth-error"
            :class="{ visible: Boolean(error) }"
            role="alert"
            aria-live="polite"
          >{{ error || '\u00A0' }}</p>
          <button class="auth-submit" type="submit" :disabled="auth.loading">
            <span class="auth-submit-label">{{ auth.loading ? '处理中…' : isRegister ? '创建账号' : '登录' }}</span>
            <span class="auth-submit-icon" :class="{ hidden: auth.loading }" aria-hidden="true">
              <IconArrowRight :size="18" />
            </span>
          </button>
        </form>

        <p class="auth-switch-copy">
          {{ isRegister ? '已经有账号？' : '第一次使用备忘录？' }}
          <RouterLink v-if="isRegister" :to="{ name: 'login', query: route.query }">直接登录</RouterLink>
          <RouterLink v-else :to="{ name: 'register', query: route.query }">创建账号</RouterLink>
        </p>

        <p class="auth-local-hint">本地迁移账号可继续使用原用户名和密码登录</p>
      </section>
    </section>
  </main>
</template>
