<script setup lang="ts">
import { IconSend, IconX } from '@tabler/icons-vue'
import { ref, watch } from 'vue'

import { useDialogEscape } from '@/composables/useDialogEscape'
import { parseTagInput } from '@/modules/notes/tagInput'
import type { KnowledgeCategory, Note, TeamNoteListItem, TeamNoteSubmissionType } from '@/services/api'

const props = defineProps<{
  open: boolean
  note: Note | null
  categories: KnowledgeCategory[]
  knowledge: TeamNoteListItem[]
  defaultType?: TeamNoteSubmissionType
  defaultTargetId?: string | null
  targetLocked?: boolean
  saving?: boolean
}>()
const emit = defineEmits<{
  close: []
  submit: [payload: { type: TeamNoteSubmissionType; targetTeamNoteId?: string | null; categoryId?: string | null; tags?: string[]; message?: string | null }]
}>()
useDialogEscape(() => props.open, () => emit('close'))
const type = ref<TeamNoteSubmissionType>('CREATE')
const targetTeamNoteId = ref('')
const categoryId = ref('')
const tags = ref('')
const message = ref('')

watch(() => props.open, (open) => {
  if (!open) return
  type.value = props.defaultType ?? 'CREATE'
  targetTeamNoteId.value = props.defaultTargetId ?? ''
  categoryId.value = ''
  tags.value = ''
  message.value = ''
})

function submit() {
  emit('submit', {
    type: type.value,
    targetTeamNoteId: type.value === 'UPDATE' ? targetTeamNoteId.value : null,
    categoryId: categoryId.value || null,
    tags: parseTagInput(tags.value),
    message: message.value.trim() || null,
  })
}
</script>

<template>
  <Teleport to="body">
    <div v-if="open" class="dialog-backdrop" @mousedown.self="emit('close')">
      <section class="note-collab-dialog publish-dialog" role="dialog" aria-modal="true" aria-labelledby="publish-title">
        <header><div><span class="eyebrow">SNAPSHOT</span><h2 id="publish-title">{{ type === 'UPDATE' ? '提交更新申请' : '发布到团队知识库' }}</h2></div><button type="button" aria-label="关闭" @click="emit('close')"><IconX :size="18" /></button></header>
        <div class="publish-note-summary"><small>笔记标题</small><strong>{{ note?.title }}</strong><p>当前内容将在提交时生成不可变审核快照，正文请回到个人笔记修改。</p></div>
        <div v-if="!defaultTargetId" class="publish-type-switch" role="group" aria-label="投稿类型">
          <button type="button" :class="{ active: type === 'CREATE' }" @click="type = 'CREATE'">发布为新知识</button>
          <button type="button" :class="{ active: type === 'UPDATE' }" @click="type = 'UPDATE'">更新已有知识</button>
        </div>
        <p v-else class="publish-update-hint">更新目标已锁定为原团队知识，本次不会创建重复条目。</p>
        <label v-if="type === 'UPDATE'" class="dialog-field"><span>目标团队知识</span><select v-model="targetTeamNoteId" :disabled="targetLocked" required><option value="">请选择</option><option v-for="item in knowledge" :key="item.id" :value="item.id">{{ item.title }}</option></select></label>
        <label class="dialog-field"><span>推荐分类</span><select v-model="categoryId"><option value="">未分类</option><option v-for="category in categories" :key="category.id" :value="category.id">{{ category.name }}</option></select></label>
        <label class="dialog-field"><span>推荐团队标签</span><input v-model="tags" placeholder="例如：性能 优化, 会议记录" /><small>多个标签用逗号分隔，标签内部可以包含空格</small></label>
        <label class="dialog-field"><span>发布说明（可选）</span><textarea v-model="message" rows="3" placeholder="总结本次贡献或更新内容" /></label>
        <footer><span>管理员审核的是本次 Snapshot</span><div><button class="secondary-button" type="button" @click="emit('close')">取消</button><button class="primary-button" type="button" :disabled="saving || (type === 'UPDATE' && !targetTeamNoteId)" @click="submit"><IconSend :size="15" />提交审核</button></div></footer>
      </section>
    </div>
  </Teleport>
</template>
