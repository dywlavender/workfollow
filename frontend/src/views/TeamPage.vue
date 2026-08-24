<script setup lang="ts">
import { computed, onBeforeUnmount, onMounted, ref, watch } from 'vue'
import { useRoute, useRouter } from 'vue-router'
import { IconLogout, IconPlus, IconSearch, IconShield, IconTrash, IconUsers } from '@tabler/icons-vue'

import ActionFeedback from '@/components/ActionFeedback.vue'
import SystemPermissionsDialog from '@/components/SystemPermissionsDialog.vue'
import ConfirmDialog from '@/components/ConfirmDialog.vue'
import { useClickOutside } from '@/composables/useClickOutside'

import {
  deleteTeamMember,
  deleteTeam,
  fetchTeam,
  fetchTeamMemberCandidates,
  fetchTeamMembers,
  leaveTeam,
  postTeam,
  postTeamMember,
  postTeamMemberResetPassword,
  type Team,
  type TeamMemberCandidate,
  type TeamMember,
  type TeamRole,
} from '@/services/api'
import { useWorkspaceStore } from '@/stores/workspace'
import { useAuthStore } from '@/stores/auth'

const route = useRoute()
const router = useRouter()
const workspace = useWorkspaceStore()
const auth = useAuthStore()
const team = ref<Team | null>(null)
const members = ref<TeamMember[]>([])
const candidateQuery = ref('')
const candidates = ref<TeamMemberCandidate[]>([])
const selectedCandidate = ref<TeamMemberCandidate | null>(null)
const candidateLoading = ref(false)
const candidateError = ref('')
const candidateOpen = ref(false)
const candidateHost = ref<HTMLElement | null>(null)
const role = ref<TeamRole>('MEMBER')
const loading = ref(false)
const loadError = ref('')
const actionError = ref('')
const notice = ref('')
const permissionsOpen = ref(false)
const resetTarget = ref<TeamMember | null>(null)
const resettingUserId = ref<string | null>(null)
const addingMember = ref(false)
let candidateTimer: number | undefined
let candidateRequest = 0

useClickOutside(candidateHost, candidateOpen, () => { candidateOpen.value = false })

const teamId = computed(() => String(route.params.teamId ?? ''))
const isSystemAdmin = computed(() => auth.user?.systemRole === 'ROOT')
const canCreateTeam = computed(() => isSystemAdmin.value || auth.user?.canCreateTeam === true)
const canManage = computed(() => isSystemAdmin.value || team.value?.role === 'OWNER' || team.value?.role === 'ADMIN')
const canDissolve = computed(() => isSystemAdmin.value || team.value?.role === 'OWNER')

async function load() {
  if (!teamId.value) return
  loading.value = true
  loadError.value = ''
  try {
    const [loadedTeam, loadedMembers] = await Promise.all([
      fetchTeam(teamId.value),
      fetchTeamMembers(teamId.value),
    ])
    team.value = loadedTeam
    workspace.selectTeam(teamId.value)
    members.value = loadedMembers
    if (team.value.role === 'ADMIN') role.value = 'MEMBER'
  } catch {
    loadError.value = '无法读取团队，可能已退出该团队。'
  } finally {
    loading.value = false
  }
}

async function searchCandidates() {
  if (!teamId.value || !canManage.value) return
  const requestId = ++candidateRequest
  candidateLoading.value = true
  candidateError.value = ''
  try {
    const result = await fetchTeamMemberCandidates(teamId.value, candidateQuery.value)
    if (requestId === candidateRequest) candidates.value = result
  } catch (cause: any) {
    if (requestId === candidateRequest) {
      candidates.value = []
      candidateError.value = cause?.response?.status === 404
        ? '成员搜索接口尚未加载，请重启后端服务后重试。'
        : cause?.response?.data?.detail ?? '成员搜索失败。'
    }
  } finally {
    if (requestId === candidateRequest) candidateLoading.value = false
  }
}

function openCandidatePicker() {
  candidateOpen.value = true
  if (!candidates.value.length && !candidateLoading.value) void searchCandidates()
}

function handleCandidateInput() {
  selectedCandidate.value = null
  candidateOpen.value = true
  window.clearTimeout(candidateTimer)
  candidateTimer = window.setTimeout(() => { void searchCandidates() }, 180)
}

function selectCandidate(candidate: TeamMemberCandidate) {
  selectedCandidate.value = candidate
  candidateQuery.value = candidate.username
  candidateOpen.value = false
}

async function createTeam() {
  const name = window.prompt('请输入新团队名称')?.trim()
  if (!name) return
  actionError.value = ''
  try {
    const created = await postTeam({ name })
    workspace.addTeam(created)
    await router.push(`/team/${created.id}`)
  } catch (cause: any) {
    actionError.value = cause?.response?.data?.detail ?? '创建团队失败。'
  }
}

async function switchTeam(event: Event) {
  const id = (event.target as HTMLSelectElement).value
  if (!id || id === teamId.value) return
  workspace.selectTeam(id)
  await router.push(`/team/${id}`)
}

function goAfterRemoval(removedId: string) {
  workspace.removeTeam(removedId)
  const next = workspace.currentTeam
  void router.push(next ? `/team/${next.id}` : '/')
}

async function exitTeam() {
  if (!team.value || isSystemAdmin.value || team.value.role === 'OWNER') return
  if (!window.confirm(`确定退出团队“${team.value.name}”吗？退出后将无法访问团队任务、笔记和附件。`)) return
  actionError.value = ''
  try {
    const removedId = team.value.id
    await leaveTeam(removedId)
    goAfterRemoval(removedId)
  } catch (cause: any) {
    actionError.value = cause?.response?.data?.detail ?? '退出团队失败。'
  }
}

async function dissolveTeam() {
  if (!team.value || !canDissolve.value) return
  const message = isSystemAdmin.value
    ? `确定以系统管理员身份介入并解散团队“${team.value.name}”吗？此操作不可撤销。`
    : `确定解散团队“${team.value.name}”吗？所有成员将立即失去团队访问权限，此操作不可撤销。`
  if (!window.confirm(message)) return
  actionError.value = ''
  try {
    const removedId = team.value.id
    await deleteTeam(removedId)
    goAfterRemoval(removedId)
  } catch (cause: any) {
    actionError.value = cause?.response?.data?.detail ?? '解散团队失败。'
  }
}

async function addMember() {
  if (!selectedCandidate.value || addingMember.value) return
  notice.value = ''
  actionError.value = ''
  addingMember.value = true
  try {
    await postTeamMember(teamId.value, { identifier: selectedCandidate.value.username, role: role.value })
    candidateQuery.value = ''
    selectedCandidate.value = null
    candidates.value = []
    candidateOpen.value = false
    await load()
    notice.value = '成员已加入团队。'
  } catch (cause: any) {
    actionError.value = cause?.response?.data?.detail ?? '添加成员失败。'
  } finally {
    addingMember.value = false
  }
}

async function removeMember(member: TeamMember) {
  if (member.userId === team.value?.ownerId) return
  if (!window.confirm(`确定移除 ${member.user.nickname} 吗？`)) return
  try {
    await deleteTeamMember(teamId.value, member.userId)
    await load()
  } catch (cause: any) {
    actionError.value = cause?.response?.data?.detail ?? '移除成员失败。'
  }
}

function canResetPassword(member: TeamMember): boolean {
  if (isSystemAdmin.value) return true
  if (!team.value || member.user.systemRole === 'ROOT') return false
  if (team.value.role === 'OWNER') return true
  if (team.value.role === 'ADMIN') return member.userId === auth.user?.id || member.role === 'MEMBER'
  return false
}

async function confirmResetPassword() {
  const target = resetTarget.value
  resetTarget.value = null
  if (!target || !team.value) return
  resettingUserId.value = target.userId
  actionError.value = ''
  notice.value = ''
  try {
    const result = await postTeamMemberResetPassword(team.value.id, target.userId)
    if (target.userId === auth.user?.id) {
      await auth.signOut()
      await router.replace('/login')
      return
    }
    notice.value = `${target.user.nickname} 的密码已重置为 ${result.initialPassword}`
  } catch (cause: any) {
    actionError.value = cause?.response?.data?.detail ?? '重置密码失败。'
  } finally {
    resettingUserId.value = null
  }
}

onMounted(load)
watch(teamId, () => {
  candidateRequest += 1
  candidateQuery.value = ''
  selectedCandidate.value = null
  candidates.value = []
  candidateOpen.value = false
  void load()
})
onBeforeUnmount(() => window.clearTimeout(candidateTimer))
</script>

<template>
  <div class="team-page page-content">
    <header class="workspace-heading">
      <div>
        <span class="eyebrow">TEAM MANAGEMENT</span>
        <h1>{{ team?.name ?? '团队管理' }}</h1>
        <p>{{ team?.description || '管理可协作的成员和权限；任务仍在统一任务页中处理。' }}</p>
      </div>
      <div class="team-header-actions">
        <button v-if="isSystemAdmin" class="secondary-button" type="button" @click="permissionsOpen = true"><IconShield :size="15" />权限管理</button>
        <button v-if="canCreateTeam" class="secondary-button" type="button" @click="createTeam"><IconPlus :size="15" />新建团队</button>
        <RouterLink class="secondary-button" :to="{ path: '/todos', query: { view: 'collaboration' } }">查看协作任务</RouterLink>
      </div>
    </header>

    <ActionFeedback :message="actionError" @dismiss="actionError = ''" />
    <ActionFeedback :message="notice" tone="success" @dismiss="notice = ''" />
    <p v-if="loading" class="state-message">正在加载团队…</p>
    <p v-else-if="loadError" class="state-message error">{{ loadError }}</p>
    <template v-else-if="team">
      <section class="team-context-bar" aria-label="切换团队">
        <label for="team-switcher">当前团队</label>
        <select id="team-switcher" :value="team.id" @change="switchTeam">
          <option v-for="item in workspace.teams" :key="item.id" :value="item.id">{{ item.name }} · {{ isSystemAdmin ? '系统管理员介入' : item.role === 'OWNER' ? '所有者' : item.role === 'ADMIN' ? '管理员' : '成员' }}</option>
        </select>
      </section>
      <section class="team-summary-card card">
        <IconUsers :size="22" />
        <div>
          <strong>{{ members.length }} 位成员</strong>
          <p>当前身份：{{ isSystemAdmin ? '系统管理员介入' : team.role === 'OWNER' ? '所有者' : team.role === 'ADMIN' ? '管理员' : '成员' }}</p>
        </div>
      </section>
      <RouterLink v-if="canManage" class="team-audit-link secondary-button" :to="`/team/${team.id}/audit`"><IconUsers :size="15" />查看审计日志</RouterLink>

      <section class="team-members-panel card">
        <header class="section-heading">
          <div>
            <span class="section-label">MEMBERS</span>
            <h2>团队成员</h2>
          </div>
        </header>

        <form v-if="canManage" class="team-invite-form" @submit.prevent="addMember">
          <div ref="candidateHost" class="team-member-picker">
            <label class="team-member-search-field" :class="{ selected: selectedCandidate }">
              <IconSearch :size="15" aria-hidden="true" />
              <input
                v-model="candidateQuery"
                placeholder="搜索昵称或用户名"
                aria-label="搜索待添加成员"
                aria-autocomplete="list"
                aria-controls="team-member-candidates"
                :aria-expanded="candidateOpen"
                autocomplete="off"
                role="combobox"
                @focus="openCandidatePicker"
                @input="handleCandidateInput"
                @keydown.esc="candidateOpen = false"
              />
            </label>
            <section v-if="candidateOpen" id="team-member-candidates" class="team-member-candidates" role="listbox" aria-label="可添加成员">
              <p v-if="candidateLoading">正在搜索…</p>
              <p v-else-if="candidateError" class="error">{{ candidateError }}</p>
              <template v-else>
                <button
                  v-for="candidate in candidates"
                  :key="candidate.id"
                  type="button"
                  role="option"
                  :aria-selected="selectedCandidate?.id === candidate.id"
                  @mousedown.prevent
                  @click="selectCandidate(candidate)"
                >
                  <span class="avatar"><img v-if="candidate.avatarUrl" :src="candidate.avatarUrl" alt="" /><IconUsers v-else :size="15" /></span>
                  <span><strong>{{ candidate.nickname }}</strong><small>@{{ candidate.username }}</small></span>
                </button>
              </template>
              <p v-if="!candidateLoading && !candidateError && !candidates.length">{{ candidateQuery.trim() ? '没有匹配的可添加成员' : '没有可添加的成员' }}</p>
            </section>
          </div>
          <select v-model="role" aria-label="成员角色">
            <option value="MEMBER">成员</option>
            <option v-if="isSystemAdmin || team.role === 'OWNER'" value="ADMIN">管理员</option>
          </select>
          <button class="primary-button" type="submit" :disabled="addingMember || !selectedCandidate"><IconPlus :size="15" />{{ addingMember ? '添加中…' : '添加' }}</button>
        </form>

        <div class="team-member-list">
          <div v-for="member in members" :key="member.id" class="team-member-row">
            <span class="avatar"><IconUsers :size="16" /></span>
            <div class="team-member-copy">
              <strong>{{ member.user.nickname }}</strong>
              <small>{{ member.user.username }} · {{ member.role === 'OWNER' ? '所有者' : member.role === 'ADMIN' ? '管理员' : '成员' }}</small>
            </div>
            <button v-if="canResetPassword(member)" class="quiet-button" type="button" :disabled="resettingUserId === member.userId" @click="resetTarget = member">重置密码</button>
            <button
              v-if="canManage && member.userId !== team.ownerId && (isSystemAdmin || team.role === 'OWNER' || member.role === 'MEMBER')"
              class="quiet-button"
              type="button"
              @click="removeMember(member)"
            >移除</button>
          </div>
        </div>
      </section>

      <section class="team-danger-zone card">
        <div>
          <strong>{{ canDissolve ? '解散团队' : '退出团队' }}</strong>
          <p>{{ canDissolve ? (isSystemAdmin ? '这是系统管理员介入操作，团队所有权仍归原所有者。' : '解散后所有成员立即失去访问权限，历史数据不会转成个人数据。') : '退出后你将无法访问该团队的任务、笔记与附件。' }}</p>
        </div>
        <button v-if="canDissolve" class="danger-button" type="button" @click="dissolveTeam"><IconTrash :size="15" />{{ isSystemAdmin ? '系统管理员解散' : '解散团队' }}</button>
        <button v-else class="danger-button" type="button" @click="exitTeam"><IconLogout :size="15" />退出团队</button>
      </section>
    </template>
    <SystemPermissionsDialog :open="permissionsOpen" @close="permissionsOpen = false" />
    <ConfirmDialog
      :open="Boolean(resetTarget)"
      title="重置成员密码"
      :message="`确定将“${resetTarget?.user.nickname ?? ''}”的密码重置为 11111111 吗？该用户当前登录会话会立即失效。`"
      confirm-label="重置密码"
      :danger="true"
      @close="resetTarget = null"
      @confirm="confirmResetPassword"
    />
  </div>
</template>
