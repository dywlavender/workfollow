<script setup lang="ts">
import { computed, onMounted, ref, watch } from 'vue'
import { useRoute } from 'vue-router'
import { IconBook, IconCheck, IconFileText, IconPlus } from '@tabler/icons-vue'
import RichTextDocument from '@/components/RichTextDocument.vue'

import {
  approveTeamNoteSubmission,
  fetchTeam,
  fetchTeamNoteSubmissions,
  fetchTeamNotes,
  postTeamNote,
  putTeamNote,
  rejectTeamNoteSubmission,
  type Team,
  type TeamNote,
  type TeamNoteSubmission,
} from '@/services/api'

const route = useRoute()
const team = ref<Team | null>(null)
const notes = ref<TeamNote[]>([])
const submissions = ref<TeamNoteSubmission[]>([])
const selected = ref<TeamNote | null>(null)
const title = ref('')
const contentJson = ref<Record<string, unknown>>({ type: 'doc', content: [{ type: 'paragraph' }] })
const plainText = ref('')
const selectedSubmission = ref<TeamNoteSubmission | null>(null)
const rejectReason = ref('')
const loading = ref(false)
const saving = ref(false)
const error = ref('')
const teamId = computed(() => String(route.params.teamId ?? ''))
const canManage = computed(() => team.value?.role === 'OWNER' || team.value?.role === 'ADMIN')

function cloneDocument(value: Record<string, unknown>): Record<string, unknown> {
  return JSON.parse(JSON.stringify(value)) as Record<string, unknown>
}

async function load() {
  if (!teamId.value) return
  loading.value = true
  error.value = ''
  try {
    team.value = await fetchTeam(teamId.value)
    notes.value = await fetchTeamNotes(teamId.value)
    submissions.value = await fetchTeamNoteSubmissions(teamId.value)
    if (!selected.value || !notes.value.some((note) => note.id === selected.value?.id)) selected.value = notes.value[0] ?? null
    if (selected.value) {
      title.value = selected.value.title
      contentJson.value = cloneDocument(selected.value.contentJson)
      plainText.value = selected.value.plainText
    }
  } catch (cause: any) {
    error.value = cause?.response?.data?.detail ?? '无法读取团队笔记。'
  } finally {
    loading.value = false
  }
}

function selectNote(note: TeamNote) {
  selected.value = note
  title.value = note.title
  contentJson.value = cloneDocument(note.contentJson)
  plainText.value = note.plainText
}

function startNewNote() {
  selected.value = null
  title.value = ''
  contentJson.value = { type: 'doc', content: [{ type: 'paragraph' }] }
  plainText.value = ''
}

async function saveNote() {
  if (!title.value.trim()) return
  saving.value = true
  try {
    const payload = { title: title.value.trim(), contentJson: contentJson.value, plainText: plainText.value.trim() }
    const note = selected.value
      ? await putTeamNote(teamId.value, selected.value.id, payload)
      : await postTeamNote(teamId.value, payload)
    if (selected.value) {
      const index = notes.value.findIndex((item) => item.id === note.id)
      if (index >= 0) notes.value[index] = note
    } else {
      notes.value.unshift(note)
    }
    selectNote(note)
  } catch (cause: any) {
    error.value = cause?.response?.data?.detail ?? '创建团队笔记失败。'
  } finally {
    saving.value = false
  }
}

async function approve(submission: TeamNoteSubmission) {
  try {
    const note = await approveTeamNoteSubmission(teamId.value, submission.id)
    notes.value.unshift(note)
    submissions.value = submissions.value.map((item) => item.id === submission.id ? { ...item, status: 'APPROVED', approvedTeamNoteId: note.id } : item)
  } catch (cause: any) {
    error.value = cause?.response?.data?.detail ?? '审核通过失败。'
  }
}

async function reject(submission: TeamNoteSubmission) {
  if (!rejectReason.value.trim()) {
    selectedSubmission.value = submission
    return
  }
  try {
    const updated = await rejectTeamNoteSubmission(teamId.value, submission.id, rejectReason.value.trim())
    submissions.value = submissions.value.map((item) => item.id === updated.id ? updated : item)
    selectedSubmission.value = updated
    rejectReason.value = ''
  } catch (cause: any) {
    error.value = cause?.response?.data?.detail ?? '驳回失败。'
  }
}

onMounted(load)
watch(teamId, load)
</script>

<template>
  <div class="team-notes-page page-content">
    <header class="workspace-heading">
      <div>
        <span class="eyebrow">{{ team?.name ?? 'TEAM' }}</span>
        <h1>团队笔记</h1>
        <p>投稿通过审核后会生成独立 TeamNote，不实时引用个人笔记。</p>
      </div>
      <span class="team-role-badge">{{ team ? (canManage ? '可管理' : '只读') : '未知' }}</span>
    </header>

    <p v-if="loading" class="state-message">正在加载团队笔记…</p>
    <p v-else-if="error" class="state-message error">{{ error }}</p>
    <template v-else>
      <section class="team-notes-layout">
        <aside class="team-note-index card">
          <header><strong>已发布</strong><span>{{ notes.length }} <button v-if="canManage" class="team-note-new-button" type="button" aria-label="新建团队笔记" @click="startNewNote"><IconPlus :size="13" /></button></span></header>
          <button v-for="note in notes" :key="note.id" type="button" :class="{ active: selected?.id === note.id }" @click="selectNote(note)">
            <IconFileText :size="15" /><span>{{ note.title }}</span>
          </button>
          <p v-if="!notes.length" class="muted-text">暂无团队笔记</p>
        </aside>

        <main class="team-note-reader card">
          <template v-if="selected || canManage">
            <input v-if="canManage" v-model="title" class="team-note-title" aria-label="团队笔记标题" placeholder="团队笔记标题" />
            <h2 v-else>{{ selected?.title }}</h2>
            <RichTextDocument
              v-model="contentJson"
              :editable="canManage"
              placeholder="输入团队笔记正文…"
              @update:plain-text="plainText = $event"
            />
            <button v-if="canManage" class="primary-button" type="button" :disabled="saving || !title.trim()" @click="saveNote"><IconCheck :size="15" />{{ selected ? '保存团队笔记' : '创建团队笔记' }}</button>
          </template>
          <div v-else class="state-message empty"><IconBook :size="24" /><span>选择一篇团队笔记</span></div>
        </main>
      </section>

      <section class="team-submissions-panel card">
        <header class="section-heading"><div><span class="section-label">REVIEW</span><h2>{{ canManage ? '投稿审核' : '我的投稿' }}</h2></div><span class="muted-text">{{ submissions.filter((item) => item.status === 'PENDING').length }} 条待处理</span></header>
        <article v-for="submission in submissions" :key="submission.id" class="team-submission-row" @click="selectedSubmission = submission">
          <div>
            <strong>{{ submission.snapshotTitle }}</strong>
            <small>{{ submission.applicant.nickname }} · {{ new Date(submission.createdAt).toLocaleString('zh-CN') }} · {{ submission.status === 'PENDING' ? '待审核' : submission.status === 'APPROVED' ? '已通过' : '已驳回' }}</small>
            <small v-if="submission.reviewReason">原因：{{ submission.reviewReason }}</small>
          </div>
          <div v-if="submission.status === 'PENDING'" class="team-submission-actions">
            <button v-if="canManage" class="primary-button" type="button" @click.stop="approve(submission)">通过并发布</button>
            <button v-if="canManage" class="secondary-button" type="button" @click.stop="selectedSubmission = submission">驳回</button>
          </div>
        </article>
        <div v-if="selectedSubmission" class="submission-preview">
          <header><strong>快照预览：{{ selectedSubmission.snapshotTitle }}</strong><button type="button" @click="selectedSubmission = null">关闭</button></header>
          <RichTextDocument :model-value="selectedSubmission.snapshotContentJson" :editable="false" />
          <div v-if="canManage && selectedSubmission.status === 'PENDING'" class="submission-reject-form">
            <input v-model="rejectReason" placeholder="填写驳回原因（必填）" aria-label="驳回原因" />
            <button class="secondary-button" type="button" :disabled="!rejectReason.trim()" @click="reject(selectedSubmission)">确认驳回</button>
          </div>
        </div>
        <p v-if="!submissions.length" class="muted-text">暂无投稿。</p>
      </section>
    </template>
  </div>
</template>
