<script setup lang="ts">
import { IconCheck, IconEdit, IconEye, IconExternalLink, IconRotate, IconX } from '@tabler/icons-vue'
import dayjs from 'dayjs'
import { ref, watch } from 'vue'

import RichTextDocument from '@/components/RichTextDocument.vue'
import type { KnowledgeCategory, SubmissionReviewPayload, TeamNote, TeamNoteSubmission } from '@/services/api'

const props = defineProps<{
  mode: 'mine' | 'review'
  submissions: TeamNoteSubmission[]
  selected: TeamNoteSubmission | null
  related?: TeamNote[]
  categories?: KnowledgeCategory[]
  busy?: boolean
}>()
const emit = defineEmits<{
  select: [submission: TeamNoteSubmission]
  withdraw: [submission: TeamNoteSubmission]
  resubmit: [submission: TeamNoteSubmission]
  openSource: [noteId: string]
  openKnowledge: [note: TeamNote]
  approve: [submission: TeamNoteSubmission, payload: SubmissionReviewPayload]
  revision: [submission: TeamNoteSubmission, reason: string]
  reject: [submission: TeamNoteSubmission, reason: string]
}>()
const comment = ref('')
const approvedTitle = ref('')
const approvedCategoryId = ref('')
const approvedTags = ref('')
watch(() => props.selected?.id, () => {
  comment.value = ''
  approvedTitle.value = props.selected?.snapshotTitle ?? ''
  approvedCategoryId.value = props.selected?.proposedCategoryId ?? ''
  approvedTags.value = props.selected?.proposedTagsJson.join(' ') ?? ''
}, { immediate: true })

function approveSelected() {
  if (!props.selected) return
  emit('approve', props.selected, {
    title: approvedTitle.value.trim() || props.selected.snapshotTitle,
    categoryId: approvedCategoryId.value || null,
    tags: approvedTags.value.split(/[,，\s]+/).map((tag) => tag.trim()).filter(Boolean),
    reason: comment.value.trim() || null,
  })
}

const labels: Record<string, string> = {
  PENDING: '待审核', NEEDS_REVISION: '需要修改', APPROVED: '已发布', REJECTED: '已拒绝', WITHDRAWN: '已撤回',
}
</script>

<template>
  <section class="submission-workspace">
    <aside class="notes-column note-list-column submission-index">
      <header class="notes-column-header"><div><h2>{{ mode === 'review' ? '知识审核' : '我的投稿' }}</h2></div><span>{{ submissions.length }}</span></header>
      <div class="note-list-items">
        <article v-for="item in submissions" :key="item.id" :class="{ active: selected?.id === item.id }"><button type="button" @click="emit('select', item)"><strong>{{ item.snapshotTitle }}</strong><p><span class="submission-status" :class="item.status.toLowerCase()">{{ labels[item.status] }}</span> · 第 {{ item.revisionNo }} 版</p><small>{{ dayjs(item.updatedAt).format('M月D日 HH:mm') }}</small></button></article>
        <p v-if="!submissions.length" class="notes-empty">暂无投稿</p>
      </div>
    </aside>
    <section class="notes-column editor-column submission-detail">
      <div v-if="!selected" class="editor-empty"><IconEye :size="28" /><strong>选择一条投稿</strong></div>
      <template v-else>
        <header class="editor-header submission-header"><div><span>{{ selected.submissionType === 'UPDATE' ? '更新投稿' : '新知识投稿' }} · {{ selected.applicant.nickname }}</span><h1>{{ selected.snapshotTitle }}</h1></div><span class="submission-status" :class="selected.status.toLowerCase()">{{ labels[selected.status] }}</span></header>
        <div v-if="selected.submissionMessage" class="submission-message"><strong>投稿说明</strong><p>{{ selected.submissionMessage }}</p></div>
        <div v-if="selected.reviewComment" class="submission-review-comment"><strong>审核意见</strong><p>{{ selected.reviewComment }}</p></div>
        <div v-if="mode === 'review' && selected.status === 'PENDING'" class="submission-review-metadata">
          <label><span>发布标题</span><input v-model="approvedTitle" /></label>
          <label><span>团队分类</span><select v-model="approvedCategoryId"><option value="">未分类</option><option v-for="category in categories" :key="category.id" :value="category.id">{{ category.name }}</option></select></label>
          <label><span>团队标签</span><input v-model="approvedTags" placeholder="空格或逗号分隔" /></label>
        </div>
        <RichTextDocument class="collaboration-document" :model-value="selected.snapshotContentJson" :editable="false" />
        <section v-if="mode === 'review' && related?.length" class="related-knowledge"><strong>可能相关知识</strong><button v-for="item in related" :key="item.id" type="button" @click="emit('openKnowledge', item)">{{ item.title }} · {{ item.category?.name ?? '未分类' }}</button></section>
        <footer class="submission-actions-footer">
          <template v-if="mode === 'mine'">
            <button v-if="selected.status === 'PENDING'" class="secondary-button" :disabled="busy" @click="emit('withdraw', selected)"><IconX :size="14" />撤回投稿</button>
            <button v-if="selected.status === 'NEEDS_REVISION'" class="secondary-button" @click="emit('openSource', selected.sourceNoteId)"><IconExternalLink :size="14" />打开原笔记</button>
            <button v-if="selected.status === 'NEEDS_REVISION'" class="primary-button" :disabled="busy" @click="emit('resubmit', selected)"><IconRotate :size="14" />重新提交快照</button>
          </template>
          <template v-else-if="selected.status === 'PENDING'">
            <textarea v-model="comment" rows="2" placeholder="审核意见；需要修改时必填" aria-label="审核意见" />
            <div><button class="secondary-button" :disabled="busy || !comment.trim()" @click="emit('revision', selected, comment.trim())"><IconEdit :size="14" />需要修改</button><button class="secondary-button danger-text" :disabled="busy || !comment.trim()" @click="emit('reject', selected, comment.trim())"><IconX :size="14" />拒绝</button><button class="primary-button" :disabled="busy || !approvedTitle.trim()" @click="approveSelected"><IconCheck :size="14" />通过</button></div>
          </template>
        </footer>
      </template>
    </section>
  </section>
</template>
