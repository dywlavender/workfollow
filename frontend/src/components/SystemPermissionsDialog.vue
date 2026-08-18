<script setup lang="ts">
import { nextTick, onBeforeUnmount, ref, watch } from 'vue'
import { IconShield, IconUsers, IconX } from '@tabler/icons-vue'

import ActionFeedback from '@/components/ActionFeedback.vue'
import ConfirmDialog from '@/components/ConfirmDialog.vue'
import { fetchAdminUsers, postAdminResetPassword, putAdminUserPermissions, type User } from '@/services/api'
import { useAuthStore } from '@/stores/auth'

const props = defineProps<{ open: boolean }>()
const emit = defineEmits<{ close: [] }>()
const auth = useAuthStore()
const users = ref<User[]>([])
const loading = ref(false)
const loadError = ref('')
const actionError = ref('')
const saving = ref<string | null>(null)
const resetting = ref<string | null>(null)
const resetTarget = ref<User | null>(null)
const notice = ref('')
const closeButton = ref<HTMLButtonElement | null>(null)
let previousFocus: HTMLElement | null = null

async function load() {
  if (auth.user?.systemRole !== 'ROOT') return
  loading.value = true
  loadError.value = ''
  try {
    users.value = await fetchAdminUsers()
  } catch (cause: any) {
    loadError.value = cause?.response?.data?.detail ?? '无法读取用户权限。'
  } finally {
    loading.value = false
  }
}

async function update(user: User, value: boolean) {
  const previous = user.canCreateTeam
  user.canCreateTeam = value
  saving.value = user.id
  actionError.value = ''
  try {
    Object.assign(user, await putAdminUserPermissions(user.id, { canCreateTeam: value }))
  } catch (cause: any) {
    user.canCreateTeam = previous
    actionError.value = cause?.response?.data?.detail ?? '保存权限失败。'
  } finally {
    saving.value = null
  }
}

async function confirmResetPassword() {
  const target = resetTarget.value
  resetTarget.value = null
  if (!target) return
  resetting.value = target.id
  actionError.value = ''
  notice.value = ''
  try {
    const result = await postAdminResetPassword(target.id)
    if (target.id === auth.user?.id) {
      await auth.signOut()
      window.location.assign('/login')
      return
    }
    notice.value = `${target.nickname} 的密码已重置为 ${result.initialPassword}`
  } catch (cause: any) {
    actionError.value = cause?.response?.data?.detail ?? '重置密码失败。'
  } finally {
    resetting.value = null
  }
}

function onPermissionChange(user: User, event: Event) {
  const input = event.target as HTMLInputElement | null
  if (input) void update(user, input.checked)
}

function close() {
  emit('close')
}

function onKeydown(event: KeyboardEvent) {
  if (event.key === 'Escape' && props.open) close()
}

watch(() => props.open, async (open) => {
  if (open) {
    previousFocus = document.activeElement as HTMLElement | null
    document.addEventListener('keydown', onKeydown)
    await load()
    await nextTick()
    closeButton.value?.focus()
  } else {
    document.removeEventListener('keydown', onKeydown)
    previousFocus?.focus()
    previousFocus = null
  }
})

onBeforeUnmount(() => document.removeEventListener('keydown', onKeydown))
</script>

<template>
  <Teleport to="body">
    <div v-if="open && auth.user?.systemRole === 'ROOT'" class="dialog-backdrop" @mousedown.self="close">
      <section class="dialog-card system-permissions-dialog" role="dialog" aria-modal="true" aria-labelledby="system-permissions-title">
        <header class="dialog-header">
          <div>
            <span class="eyebrow">SYSTEM ADMINISTRATION</span>
            <h2 id="system-permissions-title">用户权限管理</h2>
            <p>授权普通用户创建团队，不改变其系统角色和团队角色。</p>
          </div>
          <button ref="closeButton" class="icon-action" type="button" aria-label="关闭权限管理" @click="close"><IconX :size="18" /></button>
        </header>

        <ActionFeedback :message="actionError" @dismiss="actionError = ''" />
        <ActionFeedback :message="notice" tone="success" @dismiss="notice = ''" />
        <p v-if="loadError" class="state-message error" role="alert">{{ loadError }}</p>
        <p v-else-if="loading" class="state-message">正在加载用户…</p>
        <div v-else class="system-permissions-list">
          <div class="admin-users-table-head"><span>用户</span><span>系统角色</span><span>创建团队</span></div>
          <article v-for="user in users" :key="user.id" class="admin-user-row">
            <div class="admin-user-copy"><span class="avatar"><IconUsers :size="16" /></span><span><strong>{{ user.nickname }}</strong><small>{{ user.username }}</small></span></div>
            <span class="admin-role-badge" :class="{ root: user.systemRole === 'ROOT' }"><IconShield :size="13" />{{ user.systemRole === 'ROOT' ? 'ROOT' : 'NORMAL' }}</span>
            <div class="team-header-actions">
              <label class="admin-permission-toggle"><input type="checkbox" :checked="user.canCreateTeam" :disabled="user.systemRole === 'ROOT' || saving === user.id" @change="onPermissionChange(user, $event)" /><span>{{ user.systemRole === 'ROOT' ? '自动拥有' : user.canCreateTeam ? '已授权' : '未授权' }}</span></label>
              <button class="quiet-button" type="button" :disabled="resetting === user.id" @click="resetTarget = user">重置密码</button>
            </div>
          </article>
          <p v-if="!users.length" class="state-message empty">暂无用户。</p>
        </div>
      </section>
    </div>
  </Teleport>
  <ConfirmDialog
    :open="Boolean(resetTarget)"
    title="重置用户密码"
    :message="`确定将“${resetTarget?.nickname ?? ''}”的密码重置为 11111111 吗？该用户当前登录会话会立即失效。`"
    confirm-label="重置密码"
    :danger="true"
    @close="resetTarget = null"
    @confirm="confirmResetPassword"
  />
</template>
