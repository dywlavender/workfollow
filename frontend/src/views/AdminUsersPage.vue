<script setup lang="ts">
import { onMounted, ref } from 'vue'
import { IconArrowLeft, IconShield, IconUsers } from '@tabler/icons-vue'

import ActionFeedback from '@/components/ActionFeedback.vue'
import { fetchAdminUsers, putAdminUserPermissions, putAdminUserSystemRole, type User } from '@/services/api'
import { useAuthStore } from '@/stores/auth'

const auth = useAuthStore()
const users = ref<User[]>([])
const loading = ref(false)
const loadError = ref('')
const actionError = ref('')
const saving = ref<string | null>(null)

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
    const updated = await putAdminUserPermissions(user.id, { canCreateTeam: value })
    Object.assign(user, updated)
  } catch (cause: any) {
    user.canCreateTeam = previous
    actionError.value = cause?.response?.data?.detail ?? '保存权限失败。'
  } finally {
    saving.value = null
  }
}

async function updateSystemRole(user: User, systemRole: User['systemRole']) {
  const previousRole = user.systemRole
  const previousCanCreateTeam = user.canCreateTeam
  user.systemRole = systemRole
  if (systemRole === 'ROOT') user.canCreateTeam = true
  saving.value = user.id
  actionError.value = ''
  try {
    Object.assign(user, await putAdminUserSystemRole(user.id, systemRole))
  } catch (cause: any) {
    user.systemRole = previousRole
    user.canCreateTeam = previousCanCreateTeam
    actionError.value = cause?.response?.data?.detail ?? '保存系统角色失败。'
  } finally {
    saving.value = null
  }
}

function onPermissionChange(user: User, event: Event) {
  const input = event.target as HTMLInputElement | null
  if (input) void update(user, input.checked)
}

function onSystemRoleChange(user: User, event: Event) {
  const select = event.target as HTMLSelectElement | null
  const systemRole = select?.value as User['systemRole'] | undefined
  if (systemRole && systemRole !== user.systemRole) void updateSystemRole(user, systemRole)
}

onMounted(load)
</script>

<template>
  <div class="admin-users-page page-content">
    <header class="workspace-heading">
      <div>
        <span class="eyebrow">SYSTEM ADMINISTRATION</span>
        <h1>用户权限管理</h1>
        <p>授予或撤销普通用户创建团队的单项能力，不改变其系统角色或团队角色。</p>
      </div>
      <RouterLink class="secondary-button" to="/"><IconArrowLeft :size="15" />返回工作台</RouterLink>
    </header>

    <ActionFeedback :message="actionError" @dismiss="actionError = ''" />
    <p v-if="loadError" class="state-message error" role="alert">{{ loadError }}</p>
    <p v-else-if="loading" class="state-message">正在加载用户…</p>
    <section v-else class="admin-users-panel card">
        <div class="admin-users-table-head"><span>用户</span><span>系统角色</span><span>创建团队</span></div>
      <article v-for="user in users" :key="user.id" class="admin-user-row">
        <div class="admin-user-copy"><span class="avatar"><IconUsers :size="16" /></span><span><strong>{{ user.nickname }}</strong><small>{{ user.username }}</small></span></div>
        <label class="admin-role-control" :class="{ root: user.systemRole === 'ROOT' }">
          <IconShield :size="13" />
          <select :value="user.systemRole" :disabled="saving === user.id || (user.id === auth.user?.id && user.systemRole === 'ROOT')" aria-label="设置系统角色" @change="onSystemRoleChange(user, $event)">
            <option value="NORMAL">普通用户</option>
            <option value="ROOT">系统管理员</option>
          </select>
        </label>
        <label class="admin-permission-toggle"><input type="checkbox" :checked="user.canCreateTeam" :disabled="user.systemRole === 'ROOT' || saving === user.id" @change="onPermissionChange(user, $event)" /><span>{{ user.systemRole === 'ROOT' ? '自动拥有' : user.canCreateTeam ? '已授权' : '未授权' }}</span></label>
      </article>
      <p v-if="!users.length" class="state-message empty">暂无用户。</p>
    </section>
  </div>
</template>
